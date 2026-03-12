extends Node

@export var enemy_pool_size: int = 50
@export var max_enemies_per_chunk: int = 5
@export var spawn_min_distance: float = 15.0
@export var spawn_player_clearance_radius: float = 1.8
@export var despawn_distance: float = 80.0
@export var enemy_gold_reward_min: int = 3
@export var enemy_gold_reward_max: int = 12
@export var enemy_xp_reward: int = 1

const HEALTH_COMPONENT_SCRIPT: Script = preload("res://core/components/health_component.gd")
const WORLD_HEALTH_BAR_SCRIPT: Script = preload("res://ui/world_health_bar_3d.gd")

var _player: Node3D = null
var _combat_system: Node = null
var _enemy_scene: PackedScene = preload("res://enemies/scenes/enemy_root.tscn")

var _pool: Array[EnemyAI] = []
var _active_enemies: Array[EnemyAI] = []
var _enemies_by_chunk: Dictionary = {}
var _pool_index: ObjectPool = ObjectPool.new()
var _despawn_gate: UpdateIntervalGate = UpdateIntervalGate.new()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	_apply_game_config()
	_rng.randomize()
	_despawn_gate.set_interval(GameConfig.AI_UPDATE_INTERVAL)
	_warm_pool()
	EventBus.subscribe("entity_died", Callable(self, "_on_entity_died_event"))
	var tree_ref: SceneTree = get_tree()
	if tree_ref != null:
		var node_added_callback: Callable = Callable(self, "_on_tree_node_added")
		if not tree_ref.node_added.is_connected(node_added_callback):
			tree_ref.node_added.connect(node_added_callback)
		for enemy_variant in tree_ref.get_nodes_in_group("enemy"):
			var enemy_node: Node3D = enemy_variant as Node3D
			if enemy_node != null:
				call_deferred("_ensure_enemy_combat_ui", enemy_node)

func _exit_tree() -> void:
	if EventBus != null and EventBus.has_method("unsubscribe"):
		EventBus.call("unsubscribe", "entity_died", Callable(self, "_on_entity_died_event"))
	var tree_ref: SceneTree = get_tree()
	if tree_ref != null:
		var node_added_callback: Callable = Callable(self, "_on_tree_node_added")
		if tree_ref.node_added.is_connected(node_added_callback):
			tree_ref.node_added.disconnect(node_added_callback)

func _physics_process(delta: float) -> void:
	DebugProfiler.start_sample("enemy_system.physics")
	if _player == null or not is_instance_valid(_player):
		DebugProfiler.end_sample("enemy_system.physics")
		return
	if not _despawn_gate.should_run(delta):
		DebugProfiler.end_sample("enemy_system.physics")
		return
	var player_position: Vector3 = _player.global_position
	for enemy_variant in _active_enemies.duplicate():
		var enemy: EnemyAI = enemy_variant as EnemyAI
		if enemy == null or not is_instance_valid(enemy):
			_active_enemies.erase(enemy)
			continue
		var distance: float = enemy.global_position.distance_to(player_position)
		if distance > despawn_distance:
			_despawn_enemy(enemy)
	DebugProfiler.end_sample("enemy_system.physics")

func set_player(player: Node3D) -> void:
	_player = player

func set_combat_system(combat_system: Node) -> void:
	_combat_system = combat_system

func get_active_enemy_count() -> int:
	var retained: Array[EnemyAI] = []
	for enemy_variant in _active_enemies:
		var enemy: EnemyAI = enemy_variant as EnemyAI
		if enemy != null and is_instance_valid(enemy) and enemy.is_active():
			retained.append(enemy)
	_active_enemies = retained
	return _active_enemies.size()

func try_spawn_enemy(chunk_id: Vector2i, spawn_position: Vector3, chunk_root: Node3D) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var required_clearance: float = maxf(spawn_min_distance, spawn_player_clearance_radius)
	if _horizontal_distance_to_player(spawn_position) < required_clearance:
		return false
	var chunk_enemies_value: Variant = _enemies_by_chunk.get(chunk_id, [])
	var chunk_enemies: Array = chunk_enemies_value if chunk_enemies_value is Array else []
	if chunk_enemies.size() >= max_enemies_per_chunk:
		return false
	var enemy: EnemyAI = _take_enemy_from_pool()
	if enemy == null:
		return false
	if enemy.get_parent() != chunk_root:
		enemy.reparent(chunk_root)
	enemy.global_position = spawn_position
	_connect_enemy_signals(enemy)
	enemy.activate(_player, _combat_system, chunk_id)
	chunk_enemies.append(enemy)
	_enemies_by_chunk[chunk_id] = chunk_enemies
	_active_enemies.append(enemy)
	return true

func _horizontal_distance_to_player(position: Vector3) -> float:
	if _player == null or not is_instance_valid(_player):
		return INF
	var dx: float = position.x - _player.global_position.x
	var dz: float = position.z - _player.global_position.z
	return Vector2(dx, dz).length()

func on_chunk_unloaded(chunk_id: Vector2i) -> void:
	if not _enemies_by_chunk.has(chunk_id):
		return
	var chunk_enemies_value: Variant = _enemies_by_chunk[chunk_id]
	if not (chunk_enemies_value is Array):
		_enemies_by_chunk.erase(chunk_id)
		return
	var chunk_enemies: Array = chunk_enemies_value
	for enemy_variant in chunk_enemies.duplicate():
		var enemy: EnemyAI = enemy_variant as EnemyAI
		if enemy != null:
			_despawn_enemy(enemy)
	_enemies_by_chunk.erase(chunk_id)

func _warm_pool() -> void:
	for _i in range(enemy_pool_size):
		var enemy_instance_variant: Variant = _enemy_scene.instantiate()
		var enemy_instance: EnemyAI = enemy_instance_variant as EnemyAI
		if enemy_instance == null:
			continue
		add_child(enemy_instance)
		_ensure_enemy_combat_ui(enemy_instance)
		enemy_instance.deactivate()
		_connect_enemy_signals(enemy_instance)
		_pool.append(enemy_instance)
	_pool_index.setup(_pool, Callable(self, "_is_enemy_active"))

func _take_enemy_from_pool() -> EnemyAI:
	var pooled_node: Node = _pool_index.acquire()
	return pooled_node as EnemyAI

func _connect_enemy_signals(enemy: EnemyAI) -> void:
	var health_node: Node = enemy.get_node_or_null("HealthComponent")
	var health: HealthComponent = health_node as HealthComponent
	if health != null:
		var callback: Callable = Callable(self, "_on_enemy_died").bind(enemy)
		if not health.died.is_connected(callback):
			health.died.connect(callback)

func _on_enemy_died(_entity: Node, enemy: EnemyAI) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	EventBus.emit_game_event("loot_spawn_requested", {
		"position": enemy.global_position + Vector3(0.0, 0.6, 0.0),
		"item_id": "essence",
		"amount": 1
	})
	_despawn_enemy(enemy)

func _on_entity_died_event(payload: Dictionary) -> void:
	var entity_variant: Variant = payload.get("entity", null)
	var enemy: EnemyAI = entity_variant as EnemyAI
	if enemy == null:
		return
	var killer_variant: Variant = payload.get("source", null)
	var killer: Node = killer_variant as Node
	var rolled_gold_reward: int = _roll_enemy_gold_reward()
	EventBus.emit_game_event("enemy_killed", {
		"enemy_type": "default_enemy",
		"killer": killer,
		"gold_reward": rolled_gold_reward,
		"xp_reward": enemy_xp_reward,
		"position": enemy.global_position
	})

func _roll_enemy_gold_reward() -> int:
	var reward_min: int = mini(enemy_gold_reward_min, enemy_gold_reward_max)
	var reward_max: int = maxi(enemy_gold_reward_min, enemy_gold_reward_max)
	return _rng.randi_range(reward_min, reward_max)

func _despawn_enemy(enemy: EnemyAI) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_active_enemies.erase(enemy)
	var chunk_id: Vector2i = enemy.chunk_id
	if _enemies_by_chunk.has(chunk_id):
		var chunk_enemies_value: Variant = _enemies_by_chunk[chunk_id]
		if not (chunk_enemies_value is Array):
			_enemies_by_chunk.erase(chunk_id)
			enemy.deactivate()
			if enemy.get_parent() != self:
				enemy.reparent(self)
			return
		var chunk_enemies: Array = chunk_enemies_value
		chunk_enemies.erase(enemy)
		if chunk_enemies.is_empty():
			_enemies_by_chunk.erase(chunk_id)
		else:
			_enemies_by_chunk[chunk_id] = chunk_enemies
	enemy.deactivate()
	if enemy.get_parent() != self:
		enemy.reparent(self)

func _is_enemy_active(node: Node) -> bool:
	var enemy: EnemyAI = node as EnemyAI
	if enemy == null or not is_instance_valid(enemy):
		return false
	return enemy.is_active()

func _apply_game_config() -> void:
	enemy_pool_size = GameConfig.ENEMY_POOL_SIZE
	max_enemies_per_chunk = GameConfig.MAX_ENEMIES_PER_CHUNK
	spawn_min_distance = GameConfig.ENEMY_SPAWN_MIN_DISTANCE
	despawn_distance = GameConfig.ENEMY_DESPAWN_DISTANCE

func _on_tree_node_added(node: Node) -> void:
	if node == null:
		return
	var enemy_node: Node3D = node as Node3D
	if enemy_node == null:
		return
	if not _is_enemy_candidate(enemy_node):
		return
	call_deferred("_ensure_enemy_combat_ui", enemy_node)

func _ensure_enemy_combat_ui(enemy_node: Node3D) -> void:
	if enemy_node == null or not is_instance_valid(enemy_node):
		return
	if not _is_enemy_candidate(enemy_node):
		return
	var health_node: Node = _resolve_or_create_health_node(enemy_node)
	var health_bar: Node3D = enemy_node.get_node_or_null("HealthBar3D") as Node3D
	if health_bar == null:
		var bar_variant: Variant = WORLD_HEALTH_BAR_SCRIPT.new()
		health_bar = bar_variant as Node3D
		if health_bar == null:
			return
		health_bar.name = "HealthBar3D"
		enemy_node.add_child(health_bar)
	var y_offset: float = _estimate_enemy_bar_offset(enemy_node)
	health_bar.set("y_offset", y_offset)
	health_bar.set("hide_when_full_health", false)
	health_bar.set("full_health_hide_delay", 1.75)
	if health_bar.has_method("bind_health_component"):
		health_bar.call("bind_health_component", health_node)

func _resolve_or_create_health_node(enemy_node: Node3D) -> Node:
	var modern: Node = enemy_node.get_node_or_null("HealthComponent")
	if modern != null and modern.has_method("apply_damage"):
		return modern
	var legacy: Node = enemy_node.get_node_or_null("Health")
	if legacy != null and legacy.has_method("apply_damage"):
		return legacy
	var health_variant: Variant = HEALTH_COMPONENT_SCRIPT.new()
	var created_health: Node = health_variant as Node
	if created_health == null:
		return null
	created_health.name = "HealthComponent"
	var max_health_value: float = 40.0
	var from_enemy: Variant = enemy_node.get("max_health")
	if typeof(from_enemy) == TYPE_FLOAT or typeof(from_enemy) == TYPE_INT:
		max_health_value = maxf(float(from_enemy), 1.0)
	created_health.set("max_health", max_health_value)
	enemy_node.add_child(created_health)
	if created_health.has_method("reset_health"):
		created_health.call("reset_health")
	return created_health

func _estimate_enemy_bar_offset(enemy_node: Node3D) -> float:
	var collision: CollisionShape3D = enemy_node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape != null:
		var half_height: float = _shape_half_height(collision.shape)
		if half_height > 0.0:
			return collision.position.y + half_height + 0.35
	var visual: MeshInstance3D = enemy_node.get_node_or_null("Visual") as MeshInstance3D
	if visual != null and visual.mesh != null:
		var aabb: AABB = visual.mesh.get_aabb()
		return visual.position.y + aabb.position.y + aabb.size.y + 0.25
	return 1.9

func _shape_half_height(shape: Shape3D) -> float:
	if shape == null:
		return 0.0
	if shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape as CapsuleShape3D
		return capsule.height * 0.5
	if shape is CylinderShape3D:
		var cylinder: CylinderShape3D = shape as CylinderShape3D
		return cylinder.height * 0.5
	if shape is SphereShape3D:
		var sphere: SphereShape3D = shape as SphereShape3D
		return sphere.radius
	if shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		return box.size.y * 0.5
	return 0.0

func _is_enemy_candidate(node: Node3D) -> bool:
	if node == null:
		return false
	if node.is_in_group("enemy"):
		return true
	var script_resource: Script = node.get_script() as Script
	if script_resource == null:
		return false
	var script_path: String = script_resource.resource_path.to_lower()
	if script_path.find("/enemies/") >= 0:
		return true
	if script_path.ends_with("totem_wolf.gd") or script_path.ends_with("totem_enemy.gd"):
		return true
	return false
