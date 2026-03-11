extends CharacterBody3D
class_name TotemWolf

signal killed(enemy: TotemWolf, killer: Node, gold_reward: int, xp_reward: int, totem_id: StringName)

const REGULAR_ENEMY_STATS_PATH: String = "res://data/enemies/default_enemy.json"

enum WolfState {
	IDLE,
	CHASE,
	CIRCLE,
	ATTACK,
	DEAD
}

@export var max_health: float = 20.0
@export var attack_damage: float = 5.0
@export var gold_reward: int = 10
@export var random_gold_reward_enabled: bool = true
@export var gold_reward_min: int = 3
@export var gold_reward_max: int = 12
@export var xp_reward: int = 1

@export var regular_enemy_speed: float = 3.5
@export var speed_multiplier_vs_regular: float = 1.5
@export var move_speed: float = 5.25
@export var steer_acceleration: float = 10.0
@export var turn_speed: float = 9.0
@export var gravity: float = 20.0

@export var detection_range: float = 16.0
@export var disengage_range: float = 23.0
@export var circle_radius: float = 2.5
@export var circle_strong_distance: float = 3.8
@export var attack_range: float = 1.7
@export var attack_interval: float = 1.5
@export var attack_phase_duration: float = 0.22

@export var navigation_agent_path: NodePath = NodePath("NavigationAgent3D")
@export var health_component_path: NodePath = NodePath("HealthComponent")
@export var damage_component_path: NodePath = NodePath("DamageComponent")

var totem_id: StringName = &""

var _state: WolfState = WolfState.IDLE
var _player: Node3D = null
var _health_component: HealthComponent = null
var _damage_component: DamageComponent = null
var _navigation_agent: NavigationAgent3D = null
var _attack_cooldown_left: float = 0.0
var _attack_phase_left: float = 0.0
var _attack_applied: bool = false
var _circle_side: float = 1.0
var _last_damage_source: Node = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("totem_wolf")
	_ensure_core_nodes()
	_configure_components()
	floor_snap_length = 0.35
	safe_margin = 0.06
	_rng.randomize()
	move_speed = _resolve_regular_enemy_speed() * speed_multiplier_vs_regular
	_circle_side = -1.0 if randf() < 0.5 else 1.0
	_attack_cooldown_left = attack_interval
	EventBus.subscribe("entity_died", Callable(self, "_on_entity_died"))

func setup(player: Node3D, owner_totem_id: StringName) -> void:
	_player = player
	totem_id = owner_totem_id
	_state = WolfState.IDLE
	_attack_cooldown_left = attack_interval
	_attack_phase_left = 0.0
	_attack_applied = false
	visible = true
	set_physics_process(true)
	if _health_component != null:
		_health_component.max_health = max_health
		_health_component.reset_health()

func _physics_process(delta: float) -> void:
	if _state == WolfState.DEAD:
		return
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)

	match _state:
		WolfState.IDLE:
			_tick_idle(delta)
		WolfState.CHASE:
			_tick_chase(delta)
		WolfState.CIRCLE:
			_tick_circle(delta)
		WolfState.ATTACK:
			_tick_attack(delta)

	_apply_gravity(delta)
	move_and_slide()

func _tick_idle(delta: float) -> void:
	_smooth_stop(delta)
	if not _has_valid_player():
		return
	var distance_to_player: float = global_position.distance_to(_player.global_position)
	if distance_to_player <= detection_range:
		_state = WolfState.CHASE

func _tick_chase(delta: float) -> void:
	if not _has_valid_player():
		_state = WolfState.IDLE
		return
	var to_player: Vector3 = _player.global_position - global_position
	var distance_to_player: float = to_player.length()
	if distance_to_player > disengage_range:
		_state = WolfState.IDLE
		return
	if distance_to_player <= attack_range and _attack_cooldown_left <= 0.0:
		_begin_attack()
		return
	if distance_to_player <= circle_strong_distance:
		_state = WolfState.CIRCLE
		return
	var movement_direction: Vector3 = _steer_to_point(_player.global_position)
	_apply_smooth_movement(movement_direction, delta)

func _tick_circle(delta: float) -> void:
	if not _has_valid_player():
		_state = WolfState.IDLE
		return
	var distance_to_player: float = global_position.distance_to(_player.global_position)
	if distance_to_player > disengage_range:
		_state = WolfState.IDLE
		return
	if distance_to_player > circle_strong_distance + 1.5:
		_state = WolfState.CHASE
		return
	if distance_to_player <= attack_range and _attack_cooldown_left <= 0.0:
		_begin_attack()
		return
	var movement_direction: Vector3 = _calculate_circle_direction()
	_apply_smooth_movement(movement_direction, delta)

func _tick_attack(delta: float) -> void:
	_smooth_stop(delta)
	if not _has_valid_player():
		_state = WolfState.IDLE
		return
	var direction_to_player: Vector3 = _player.global_position - global_position
	direction_to_player.y = 0.0
	_rotate_towards(direction_to_player, delta)

	_attack_phase_left -= delta
	if not _attack_applied and _attack_phase_left <= attack_phase_duration * 0.5:
		_try_attack()
		_attack_applied = true
		_attack_cooldown_left = attack_interval
	if _attack_phase_left <= 0.0:
		_state = WolfState.CIRCLE

func _begin_attack() -> void:
	_state = WolfState.ATTACK
	_attack_phase_left = attack_phase_duration
	_attack_applied = false

func _calculate_circle_direction() -> Vector3:
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() <= 0.0001:
		return Vector3.ZERO
	var radial_to_player: Vector3 = to_player.normalized()
	var tangent: Vector3 = Vector3(-radial_to_player.z, 0.0, radial_to_player.x) * _circle_side
	var current_distance: float = to_player.length()
	var radial_adjust: Vector3 = (-radial_to_player) * (current_distance - circle_radius)
	var desired: Vector3 = (tangent + radial_adjust * 0.9).normalized()
	return _steer_to_point(global_position + desired * 2.2)

func _steer_to_point(target_point: Vector3) -> Vector3:
	if _navigation_agent != null:
		_navigation_agent.target_position = target_point
		if not _navigation_agent.is_navigation_finished():
			var next_point: Vector3 = _navigation_agent.get_next_path_position()
			var path_direction: Vector3 = next_point - global_position
			path_direction.y = 0.0
			if path_direction.length_squared() > 0.0001:
				return path_direction.normalized()
	var fallback: Vector3 = target_point - global_position
	fallback.y = 0.0
	return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector3.ZERO

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

func _try_attack() -> void:
	if not _has_valid_player():
		return
	if global_position.distance_to(_player.global_position) > attack_range + 0.5:
		return
	if _damage_component != null:
		_damage_component.deal_damage(_player, self)
		return
	var player_health: HealthComponent = _player.get_node_or_null("HealthComponent") as HealthComponent
	if player_health != null:
		player_health.apply_damage(attack_damage, self)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

func _has_valid_player() -> bool:
	return _player != null and is_instance_valid(_player)

func _resolve_regular_enemy_speed() -> float:
	var parsed_stats: Dictionary = JsonDataLoader.load_dictionary(REGULAR_ENEMY_STATS_PATH)
	if parsed_stats.is_empty():
		return maxf(regular_enemy_speed, 0.1)
	var loaded_speed: float = float(parsed_stats.get("move_speed", regular_enemy_speed))
	return maxf(loaded_speed, 0.1)

func _on_entity_died(payload: Dictionary) -> void:
	if _state == WolfState.DEAD:
		return
	if payload.get("entity", null) != self:
		return
	var source_variant: Variant = payload.get("source", null)
	_last_damage_source = source_variant as Node
	_state = WolfState.DEAD
	velocity = Vector3.ZERO
	set_physics_process(false)
	var resolved_gold_reward: int = _resolve_gold_reward()

	EventBus.emit_game_event("loot_spawn_requested", {
		"position": global_position + Vector3(0.0, 0.55, 0.0),
		"item_id": "essence",
		"amount": maxi(xp_reward, 1)
	})
	EventBus.emit_game_event("enemy_killed", {
		"enemy_type": "totem_wolf",
		"killer": _last_damage_source,
		"gold_reward": resolved_gold_reward,
		"xp_reward": xp_reward,
		"totem_id": String(totem_id),
		"position": global_position
	})
	killed.emit(self, _last_damage_source, resolved_gold_reward, xp_reward, totem_id)
	queue_free()

func _resolve_gold_reward() -> int:
	if not random_gold_reward_enabled:
		return maxi(gold_reward, 0)
	var reward_min: int = mini(gold_reward_min, gold_reward_max)
	var reward_max: int = maxi(gold_reward_min, gold_reward_max)
	return _rng.randi_range(reward_min, reward_max)

func _ensure_core_nodes() -> void:
	_navigation_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "NavigationAgent3D"
		add_child(_navigation_agent)
		navigation_agent_path = NodePath("NavigationAgent3D")
	if get_node_or_null("CollisionShape3D") == null:
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var shape: CapsuleShape3D = CapsuleShape3D.new()
		shape.radius = 0.42
		shape.height = 1.25
		collision.shape = shape
		add_child(collision)
	if get_node_or_null("Visual") == null:
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = "Visual"
		var mesh: CapsuleMesh = CapsuleMesh.new()
		mesh.radius = 0.42
		mesh.height = 1.25
		visual.mesh = mesh
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.33, 0.31, 0.64, 1.0)
		material.emission_enabled = true
		material.emission = Color(0.24, 0.32, 0.68, 1.0)
		material.emission_energy_multiplier = 0.3
		material.roughness = 0.42
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
