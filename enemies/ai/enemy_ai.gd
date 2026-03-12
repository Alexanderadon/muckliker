extends CharacterBody3D
class_name EnemyAI

const ENEMY_STATS_PATH: String = "res://data/enemies/default_enemy.json"
const WORLD_HEALTH_BAR_SCRIPT: Script = preload("res://ui/world_health_bar_3d.gd")
const DEFAULT_STATS: Dictionary = {
	"move_speed": 3.5,
	"detect_radius": 12.0,
	"chase_radius": 16.0,
	"lose_target_radius": 20.0,
	"attack_distance": 1.4,
	"attack_interval": 1.0,
	"attack_damage": 1.0,
	"max_health": 40.0
}

@export var move_speed: float = 3.5
@export var detect_radius: float = 12.0
@export var chase_radius: float = 16.0
@export var lose_target_radius: float = 20.0
@export var attack_distance: float = 1.4
@export var attack_interval: float = 1.0
@export var attack_damage: float = 1.0

var state: String = "idle"
var chunk_id: Vector2i = Vector2i.ZERO

var _is_active: bool = false
var _player: Node3D = null
var _combat_system: Node = null
var _time_since_attack: float = 0.0
var _target_locked: bool = false

var _health_component: HealthComponent = null
var _damage_component: DamageComponent = null
var _health_bar: Node3D = null
var _stats: Dictionary = {}

func _ready() -> void:
	add_to_group("enemy")
	_load_stats()
	_ensure_visuals()
	_ensure_components()
	_ensure_health_bar()
	set_active(false)

func _physics_process(delta: float) -> void:
	if not _is_active:
		return
	_time_since_attack += delta
	if _player == null or not is_instance_valid(_player):
		state = "idle"
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()

	if not _target_locked and distance <= detect_radius:
		_target_locked = true
	if _target_locked and distance > lose_target_radius:
		_target_locked = false
		_process_idle_state()
	elif not _target_locked:
		_process_idle_state()
	elif distance <= attack_distance:
		_process_attack_state()
	elif distance <= chase_radius:
		_process_chase_state(to_player, delta)
	else:
		_process_idle_state()

	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	move_and_slide()

func activate(player: Node3D, combat_system: Node, spawn_chunk_id: Vector2i) -> void:
	_player = player
	_combat_system = combat_system
	chunk_id = spawn_chunk_id
	state = "idle"
	_target_locked = false
	_time_since_attack = attack_interval
	velocity = Vector3.ZERO
	visible = true
	set_active(true)
	if _health_component != null:
		_health_component.reset_health()

func deactivate() -> void:
	state = "idle"
	_target_locked = false
	velocity = Vector3.ZERO
	set_active(false)

func is_active() -> bool:
	return _is_active

func set_active(value: bool) -> void:
	_is_active = value
	set_physics_process(value)
	visible = value
	for child in get_children():
		if child is CollisionShape3D:
			child.disabled = not value

func _process_idle_state() -> void:
	state = "idle"
	velocity.x = 0.0
	velocity.z = 0.0

func _process_chase_state(to_player: Vector3, delta: float) -> void:
	state = "chase"
	var direction := to_player.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	var target_yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * 8.0)

func _process_attack_state() -> void:
	state = "attack"
	velocity.x = 0.0
	velocity.z = 0.0
	if _time_since_attack < attack_interval:
		return
	_time_since_attack = 0.0
	if _damage_component != null:
		_damage_component.deal_damage(_player, self)

func _ensure_components() -> void:
	detect_radius = float(_stats.get("detect_radius", 12.0))
	chase_radius = float(_stats.get("chase_radius", 16.0))
	lose_target_radius = float(_stats.get("lose_target_radius", 20.0))
	attack_distance = float(_stats.get("attack_distance", 1.4))
	attack_interval = float(_stats.get("attack_interval", 1.0))
	attack_damage = float(_stats.get("attack_damage", 1.0))
	move_speed = float(_stats.get("move_speed", 3.5))
	_health_component = _get_or_create_component("HealthComponent", "res://core/components/health_component.gd") as HealthComponent
	_damage_component = _get_or_create_component("DamageComponent", "res://core/components/damage_component.gd") as DamageComponent
	if _health_component != null:
		_health_component.max_health = float(_stats.get("max_health", 40.0))
		_health_component.reset_health()
	if _damage_component != null:
		_damage_component.base_damage = attack_damage
	if _health_bar != null and _health_bar.has_method("bind_health_component"):
		_health_bar.call("bind_health_component", _health_component)

func _load_stats() -> void:
	_stats = DEFAULT_STATS.duplicate(true)
	var loaded_stats: Dictionary = JsonDataLoader.load_dictionary(ENEMY_STATS_PATH)
	if loaded_stats.is_empty():
		return
	for stat_key in loaded_stats.keys():
		_stats[String(stat_key)] = loaded_stats[stat_key]

func _get_or_create_component(node_name: String, script_path: String) -> Node:
	var existing := get_node_or_null(node_name)
	if existing != null:
		return existing
	var component := Node.new()
	component.name = node_name
	component.set_script(load(script_path))
	add_child(component)
	return component

func _ensure_visuals() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var collider := CollisionShape3D.new()
		collider.name = "CollisionShape3D"
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.42
		capsule.height = 1.3
		collider.shape = capsule
		add_child(collider)
	if get_node_or_null("Visual") == null:
		var visual := MeshInstance3D.new()
		visual.name = "Visual"
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.42
		mesh.height = 1.3
		visual.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.88, 0.21, 0.2, 1.0)
		material.roughness = 0.45
		visual.material_override = material
		add_child(visual)

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
