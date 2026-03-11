extends Node3D

@export var chunk_size := 32
@export var view_distance_chunks := 2
@export var resource_scene: PackedScene
@export var tree_scene: PackedScene
@export var rock_scene: PackedScene
@export var enemy_scene: PackedScene
@export var pool_warmup := 20

var _loaded_chunks = {}
var _enemy_pool = []

func _ready():
	_warmup_enemy_pool()
	var player = get_tree().get_first_node_in_group("player")
	if player:
		_update_chunks(player.global_position)

func _process(_delta):
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_update_chunks(player.global_position)

func _warmup_enemy_pool():
	if enemy_scene == null:
		return
	for _i in range(pool_warmup):
		var enemy = enemy_scene.instantiate()
		if enemy is Node3D:
			enemy.visible = false
			add_child(enemy)
			_enemy_pool.append(enemy)

func _take_enemy_from_pool():
	for enemy in _enemy_pool:
		if enemy.visible == false:
			enemy.visible = true
			return enemy
	if enemy_scene:
		return enemy_scene.instantiate()
	return null

func _update_chunks(player_pos):
	var cx = int(floor(player_pos.x / float(chunk_size)))
	var cz = int(floor(player_pos.z / float(chunk_size)))
	var required = {}
	for x in range(cx - view_distance_chunks, cx + view_distance_chunks + 1):
		for z in range(cz - view_distance_chunks, cz + view_distance_chunks + 1):
			var key = Vector2i(x, z)
			required[key] = true
			if not _loaded_chunks.has(key):
				_load_chunk(key)
	for key in _loaded_chunks.keys().duplicate():
		if not required.has(key):
			_unload_chunk(key)

func _load_chunk(key):
	var root = Node3D.new()
	root.name = "Chunk_%s_%s" % [key.x, key.y]
	add_child(root)
	_loaded_chunks[key] = root
	_spawn_chunk_content(root, key)
	EventBus.emit_game_event("chunk_loaded", {"chunk_id": key, "seed": hash("%s_%s" % [key.x, key.y])})

func _unload_chunk(key):
	if not _loaded_chunks.has(key):
		return
	var root = _loaded_chunks[key]
	_loaded_chunks.erase(key)
	for n in root.get_children():
		if n.is_in_group("enemy"):
			n.visible = false
			n.reparent(self)
	root.queue_free()
	EventBus.emit_game_event("chunk_unloaded", {"chunk_id": key})

func _spawn_chunk_content(root, key):
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("%s_%s" % [key.x, key.y])

	for _i in range(10):
		var p = Vector3(
			key.x * chunk_size + rng.randi_range(1, chunk_size - 1),
			0.0,
			key.y * chunk_size + rng.randi_range(1, chunk_size - 1)
		)
		var roll = rng.randi_range(0, 99)
		var scene = null
		if roll < 50:
			scene = tree_scene
		elif roll < 85:
			scene = rock_scene
		else:
			scene = resource_scene
		if scene == null:
			continue
		var n = scene.instantiate()
		if n is Node3D:
			n.global_position = p
			n.scale = Vector3.ONE * rng.randf_range(0.85, 1.25)
			root.add_child(n)

	if rng.randf() < 0.7:
		var enemy = _take_enemy_from_pool()
		if enemy:
			enemy.global_position = Vector3(key.x * chunk_size + chunk_size * 0.5, 1.0, key.y * chunk_size + chunk_size * 0.5)
			root.add_child(enemy)
