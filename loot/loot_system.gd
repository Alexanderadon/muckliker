extends Node

@export var loot_pool_size: int = 220
@export var max_spawn_operations_per_frame: int = 10
@export var pickup_distance: float = 2.0
@export var pickup_delay_seconds: float = 0.35
@export var loot_auto_despawn_seconds: float = 120.0
@export var max_total_loot_pool_size: int = 600
@export var enable_chunk_loot_cleanup: bool = true

const ITEM_DB_PATH: String = "res://shared/items/item_db.json"
const LOOT_PHYSICS_ACTIVE_TIME: float = 2.0
const LOOT_PHYSICS_FREEZE_TIME: float = 4.0
const LOOT_BASE_LINEAR_DAMP: float = 0.05
const LOOT_BASE_ANGULAR_DAMP: float = 0.05
const LOOT_SLOW_LINEAR_DAMP: float = 3.0
const LOOT_SLOW_ANGULAR_DAMP: float = 3.0
const LOOT_MAX_LINEAR_DAMP: float = 7.5
const LOOT_MAX_ANGULAR_DAMP: float = 9.0
const LOOT_SETTLE_SLOPE_DEGREES: float = 10.0
const LOOT_GROUND_RAYCAST_DISTANCE: float = 1.5
const LOOT_BOUNCE: float = 0.2
const LOOT_FRICTION: float = 1.0

var _player: Node3D = null
var _inventory_system: Node = null
var _loot_pool: Array[Node3D] = []
var _active_loot: Array[Node3D] = []
var _loot_by_chunk: Dictionary = {}
var _pending_spawns: Array[Dictionary] = []
var _item_definitions: Dictionary = {}
var _pool_index: ObjectPool = ObjectPool.new()

func _ready() -> void:
	_apply_game_config()
	_load_item_definitions()
	_warm_pool()
	EventBus.subscribe("loot_spawn_requested", Callable(self, "_on_loot_spawn_requested"))

func _exit_tree() -> void:
	if EventBus != null and EventBus.has_method("unsubscribe"):
		EventBus.call("unsubscribe", "loot_spawn_requested", Callable(self, "_on_loot_spawn_requested"))

func _process(_delta: float) -> void:
	_process_pending_spawns()
	_update_active_loot_physics()

func set_player(player: Node3D) -> void:
	_player = player

func set_inventory_system(inventory_system: Node) -> void:
	_inventory_system = inventory_system

func on_chunk_unloaded(chunk_id: Vector2i) -> void:
	if not enable_chunk_loot_cleanup:
		return
	_drop_pending_spawns_for_chunk(chunk_id)
	_despawn_loot_for_chunk(chunk_id)

func get_debug_counts() -> Dictionary:
	var active_count: int = 0
	for loot_variant in _active_loot:
		var loot: Node3D = loot_variant as Node3D
		if loot != null and is_instance_valid(loot) and bool(loot.get_meta("active", false)):
			active_count += 1
	return {
		"pool_size": _loot_pool.size(),
		"active_loot": active_count,
		"pending_spawns": _pending_spawns.size(),
		"chunk_buckets": _loot_by_chunk.size()
	}

func _on_loot_spawn_requested(payload: Dictionary) -> void:
	_pending_spawns.append(payload)

func _process_pending_spawns() -> void:
	var operations_done := 0
	while operations_done < max_spawn_operations_per_frame and not _pending_spawns.is_empty():
		var payload: Dictionary = _pending_spawns.pop_front()
		_spawn_loot(payload)
		operations_done += 1

func _spawn_loot(payload: Dictionary) -> bool:
	var loot := _take_from_pool()
	if loot == null:
		return false
	var rigid_loot: RigidBody3D = loot as RigidBody3D
	if rigid_loot != null:
		rigid_loot.freeze = true
		rigid_loot.linear_velocity = Vector3.ZERO
		rigid_loot.angular_velocity = Vector3.ZERO
	var position_variant: Variant = payload.get("position", Vector3.ZERO)
	var item_id_variant: Variant = payload.get("item_id", "unknown")
	var amount_variant: Variant = payload.get("amount", 1)
	var spawned_from_world_variant: Variant = payload.get("spawned_from_world", false)
	var chunk_id_variant: Variant = payload.get("chunk_id", null)
	var spawned_from_world: bool = bool(spawned_from_world_variant)
	var has_chunk_id: bool = chunk_id_variant is Vector2i
	var chunk_id: Vector2i = chunk_id_variant if has_chunk_id else Vector2i.ZERO
	var item_id: String = String(item_id_variant)
	var amount: int = int(amount_variant)
	var base_position: Vector3 = position_variant if position_variant is Vector3 else Vector3.ZERO
	loot.global_position = base_position if spawned_from_world else base_position + Vector3(0.0, 0.12, 0.0)
	loot.set_meta("item_id", item_id)
	loot.set_meta("amount", amount)
	loot.set_meta("spawned_from_world", spawned_from_world)
	loot.set_meta("motion_frozen", spawned_from_world)
	loot.set_meta("motion_slowing", false)
	loot.set_meta("active", true)
	loot.set_meta("spawn_time", float(Time.get_ticks_msec()) / 1000.0)
	if spawned_from_world and has_chunk_id:
		loot.set_meta("chunk_id", chunk_id)
		_register_loot_in_chunk(chunk_id, loot)
	elif loot.has_meta("chunk_id"):
		loot.remove_meta("chunk_id")
	loot.visible = true
	_apply_loot_visual(loot, item_id)
	if rigid_loot != null:
		if spawned_from_world:
			rigid_loot.freeze = true
			rigid_loot.sleeping = true
			rigid_loot.linear_damp = LOOT_MAX_LINEAR_DAMP
			rigid_loot.angular_damp = LOOT_MAX_ANGULAR_DAMP
		else:
			_activate_loot_physics(rigid_loot)
	_active_loot.append(loot)
	return true

func get_nearest_pickup(world_position: Vector3, radius: float = 2.0) -> Node3D:
	var best: Node3D = null
	var best_distance_sq: float = radius * radius
	var now_seconds: float = float(Time.get_ticks_msec()) / 1000.0
	for loot_variant in _active_loot:
		var loot: Node3D = loot_variant as Node3D
		if loot == null or not is_instance_valid(loot):
			continue
		if not bool(loot.get_meta("active", false)):
			continue
		var spawn_time_variant: Variant = loot.get_meta("spawn_time", 0.0)
		var spawn_time: float = float(spawn_time_variant)
		if now_seconds - spawn_time < pickup_delay_seconds:
			continue
		var distance_sq: float = loot.global_position.distance_squared_to(world_position)
		if distance_sq > best_distance_sq:
			continue
		best_distance_sq = distance_sq
		best = loot
	return best

func pickup_loot(loot: Node3D, picker: Node) -> bool:
	if loot == null or not is_instance_valid(loot):
		return false
	if not bool(loot.get_meta("active", false)):
		return false
	var picker_body: Node3D = picker as Node3D
	if picker_body != null and loot.global_position.distance_to(picker_body.global_position) > pickup_distance:
		return false
	var now_seconds: float = float(Time.get_ticks_msec()) / 1000.0
	var spawn_time_variant: Variant = loot.get_meta("spawn_time", 0.0)
	var spawn_time: float = float(spawn_time_variant)
	if now_seconds - spawn_time < pickup_delay_seconds:
		return false
	var item_id: String = String(loot.get_meta("item_id", "unknown"))
	var amount: int = int(loot.get_meta("amount", 1))
	if item_id.is_empty() or amount <= 0:
		return false
	var added: bool = false
	var picker_inventory_component: InventoryComponent = null
	var has_inventory_system_add: bool = _inventory_system != null and _inventory_system.has_method("add_item")
	if _inventory_system != null and _inventory_system.has_method("add_item"):
		added = bool(_inventory_system.call("add_item", item_id, amount))
	# Do not bypass InventorySystem limits (stack/capacity) when it is available.
	if not added and not has_inventory_system_add and picker != null and picker.has_method("get_inventory_component"):
		var inventory_component_variant: Variant = picker.call("get_inventory_component")
		picker_inventory_component = inventory_component_variant as InventoryComponent
		if picker_inventory_component != null:
			added = picker_inventory_component.add_item(item_id, amount)
			if added and _inventory_system != null and _inventory_system.has_method("notify_inventory_changed"):
				_inventory_system.call("notify_inventory_changed", picker_inventory_component)
	if not added:
		return false
	print("Picked:", item_id)
	var inventory_data: Variant = []
	if _inventory_system != null and _inventory_system.has_method("get_inventory_data"):
		inventory_data = _inventory_system.call("get_inventory_data")
	elif picker != null and picker.has_method("get_inventory_component"):
		var picker_inventory_variant: Variant = picker.call("get_inventory_component")
		var picker_inventory: InventoryComponent = picker_inventory_variant as InventoryComponent
		if picker_inventory != null:
			inventory_data = picker_inventory.items.duplicate(true)
	print("Inventory:", inventory_data)
	EventBus.emit_game_event("loot_picked", {
		"item_id": item_id,
		"amount": amount
	})
	_despawn_loot(loot)
	return true

func _warm_pool() -> void:
	for _i in range(loot_pool_size):
		var loot := _create_loot_node()
		add_child(loot)
		loot.visible = false
		loot.set_meta("active", false)
		_loot_pool.append(loot)
	_pool_index.setup(_loot_pool, Callable(self, "_is_loot_active"))

func _create_loot_node() -> Node3D:
	var loot := RigidBody3D.new()
	loot.name = "Loot"
	loot.add_to_group("loot_pickup")
	loot.freeze = true
	loot.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	loot.gravity_scale = 1.0
	loot.mass = 0.2
	loot.can_sleep = false
	loot.contact_monitor = false
	# Godot 4.6 compatibility: use boolean CCD toggle on RigidBody3D.
	loot.continuous_cd = true
	var physics_material: PhysicsMaterial = PhysicsMaterial.new()
	physics_material.bounce = LOOT_BOUNCE
	physics_material.friction = LOOT_FRICTION
	loot.physics_material_override = physics_material

	var collider := CollisionShape3D.new()
	collider.name = "Collider"
	var collision_shape := SphereShape3D.new()
	collision_shape.radius = 0.18
	collider.shape = collision_shape
	loot.add_child(collider)

	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.35, 0.35)
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.82, 0.2, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.75, 0.2, 1.0)
	material.emission_energy_multiplier = 0.35
	visual.material_override = material
	loot.add_child(visual)
	return loot

func _apply_loot_visual(loot: Node3D, item_id: String) -> void:
	var visual: MeshInstance3D = loot.get_node_or_null("Visual") as MeshInstance3D
	if visual == null:
		return
	_apply_loot_mesh(visual, item_id)
	var material: StandardMaterial3D = visual.material_override as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		visual.material_override = material
	var color: Color = _get_item_color(item_id)
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.3

func _apply_loot_mesh(visual: MeshInstance3D, item_id: String) -> void:
	visual.rotation = Vector3.ZERO
	if item_id == "axe":
		var axe_mesh: BoxMesh = BoxMesh.new()
		axe_mesh.size = Vector3(0.16, 0.42, 0.1)
		visual.mesh = axe_mesh
		visual.rotation_degrees = Vector3(0.0, 0.0, -18.0)
		return
	if item_id == "pickaxe":
		var pickaxe_mesh: BoxMesh = BoxMesh.new()
		pickaxe_mesh.size = Vector3(0.3, 0.18, 0.1)
		visual.mesh = pickaxe_mesh
		visual.rotation_degrees = Vector3(0.0, 0.0, 0.0)
		return
	if item_id == "stick":
		var stick_mesh: CylinderMesh = CylinderMesh.new()
		stick_mesh.top_radius = 0.04
		stick_mesh.bottom_radius = 0.045
		stick_mesh.height = 0.38
		visual.mesh = stick_mesh
		visual.rotation_degrees = Vector3(90.0, 0.0, 25.0)
		return
	if item_id == "wood":
		var wood_mesh: CylinderMesh = CylinderMesh.new()
		wood_mesh.top_radius = 0.09
		wood_mesh.bottom_radius = 0.1
		wood_mesh.height = 0.52
		visual.mesh = wood_mesh
		visual.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		return
	if item_id == "stone":
		var stone_mesh: SphereMesh = SphereMesh.new()
		stone_mesh.radius = 0.14
		stone_mesh.height = 0.22
		visual.mesh = stone_mesh
		return
	var default_mesh: BoxMesh = BoxMesh.new()
	default_mesh.size = Vector3(0.35, 0.35, 0.35)
	visual.mesh = default_mesh

func _get_item_color(item_id: String) -> Color:
	if _item_definitions.is_empty():
		_load_item_definitions()
	var definition_variant: Variant = _item_definitions.get(item_id, {})
	if definition_variant is Dictionary:
		var definition: Dictionary = definition_variant
		var color_variant: Variant = definition.get("ui_color", "#FFD233")
		var color_hex: String = String(color_variant)
		return Color.from_string(color_hex, Color(1.0, 0.82, 0.2, 1.0))
	return Color(1.0, 0.82, 0.2, 1.0)

func _load_item_definitions() -> void:
	_item_definitions.clear()
	var parsed: Dictionary = JsonDataLoader.load_dictionary(ITEM_DB_PATH)
	if parsed.is_empty():
		return
	var items_variant: Variant = parsed.get("items", [])
	if not (items_variant is Array):
		return
	var entries: Array = items_variant
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = Dictionary(entry_variant)
		var item_id: String = String(entry.get("id", ""))
		if item_id.is_empty():
			continue
		_item_definitions[item_id] = entry.duplicate(true)

func _take_from_pool() -> Node3D:
	var pooled_node: Node = _pool_index.acquire()
	var pooled_loot: Node3D = pooled_node as Node3D
	if pooled_loot != null:
		return pooled_loot
	if _loot_pool.size() >= maxi(max_total_loot_pool_size, loot_pool_size):
		return null
	# Fallback: dynamically grow pool to avoid dropping items/resources on pool exhaustion.
	var new_loot: Node3D = _create_loot_node()
	add_child(new_loot)
	new_loot.visible = false
	new_loot.set_meta("active", false)
	_loot_pool.append(new_loot)
	_pool_index.setup(_loot_pool, Callable(self, "_is_loot_active"))
	return new_loot

func _despawn_loot(loot: Node3D) -> void:
	_active_loot.erase(loot)
	_unregister_loot_from_chunk(loot)
	loot.visible = false
	loot.set_meta("active", false)
	loot.set_meta("motion_frozen", false)
	loot.set_meta("motion_slowing", false)
	var rigid_loot: RigidBody3D = loot as RigidBody3D
	if rigid_loot != null:
		rigid_loot.linear_velocity = Vector3.ZERO
		rigid_loot.angular_velocity = Vector3.ZERO
		rigid_loot.linear_damp = LOOT_BASE_LINEAR_DAMP
		rigid_loot.angular_damp = LOOT_BASE_ANGULAR_DAMP
		rigid_loot.freeze = true
		rigid_loot.sleeping = true

func _is_loot_active(node: Node) -> bool:
	if node == null:
		return false
	return bool(node.get_meta("active", false))

func _apply_game_config() -> void:
	loot_pool_size = GameConfig.LOOT_POOL_SIZE
	max_spawn_operations_per_frame = GameConfig.MAX_SPAWN_OPERATIONS_PER_FRAME
	pickup_distance = GameConfig.LOOT_PICKUP_DISTANCE
	pickup_delay_seconds = GameConfig.LOOT_PICKUP_DELAY_SECONDS

func _activate_loot_physics(rigid_loot: RigidBody3D) -> void:
	if rigid_loot == null:
		return
	rigid_loot.linear_damp = LOOT_BASE_LINEAR_DAMP
	rigid_loot.angular_damp = LOOT_BASE_ANGULAR_DAMP
	rigid_loot.freeze = false
	rigid_loot.sleeping = false
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec()) ^ int(rigid_loot.get_instance_id())
	var impulse: Vector3 = Vector3(
		rng.randf_range(-0.35, 0.35),
		rng.randf_range(0.5, 1.1),
		rng.randf_range(-0.35, 0.35)
	)
	rigid_loot.apply_central_impulse(impulse)
	rigid_loot.apply_torque_impulse(Vector3(
		rng.randf_range(-0.08, 0.08),
		rng.randf_range(-0.08, 0.08),
		rng.randf_range(-0.08, 0.08)
	))
	if rigid_loot.linear_velocity.length_squared() < 0.0001:
		rigid_loot.linear_velocity = impulse * 2.2

func _update_active_loot_physics() -> void:
	if _active_loot.is_empty():
		return
	var now_seconds: float = float(Time.get_ticks_msec()) / 1000.0
	for loot_variant in _active_loot.duplicate():
		var loot: Node3D = loot_variant as Node3D
		if loot == null or not is_instance_valid(loot):
			_active_loot.erase(loot_variant)
			continue
		if not bool(loot.get_meta("active", false)):
			continue
		var spawn_time_variant: Variant = loot.get_meta("spawn_time", now_seconds)
		var spawn_time: float = float(spawn_time_variant)
		var age_seconds: float = now_seconds - spawn_time
		# Prevent long-running sessions from accumulating uncollected drops forever.
		if loot_auto_despawn_seconds > 0.0 and age_seconds >= loot_auto_despawn_seconds:
			_despawn_loot(loot)
			continue
		if bool(loot.get_meta("motion_frozen", false)):
			continue
		var rigid_loot: RigidBody3D = loot as RigidBody3D
		if rigid_loot == null:
			continue
		if not _is_loot_on_settle_surface(rigid_loot):
			rigid_loot.linear_damp = LOOT_BASE_LINEAR_DAMP
			rigid_loot.angular_damp = LOOT_BASE_ANGULAR_DAMP
			loot.set_meta("motion_slowing", false)
			continue
		if age_seconds >= LOOT_PHYSICS_FREEZE_TIME:
			rigid_loot.linear_velocity = Vector3.ZERO
			rigid_loot.angular_velocity = Vector3.ZERO
			rigid_loot.linear_damp = LOOT_MAX_LINEAR_DAMP
			rigid_loot.angular_damp = LOOT_MAX_ANGULAR_DAMP
			rigid_loot.freeze = true
			rigid_loot.sleeping = true
			loot.set_meta("motion_frozen", true)
			continue
		if age_seconds <= LOOT_PHYSICS_ACTIVE_TIME:
			rigid_loot.linear_damp = LOOT_BASE_LINEAR_DAMP
			rigid_loot.angular_damp = LOOT_BASE_ANGULAR_DAMP
			loot.set_meta("motion_slowing", false)
			continue
		if not bool(loot.get_meta("motion_slowing", false)):
			loot.set_meta("motion_slowing", true)
			rigid_loot.linear_damp = LOOT_SLOW_LINEAR_DAMP
			rigid_loot.angular_damp = LOOT_SLOW_ANGULAR_DAMP

func _is_loot_on_settle_surface(rigid_loot: RigidBody3D) -> bool:
	if rigid_loot == null:
		return false
	var world_3d: World3D = rigid_loot.get_world_3d()
	if world_3d == null:
		return false
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if space_state == null:
		return false
	var from: Vector3 = rigid_loot.global_position
	var to: Vector3 = from + Vector3.DOWN * LOOT_GROUND_RAYCAST_DISTANCE
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [rigid_loot]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return false
	var normal_variant: Variant = result.get("normal", Vector3.UP)
	var normal: Vector3 = normal_variant if normal_variant is Vector3 else Vector3.UP
	var slope_dot: float = clampf(normal.dot(Vector3.UP), -1.0, 1.0)
	var slope_degrees: float = rad_to_deg(acos(slope_dot))
	return slope_degrees < LOOT_SETTLE_SLOPE_DEGREES

func _register_loot_in_chunk(chunk_id: Vector2i, loot: Node3D) -> void:
	if not _loot_by_chunk.has(chunk_id):
		_loot_by_chunk[chunk_id] = []
	var chunk_loot_variant: Variant = _loot_by_chunk.get(chunk_id, [])
	var chunk_loot: Array = chunk_loot_variant if chunk_loot_variant is Array else []
	if chunk_loot.find(loot) < 0:
		chunk_loot.append(loot)
	_loot_by_chunk[chunk_id] = chunk_loot

func _unregister_loot_from_chunk(loot: Node3D) -> void:
	if loot == null or not loot.has_meta("chunk_id"):
		return
	var chunk_id_variant: Variant = loot.get_meta("chunk_id", Vector2i.ZERO)
	if not (chunk_id_variant is Vector2i):
		return
	var chunk_id: Vector2i = chunk_id_variant
	if not _loot_by_chunk.has(chunk_id):
		return
	var chunk_loot_variant: Variant = _loot_by_chunk.get(chunk_id, [])
	if not (chunk_loot_variant is Array):
		_loot_by_chunk.erase(chunk_id)
		return
	var chunk_loot: Array = chunk_loot_variant
	chunk_loot.erase(loot)
	if chunk_loot.is_empty():
		_loot_by_chunk.erase(chunk_id)
	else:
		_loot_by_chunk[chunk_id] = chunk_loot

func _despawn_loot_for_chunk(chunk_id: Vector2i) -> void:
	if not _loot_by_chunk.has(chunk_id):
		return
	var chunk_loot_variant: Variant = _loot_by_chunk.get(chunk_id, [])
	if not (chunk_loot_variant is Array):
		_loot_by_chunk.erase(chunk_id)
		return
	var chunk_loot: Array = chunk_loot_variant
	for loot_variant in chunk_loot.duplicate():
		var loot: Node3D = loot_variant as Node3D
		if loot != null and is_instance_valid(loot):
			_despawn_loot(loot)
	_loot_by_chunk.erase(chunk_id)

func _drop_pending_spawns_for_chunk(chunk_id: Vector2i) -> void:
	if _pending_spawns.is_empty():
		return
	var retained: Array[Dictionary] = []
	for payload in _pending_spawns:
		var payload_chunk_variant: Variant = payload.get("chunk_id", null)
		if payload_chunk_variant is Vector2i and payload_chunk_variant == chunk_id:
			continue
		retained.append(payload)
	_pending_spawns = retained
