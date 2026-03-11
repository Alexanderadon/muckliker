extends StaticBody3D
class_name Totem

signal activated(totem_id: StringName)
signal completed(totem_id: StringName)

enum TotemState {
	READY,
	ACTIVE,
	COMPLETED
}

@export var totem_id: StringName = &""
@export var wolf_scene: PackedScene = preload("res://totem/totem_wolf.tscn")
@export var ability_capsule_scene: PackedScene = preload("res://abilities/ability_capsule.tscn")
@export var spawn_radius: float = 2.5
@export var completion_gold_bonus: int = 20
@export var reward_item_id: String = ""
@export var reward_item_amount: int = 0
@export var break_animation_duration: float = 0.42
@export var ability_capsule_spawn_height: float = 0.7
@export var wolf_spawn_height_offset: float = 1.0
@export var ground_probe_up: float = 24.0
@export var ground_probe_down: float = 72.0

var _state: TotemState = TotemState.READY
var _active_enemies: Dictionary = {}
var _activator: Node = null
var _is_breaking: bool = false

func _ready() -> void:
	add_to_group("totem")
	if String(totem_id).is_empty():
		totem_id = StringName("totem_%s" % str(get_instance_id()))
	_ensure_visuals()
	_apply_state_visuals()

func set_totem_id(value: StringName) -> void:
	totem_id = value

func interact(interactor: Node) -> bool:
	if _state != TotemState.READY or _is_breaking:
		return false
	if interactor == null or not is_instance_valid(interactor):
		return false
	_activate(interactor)
	return true

func _activate(interactor: Node) -> void:
	_state = TotemState.ACTIVE
	_activator = interactor
	_spawn_wave()
	_apply_state_visuals()
	activated.emit(totem_id)
	EventBus.emit_game_event("totem_activated", {
		"totem_id": String(totem_id),
		"position": global_position
	})
	if _active_enemies.is_empty():
		_start_completion_sequence()
		return

func _spawn_wave() -> void:
	if wolf_scene == null:
		push_warning("Totem has no wolf_scene assigned.")
		return
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var shared_xp_reward: int = _resolve_regular_enemy_xp_reward()
	# Triangle formation: exactly three wolves.
	for angle in [0.0, 120.0, 240.0]:
		var wolf_variant: Variant = wolf_scene.instantiate()
		var wolf: TotemWolf = wolf_variant as TotemWolf
		if wolf == null:
			continue
		wolf.xp_reward = shared_xp_reward
		parent_node.add_child(wolf)
		wolf.global_position = _build_triangle_spawn_position(angle)
		wolf.setup(_activator as Node3D, totem_id)
		wolf.killed.connect(Callable(self, "_on_enemy_killed"))
		_active_enemies[wolf.get_instance_id()] = true

func _resolve_regular_enemy_xp_reward() -> int:
	var tree_ref: SceneTree = get_tree()
	if tree_ref == null:
		return 1
	if tree_ref.current_scene != null:
		var from_scene: Node = tree_ref.current_scene.find_child("EnemySystem", true, false)
		if from_scene != null:
			var scene_reward_variant: Variant = from_scene.get("enemy_xp_reward")
			if scene_reward_variant != null:
				return maxi(int(scene_reward_variant), 1)
	var root_node: Node = tree_ref.root
	if root_node != null:
		var from_root: Node = root_node.find_child("EnemySystem", true, false)
		if from_root != null:
			var root_reward_variant: Variant = from_root.get("enemy_xp_reward")
			if root_reward_variant != null:
				return maxi(int(root_reward_variant), 1)
	return 1

func _build_triangle_spawn_position(angle_degrees: float) -> Vector3:
	var angle_rad: float = deg_to_rad(angle_degrees)
	var offset: Vector3 = Vector3(cos(angle_rad), 0.0, sin(angle_rad)) * spawn_radius
	var position: Vector3 = global_position + offset
	return _project_position_to_ground(position, wolf_spawn_height_offset)

func _on_enemy_killed(enemy: TotemWolf, _killer: Node, _gold_reward: int, _xp_reward: int, enemy_totem_id: StringName) -> void:
	if enemy_totem_id != totem_id:
		return
	if enemy != null:
		_active_enemies.erase(enemy.get_instance_id())
	if _active_enemies.is_empty():
		_start_completion_sequence()

func _start_completion_sequence() -> void:
	if _state == TotemState.COMPLETED or _is_breaking:
		return
	_state = TotemState.COMPLETED
	_is_breaking = true
	var collision: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null:
		collision.disabled = true
	_apply_state_visuals()
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), maxf(break_animation_duration, 0.08))
	tween.parallel().tween_property(self, "rotation:y", rotation.y + 0.85, maxf(break_animation_duration, 0.08))
	await tween.finished
	_spawn_ability_capsule()
	EventBus.emit_game_event("totem_completed", {
		"totem_id": String(totem_id),
		"activator": _activator,
		"bonus_gold": completion_gold_bonus
	})
	if not reward_item_id.is_empty() and reward_item_amount > 0:
		EventBus.emit_game_event("loot_spawn_requested", {
			"position": global_position + Vector3(0.0, 0.9, 0.0),
			"item_id": reward_item_id,
			"amount": reward_item_amount
		})
	completed.emit(totem_id)
	queue_free()

func _spawn_ability_capsule() -> void:
	if ability_capsule_scene == null:
		return
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var capsule_variant: Variant = ability_capsule_scene.instantiate()
	var capsule: Node3D = capsule_variant as Node3D
	if capsule == null:
		return
	var spawn_position: Vector3 = _project_position_to_ground(global_position, ability_capsule_spawn_height)
	if capsule.has_method("set_spawn_world_position"):
		capsule.call("set_spawn_world_position", spawn_position)
	parent_node.add_child(capsule)
	capsule.global_position = spawn_position

func _project_position_to_ground(world_position: Vector3, height_offset: float) -> Vector3:
	var position: Vector3 = world_position
	if not is_inside_tree() or get_world_3d() == null:
		position.y += height_offset
		return position
	var from: Vector3 = world_position + Vector3(0.0, ground_probe_up, 0.0)
	var to: Vector3 = world_position - Vector3(0.0, ground_probe_down, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [self]
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var hit_position_variant: Variant = result.get("position")
	if hit_position_variant is Vector3:
		var hit_position: Vector3 = hit_position_variant
		position.y = hit_position.y + height_offset
		return position
	position.y = global_position.y + height_offset
	return position

func _ensure_visuals() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape: CylinderShape3D = CylinderShape3D.new()
		shape.radius = 0.9
		shape.height = 2.2
		collision.shape = shape
		add_child(collision)
	if get_node_or_null("Visual") == null:
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = "Visual"
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = 0.45
		mesh.bottom_radius = 0.55
		mesh.height = 2.2
		visual.mesh = mesh
		add_child(visual)

func _apply_state_visuals() -> void:
	var visual: MeshInstance3D = get_node_or_null("Visual") as MeshInstance3D
	if visual == null:
		return
	var material: StandardMaterial3D = visual.material_override as StandardMaterial3D
	if material == null:
		material = StandardMaterial3D.new()
		visual.material_override = material
	match _state:
		TotemState.READY:
			material.albedo_color = Color(0.26, 0.58, 0.96, 1.0)
		TotemState.ACTIVE:
			material.albedo_color = Color(0.93, 0.36, 0.16, 1.0)
		TotemState.COMPLETED:
			material.albedo_color = Color(0.3, 0.82, 0.38, 1.0)
