extends CharacterBody3D

@export var attack_distance: float = 4.0
@export var mouse_sensitivity: float = 0.0025
@export var min_pitch_degrees: float = -80.0
@export var max_pitch_degrees: float = 75.0
@export_file("*.fbx", "*.glb", "*.gltf", "*.tscn", "*.scn")
var player_model_scene_path: String = "res://assets/models/player/Running.fbx"
@export var player_model_target_height: float = 1.45
@export var player_model_height_scale_multiplier: float = 1.0
@export var player_model_yaw_offset_degrees: float = 180.0
@export var player_model_vertical_offset: float = 0.0
@export var run_animation_name: StringName = &"Running"
@export var run_animation_fallback_names: PackedStringArray = ["Run", "run", "Running", "Take 001"]
@export var run_animation_speed_multiplier: float = 1.0
@export var model_move_speed_threshold: float = 0.08
@export var first_person_eye_height: float = 1.7
@export var third_person_distance: float = 3.2
@export var third_person_height_offset: float = 0.25
@export var third_person_shoulder_offset: float = 0.0
@export var third_person_collision_buffer: float = 0.2
@export var third_person_min_distance: float = 0.45

const BASE_MOVE_SPEED: float = 7.0
const BASE_JUMP_VELOCITY: float = 6.5
const HOTBAR_SLOT_COUNT: int = 8
const DROP_ONE_ACTION: StringName = &"drop_item_one"
const CAMERA_TOGGLE_ACTION: StringName = &"toggle_camera_mode"
const INVENTORY_GROUND_DECELERATION: float = 8.0
const PICKUP_INTERACT_RADIUS: float = 2.0
const PICKUP_PROMPT_TEXT: String = "Press E to pick up"
const WATER_SLOWDOWN_MULTIPLIER: float = 0.55
const DEEP_WATER_SLOWDOWN_MULTIPLIER: float = 0.35
const DROWNING_DAMAGE_PER_TICK: float = 2.0
const DROWNING_INTERVAL_SECONDS: float = 1.0
const RESPAWN_DELAY_SECONDS: float = 3.0
const SWIM_BUOYANCY_ACCEL: float = 12.0
const SWIM_MAX_SINK_SPEED: float = -2.1
const SWIM_SURFACE_TARGET_OFFSET: float = 0.18

signal hotbar_slot_selected(slot_index: int)
signal gold_changed(old_value: int, new_value: int)

var _world_system: Node = null
var _combat_system: Node = null
var _inventory_system: Node = null
var _loot_system: Node = null
var _ui_system: Node = null

var _movement_component: MovementComponent = null
var _health_component: HealthComponent = null
var _damage_component: DamageComponent = null
var _inventory_component: InventoryComponent = null
var _ability_component: AbilityComponent = null
var _ability_manager: AbilityManager = null
var _player_economy: PlayerEconomy = null

var _player_head: Node3D = null
var _camera: Camera3D = null
var _player_model_root: Node3D = null
var _player_model_anim: AnimationPlayer = null
var _resolved_run_animation: StringName = &""
var _camera_pitch: float = 0.0
var _is_dead: bool = false
var is_swimming: bool = false
var _respawn_time_left: float = 0.0
var _drown_timer: float = 0.0
var _current_speed_multiplier: float = 1.0
var _selected_hotbar_index: int = 0
var _interaction_pickup: Node3D = null
var _is_in_deep_water: bool = false
var gold: int = 0
var _permanent_move_speed_bonus: float = 0.0
var _permanent_jump_bonus_percent: float = 0.0
var _is_third_person_view: bool = false

func _ready() -> void:
	add_to_group("player")
	_ensure_input_map()
	_ensure_visuals()
	_cache_view_nodes()
	_update_camera_mode_and_position(true)
	_ensure_components()
	_bind_health_signals()
	_bind_economy_signals()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	var inventory_open: bool = _is_inventory_open()
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo:
			if key_event.is_action_pressed(CAMERA_TOGGLE_ACTION):
				_toggle_camera_mode()
				get_viewport().set_input_as_handled()
				return
			if not inventory_open and key_event.is_action_pressed(DROP_ONE_ACTION):
				_drop_one_from_selected_hotbar()
				get_viewport().set_input_as_handled()
				return
			if not inventory_open:
				_handle_hotbar_key_input(key_event)
	if event is InputEventMouseMotion:
		if not inventory_open and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and not get_tree().paused:
			var motion: InputEventMouseMotion = event
			_apply_mouse_look(motion.relative)
	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event
		if not inventory_open and mouse_button_event.pressed:
			if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_set_selected_hotbar_index(_selected_hotbar_index - 1)
			elif mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_set_selected_hotbar_index(_selected_hotbar_index + 1)
		if not inventory_open and mouse_button_event.pressed and mouse_button_event.button_index == MOUSE_BUTTON_LEFT and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	_update_camera_mode_and_position()
	if _is_dead:
		velocity = Vector3.ZERO
		_respawn_time_left -= delta
		if _respawn_time_left <= 0.0:
			_respawn_player()
		_update_player_model_animation_state()
		return
	if get_tree().paused:
		_update_player_model_animation_state()
		return
	if _movement_component == null:
		_update_player_model_animation_state()
		return
	_resolve_interaction_system_refs()
	var inventory_open: bool = _is_inventory_open()
	if inventory_open:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_update_water_effects(delta)
	_movement_component.move_speed = (BASE_MOVE_SPEED + _permanent_move_speed_bonus) * _current_speed_multiplier
	if inventory_open:
		_set_interaction_prompt(false)
		_move_with_inertia(delta)
		_enforce_world_boundary()
		_update_player_model_animation_state()
		return
	_update_interaction_target()
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wants_jump: bool = Input.is_action_just_pressed("jump")
	_apply_swim_buoyancy(delta)
	_movement_component.move_character(self, input_vector, wants_jump, delta, global_transform.basis)
	_enforce_world_boundary()
	if Input.is_action_just_pressed("attack"):
		_perform_attack()
	if Input.is_action_just_pressed("interact"):
		if _try_pickup_interaction():
			_update_player_model_animation_state()
			return
		_try_interact()
	_update_player_model_animation_state()

func set_world_system(world_system: Node) -> void:
	_world_system = world_system
	_resolve_interaction_system_refs()

func set_combat_system(combat_system: Node) -> void:
	_combat_system = combat_system

func set_inventory_system(inventory_system: Node) -> void:
	_inventory_system = inventory_system
	_try_bind_inventory_system()

func set_loot_system(loot_system: Node) -> void:
	_loot_system = loot_system

func set_ui_system(ui_system: Node) -> void:
	_ui_system = ui_system

func get_inventory_component() -> InventoryComponent:
	return _inventory_component

func get_player_economy() -> PlayerEconomy:
	return _player_economy

func get_ability_manager() -> AbilityManager:
	return _ability_manager

func add_permanent_move_speed_bonus(amount: float) -> void:
	if amount <= 0.0:
		return
	_permanent_move_speed_bonus += amount

func add_permanent_jump_bonus_percent(percent_amount: float) -> void:
	if percent_amount <= 0.0:
		return
	_permanent_jump_bonus_percent += percent_amount
	if _movement_component != null:
		var jump_multiplier: float = 1.0 + (_permanent_jump_bonus_percent / 100.0)
		_movement_component.jump_velocity = BASE_JUMP_VELOCITY * jump_multiplier

func get_selected_hotbar_index() -> int:
	return _selected_hotbar_index

func get_selected_hotbar_item() -> Dictionary:
	if _inventory_component == null:
		return {}
	if _selected_hotbar_index < 0 or _selected_hotbar_index >= HOTBAR_SLOT_COUNT:
		return {}
	if _selected_hotbar_index >= _inventory_component.items.size():
		return {}
	var item_entry: Dictionary = _inventory_component.items[_selected_hotbar_index]
	return item_entry.duplicate(true)

func _apply_mouse_look(relative: Vector2) -> void:
	rotation.y -= relative.x * mouse_sensitivity
	_camera_pitch = clampf(
		_camera_pitch - relative.y * mouse_sensitivity,
		deg_to_rad(min_pitch_degrees),
		deg_to_rad(max_pitch_degrees)
	)
	if _player_head != null:
		_player_head.rotation.x = _camera_pitch

func _toggle_camera_mode() -> void:
	_is_third_person_view = not _is_third_person_view
	_update_camera_mode_and_position(true)

func _update_camera_mode_and_position(force: bool = false) -> void:
	if _camera == null or _player_head == null:
		return
	_set_character_visual_visibility(_is_third_person_view)
	if not _is_third_person_view:
		if force or _camera.position.distance_squared_to(Vector3.ZERO) > 0.000001:
			_camera.position = Vector3.ZERO
		return
	var head_origin: Vector3 = _player_head.global_position
	var distance: float = maxf(third_person_distance, third_person_min_distance)
	var desired_local_offset: Vector3 = Vector3(
		third_person_shoulder_offset,
		third_person_height_offset,
		distance
	)
	var desired_global_position: Vector3 = _player_head.global_transform * desired_local_offset
	var view_vector: Vector3 = desired_global_position - head_origin
	var desired_distance: float = view_vector.length()
	if desired_distance <= 0.0001:
		_camera.global_position = desired_global_position
		return
	var safe_distance: float = desired_distance
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state != null:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(head_origin, desired_global_position)
		query.exclude = [self]
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = space_state.intersect_ray(query)
		if not hit.is_empty():
			var hit_position_variant: Variant = hit.get("position", desired_global_position)
			if hit_position_variant is Vector3:
				var hit_position: Vector3 = hit_position_variant
				safe_distance = clampf(
					head_origin.distance_to(hit_position) - maxf(third_person_collision_buffer, 0.0),
					maxf(third_person_min_distance, 0.1),
					desired_distance
				)
	_camera.global_position = head_origin + view_vector.normalized() * safe_distance

func _set_character_visual_visibility(is_visible: bool) -> void:
	if _player_model_root != null and is_instance_valid(_player_model_root):
		_player_model_root.visible = is_visible
	var fallback_visual: Node3D = get_node_or_null("Visual") as Node3D
	if fallback_visual != null:
		fallback_visual.visible = is_visible

func _perform_attack() -> void:
	var hit: Dictionary = _raycast(attack_distance)
	if not hit.is_empty():
		var collider_variant: Variant = hit.get("collider")
		if collider_variant is Object:
			var collider: Object = collider_variant
			if _try_harvest_from_attack(collider):
				return
	if _combat_system == null:
		return
	var raycast_data: Dictionary = _build_camera_raycast_data()
	var from_variant: Variant = raycast_data.get("origin", global_position)
	var direction_variant: Variant = raycast_data.get("direction", -global_transform.basis.z)
	var from: Vector3 = from_variant if from_variant is Vector3 else global_position
	var direction: Vector3 = direction_variant if direction_variant is Vector3 else -global_transform.basis.z
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	_combat_system.call("raycast_attack", self, from, direction, space_state, [self], attack_distance)

func _try_interact() -> void:
	var hit: Dictionary = _raycast(attack_distance)
	if hit.is_empty():
		return
	var collider_variant: Variant = hit.get("collider")
	if collider_variant is Node:
		var collider_node: Node = collider_variant as Node
		if collider_node != null and collider_node.has_method("interact"):
			var interacted_variant: Variant = collider_node.call("interact", self)
			if bool(interacted_variant):
				return
		if collider_node != null:
			var collider_parent: Node = collider_node.get_parent()
			if collider_parent != null and collider_parent.has_method("interact"):
				var parent_interacted_variant: Variant = collider_parent.call("interact", self)
				if bool(parent_interacted_variant):
					return

func _try_pickup_interaction() -> bool:
	if _loot_system == null or not _loot_system.has_method("pickup_loot"):
		return false
	if _interaction_pickup == null or not is_instance_valid(_interaction_pickup):
		_interaction_pickup = _find_nearest_pickup(PICKUP_INTERACT_RADIUS)
		if _interaction_pickup == null:
			return false
	var picked_variant: Variant = _loot_system.call("pickup_loot", _interaction_pickup, self)
	var picked: bool = bool(picked_variant)
	if picked:
		_interaction_pickup = null
		_set_interaction_prompt(false)
	return picked

func _try_harvest_from_attack(collider: Object) -> bool:
	if _world_system == null:
		return false
	if not _world_system.has_method("harvest_resource_from_collider_with_tool"):
		return false
	var result_variant: Variant = _world_system.call("harvest_resource_from_collider_with_tool", collider, self, _build_tool_context())
	return bool(result_variant)

func _raycast(distance: float) -> Dictionary:
	var raycast_data: Dictionary = _build_camera_raycast_data()
	var from_variant: Variant = raycast_data.get("origin", global_position)
	var direction_variant: Variant = raycast_data.get("direction", -global_transform.basis.z)
	var from: Vector3 = from_variant if from_variant is Vector3 else global_position
	var direction: Vector3 = direction_variant if direction_variant is Vector3 else -global_transform.basis.z
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from + direction.normalized() * distance)
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func _build_camera_raycast_data() -> Dictionary:
	var from: Vector3 = global_position + Vector3(0.0, 1.6, 0.0)
	var direction: Vector3 = -global_transform.basis.z
	if _camera != null:
		from = _camera.global_position
		direction = -_camera.global_transform.basis.z
	return {
		"origin": from,
		"direction": direction
	}

func _cache_view_nodes() -> void:
	var head_node: Node = get_node_or_null("PlayerHead")
	_player_head = head_node as Node3D
	var camera_node: Node = get_node_or_null("PlayerHead/Camera3D")
	_camera = camera_node as Camera3D
	if _camera != null:
		_camera.current = true
	if _player_head != null:
		_camera_pitch = _player_head.rotation.x

func _ensure_components() -> void:
	_movement_component = _get_or_create_component("MovementComponent", "res://core/components/movement_component.gd") as MovementComponent
	_health_component = _get_or_create_component("HealthComponent", "res://core/components/health_component.gd") as HealthComponent
	_damage_component = _get_or_create_component("DamageComponent", "res://core/components/damage_component.gd") as DamageComponent
	_inventory_component = _get_or_create_component("InventoryComponent", "res://core/components/inventory_component.gd") as InventoryComponent
	_ability_component = _get_or_create_component("AbilityComponent", "res://core/components/ability_component.gd") as AbilityComponent
	_ability_manager = _get_or_create_component("AbilityManager", "res://abilities/ability_manager.gd") as AbilityManager
	_player_economy = _get_or_create_component("PlayerEconomy", "res://core/components/player_economy.gd") as PlayerEconomy
	if _movement_component != null:
		_movement_component.move_speed = BASE_MOVE_SPEED
		var jump_multiplier: float = 1.0 + (_permanent_jump_bonus_percent / 100.0)
		_movement_component.jump_velocity = BASE_JUMP_VELOCITY * jump_multiplier
	if _health_component != null:
		_health_component.max_health = 100.0
		_health_component.reset_health()
	if _damage_component != null:
		_damage_component.base_damage = 18.0
	if _player_economy != null:
		gold = _player_economy.gold
	_try_bind_inventory_system()

func _bind_health_signals() -> void:
	if _health_component == null:
		return
	var died_callback: Callable = Callable(self, "_on_player_died")
	if not _health_component.died.is_connected(died_callback):
		_health_component.died.connect(died_callback)

func _bind_economy_signals() -> void:
	if _player_economy == null:
		return
	var callback: Callable = Callable(self, "_on_gold_changed")
	if not _player_economy.gold_changed.is_connected(callback):
		_player_economy.gold_changed.connect(callback)
	gold = _player_economy.gold

func _on_gold_changed(old_value: int, new_value: int) -> void:
	gold = new_value
	gold_changed.emit(old_value, new_value)

func _on_player_died(_entity: Node) -> void:
	if _is_dead:
		return
	_is_dead = true
	_respawn_time_left = RESPAWN_DELAY_SECONDS
	_set_water_tint(0.0)
	_set_interaction_prompt(false)
	_interaction_pickup = null
	_drown_timer = 0.0
	_current_speed_multiplier = 1.0
	is_swimming = false
	_is_in_deep_water = false
	visible = false
	velocity = Vector3.ZERO

func _respawn_player() -> void:
	if _health_component == null:
		return
	var respawn_position: Vector3 = global_position
	if _world_system != null and _world_system.has_method("terrain_height"):
		var respawn_height_variant: Variant = _world_system.call("terrain_height", 0.0, 0.0)
		if typeof(respawn_height_variant) == TYPE_FLOAT or typeof(respawn_height_variant) == TYPE_INT:
			var respawn_height: float = float(respawn_height_variant)
			respawn_position = Vector3(0.0, respawn_height + 2.0, 0.0)
	global_position = respawn_position
	velocity = Vector3.ZERO
	_is_dead = false
	_respawn_time_left = 0.0
	visible = true
	_health_component.reset_health()

func _update_water_effects(delta: float) -> void:
	if _world_system == null:
		is_swimming = false
		_is_in_deep_water = false
		_current_speed_multiplier = 1.0
		_set_water_tint(0.0)
		_drown_timer = 0.0
		return
	var underwater: bool = false
	var deep_water: bool = false
	if _world_system.has_method("is_position_underwater"):
		var underwater_variant: Variant = _world_system.call("is_position_underwater", global_position)
		underwater = bool(underwater_variant)
	if _world_system.has_method("is_position_in_deep_water"):
		var deep_water_variant: Variant = _world_system.call("is_position_in_deep_water", global_position)
		deep_water = bool(deep_water_variant)
	is_swimming = underwater
	_is_in_deep_water = deep_water

	if deep_water:
		_current_speed_multiplier = DEEP_WATER_SLOWDOWN_MULTIPLIER
		_set_water_tint(0.65)
		_drown_timer += delta
		if _drown_timer >= DROWNING_INTERVAL_SECONDS:
			_drown_timer -= DROWNING_INTERVAL_SECONDS
			if _health_component != null:
				_health_component.apply_damage(DROWNING_DAMAGE_PER_TICK, self)
	elif underwater:
		_current_speed_multiplier = WATER_SLOWDOWN_MULTIPLIER
		_set_water_tint(0.35)
		_drown_timer = 0.0
	else:
		_current_speed_multiplier = 1.0
		_set_water_tint(0.0)
		_drown_timer = 0.0

func _apply_swim_buoyancy(delta: float) -> void:
	if not is_swimming or is_on_floor():
		return
	var water_level: float = 0.0
	if _world_system != null and _world_system.has_method("get_water_level"):
		var water_level_variant: Variant = _world_system.call("get_water_level")
		if typeof(water_level_variant) == TYPE_FLOAT or typeof(water_level_variant) == TYPE_INT:
			water_level = float(water_level_variant)
	var depth: float = water_level - global_position.y
	var buoyancy: float = SWIM_BUOYANCY_ACCEL
	if _is_in_deep_water:
		buoyancy *= 1.15
	if depth > 0.0:
		buoyancy += minf(depth * 1.6, 4.5)
	velocity.y += buoyancy * delta
	if velocity.y < SWIM_MAX_SINK_SPEED:
		velocity.y = SWIM_MAX_SINK_SPEED
	var target_surface_y: float = water_level + SWIM_SURFACE_TARGET_OFFSET
	if global_position.y < target_surface_y and velocity.y < 0.2:
		velocity.y = 0.2

func _set_water_tint(intensity: float) -> void:
	if _world_system != null and _world_system.has_method("set_water_tint"):
		_world_system.call("set_water_tint", intensity)

func _enforce_world_boundary() -> void:
	if _world_system == null or not _world_system.has_method("clamp_position_to_world"):
		return
	var clamped_position_variant: Variant = _world_system.call("clamp_position_to_world", global_position)
	if not (clamped_position_variant is Vector3):
		return
	var clamped_position: Vector3 = clamped_position_variant
	if clamped_position.distance_squared_to(global_position) <= 0.0001:
		return
	global_position = clamped_position
	velocity.x = 0.0
	velocity.z = 0.0

func _get_or_create_component(node_name: String, script_path: String) -> Node:
	var existing: Node = get_node_or_null(node_name)
	if existing != null:
		return existing
	var component_script: Script = load(script_path)
	if component_script == null:
		return Node.new()
	var component_variant: Variant = component_script.new()
	if not (component_variant is Node):
		return Node.new()
	var component: Node = component_variant as Node
	if component == null:
		return Node.new()
	component.name = node_name
	add_child(component)
	return component

func _ensure_visuals() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = 0.45
		capsule.height = 1.4
		collider.shape = capsule
		add_child(collider)
	_ensure_character_model_visual()
	var head: Node3D = get_node_or_null("PlayerHead") as Node3D
	if head == null:
		head = Node3D.new()
		head.name = "PlayerHead"
		add_child(head)
	head.position = Vector3(0.0, first_person_eye_height, 0.0)
	if get_node_or_null("PlayerHead/Camera3D") == null:
		var camera: Camera3D = Camera3D.new()
		camera.name = "Camera3D"
		camera.position = Vector3(0.0, 0.0, 0.0)
		camera.current = true
		get_node("PlayerHead").add_child(camera)

func _ensure_character_model_visual() -> void:
	var existing_model: Node3D = get_node_or_null("CharacterModel") as Node3D
	if existing_model != null:
		_player_model_root = existing_model
		_fit_model_to_capsule(_player_model_root)
		_player_model_root.rotation_degrees.y = player_model_yaw_offset_degrees
		_player_model_anim = _find_animation_player_recursive(_player_model_root)
		_resolved_run_animation = _resolve_run_animation_name(_player_model_anim)
		var fallback_visual_existing: Node = get_node_or_null("Visual")
		if fallback_visual_existing != null:
			fallback_visual_existing.queue_free()
		return
	var model_scene: PackedScene = _load_player_model_scene()
	if model_scene == null:
		_ensure_fallback_capsule_visual()
		return
	var model_variant: Variant = model_scene.instantiate()
	var model_root: Node3D = model_variant as Node3D
	if model_root == null:
		_ensure_fallback_capsule_visual()
		return
	model_root.name = "CharacterModel"
	add_child(model_root)
	_player_model_root = model_root
	_fit_model_to_capsule(_player_model_root)
	_player_model_root.rotation_degrees.y = player_model_yaw_offset_degrees
	_player_model_anim = _find_animation_player_recursive(_player_model_root)
	_resolved_run_animation = _resolve_run_animation_name(_player_model_anim)
	if _player_model_anim != null and not _resolved_run_animation.is_empty():
		_player_model_anim.play(_resolved_run_animation)
		_player_model_anim.pause()
	var fallback_visual: Node = get_node_or_null("Visual")
	if fallback_visual != null:
		fallback_visual.queue_free()

func _ensure_fallback_capsule_visual() -> void:
	_player_model_root = null
	_player_model_anim = null
	_resolved_run_animation = &""
	if get_node_or_null("Visual") != null:
		return
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.name = "Visual"
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = 0.45
	mesh.height = 1.4
	visual.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.45, 0.95, 1.0)
	material.roughness = 0.4
	visual.material_override = material
	add_child(visual)

func _load_player_model_scene() -> PackedScene:
	if player_model_scene_path.is_empty():
		return null
	var loaded: Resource = load(player_model_scene_path)
	return loaded as PackedScene

func _fit_model_to_capsule(model_root: Node3D) -> void:
	if model_root == null:
		return
	var model_aabb: AABB = _compute_model_aabb(model_root)
	if model_aabb.size.y <= 0.0001:
		model_root.position = Vector3(0.0, player_model_vertical_offset, 0.0)
		return
	var target_height: float = maxf(player_model_target_height, 0.1)
	var auto_scale: float = (target_height / model_aabb.size.y) * maxf(player_model_height_scale_multiplier, 0.001)
	model_root.scale = Vector3.ONE * auto_scale
	model_aabb = _compute_model_aabb(model_root)
	model_root.position = Vector3(0.0, -model_aabb.position.y + player_model_vertical_offset, 0.0)

func _compute_model_aabb(root: Node3D) -> AABB:
	var has_any_mesh: bool = false
	var combined: AABB = AABB()
	for child_variant in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = child_variant as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var local_aabb: AABB = mesh_node.mesh.get_aabb()
		var world_transform: Transform3D = root.global_transform.affine_inverse() * mesh_node.global_transform
		var transformed: AABB = _transform_aabb(local_aabb, world_transform)
		if not has_any_mesh:
			combined = transformed
			has_any_mesh = true
		else:
			combined = combined.merge(transformed)
	return combined if has_any_mesh else AABB(Vector3.ZERO, Vector3.ONE)

func _transform_aabb(local_aabb: AABB, transform: Transform3D) -> AABB:
	var p0: Vector3 = local_aabb.position
	var s: Vector3 = local_aabb.size
	var corners: Array[Vector3] = [
		p0,
		p0 + Vector3(s.x, 0.0, 0.0),
		p0 + Vector3(0.0, s.y, 0.0),
		p0 + Vector3(0.0, 0.0, s.z),
		p0 + Vector3(s.x, s.y, 0.0),
		p0 + Vector3(s.x, 0.0, s.z),
		p0 + Vector3(0.0, s.y, s.z),
		p0 + s
	]
	var first_point: Vector3 = transform * corners[0]
	var result: AABB = AABB(first_point, Vector3.ZERO)
	for corner in corners:
		result = result.expand(transform * corner)
	return result

func _find_animation_player_recursive(root: Node) -> AnimationPlayer:
	if root == null:
		return null
	var direct: AnimationPlayer = root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if direct != null:
		return direct
	for child_variant in root.find_children("*", "AnimationPlayer", true, false):
		var anim_player: AnimationPlayer = child_variant as AnimationPlayer
		if anim_player != null:
			return anim_player
	return null

func _resolve_run_animation_name(anim_player: AnimationPlayer) -> StringName:
	if anim_player == null:
		return &""
	if not run_animation_name.is_empty() and anim_player.has_animation(run_animation_name):
		return run_animation_name
	for fallback_name_variant in run_animation_fallback_names:
		var fallback_name: StringName = StringName(String(fallback_name_variant))
		if anim_player.has_animation(fallback_name):
			return fallback_name
	var animation_list: PackedStringArray = anim_player.get_animation_list()
	if animation_list.is_empty():
		return &""
	return StringName(animation_list[0])

func _update_player_model_animation_state() -> void:
	if _player_model_anim == null or _resolved_run_animation.is_empty():
		return
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var is_moving: bool = horizontal_speed > model_move_speed_threshold and not _is_dead
	if not is_moving:
		if _player_model_anim.is_playing():
			_player_model_anim.pause()
			_player_model_anim.seek(0.0, true)
		return
	if _player_model_anim.current_animation != _resolved_run_animation:
		_player_model_anim.play(_resolved_run_animation, 0.08)
	elif not _player_model_anim.is_playing():
		_player_model_anim.play(_resolved_run_animation, 0.08)
	var normalized_speed: float = clampf(horizontal_speed / maxf(BASE_MOVE_SPEED, 0.01), 0.65, 1.5)
	_player_model_anim.speed_scale = normalized_speed * maxf(run_animation_speed_multiplier, 0.05)

func _ensure_input_map() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("interact", KEY_E)
	_add_mouse_button_action("attack", MOUSE_BUTTON_LEFT)
	_add_key_action("hotbar_1", KEY_1)
	_add_key_action("hotbar_2", KEY_2)
	_add_key_action("hotbar_3", KEY_3)
	_add_key_action("hotbar_4", KEY_4)
	_add_key_action("hotbar_5", KEY_5)
	_add_key_action("hotbar_6", KEY_6)
	_add_key_action("hotbar_7", KEY_7)
	_add_key_action("hotbar_8", KEY_8)
	_add_key_action(DROP_ONE_ACTION, KEY_Q)
	_add_key_action(CAMERA_TOGGLE_ACTION, KEY_F3)

func _add_key_action(action_name: StringName, key_code: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if _has_key_binding(action_name, key_code):
		return
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = key_code
	InputMap.action_add_event(action_name, key_event)

func _has_key_binding(action_name: StringName, key_code: int) -> bool:
	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.physical_keycode == key_code:
			return true
	return false

func _add_mouse_button_action(action_name: StringName, button: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event in InputMap.action_get_events(action_name):
		if event is InputEventMouseButton and event.button_index == button:
			return
	var mouse_event: InputEventMouseButton = InputEventMouseButton.new()
	mouse_event.button_index = button
	InputMap.action_add_event(action_name, mouse_event)

func _move_with_inertia(delta: float) -> void:
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, INVENTORY_GROUND_DECELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, INVENTORY_GROUND_DECELERATION * delta)
		if velocity.y < 0.0:
			velocity.y = -0.1
	else:
		var gravity_value: float = 18.0
		if _movement_component != null:
			gravity_value = _movement_component.gravity
		velocity.y -= gravity_value * delta
	_apply_swim_buoyancy(delta)
	move_and_slide()

func _is_inventory_open() -> bool:
	var inventory_nodes: Array = get_tree().get_nodes_in_group("inventory_ui")
	for ui_node_variant in inventory_nodes:
		var ui_control: Control = ui_node_variant as Control
		if ui_control == null:
			continue
		if not ui_control.has_method("is_inventory_panel_open"):
			continue
		var open_variant: Variant = ui_control.call("is_inventory_panel_open")
		if bool(open_variant):
			return true
	return false

func _update_interaction_target() -> void:
	_interaction_pickup = _find_nearest_pickup(PICKUP_INTERACT_RADIUS)
	_set_interaction_prompt(_interaction_pickup != null)

func _find_nearest_pickup(radius: float) -> Node3D:
	if _loot_system != null and _loot_system.has_method("get_nearest_pickup"):
		var nearest_variant: Variant = _loot_system.call("get_nearest_pickup", global_position, radius)
		var nearest_loot: Node3D = nearest_variant as Node3D
		if nearest_loot != null and is_instance_valid(nearest_loot):
			return nearest_loot
	var nearest: Node3D = null
	var best_distance_sq: float = radius * radius
	var loot_nodes: Array = get_tree().get_nodes_in_group("loot_pickup")
	for loot_variant in loot_nodes:
		var loot_node: Node3D = loot_variant as Node3D
		if loot_node == null or not is_instance_valid(loot_node):
			continue
		if not bool(loot_node.get_meta("active", false)):
			continue
		var distance_sq: float = loot_node.global_position.distance_squared_to(global_position)
		if distance_sq > best_distance_sq:
			continue
		best_distance_sq = distance_sq
		nearest = loot_node
	return nearest

func _set_interaction_prompt(visible_prompt: bool) -> void:
	_resolve_interaction_system_refs()
	if _ui_system == null or not _ui_system.has_method("set_interaction_prompt"):
		return
	var text: String = PICKUP_PROMPT_TEXT if visible_prompt else ""
	_ui_system.call("set_interaction_prompt", text, visible_prompt)

func _resolve_interaction_system_refs() -> void:
	if (_loot_system == null or not is_instance_valid(_loot_system)) and _world_system != null and _world_system.has_method("get_loot_system"):
		var loot_system_variant: Variant = _world_system.call("get_loot_system")
		_loot_system = loot_system_variant as Node
	if (_ui_system == null or not is_instance_valid(_ui_system)):
		if _world_system != null and _world_system.has_method("get_ui_system"):
			var ui_system_variant: Variant = _world_system.call("get_ui_system")
			_ui_system = ui_system_variant as Node
		if _ui_system == null:
			_ui_system = get_tree().get_first_node_in_group("ui_system")

func _handle_hotbar_key_input(event: InputEventKey) -> void:
	match event.physical_keycode:
		KEY_1:
			_set_selected_hotbar_index(0)
			return
		KEY_2:
			_set_selected_hotbar_index(1)
			return
		KEY_3:
			_set_selected_hotbar_index(2)
			return
		KEY_4:
			_set_selected_hotbar_index(3)
			return
		KEY_5:
			_set_selected_hotbar_index(4)
			return
		KEY_6:
			_set_selected_hotbar_index(5)
			return
		KEY_7:
			_set_selected_hotbar_index(6)
			return
		KEY_8:
			_set_selected_hotbar_index(7)
			return
		_:
			pass
	for index in range(HOTBAR_SLOT_COUNT):
		var action_name: String = "hotbar_%d" % [index + 1]
		if event.is_action_pressed(action_name):
			_set_selected_hotbar_index(index)
			return

func _set_selected_hotbar_index(slot_index: int) -> void:
	var clamped_index: int = clampi(slot_index, 0, HOTBAR_SLOT_COUNT - 1)
	if _selected_hotbar_index == clamped_index:
		return
	_selected_hotbar_index = clamped_index
	hotbar_slot_selected.emit(_selected_hotbar_index)

func _build_tool_context() -> Dictionary:
	var selected_item: Dictionary = get_selected_hotbar_item()
	var item_id: String = String(selected_item.get("item_id", ""))
	var metadata_variant: Variant = selected_item.get("metadata", {})
	var tool_type: String = ""
	if metadata_variant is Dictionary:
		var metadata: Dictionary = metadata_variant
		tool_type = String(metadata.get("tool_type", ""))
	if tool_type.is_empty():
		if item_id == "axe":
			tool_type = "axe"
		elif item_id == "pickaxe":
			tool_type = "pickaxe"
	return {
		"tool_id": tool_type,
		"item_id": item_id,
		"slot_index": _selected_hotbar_index
	}

func _drop_one_from_selected_hotbar() -> void:
	var extracted: Dictionary = {}
	if _inventory_system != null and _inventory_system.has_method("extract_from_slot"):
		var extracted_variant: Variant = _inventory_system.call("extract_from_slot", _selected_hotbar_index, 1)
		if extracted_variant is Dictionary:
			extracted = Dictionary(extracted_variant)
	if extracted.is_empty():
		var slot_entry: Dictionary = {}
		if _inventory_system != null and _inventory_system.has_method("get_slot"):
			var slot_variant: Variant = _inventory_system.call("get_slot", _selected_hotbar_index)
			if slot_variant is Dictionary:
				slot_entry = Dictionary(slot_variant)
		elif _inventory_component != null and _selected_hotbar_index >= 0 and _selected_hotbar_index < _inventory_component.items.size():
			slot_entry = _inventory_component.items[_selected_hotbar_index].duplicate(true)
		if slot_entry.is_empty():
			return
		var fallback_item_id: String = String(slot_entry.get("id", slot_entry.get("item_id", "")))
		var fallback_amount: int = int(slot_entry.get("amount", 0))
		if fallback_item_id.is_empty() or fallback_amount <= 0:
			return
		extracted = {
			"id": fallback_item_id,
			"amount": 1
		}
		if _inventory_system != null and _inventory_system.has_method("set_slot"):
			if fallback_amount <= 1:
				_inventory_system.call("set_slot", _selected_hotbar_index, {})
			else:
				var next_entry: Dictionary = slot_entry.duplicate(true)
				next_entry["id"] = fallback_item_id
				next_entry["amount"] = fallback_amount - 1
				_inventory_system.call("set_slot", _selected_hotbar_index, next_entry)
	var item_id: String = String(extracted.get("id", extracted.get("item_id", "")))
	var amount: int = int(extracted.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return
	var drop_position: Vector3 = global_position + -global_transform.basis.z * 1.2 + Vector3(0.0, 0.7, 0.0)
	EventBus.emit_game_event("loot_spawn_requested", {
		"position": drop_position,
		"item_id": item_id,
		"amount": amount
	})

func _try_bind_inventory_system() -> void:
	if _inventory_system == null or not _inventory_system.has_method("bind_inventory"):
		return
	if _inventory_component == null:
		return
	_inventory_system.call("bind_inventory", _inventory_component)
