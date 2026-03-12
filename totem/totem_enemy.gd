extends CharacterBody3D
class_name TotemEnemy

signal killed(enemy: TotemEnemy, killer: Node, gold_reward: int, totem_id: StringName)
const WORLD_HEALTH_BAR_SCRIPT: Script = preload("res://ui/world_health_bar_3d.gd")
const DEBUG_TOTEM_ENEMY_DIAGNOSTICS: bool = true

enum EnemyState {
	IDLE,
	CIRCLE_PLAYER,
	ATTACK,
	DEAD
}

@export var max_health: float = 20.0
@export var attack_damage: float = 5.0
@export var gold_reward: int = 10

@export var detection_range: float = 14.0
@export var disengage_range: float = 21.0
@export var attack_range: float = 1.7
@export var attack_interval: float = 2.0
@export var attack_phase_duration: float = 0.25

@export var move_speed: float = 3.8
@export var steer_acceleration: float = 9.0
@export var turn_speed: float = 8.5
@export var circle_radius_min: float = 2.0
@export var circle_radius_max: float = 3.0
@export var circle_strafe_strength: float = 0.9
@export var gravity: float = 20.0

@export var navigation_agent_path: NodePath = NodePath("NavigationAgent3D")
@export var health_component_path: NodePath = NodePath("HealthComponent")
@export var damage_component_path: NodePath = NodePath("DamageComponent")

var totem_id: StringName = &""

var _state: EnemyState = EnemyState.IDLE
var _player: Node3D = null
var _health_component: HealthComponent = null
var _damage_component: DamageComponent = null
var _navigation_agent: NavigationAgent3D = null
var _health_bar: Node3D = null
var _attack_cooldown_left: float = 0.0
var _attack_phase_left: float = 0.0
var _attack_hit_applied: bool = false
var _circle_side: float = 1.0
var _last_damage_source: Node = null

func _ready() -> void:
	add_to_group("enemy")
	_ensure_core_nodes()
	_configure_components()
	_ensure_health_bar()
	_circle_side = -1.0 if randf() < 0.5 else 1.0
	_attack_cooldown_left = attack_interval
	var subscribed: bool = EventBus.subscribe("entity_died", Callable(self, "_on_entity_died"))
	_log("spawn: subscribed=%s" % str(subscribed))

func _exit_tree() -> void:
	var unsubscribed: bool = false
	if EventBus != null and EventBus.has_method("unsubscribe"):
		unsubscribed = bool(EventBus.call("unsubscribe", "entity_died", Callable(self, "_on_entity_died")))
	_log("_exit_tree: unsubscribed=%s" % str(unsubscribed))

func setup(player: Node3D, owner_totem_id: StringName) -> void:
	_player = player
	totem_id = owner_totem_id
	_state = EnemyState.IDLE
	_attack_cooldown_left = attack_interval
	_attack_phase_left = 0.0
	_attack_hit_applied = false
	visible = true
	set_physics_process(true)
	if _health_component != null:
		_health_component.max_health = max_health
		_health_component.reset_health()
		if _health_bar != null and _health_bar.has_method("bind_health_component"):
			_health_bar.call("bind_health_component", _health_component)

func _physics_process(delta: float) -> void:
	if _state == EnemyState.DEAD:
		return
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)

	match _state:
		EnemyState.IDLE:
			_tick_idle(delta)
		EnemyState.CIRCLE_PLAYER:
			_tick_circle_player(delta)
		EnemyState.ATTACK:
			_tick_attack(delta)

	_apply_gravity(delta)
	move_and_slide()

func _tick_idle(delta: float) -> void:
	_smooth_stop(delta)
	if not _has_valid_player():
		return
	var distance_to_player: float = global_position.distance_to(_player.global_position)
	if distance_to_player <= detection_range:
		_state = EnemyState.CIRCLE_PLAYER

func _tick_circle_player(delta: float) -> void:
	if not _has_valid_player():
		_state = EnemyState.IDLE
		return
	var distance_to_player: float = global_position.distance_to(_player.global_position)
	if distance_to_player > disengage_range:
		_state = EnemyState.IDLE
		return
	if distance_to_player <= attack_range and _attack_cooldown_left <= 0.0:
		_state = EnemyState.ATTACK
		_attack_phase_left = attack_phase_duration
		_attack_hit_applied = false
		return

	var movement_direction: Vector3 = _calculate_circle_movement_direction()
	_apply_smooth_movement(movement_direction, delta)

func _tick_attack(delta: float) -> void:
	_smooth_stop(delta)
	if not _has_valid_player():
		_state = EnemyState.IDLE
		return
	var direction_to_player: Vector3 = _player.global_position - global_position
	direction_to_player.y = 0.0
	_rotate_towards(direction_to_player, delta)

	_attack_phase_left -= delta
	if not _attack_hit_applied and _attack_phase_left <= attack_phase_duration * 0.5:
		_try_deal_attack_damage()
		_attack_hit_applied = true
		_attack_cooldown_left = attack_interval
	if _attack_phase_left <= 0.0:
		_state = EnemyState.CIRCLE_PLAYER

func _calculate_circle_movement_direction() -> Vector3:
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() <= 0.0001:
		return Vector3.ZERO
	var radial_to_player: Vector3 = to_player.normalized()
	var radial_from_player: Vector3 = -radial_to_player

	var tangent: Vector3 = Vector3(-radial_to_player.z, 0.0, radial_to_player.x) * _circle_side
	var current_distance: float = to_player.length()
	var target_radius: float = clampf(current_distance, circle_radius_min, circle_radius_max)
	var radius_error: float = current_distance - target_radius
	var radial_correction: Vector3 = radial_from_player * radius_error * 0.9

	var desired_direction: Vector3 = (tangent * circle_strafe_strength) + radial_correction
	desired_direction.y = 0.0
	if desired_direction.length_squared() <= 0.0001:
		desired_direction = tangent
	desired_direction = desired_direction.normalized()

	if _navigation_agent != null:
		var desired_point: Vector3 = global_position + desired_direction * 2.0
		_navigation_agent.target_position = desired_point
		if not _navigation_agent.is_navigation_finished():
			var next_path_position: Vector3 = _navigation_agent.get_next_path_position()
			var path_direction: Vector3 = next_path_position - global_position
			path_direction.y = 0.0
			if path_direction.length_squared() > 0.0001:
				return path_direction.normalized()
	return desired_direction

func _apply_smooth_movement(direction: Vector3, delta: float) -> void:
	var desired_velocity: Vector3 = direction * move_speed
	var blend: float = clampf(steer_acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, desired_velocity.x, blend)
	velocity.z = lerpf(velocity.z, desired_velocity.z, blend)
	_rotate_towards(direction, delta)

func _smooth_stop(delta: float) -> void:
	var blend: float = clampf(steer_acceleration * delta, 0.0, 1.0)
	velocity.x = lerpf(velocity.x, 0.0, blend)
	velocity.z = lerpf(velocity.z, 0.0, blend)

func _rotate_towards(direction: Vector3, delta: float) -> void:
	var flat_direction: Vector3 = direction
	flat_direction.y = 0.0
	if flat_direction.length_squared() <= 0.0001:
		return
	var target_yaw: float = atan2(flat_direction.x, flat_direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, turn_speed * delta)

func _try_deal_attack_damage() -> void:
	if not _has_valid_player():
		return
	if global_position.distance_to(_player.global_position) > attack_range + 0.5:
		return
	if _damage_component != null:
		_damage_component.deal_damage(_player, self)
		return
	var health_node: Node = _player.get_node_or_null("HealthComponent")
	var player_health: HealthComponent = health_node as HealthComponent
	if player_health != null:
		player_health.apply_damage(attack_damage, self)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

func _has_valid_player() -> bool:
	return _player != null and is_instance_valid(_player)

func _on_entity_died(payload: Dictionary) -> void:
	if _state == EnemyState.DEAD:
		return
	if payload.get("entity", null) != self:
		return
	var source_variant: Variant = payload.get("source", null)
	_last_damage_source = source_variant as Node
	_state = EnemyState.DEAD
	velocity = Vector3.ZERO
	set_physics_process(false)

	killed.emit(self, _last_damage_source, gold_reward, totem_id)
	_log("queue_free requested")
	EventBus.emit_game_event("enemy_killed", {
		"enemy_type": "totem_enemy",
		"killer": _last_damage_source,
		"gold_reward": gold_reward,
		"totem_id": String(totem_id),
		"position": global_position
	})
	queue_free()

func _log(message: String) -> void:
	if not DEBUG_TOTEM_ENEMY_DIAGNOSTICS:
		return
	print("[TotemEnemy#", get_instance_id(), "] ", message)

func _ensure_core_nodes() -> void:
	_navigation_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "NavigationAgent3D"
		add_child(_navigation_agent)
		navigation_agent_path = NodePath("NavigationAgent3D")
	if get_node_or_null("CollisionShape3D") == null:
		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
		capsule_shape.radius = 0.4
		capsule_shape.height = 1.3
		collision_shape.shape = capsule_shape
		add_child(collision_shape)
	if get_node_or_null("Visual") == null:
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = "Visual"
		var mesh: CapsuleMesh = CapsuleMesh.new()
		mesh.radius = 0.4
		mesh.height = 1.3
		visual.mesh = mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.95, 0.31, 0.22, 1.0)
		material.roughness = 0.55
		visual.material_override = material
		add_child(visual)

func _configure_components() -> void:
	_health_component = get_node_or_null(health_component_path) as HealthComponent
	if _health_component == null:
		_health_component = _get_or_create_component("HealthComponent", "res://core/components/health_component.gd") as HealthComponent
		health_component_path = NodePath("HealthComponent")
	_damage_component = get_node_or_null(damage_component_path) as DamageComponent
	if _damage_component == null:
		_damage_component = _get_or_create_component("DamageComponent", "res://core/components/damage_component.gd") as DamageComponent
		damage_component_path = NodePath("DamageComponent")
	if _health_component != null:
		_health_component.max_health = max_health
		_health_component.reset_health()
	if _damage_component != null:
		_damage_component.base_damage = attack_damage
	if _health_bar != null and _health_bar.has_method("bind_health_component"):
		_health_bar.call("bind_health_component", _health_component)

func _get_or_create_component(node_name: String, script_path: String) -> Node:
	var existing: Node = get_node_or_null(node_name)
	if existing != null:
		return existing
	var script_resource: Script = load(script_path)
	if script_resource == null:
		return null
	var component_variant: Variant = script_resource.new()
	if not (component_variant is Node):
		return null
	var component: Node = component_variant as Node
	if component == null:
		return null
	component.name = node_name
	add_child(component)
	return component

func _ensure_health_bar() -> void:
	var existing: Node3D = get_node_or_null("HealthBar3D") as Node3D
	if existing != null:
		_health_bar = existing
	else:
		var bar_variant: Variant = WORLD_HEALTH_BAR_SCRIPT.new()
		var bar_node: Node3D = bar_variant as Node3D
		if bar_node == null:
			return
		bar_node.name = "HealthBar3D"
		add_child(bar_node)
		_health_bar = bar_node
	if _health_bar != null:
		if _health_bar.has_method("bind_health_component"):
			_health_bar.call("bind_health_component", _health_component)
