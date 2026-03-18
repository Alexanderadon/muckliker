extends Node3D
class_name WorldSystem
const ChunkDataModel = preload("res://world/systems/chunk_data.gd")

@export var chunk_size: int = 64
@export var terrain_height_scale: float = 10.0
@export var max_spawn_operations_per_frame: int = 10
@export var max_chunk_loads_per_frame: int = 1
@export var max_chunk_unloads_per_frame: int = 1
@export var prefetch_distance_chunks: int = 1
@export var streaming_spawn_operations_per_frame: int = 3
@export var terrain_grass_color: Color = Color8(34, 141, 86, 255) # 228D56
@export var terrain_sand_color: Color = Color8(255, 237, 134, 255) # FFED86
@export var terrain_shore_sand_height_offset: float = 2.4
@export var player_path: NodePath = NodePath("../PlayerRoot")
@export var totem_scene: PackedScene = preload("res://totem/totem.tscn")
@export var totem_spawn_chance_per_chunk: float = 0.08
@export var totem_density_multiplier: float = 3.0
@export var totem_distribution_grid_size_chunks: int = 2
@export var totem_min_spawn_distance: float = 12.0
@export var max_cached_chunk_data_entries: int = 512
@export var chunk_data_retention_distance_chunks: int = 8
@export var debug_enable_scene_diagnostics: bool = true
@export var debug_diagnostics_auto_once: bool = true
@export var debug_diagnostics_delay_seconds: float = 2.0
@export var debug_diagnostics_top_types: int = 25

const VIEW_DISTANCE_CHUNKS: int = 4
const MAX_ACTIVE_CHUNKS: int = 81
const LOD_CULL_DISTANCE_CHUNKS: int = 6
const WORLD_BOUNDARY_MARGIN: float = 2.0
const WATER_LEVEL: float = -3.5
const DEEP_WATER_TERRAIN_THRESHOLD: float = -4.0
const RESOURCE_SPAWNS_PER_CHUNK: int = 8
const GROUND_PICKUPS_PER_CHUNK: int = 6
const TERRAIN_RESOLUTION: int = 32
const CAMERA_FAR_CLIP: float = 1000.0
const FOG_DEPTH_BEGIN: float = 260.0
const FOG_DEPTH_END: float = 980.0
const FOG_DENSITY: float = 0.0025
const MAX_FPS_LIMIT: int = 240
var world_seed: int = 0
var _last_player_chunk: Vector2i = Vector2i(2147483647, 2147483647)

var _view_distance_chunks: int = VIEW_DISTANCE_CHUNKS
var _max_active_chunks: int = MAX_ACTIVE_CHUNKS
var _lod_cull_distance_chunks: int = LOD_CULL_DISTANCE_CHUNKS
var _resource_spawns_per_chunk: int = RESOURCE_SPAWNS_PER_CHUNK
var _ground_pickups_per_chunk: int = GROUND_PICKUPS_PER_CHUNK
var _terrain_resolution: int = TERRAIN_RESOLUTION

var _player_root: CharacterBody3D = null
var _terrain_generator: TerrainGenerator = null
var _loaded_chunks: Dictionary = {}
var _chunk_data_store: Dictionary = {}
var _pending_spawn_operations: Array[Dictionary] = []
var _pending_chunk_loads: Array[Vector2i] = []
var _pending_chunk_load_lookup: Dictionary = {}
var _pending_chunk_unloads: Array[Vector2i] = []
var _pending_chunk_unload_lookup: Dictionary = {}

var _chunks_root: Node3D = null
var _terrain_colored_material: Material = null
var _combat_system: Node = null
var _resource_system: Node = null
var _enemy_system: Node = null
var _loot_system: Node = null
var _inventory_system: Node = null
var _ui_system: Node = null
var _crafting_system: Node = null

func _ready() -> void:
	Engine.max_fps = MAX_FPS_LIMIT
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_game_config()
	_initialize_runtime_systems()
	_initialize_terrain()
	_initialize_world_nodes()
	_resolve_player()
	if _player_root != null:
		_set_player_spawn()
	var game_state := _get_game_state()
	if game_state != null and game_state.has_method("set_state"):
		game_state.call("set_state", "loading")
	if _player_root != null:
		_last_player_chunk = _chunk_id_from_position(_player_root.global_position)
		_update_chunks(_player_root.global_position, true)
	else:
		_last_player_chunk = _chunk_id_from_position(Vector3.ZERO)
		_update_chunks(Vector3.ZERO, true)
	_refresh_loaded_chunk_terrain_visuals()
	_process_spawn_operations()
	if game_state != null and game_state.has_method("set_state"):
		game_state.call("set_state", "playing")
	_schedule_debug_diagnostics_once()

func _process(_delta: float) -> void:
	DebugProfiler.start_sample("world.process")
	if _player_root == null or not is_instance_valid(_player_root):
		_resolve_player()
		if _player_root == null:
			DebugProfiler.end_sample("world.process")
			return
	var player_position: Vector3 = _player_root.global_position
	var player_chunk: Vector2i = _chunk_id_from_position(player_position)
	if player_chunk != _last_player_chunk:
		_last_player_chunk = player_chunk
		_update_chunks(player_position)
	_process_chunk_unload_queue()
	_process_chunk_load_queue()
	if _pending_chunk_loads.is_empty():
		_process_spawn_operations()
	else:
		_process_spawn_operations(mini(streaming_spawn_operations_per_frame, max_spawn_operations_per_frame))
	DebugProfiler.end_sample("world.process")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F9:
			_run_debug_scene_diagnostics()
			return
		if not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
			return
		var game_state := _get_game_state()
		if game_state == null:
			return
		var current_state := String(game_state.get("current_state"))
		if current_state == "paused":
			game_state.call("resume_game")
		else:
			game_state.call("pause_game")

func terrain_height(x: float, z: float) -> float:
	if _terrain_generator == null:
		return 0.0
	return _terrain_generator.terrain_height(x, z)

func get_world_seed() -> int:
	return world_seed

func get_world_radius() -> float:
	if _terrain_generator == null:
		return 500.0
	if _terrain_generator.has_method("get_island_radius"):
		var radius_variant: Variant = _terrain_generator.call("get_island_radius")
		if typeof(radius_variant) == TYPE_FLOAT or typeof(radius_variant) == TYPE_INT:
			return maxf(float(radius_variant) - WORLD_BOUNDARY_MARGIN, 1.0)
	return 500.0

func clamp_position_to_world(world_position: Vector3) -> Vector3:
	var world_radius: float = get_world_radius()
	var horizontal: Vector2 = Vector2(world_position.x, world_position.z)
	var distance: float = horizontal.length()
	if distance <= world_radius or distance <= 0.0001:
		return world_position
	var clamped_horizontal: Vector2 = horizontal.normalized() * world_radius
	return Vector3(clamped_horizontal.x, world_position.y, clamped_horizontal.y)

func get_water_level() -> float:
	return WATER_LEVEL

func is_position_underwater(world_position: Vector3) -> bool:
	return world_position.y < WATER_LEVEL

func is_position_in_deep_water(world_position: Vector3) -> bool:
	var ground_height: float = terrain_height(world_position.x, world_position.z)
	return world_position.y < WATER_LEVEL and ground_height < DEEP_WATER_TERRAIN_THRESHOLD

func set_water_tint(intensity: float) -> void:
	if _ui_system != null and _ui_system.has_method("set_water_tint"):
		_ui_system.call("set_water_tint", clampf(intensity, 0.0, 1.0))

func get_combat_system() -> Node:
	return _combat_system

func get_inventory_system() -> Node:
	return _inventory_system

func get_loot_system() -> Node:
	return _loot_system

func get_ui_system() -> Node:
	return _ui_system

func harvest_resource_from_collider(collider: Object, harvester: Node) -> bool:
	if _resource_system == null or not _resource_system.has_method("harvest_from_collider"):
		return false
	return bool(_resource_system.call("harvest_from_collider", collider, harvester, {}))

func harvest_resource_from_collider_with_tool(collider: Object, harvester: Node, tool_context: Dictionary) -> bool:
	if _resource_system == null or not _resource_system.has_method("harvest_from_collider"):
		return false
	return bool(_resource_system.call("harvest_from_collider", collider, harvester, tool_context))

func _initialize_runtime_systems() -> void:
	_combat_system = _get_or_create_system("CombatSystem", "res://combat/combat_system.gd")
	_resource_system = _get_or_create_system("ResourceSystem", "res://resource/resource_system.gd")
	_enemy_system = _get_or_create_system("EnemySystem", "res://enemies/systems/enemy_system.gd")
	_loot_system = _get_or_create_system("LootSystem", "res://loot/loot_system.gd")
	_inventory_system = _get_or_create_system("InventorySystem", "res://inventory/inventory_system.gd")
	_crafting_system = _get_or_create_system("CraftingSystem", "res://crafting/crafting_system.gd")
	_ui_system = _get_or_create_system("UISystem", "res://ui/ui_system.gd")

func _initialize_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	world_seed = rng.randi()
	_terrain_generator = TerrainGenerator.new()
	_terrain_generator.configure(world_seed, terrain_height_scale)

func _initialize_world_nodes() -> void:
	_chunks_root = get_node_or_null("ChunksRoot")
	if _chunks_root == null:
		_chunks_root = Node3D.new()
		_chunks_root.name = "ChunksRoot"
		add_child(_chunks_root)
	_terrain_colored_material = null
	_ensure_lighting()
	var water: MeshInstance3D = get_node_or_null("WaterPlane") as MeshInstance3D
	if water == null:
		water = MeshInstance3D.new()
		water.name = "WaterPlane"
		var plane := PlaneMesh.new()
		plane.size = Vector2(2048.0, 2048.0)
		water.mesh = plane
		water.position = Vector3(0.0, WATER_LEVEL, 0.0)
		add_child(water)
	_configure_water_surface(water)

func _ensure_lighting() -> void:
	if get_node_or_null("SunLight") == null:
		var sun_light: DirectionalLight3D = DirectionalLight3D.new()
		sun_light.name = "SunLight"
		sun_light.rotation = Vector3(-0.9, 0.3, 0.0)
		sun_light.light_energy = 1.15
		add_child(sun_light)
	var environment_node: WorldEnvironment = get_node_or_null("SkyEnvironment") as WorldEnvironment
	if environment_node == null:
		environment_node = WorldEnvironment.new()
		environment_node.name = "SkyEnvironment"
		add_child(environment_node)
	var environment: Environment = environment_node.environment
	if environment == null:
		environment = Environment.new()
		environment_node.environment = environment
	environment.background_mode = Environment.BG_SKY
	var sky: Sky = environment.sky
	if sky == null:
		sky = Sky.new()
	var sky_material: ProceduralSkyMaterial = sky.sky_material as ProceduralSkyMaterial
	if sky_material == null:
		sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_horizon_color = Color(0.62, 0.76, 0.95, 1.0)
	sky_material.sky_top_color = Color(0.2, 0.43, 0.86, 1.0)
	sky_material.ground_horizon_color = Color(0.5, 0.62, 0.7, 1.0)
	sky.sky_material = sky_material
	environment.sky = sky
	_configure_environment_fog(environment)

func _configure_environment_fog(environment: Environment) -> void:
	environment.set("fog_enabled", true)
	environment.set("fog_density", GameConfig.FOG_DENSITY)
	environment.set("fog_light_color", Color(0.66, 0.74, 0.84, 1.0))
	environment.set("fog_light_energy", 0.9)
	environment.set("fog_aerial_perspective", 0.45)
	environment.set("fog_sky_affect", 0.5)
	environment.set("fog_depth_begin", GameConfig.FOG_DEPTH_BEGIN)
	environment.set("fog_depth_end", GameConfig.FOG_DEPTH_END)
	environment.set("fog_depth_curve", 1.0)

func _configure_water_surface(water: MeshInstance3D) -> void:
	if water == null:
		return
	var existing_plane: PlaneMesh = water.mesh as PlaneMesh
	if existing_plane != null:
		var target_size: float = _compute_water_plane_size()
		existing_plane.size = Vector2(target_size, target_size)
		if existing_plane.subdivide_width < 8:
			existing_plane.subdivide_width = 8
		if existing_plane.subdivide_depth < 8:
			existing_plane.subdivide_depth = 8
	var water_position: Vector3 = water.position
	water_position.y = WATER_LEVEL
	water.position = water_position
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var water_material: StandardMaterial3D = StandardMaterial3D.new()
	water_material.albedo_color = Color(0.0, 0.35, 0.6, 1.0)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var material_color: Color = water_material.albedo_color
	material_color.a = 0.75
	water_material.albedo_color = material_color
	water_material.roughness = 0.6
	water_material.metallic = 0.0
	water.material_override = water_material

func _compute_water_plane_size() -> float:
	var world_radius: float = get_world_radius()
	var lod_padding: float = float(_view_distance_chunks * chunk_size) * 2.0
	var diameter_with_margin: float = world_radius * 2.6 + lod_padding
	return maxf(diameter_with_margin, 4096.0)

func _resolve_player() -> void:
	_player_root = get_node_or_null(player_path)
	if _player_root == null:
		return
	_configure_player_camera()
	if _player_root.has_method("set_world_system"):
		_player_root.call("set_world_system", self)
	if _player_root.has_method("set_combat_system"):
		_player_root.call("set_combat_system", _combat_system)
	if _player_root.has_method("set_inventory_system"):
		_player_root.call("set_inventory_system", _inventory_system)
	if _player_root.has_method("set_loot_system"):
		_player_root.call("set_loot_system", _loot_system)
	if _player_root.has_method("set_ui_system"):
		_player_root.call("set_ui_system", _ui_system)
	if _enemy_system != null and _enemy_system.has_method("set_player"):
		_enemy_system.call("set_player", _player_root)
	if _enemy_system != null and _enemy_system.has_method("set_combat_system"):
		_enemy_system.call("set_combat_system", _combat_system)
	if _loot_system != null and _loot_system.has_method("set_player"):
		_loot_system.call("set_player", _player_root)
	if _loot_system != null and _loot_system.has_method("set_inventory_system"):
		_loot_system.call("set_inventory_system", _inventory_system)
	if _inventory_system != null and _inventory_system.has_method("bind_inventory") and _player_root.has_method("get_inventory_component"):
		var player_inventory_variant: Variant = _player_root.call("get_inventory_component")
		var player_inventory: InventoryComponent = player_inventory_variant as InventoryComponent
		if player_inventory != null:
			_inventory_system.call("bind_inventory", player_inventory)
	if _ui_system != null and _ui_system.has_method("set_world_system"):
		_ui_system.call("set_world_system", self)
	if _ui_system != null and _ui_system.has_method("set_inventory_system"):
		_ui_system.call("set_inventory_system", _inventory_system)
	if _ui_system != null and _ui_system.has_method("set_crafting_system"):
		_ui_system.call("set_crafting_system", _crafting_system)
	if _ui_system != null and _ui_system.has_method("bind"):
		_ui_system.call("bind", _player_root)

func _configure_player_camera() -> void:
	if _player_root == null:
		return
	var camera_node: Node = _player_root.get_node_or_null("PlayerHead/Camera3D")
	var player_camera: Camera3D = camera_node as Camera3D
	if player_camera == null:
		return
	player_camera.far = GameConfig.CAMERA_FAR_CLIP

func _set_player_spawn() -> void:
	var spawn_height := terrain_height(0.0, 0.0)
	_player_root.global_position = Vector3(0.0, spawn_height + 2.0, 0.0)

func _get_or_create_system(node_name: String, script_path: String) -> Node:
	var existing := get_node_or_null(node_name)
	if existing != null:
		return existing
	var script_resource: Script = load(script_path)
	if script_resource == null:
		push_error("WorldSystem failed to load script: %s" % script_path)
		var fallback := Node.new()
		fallback.name = node_name
		add_child(fallback)
		return fallback
	var new_node_variant: Variant = script_resource.new()
	if not (new_node_variant is Node):
		push_error("WorldSystem script is not a Node: %s" % script_path)
		var invalid_fallback := Node.new()
		invalid_fallback.name = node_name
		add_child(invalid_fallback)
		return invalid_fallback
	var new_node: Node = new_node_variant as Node
	if new_node == null:
		var null_fallback := Node.new()
		null_fallback.name = node_name
		add_child(null_fallback)
		return null_fallback
	new_node.name = node_name
	add_child(new_node)
	return new_node

func _update_chunks(player_position: Vector3, immediate_load: bool = false) -> void:
	var player_chunk := _chunk_id_from_position(player_position)
	var preload_radius: int = _view_distance_chunks
	if not immediate_load:
		preload_radius += maxi(prefetch_distance_chunks, 0)
	var required_chunks: Array[Vector2i] = ChunkMath.build_required_chunks(player_chunk, preload_radius)
	var required_lookup := {}
	for chunk_id in required_chunks:
		required_lookup[chunk_id] = true
		_remove_pending_chunk_unload(chunk_id)
		if not _loaded_chunks.has(chunk_id):
			if immediate_load:
				_load_chunk(chunk_id)
			else:
				_enqueue_chunk_load(chunk_id)
	_drop_stale_pending_chunk_loads(required_lookup)
	_drop_stale_pending_chunk_unloads(required_lookup)
	for loaded_chunk_key in _loaded_chunks.keys().duplicate():
		if not (loaded_chunk_key is Vector2i):
			continue
		var loaded_chunk: Vector2i = loaded_chunk_key
		if not required_lookup.has(loaded_chunk):
			_enqueue_chunk_unload(loaded_chunk)
	var required_capacity: int = (preload_radius * 2 + 1) * (preload_radius * 2 + 1)
	var effective_max_active_chunks: int = maxi(_max_active_chunks, required_capacity)
	if _loaded_chunks.size() > effective_max_active_chunks:
		var overflow := _loaded_chunks.size() - effective_max_active_chunks
		for i in range(overflow):
			var farthest_chunk := _find_farthest_chunk(player_chunk)
			_enqueue_chunk_unload(farthest_chunk)
	_update_chunk_lod(player_chunk)
	_trim_chunk_data_cache(player_chunk)

func _chunk_id_from_position(world_position: Vector3) -> Vector2i:
	return ChunkMath.chunk_id_from_position(world_position, chunk_size)

func _load_chunk(chunk_id: Vector2i) -> void:
	if _loaded_chunks.has(chunk_id):
		return
	_remove_pending_chunk_unload(chunk_id)
	var chunk_data = _get_or_create_chunk_data(chunk_id)
	chunk_data.touch()
	var chunk_root := Node3D.new()
	chunk_root.name = "Chunk_%s_%s" % [chunk_id.x, chunk_id.y]
	chunk_root.set_meta("chunk_id", chunk_id)
	_chunks_root.add_child(chunk_root)
	_loaded_chunks[chunk_id] = chunk_root
	_spawn_chunk_terrain(chunk_id, chunk_root)
	var should_queue_spawns: bool = _should_queue_spawns_for_chunk(chunk_id)
	chunk_root.set_meta("spawns_queued", should_queue_spawns)
	if should_queue_spawns:
		_queue_chunk_spawns(chunk_id, chunk_data)
	EventBus.emit_game_event("chunk_loaded", {
		"chunk_id": chunk_id,
		"seed": chunk_data.seed
	})

func _unload_chunk(chunk_id: Vector2i) -> void:
	_remove_pending_chunk_unload(chunk_id)
	if not _loaded_chunks.has(chunk_id):
		return
	var chunk_data = _get_or_create_chunk_data(chunk_id)
	chunk_data.touch()
	_remove_pending_chunk_load(chunk_id)
	if _enemy_system != null and _enemy_system.has_method("on_chunk_unloaded"):
		_enemy_system.call("on_chunk_unloaded", chunk_id)
	if _resource_system != null and _resource_system.has_method("on_chunk_unloaded"):
		_resource_system.call("on_chunk_unloaded", chunk_id)
	if _loot_system != null and _loot_system.has_method("on_chunk_unloaded"):
		_loot_system.call("on_chunk_unloaded", chunk_id)
	var chunk_root_variant: Variant = _loaded_chunks[chunk_id]
	var chunk_root: Node = chunk_root_variant as Node
	_loaded_chunks.erase(chunk_id)
	_drop_pending_operations_for_chunk(chunk_id)
	if is_instance_valid(chunk_root):
		chunk_root.queue_free()
	EventBus.emit_game_event("chunk_unloaded", {
		"chunk_id": chunk_id
	})

func _enqueue_chunk_load(chunk_id: Vector2i) -> void:
	if _loaded_chunks.has(chunk_id):
		return
	if _pending_chunk_load_lookup.has(chunk_id):
		return
	_pending_chunk_load_lookup[chunk_id] = true
	_pending_chunk_loads.append(chunk_id)

func _enqueue_chunk_unload(chunk_id: Vector2i) -> void:
	if not _loaded_chunks.has(chunk_id):
		return
	if _pending_chunk_unload_lookup.has(chunk_id):
		return
	_pending_chunk_unload_lookup[chunk_id] = true
	_pending_chunk_unloads.append(chunk_id)

func _process_chunk_unload_queue() -> void:
	if _pending_chunk_unloads.is_empty():
		return
	var unloads_done: int = 0
	var unload_budget: int = maxi(max_chunk_unloads_per_frame, 1)
	while unloads_done < unload_budget and not _pending_chunk_unloads.is_empty():
		var chunk_id: Vector2i = _pending_chunk_unloads.pop_front()
		_pending_chunk_unload_lookup.erase(chunk_id)
		if not _loaded_chunks.has(chunk_id):
			continue
		_unload_chunk(chunk_id)
		unloads_done += 1

func _process_chunk_load_queue() -> void:
	if _pending_chunk_loads.is_empty():
		return
	var loads_done: int = 0
	var load_budget: int = maxi(max_chunk_loads_per_frame, 1)
	while loads_done < load_budget and not _pending_chunk_loads.is_empty():
		var chunk_id: Vector2i = _pending_chunk_loads.pop_front()
		_pending_chunk_load_lookup.erase(chunk_id)
		if _loaded_chunks.has(chunk_id):
			continue
		_load_chunk(chunk_id)
		loads_done += 1

func _drop_stale_pending_chunk_loads(required_lookup: Dictionary) -> void:
	if _pending_chunk_loads.is_empty():
		return
	var retained: Array[Vector2i] = []
	var retained_lookup: Dictionary = {}
	for chunk_id in _pending_chunk_loads:
		if required_lookup.has(chunk_id) and not _loaded_chunks.has(chunk_id):
			retained.append(chunk_id)
			retained_lookup[chunk_id] = true
	_pending_chunk_loads = retained
	_pending_chunk_load_lookup = retained_lookup

func _drop_stale_pending_chunk_unloads(required_lookup: Dictionary) -> void:
	if _pending_chunk_unloads.is_empty():
		return
	var retained: Array[Vector2i] = []
	var retained_lookup: Dictionary = {}
	for chunk_id in _pending_chunk_unloads:
		if required_lookup.has(chunk_id):
			continue
		if not _loaded_chunks.has(chunk_id):
			continue
		retained.append(chunk_id)
		retained_lookup[chunk_id] = true
	_pending_chunk_unloads = retained
	_pending_chunk_unload_lookup = retained_lookup

func _remove_pending_chunk_load(chunk_id: Vector2i) -> void:
	if not _pending_chunk_load_lookup.has(chunk_id):
		return
	_pending_chunk_load_lookup.erase(chunk_id)
	var pending_index: int = _pending_chunk_loads.find(chunk_id)
	if pending_index >= 0:
		_pending_chunk_loads.remove_at(pending_index)

func _remove_pending_chunk_unload(chunk_id: Vector2i) -> void:
	if not _pending_chunk_unload_lookup.has(chunk_id):
		return
	_pending_chunk_unload_lookup.erase(chunk_id)
	var pending_index: int = _pending_chunk_unloads.find(chunk_id)
	if pending_index >= 0:
		_pending_chunk_unloads.remove_at(pending_index)

func _find_farthest_chunk(player_chunk: Vector2i) -> Vector2i:
	var farthest_chunk := player_chunk
	var max_distance := -1.0
	for chunk_key in _loaded_chunks.keys():
		if not (chunk_key is Vector2i):
			continue
		var chunk_id: Vector2i = chunk_key
		var distance := float(chunk_id.distance_squared_to(player_chunk))
		if distance > max_distance:
			max_distance = distance
			farthest_chunk = chunk_id
	return farthest_chunk

func _update_chunk_lod(player_chunk: Vector2i) -> void:
	var visible_distance_chunks: int = mini(_lod_cull_distance_chunks, _view_distance_chunks)
	var cull_distance_squared: float = float(visible_distance_chunks * visible_distance_chunks)
	for chunk_key in _loaded_chunks.keys():
		if not (chunk_key is Vector2i):
			continue
		var chunk_id: Vector2i = chunk_key
		var chunk_root_variant: Variant = _loaded_chunks[chunk_id]
		var chunk_root: Node3D = chunk_root_variant as Node3D
		if chunk_root == null:
			continue
		var is_within_lod: bool = float(chunk_id.distance_squared_to(player_chunk)) <= cull_distance_squared
		if is_within_lod and not bool(chunk_root.get_meta("spawns_queued", false)):
			var chunk_data = _get_or_create_chunk_data(chunk_id)
			_queue_chunk_spawns(chunk_id, chunk_data)
			chunk_root.set_meta("spawns_queued", true)
		_set_chunk_lod_state(chunk_root, is_within_lod)

func _should_queue_spawns_for_chunk(chunk_id: Vector2i) -> bool:
	var prefetch_chunks: int = maxi(prefetch_distance_chunks, 0)
	var spawn_distance_chunks: int = _view_distance_chunks + prefetch_chunks
	var spawn_distance_chunks_squared: float = float(spawn_distance_chunks * spawn_distance_chunks)
	return float(chunk_id.distance_squared_to(_last_player_chunk)) <= spawn_distance_chunks_squared

func _set_chunk_lod_state(chunk_root: Node3D, visible_in_lod: bool) -> void:
	var currently_culled: bool = bool(chunk_root.get_meta("lod_culled", false))
	var target_culled: bool = not visible_in_lod
	if currently_culled == target_culled:
		return
	chunk_root.set_meta("lod_culled", target_culled)
	# Keep terrain visible at all times to avoid distant chunk cut lines.
	chunk_root.visible = true
	_set_chunk_gameplay_nodes_lod_state(chunk_root, visible_in_lod)

func _set_chunk_gameplay_nodes_lod_state(chunk_root: Node3D, visible_in_lod: bool) -> void:
	for child_variant in chunk_root.get_children():
		if not (child_variant is Node):
			continue
		var child: Node = child_variant
		if child.name == "GroundBody":
			# Terrain mesh stays visible and collidable to keep horizon continuous.
			continue
		if child is Node3D:
			var child_3d: Node3D = child
			child_3d.visible = visible_in_lod
		_set_chunk_collision_enabled(child, visible_in_lod)

func _set_chunk_collision_enabled(node: Node, enabled: bool) -> void:
	for child_variant in node.get_children():
		if not (child_variant is Node):
			continue
		var child: Node = child_variant
		if child is CollisionShape3D:
			var collision_shape: CollisionShape3D = child
			collision_shape.disabled = not enabled
		_set_chunk_collision_enabled(child, enabled)

func _spawn_chunk_terrain(chunk_id: Vector2i, chunk_root: Node3D) -> void:
	var existing_ground: Node = chunk_root.get_node_or_null("GroundBody")
	if existing_ground != null:
		chunk_root.remove_child(existing_ground)
		existing_ground.queue_free()
	var terrain_mesh_raw: ArrayMesh = _terrain_generator.build_chunk_mesh(chunk_id, chunk_size, _terrain_resolution)
	var terrain_mesh: ArrayMesh = _build_terrain_mesh_with_palette(terrain_mesh_raw)
	var ground_body := StaticBody3D.new()
	ground_body.name = "GroundBody"
	ground_body.position = Vector3(float(chunk_id.x * chunk_size), 0.0, float(chunk_id.y * chunk_size))
	chunk_root.add_child(ground_body)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = terrain_mesh
	_apply_terrain_material_to_mesh_instance(mesh_instance, terrain_mesh.get_surface_count())
	ground_body.add_child(mesh_instance)

	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(terrain_mesh_raw.get_faces())
	collider.shape = shape
	ground_body.add_child(collider)

func _refresh_loaded_chunk_terrain_visuals() -> void:
	for chunk_key in _loaded_chunks.keys():
		if not (chunk_key is Vector2i):
			continue
		var chunk_id: Vector2i = chunk_key
		var chunk_root_variant: Variant = _loaded_chunks[chunk_id]
		var chunk_root: Node3D = chunk_root_variant as Node3D
		if chunk_root == null:
			continue
		_spawn_chunk_terrain(chunk_id, chunk_root)

func _build_terrain_mesh_with_palette(source_mesh: ArrayMesh) -> ArrayMesh:
	if source_mesh == null or source_mesh.get_surface_count() <= 0:
		return source_mesh
	var source_arrays_variant: Variant = source_mesh.surface_get_arrays(0)
	if not (source_arrays_variant is Array):
		return source_mesh
	var source_arrays: Array = source_arrays_variant
	if source_arrays.size() < Mesh.ARRAY_MAX:
		return source_mesh
	var vertices_variant: Variant = source_arrays[Mesh.ARRAY_VERTEX]
	var normals_variant: Variant = source_arrays[Mesh.ARRAY_NORMAL]
	var uvs_variant: Variant = source_arrays[Mesh.ARRAY_TEX_UV]
	var indices_variant: Variant = source_arrays[Mesh.ARRAY_INDEX]
	if not (vertices_variant is PackedVector3Array) or not (indices_variant is PackedInt32Array):
		return source_mesh
	var vertices: PackedVector3Array = PackedVector3Array(vertices_variant)
	var normals: PackedVector3Array = PackedVector3Array(normals_variant) if normals_variant is PackedVector3Array else PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array(uvs_variant) if uvs_variant is PackedVector2Array else PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array(indices_variant)
	if vertices.is_empty():
		return source_mesh
	if normals.size() != vertices.size():
		normals.resize(vertices.size())
		for i in range(vertices.size()):
			normals[i] = Vector3.UP

	var grass_color: Color = terrain_grass_color
	var sand_color: Color = terrain_sand_color
	var shore_sand_height: float = WATER_LEVEL + terrain_shore_sand_height_offset
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(vertices.size())
	for i in range(vertices.size()):
		var vertex_y: float = vertices[i].y
		colors[i] = sand_color if vertex_y <= shore_sand_height else grass_color

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _apply_terrain_material_to_mesh_instance(mesh_instance: MeshInstance3D, surface_count: int) -> void:
	if mesh_instance == null:
		return
	var material: Material = _resolve_terrain_colored_material()
	mesh_instance.material_override = material
	var resolved_surface_count: int = maxi(surface_count, 1)
	for surface_idx in range(resolved_surface_count):
		mesh_instance.set_surface_override_material(surface_idx, material)

func _resolve_terrain_colored_material() -> Material:
	if _terrain_colored_material != null:
		return _terrain_colored_material
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.vertex_color_use_as_albedo = true
	# Vertex colors are authored from hex/sRGB values; keep their on-screen color faithful.
	material.vertex_color_is_srgb = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	material.roughness = 1.0
	material.metallic = 0.0
	_terrain_colored_material = material
	return _terrain_colored_material

func _queue_chunk_spawns(chunk_id: Vector2i, chunk_data = null) -> void:
	if chunk_data == null:
		chunk_data = _get_or_create_chunk_data(chunk_id)
	chunk_data.touch()
	var rng := RandomNumberGenerator.new()
	rng.seed = chunk_data.seed
	for _i in range(_resource_spawns_per_chunk):
		var position := _random_position_in_chunk(chunk_id, rng)
		if position.y <= WATER_LEVEL + 0.2:
			continue
		var roll: float = rng.randf()
		var resource_type: String = "tree"
		if roll < 0.5:
			resource_type = "tree"
		elif roll < 0.82:
			resource_type = "rock"
		else:
			resource_type = "big_rock"
		_pending_spawn_operations.append({
			"type": "resource",
			"chunk_id": chunk_id,
			"resource_type": resource_type,
			"position": position
		})
	for _j in range(5):
		var enemy_position := _random_position_in_chunk(chunk_id, rng)
		if enemy_position.y <= WATER_LEVEL + 0.2:
			continue
		enemy_position.y += 1.0
		_pending_spawn_operations.append({
			"type": "enemy",
			"chunk_id": chunk_id,
			"position": enemy_position
		})
	for _k in range(_ground_pickups_per_chunk):
		var pickup_position := _random_position_in_chunk(chunk_id, rng)
		if pickup_position.y <= WATER_LEVEL + 0.1:
			continue
		var pickup_item_id: String = "stick" if rng.randf() < 0.65 else "stone"
		_pending_spawn_operations.append({
			"type": "ground_pickup",
			"chunk_id": chunk_id,
			"position": pickup_position + Vector3(0.0, 0.2, 0.0),
			"item_id": pickup_item_id,
			"amount": 1
		})
	_queue_totem_spawn_for_chunk(chunk_id, rng, chunk_data)

func _queue_totem_spawn_for_chunk(chunk_id: Vector2i, rng: RandomNumberGenerator, chunk_data) -> void:
	if chunk_data == null:
		return
	if chunk_data.totem_state == ChunkDataModel.TotemState.COMPLETED:
		return
	if chunk_data.totem_state == ChunkDataModel.TotemState.SPAWNED:
		_pending_spawn_operations.append({
			"type": "totem",
			"chunk_id": chunk_id,
			"position": chunk_data.totem_position,
			"totem_id": "totem_%s_%s" % [chunk_id.x, chunk_id.y]
		})
		return
	if not _should_spawn_totem_in_chunk(chunk_id):
		chunk_data.set_totem_none()
		return
	var totem_spawn_result: Dictionary = _compute_totem_spawn_position(chunk_id, rng)
	if not bool(totem_spawn_result.get("valid", false)):
		chunk_data.touch()
		return
	var totem_position_variant: Variant = totem_spawn_result.get("position", Vector3.ZERO)
	var totem_position: Vector3 = totem_position_variant if totem_position_variant is Vector3 else Vector3.ZERO
	chunk_data.set_totem_spawned(totem_position)
	_pending_spawn_operations.append({
		"type": "totem",
		"chunk_id": chunk_id,
		"position": totem_position,
		"totem_id": "totem_%s_%s" % [chunk_id.x, chunk_id.y]
	})

func _process_spawn_operations(operation_budget: int = -1) -> void:
	var operations_done := 0
	var budget: int = max_spawn_operations_per_frame if operation_budget <= 0 else operation_budget
	budget = maxi(budget, 1)
	while operations_done < budget and not _pending_spawn_operations.is_empty():
		var operation: Dictionary = _pending_spawn_operations.pop_front()
		_execute_spawn_operation(operation)
		operations_done += 1

func _execute_spawn_operation(operation: Dictionary) -> bool:
	var chunk_id_variant: Variant = operation.get("chunk_id", Vector2i.ZERO)
	var chunk_id: Vector2i = chunk_id_variant if chunk_id_variant is Vector2i else Vector2i.ZERO
	if not _loaded_chunks.has(chunk_id):
		return false
	var chunk_root_variant: Variant = _loaded_chunks[chunk_id]
	var chunk_root: Node3D = chunk_root_variant as Node3D
	if chunk_root == null:
		return false
	var operation_type_variant: Variant = operation.get("type", "")
	var operation_type: String = String(operation_type_variant)
	if operation_type == "resource":
		if _resource_system == null or not _resource_system.has_method("spawn_resource"):
			return false
		var position_variant: Variant = operation.get("position", Vector3.ZERO)
		var resource_type_variant: Variant = operation.get("resource_type", "tree")
		var position: Vector3 = position_variant if position_variant is Vector3 else Vector3.ZERO
		var resource_type: String = String(resource_type_variant)
		return _resource_system.call("spawn_resource", chunk_root, position, resource_type, chunk_id) != null
	if operation_type == "enemy":
		if _enemy_system == null or not _enemy_system.has_method("try_spawn_enemy"):
			return false
		var enemy_position_variant: Variant = operation.get("position", Vector3.ZERO)
		var enemy_position: Vector3 = enemy_position_variant if enemy_position_variant is Vector3 else Vector3.ZERO
		return bool(_enemy_system.call("try_spawn_enemy", chunk_id, enemy_position, chunk_root))
	if operation_type == "ground_pickup":
		var pickup_position_variant: Variant = operation.get("position", Vector3.ZERO)
		var pickup_item_variant: Variant = operation.get("item_id", "stick")
		var pickup_amount_variant: Variant = operation.get("amount", 1)
		var pickup_position: Vector3 = pickup_position_variant if pickup_position_variant is Vector3 else Vector3.ZERO
		var pickup_item_id: String = String(pickup_item_variant)
		var pickup_amount: int = int(pickup_amount_variant)
		return EventBus.emit_game_event("loot_spawn_requested", {
			"position": pickup_position,
			"item_id": pickup_item_id,
			"amount": pickup_amount,
			"chunk_id": chunk_id,
			"spawned_from_world": true
		})
	if operation_type == "totem":
		if totem_scene == null:
			return false
		var totem_variant: Variant = totem_scene.instantiate()
		if not (totem_variant is Node3D):
			return false
		var totem_node: Node3D = totem_variant as Node3D
		if totem_node == null:
			return false
		var totem_position_variant: Variant = operation.get("position", Vector3.ZERO)
		var totem_position: Vector3 = totem_position_variant if totem_position_variant is Vector3 else Vector3.ZERO
		chunk_root.add_child(totem_node)
		totem_node.global_position = totem_position
		if totem_node.has_method("set_totem_id"):
			var totem_id_variant: Variant = operation.get("totem_id", "")
			totem_node.call("set_totem_id", StringName(String(totem_id_variant)))
		var chunk_data = _get_or_create_chunk_data(chunk_id)
		chunk_data.set_totem_spawned(totem_position)
		var totem_ref: Totem = totem_node as Totem
		if totem_ref != null:
			var completed_callback: Callable = Callable(self, "_on_chunk_totem_completed").bind(chunk_id)
			if not totem_ref.completed.is_connected(completed_callback):
				totem_ref.completed.connect(completed_callback, CONNECT_ONE_SHOT)
		return true
	return false

func _random_position_in_chunk(chunk_id: Vector2i, rng: RandomNumberGenerator) -> Vector3:
	var world_x := chunk_id.x * chunk_size + rng.randf_range(1.0, chunk_size - 1.0)
	var world_z := chunk_id.y * chunk_size + rng.randf_range(1.0, chunk_size - 1.0)
	var world_y := terrain_height(world_x, world_z)
	return Vector3(world_x, world_y, world_z)

func _should_spawn_totem_in_chunk(chunk_id: Vector2i) -> bool:
	var chunk_data = _get_or_create_chunk_data(chunk_id)
	if chunk_data.totem_state == ChunkDataModel.TotemState.COMPLETED:
		return false
	if chunk_data.totem_state == ChunkDataModel.TotemState.SPAWNED:
		return true
	if chunk_data.totem_state == ChunkDataModel.TotemState.NONE:
		return false
	var grid_size: int = maxi(totem_distribution_grid_size_chunks, 2)
	var macro_x: int = int(floor(float(chunk_id.x) / float(grid_size)))
	var macro_y: int = int(floor(float(chunk_id.y) / float(grid_size)))
	var local_x: int = posmod(chunk_id.x, grid_size)
	var local_y: int = posmod(chunk_id.y, grid_size)

	var cell_hash: int = absi(int(hash("%s:totem_cell:%s:%s" % [world_seed, macro_x, macro_y])))
	var selected_cell_index: int = cell_hash % (grid_size * grid_size)
	var selected_local_x: int = selected_cell_index % grid_size
	var selected_local_y: int = int(selected_cell_index / grid_size)
	if local_x != selected_local_x or local_y != selected_local_y:
		return false

	var target_density: float = clampf(totem_spawn_chance_per_chunk * totem_density_multiplier, 0.0, 1.0)
	var grid_density: float = 1.0 / float(grid_size * grid_size)
	var activation_probability: float = clampf(target_density / grid_density, 0.0, 1.0)
	var roll_hash: int = absi(int(hash("%s:totem_roll:%s:%s" % [world_seed, macro_x, macro_y])))
	var roll: float = float(roll_hash % 10000) / 10000.0
	return roll <= activation_probability

func _compute_totem_spawn_position(chunk_id: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var attempts: int = 8
	for _i in range(attempts):
		var position: Vector3 = _random_position_in_chunk(chunk_id, rng)
		if position.y <= WATER_LEVEL + 0.2:
			continue
		position += Vector3(0.0, 0.2, 0.0)
		if _is_totem_spawn_position_clear(position):
			return {
				"valid": true,
				"position": position
			}
	return {
		"valid": false
	}

func _is_totem_spawn_position_clear(position: Vector3) -> bool:
	var min_distance_squared: float = totem_min_spawn_distance * totem_min_spawn_distance
	for chunk_data_variant in _chunk_data_store.values():
		var chunk_data = chunk_data_variant
		if chunk_data == null:
			continue
		if chunk_data.totem_state != ChunkDataModel.TotemState.SPAWNED and chunk_data.totem_state != ChunkDataModel.TotemState.COMPLETED:
			continue
		var existing_position: Vector3 = chunk_data.totem_position
		if existing_position.distance_squared_to(position) < min_distance_squared:
			return false
	for pending_operation in _pending_spawn_operations:
		if String(pending_operation.get("type", "")) != "totem":
			continue
		var pending_position_variant: Variant = pending_operation.get("position", Vector3.ZERO)
		if not (pending_position_variant is Vector3):
			continue
		var pending_position: Vector3 = pending_position_variant
		if pending_position.distance_squared_to(position) < min_distance_squared:
			return false
	return true

func _chunk_center(chunk_id: Vector2i) -> Vector2:
	return Vector2(
		chunk_id.x * chunk_size + chunk_size * 0.5,
		chunk_id.y * chunk_size + chunk_size * 0.5
	)

func _chunk_seed(chunk_id: Vector2i) -> int:
	return int(hash("%s:%s:%s" % [world_seed, chunk_id.x, chunk_id.y]))

func _get_or_create_chunk_data(chunk_id: Vector2i):
	var existing_variant: Variant = _chunk_data_store.get(chunk_id, null)
	var existing_data = existing_variant
	if existing_data != null:
		existing_data.touch()
		return existing_data
	var new_data = ChunkDataModel.new()
	new_data.chunk_id = chunk_id
	new_data.seed = _chunk_seed(chunk_id)
	new_data.touch()
	_chunk_data_store[chunk_id] = new_data
	return new_data

func _trim_chunk_data_cache(player_chunk: Vector2i) -> void:
	var cache_limit: int = maxi(max_cached_chunk_data_entries, 64)
	if _chunk_data_store.size() <= cache_limit:
		return
	var retention_distance: int = maxi(chunk_data_retention_distance_chunks, _view_distance_chunks + 1)
	var retention_distance_squared: int = retention_distance * retention_distance
	var eviction_candidates: Array[Dictionary] = []
	for chunk_key in _chunk_data_store.keys():
		if not (chunk_key is Vector2i):
			continue
		var chunk_id: Vector2i = chunk_key
		var chunk_data_variant: Variant = _chunk_data_store[chunk_id]
		var chunk_data = chunk_data_variant
		if chunk_data == null:
			continue
		if _loaded_chunks.has(chunk_id):
			continue
		if chunk_data.has_runtime_changes:
			continue
		if int(chunk_id.distance_squared_to(player_chunk)) <= retention_distance_squared:
			continue
		eviction_candidates.append({
			"chunk_id": chunk_id,
			"last_touched_usec": chunk_data.last_touched_usec
		})
	if eviction_candidates.is_empty():
		return
	eviction_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("last_touched_usec", 0)) < int(b.get("last_touched_usec", 0))
	)
	var remove_count: int = _chunk_data_store.size() - cache_limit
	var removed: int = 0
	for entry in eviction_candidates:
		if removed >= remove_count:
			break
		var chunk_id: Vector2i = entry.get("chunk_id", Vector2i.ZERO)
		_chunk_data_store.erase(chunk_id)
		removed += 1

func _on_chunk_totem_completed(_totem_id: StringName, chunk_id: Vector2i) -> void:
	var chunk_data = _get_or_create_chunk_data(chunk_id)
	chunk_data.set_totem_completed()

func _drop_pending_operations_for_chunk(chunk_id: Vector2i) -> void:
	var retained: Array[Dictionary] = []
	for operation in _pending_spawn_operations:
		if operation.get("chunk_id", Vector2i.ZERO) != chunk_id:
			retained.append(operation)
	_pending_spawn_operations = retained

func _schedule_debug_diagnostics_once() -> void:
	if not debug_enable_scene_diagnostics or not debug_diagnostics_auto_once:
		return
	var delay_seconds: float = maxf(debug_diagnostics_delay_seconds, 0.0)
	if delay_seconds <= 0.0:
		_run_debug_scene_diagnostics()
		return
	var tree_ref: SceneTree = get_tree()
	if tree_ref == null:
		return
	var timer: SceneTreeTimer = tree_ref.create_timer(delay_seconds)
	timer.timeout.connect(Callable(self, "_run_debug_scene_diagnostics"), CONNECT_ONE_SHOT)

func _run_debug_scene_diagnostics() -> void:
	if not debug_enable_scene_diagnostics:
		return
	var tree_ref: SceneTree = get_tree()
	if tree_ref == null:
		return
	var root: Node = tree_ref.current_scene
	if root == null:
		return
	var type_counts: Dictionary = _collect_node_type_counts(root)
	var top_lines: PackedStringArray = _build_top_type_lines(type_counts, maxi(debug_diagnostics_top_types, 1))
	var chunk_lines: PackedStringArray = _build_chunk_diagnostic_lines()
	print("===== [DebugDiagnostics] Node Types Top %d =====" % maxi(debug_diagnostics_top_types, 1))
	for line in top_lines:
		print(line)
	print("===== [DebugDiagnostics] Chunk Report =====")
	for line in chunk_lines:
		print(line)

func _collect_node_type_counts(root: Node) -> Dictionary:
	var counts: Dictionary = {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var node_type_name: String = node.get_class()
		counts[node_type_name] = int(counts.get(node_type_name, 0)) + 1
		for child_variant in node.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	return counts

func _build_top_type_lines(type_counts: Dictionary, top_limit: int) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var keys: Array = type_counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		var class_a: String = String(a)
		var class_b: String = String(b)
		var count_a: int = int(type_counts.get(class_a, 0))
		var count_b: int = int(type_counts.get(class_b, 0))
		if count_a == count_b:
			return class_a < class_b
		return count_a > count_b
	)
	var result_count: int = mini(top_limit, keys.size())
	for i in range(result_count):
		var node_type_name: String = String(keys[i])
		lines.append("%s: %d" % [node_type_name, int(type_counts.get(node_type_name, 0))])
	return lines

func _build_chunk_diagnostic_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var chunk_entries: Array[Dictionary] = []
	var total_direct_objects: int = 0
	var total_subtree_nodes: int = 0
	for chunk_key in _loaded_chunks.keys():
		if not (chunk_key is Vector2i):
			continue
		var chunk_id: Vector2i = chunk_key
		var chunk_root_variant: Variant = _loaded_chunks[chunk_id]
		var chunk_root: Node = chunk_root_variant as Node
		if chunk_root == null or not is_instance_valid(chunk_root):
			continue
		var direct_objects: int = chunk_root.get_child_count()
		var subtree_nodes: int = _count_subtree_nodes(chunk_root)
		total_direct_objects += direct_objects
		total_subtree_nodes += subtree_nodes
		chunk_entries.append({
			"chunk_id": chunk_id,
			"direct_objects": direct_objects,
			"subtree_nodes": subtree_nodes
		})
	var loaded_chunks_count: int = chunk_entries.size()
	var avg_direct: float = 0.0
	var avg_nodes: float = 0.0
	if loaded_chunks_count > 0:
		avg_direct = float(total_direct_objects) / float(loaded_chunks_count)
		avg_nodes = float(total_subtree_nodes) / float(loaded_chunks_count)
	var dirty_chunk_data_count: int = 0
	for chunk_data_variant in _chunk_data_store.values():
		var chunk_data = chunk_data_variant
		if chunk_data != null and chunk_data.has_runtime_changes:
			dirty_chunk_data_count += 1
	lines.append("Chunks loaded: %d" % loaded_chunks_count)
	lines.append("ChunkData cached: %d (dirty=%d)" % [_chunk_data_store.size(), dirty_chunk_data_count])
	if _loot_system != null and _loot_system.has_method("get_debug_counts"):
		var loot_debug_variant: Variant = _loot_system.call("get_debug_counts")
		if loot_debug_variant is Dictionary:
			var loot_debug: Dictionary = loot_debug_variant
			lines.append(
				"Loot debug: pool=%d active=%d pending=%d chunk_buckets=%d" % [
					int(loot_debug.get("pool_size", 0)),
					int(loot_debug.get("active_loot", 0)),
					int(loot_debug.get("pending_spawns", 0)),
					int(loot_debug.get("chunk_buckets", 0))
				]
			)
	lines.append("Average objects per chunk (direct children): %.2f" % avg_direct)
	lines.append("Average nodes per chunk (full subtree): %.2f" % avg_nodes)
	chunk_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_nodes: int = int(a.get("subtree_nodes", 0))
		var b_nodes: int = int(b.get("subtree_nodes", 0))
		if a_nodes == b_nodes:
			var a_id: Vector2i = a.get("chunk_id", Vector2i.ZERO)
			var b_id: Vector2i = b.get("chunk_id", Vector2i.ZERO)
			if a_id.x == b_id.x:
				return a_id.y < b_id.y
			return a_id.x < b_id.x
		return a_nodes > b_nodes
	)
	lines.append("Nodes created per chunk:")
	for entry in chunk_entries:
		var chunk_id: Vector2i = entry.get("chunk_id", Vector2i.ZERO)
		var direct_objects: int = int(entry.get("direct_objects", 0))
		var subtree_nodes: int = int(entry.get("subtree_nodes", 0))
		lines.append("Chunk(%d,%d): direct=%d total_nodes=%d" % [chunk_id.x, chunk_id.y, direct_objects, subtree_nodes])
	return lines

func _count_subtree_nodes(root: Node) -> int:
	var total: int = 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		total += 1
		for child_variant in node.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	return total

func _get_game_state() -> Node:
	return get_node_or_null("/root/GameState")

func _apply_game_config() -> void:
	chunk_size = GameConfig.CHUNK_SIZE
	terrain_height_scale = GameConfig.TERRAIN_HEIGHT_SCALE
	max_spawn_operations_per_frame = GameConfig.MAX_SPAWN_OPERATIONS_PER_FRAME
	_view_distance_chunks = GameConfig.VIEW_DISTANCE_CHUNKS
	_max_active_chunks = GameConfig.MAX_ACTIVE_CHUNKS
	_lod_cull_distance_chunks = GameConfig.LOD_CULL_DISTANCE_CHUNKS
	_resource_spawns_per_chunk = GameConfig.RESOURCE_SPAWNS_PER_CHUNK
	_ground_pickups_per_chunk = GameConfig.GROUND_PICKUPS_PER_CHUNK
	_terrain_resolution = GameConfig.TERRAIN_RESOLUTION
