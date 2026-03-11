extends Node

@export var enemy_pool_size: int = 50
@export var max_enemies_per_chunk: int = 5
@export var spawn_min_distance: float = 15.0
@export var despawn_distance: float = 80.0
@export var enemy_gold_reward_min: int = 3
@export var enemy_gold_reward_max: int = 12
@export var enemy_xp_reward: int = 1

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

func try_spawn_enemy(chunk_id: Vector2i, spawn_position: Vector3, chunk_root: Node3D) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if spawn_position.distance_to(_player.global_position) < spawn_min_distance:
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
