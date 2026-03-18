extends Node
class_name ResourceSystem

const RESOURCE_DATA_PATH: String = "res://data/resources/resource_types.json"
const RESOURCE_NODE_SCRIPT: Script = preload("res://resource/scripts/resource_node.gd")
const DEBUG_RESOURCE_RUNTIME: bool = false
const TREE_RESOURCE_TYPES: Dictionary = {"tree": true}
const ROCK_RESOURCE_TYPES: Dictionary = {"rock": true, "big_rock": true}
const BOX_RESOURCE_TYPES: Dictionary = {"crate": true, "log": true, "chest": true}
const DEFAULT_RESOURCE_DEFINITIONS: Dictionary = {
	"tree": {
		"required_tool": "axe",
		"drop_item_id": "wood",
		"drop_amount": 3,
		"drop_min_amount": 3,
		"drop_max_amount": 12,
		"drop_table": [
			{"item_id": "wood", "amount": 3}
		],
		"max_hp": 3.0,
		"scene_path": "res://resource/scenes/tree_resource.tscn",
		"visual_scale": 1.0,
		"visual_offset_y": 0.0,
		"collision_mode": "tree_profile",
		"trunk_radius": 0.48,
		"trunk_height": 3.2,
		"trunk_offset_y": 1.6,
		"base_block_enabled": true,
		"base_block_radius": 0.62,
		"base_block_height": 1.6,
		"base_block_offset_y": 0.8,
		"base_sample_height_ratio": 0.4,
		"trunk_sample_height_ratio": 0.58,
		"trunk_height_ratio": 0.72,
		"base_block_padding": 0.06,
		"trunk_padding": 0.03,
		"trunk_min_radius": 0.22,
		"base_block_min_radius": 0.4,
		"base_block_min_height": 0.8,
		"collision_type": "tree",
		"tree_collider_shape": "cylinder",
		"debug_show_collision": false,
		"debug_trunk_color": Color(0.14, 0.86, 1.0, 0.26),
		"debug_base_color": Color(1.0, 0.72, 0.18, 0.22),
		"mesh_kind": "cylinder",
		"radius": 0.42,
		"height": 2.3,
		"offset_y": 1.15,
		"color": Color(0.2, 0.67, 0.26, 1.0)
	},
	"rock": {
		"required_tool": "pickaxe",
		"drop_item_id": "stone",
		"drop_amount": 3,
		"drop_min_amount": 3,
		"drop_max_amount": 12,
		"drop_table": [
			{"item_id": "stone", "amount": 3}
		],
		"max_hp": 4.0,
		"collision_type": "rock",
		"rock_collider_shape": "sphere",
		"mesh_kind": "sphere",
		"radius": 0.62,
		"height": 1.24,
		"offset_y": 0.62,
		"color": Color(0.53, 0.56, 0.61, 1.0)
	},
	"big_rock": {
		"required_tool": "pickaxe",
		"drop_item_id": "stone",
		"drop_amount": 3,
		"drop_min_amount": 3,
		"drop_max_amount": 12,
		"drop_table": [
			{"item_id": "stone", "amount": 3}
		],
		"max_hp": 8.0,
		"collision_type": "rock",
		"rock_collider_shape": "sphere",
		"mesh_kind": "sphere",
		"radius": 1.0,
		"height": 2.0,
		"offset_y": 1.0,
		"color": Color(0.46, 0.49, 0.55, 1.0)
	}
}

const BASE_HAND_DAMAGE: float = 0.35
const CORRECT_TOOL_DAMAGE: float = 2.0
const WRONG_TOOL_DAMAGE: float = 0.2

@export_group("Tree Visual")
@export var tree_visual_scene: PackedScene = preload("res://resource/scenes/tree_resource.tscn")
@export_range(0.05, 10.0, 0.01) var tree_visual_scale: float = 1.0
@export_range(-10.0, 10.0, 0.01) var tree_visual_offset_y: float = 0.0

@export_group("Tree Collision")
@export_enum("tree_profile", "trunk", "visual_bounds") var tree_collision_mode: String = "tree_profile"
@export_enum("cylinder", "capsule") var tree_collider_shape: String = "cylinder"
@export_range(0.05, 10.0, 0.01) var tree_trunk_radius: float = 0.48
@export_range(0.1, 20.0, 0.01) var tree_trunk_height: float = 3.2
@export_range(-10.0, 10.0, 0.01) var tree_trunk_offset_y: float = 1.6
@export var tree_base_block_enabled: bool = true
@export_range(0.05, 10.0, 0.01) var tree_base_block_radius: float = 0.62
@export_range(0.1, 20.0, 0.01) var tree_base_block_height: float = 1.6
@export_range(-10.0, 10.0, 0.01) var tree_base_block_offset_y: float = 0.8

@export_group("Tree Debug")
@export var tree_debug_show_collision: bool = false
@export var tree_debug_trunk_color: Color = Color(0.14, 0.86, 1.0, 0.26)
@export var tree_debug_base_color: Color = Color(1.0, 0.72, 0.18, 0.22)

var _resources_by_chunk: Dictionary = {}
var _resource_definitions: Dictionary = {}
var _visual_scene_cache: Dictionary = {}
var _tree_collision_profile_cache: Dictionary = {}

func _ready() -> void:
	_load_resource_definitions()
	_apply_inspector_resource_overrides()

func spawn_resource(chunk_root: Node3D, world_position: Vector3, resource_type: String, chunk_id: Vector2i) -> Node3D:
	if chunk_root == null:
		return null
	var definition: Dictionary = _get_resource_definition(resource_type)
	var scene_path: String = String(definition.get("scene_path", ""))
	if not scene_path.is_empty():
		return _spawn_authored_resource_scene(chunk_root, world_position, resource_type, chunk_id, definition)

	var resource_root_variant: Variant = RESOURCE_NODE_SCRIPT.new()
	var resource_root: Node3D = resource_root_variant as Node3D
	if resource_root == null:
		resource_root = Node3D.new()
	_configure_spawned_resource_root(resource_root, resource_type, chunk_id, definition)
	chunk_root.add_child(resource_root)
	if resource_root.is_inside_tree():
		resource_root.global_position = world_position
	else:
		resource_root.position = world_position

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 1
	body.set_meta("resource_root", resource_root)
	resource_root.add_child(body)

	var collider: CollisionShape3D = CollisionShape3D.new()
	var mesh_kind: String = String(definition.get("mesh_kind", "sphere"))
	var radius: float = float(definition.get("radius", 0.6))
	var height: float = float(definition.get("height", radius * 2.0))
	var offset_y: float = float(definition.get("offset_y", height * 0.5))
	var has_custom_visual: bool = _try_attach_custom_visual(resource_root, definition)
	if not has_custom_visual:
		body.position = Vector3(0.0, offset_y, 0.0)
		_configure_primitive_resource_collider(collider, resource_type, definition, mesh_kind, radius, height, resource_root)
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = definition.get("color", Color(0.6, 0.6, 0.6, 1.0))
		material.roughness = 0.88
		if mesh_kind == "cylinder":
			var cylinder_mesh: CylinderMesh = CylinderMesh.new()
			cylinder_mesh.top_radius = radius
			cylinder_mesh.bottom_radius = radius
			cylinder_mesh.height = height
			mesh_instance.mesh = cylinder_mesh
		else:
			var sphere_mesh: SphereMesh = SphereMesh.new()
			sphere_mesh.radius = radius
			sphere_mesh.height = height
			mesh_instance.mesh = sphere_mesh
		mesh_instance.material_override = material
		body.add_child(mesh_instance)
	else:
		var collision_mode: String = String(definition.get("collision_mode", "trunk"))
		if collision_mode == "visual_bounds":
			body.position = Vector3.ZERO
			var configured_from_visual: bool = _configure_collider_from_visual(collider, resource_root, definition)
			if not configured_from_visual:
				body.position = Vector3(0.0, offset_y, 0.0)
				_configure_primitive_resource_collider(collider, resource_type, definition, mesh_kind, radius, height, resource_root)
			_maybe_add_tree_collision_debug_visual(body, definition, collider.shape, collider.position, "TrunkDebug", Color(0.14, 0.86, 1.0, 0.26))
		elif collision_mode == "tree_profile":
			body.position = Vector3.ZERO
			var applied_profile: bool = _apply_tree_profile_collision(body, collider, resource_root, definition)
			if not applied_profile:
				var trunk_radius_fallback: float = maxf(float(definition.get("trunk_radius", radius)), 0.1)
				var trunk_height_fallback: float = maxf(float(definition.get("trunk_height", height)), 0.3)
				var trunk_offset_y_fallback: float = float(definition.get("trunk_offset_y", trunk_height_fallback * 0.5))
				_configure_primitive_resource_collider(
					collider,
					"tree",
					definition,
					"cylinder",
					trunk_radius_fallback,
					trunk_height_fallback,
					resource_root
				)
				collider.position = Vector3(0.0, trunk_offset_y_fallback, 0.0)
				_maybe_add_tree_collision_debug_visual(body, definition, collider.shape, collider.position, "TrunkDebug", Color(0.14, 0.86, 1.0, 0.26))
				_add_tree_base_blocking_collider(body, definition, trunk_radius_fallback)
		else:
			var trunk_radius: float = maxf(float(definition.get("trunk_radius", radius)), 0.1)
			var trunk_height: float = maxf(float(definition.get("trunk_height", height)), 0.3)
			var trunk_offset_y: float = float(definition.get("trunk_offset_y", trunk_height * 0.5))
			body.position = Vector3.ZERO
			_configure_primitive_resource_collider(collider, "tree", definition, "cylinder", trunk_radius, trunk_height, resource_root)
			collider.position = Vector3(0.0, trunk_offset_y, 0.0)
			_maybe_add_tree_collision_debug_visual(body, definition, collider.shape, collider.position, "TrunkDebug", Color(0.14, 0.86, 1.0, 0.26))
			_add_tree_base_blocking_collider(body, definition, trunk_radius)
	body.add_child(collider)

	if not _resources_by_chunk.has(chunk_id):
		_resources_by_chunk[chunk_id] = []
	var resources_variant: Variant = _resources_by_chunk[chunk_id]
	var resources: Array = resources_variant if resources_variant is Array else []
	resources.append(resource_root)
	_resources_by_chunk[chunk_id] = resources
	return resource_root

func _configure_resource_root_metadata(resource_root: Node3D, resource_type: String, chunk_id: Vector2i, definition: Dictionary) -> void:
	if resource_root == null:
		return
	resource_root.name = "Resource_%s_%s_%s" % [resource_type, chunk_id.x, chunk_id.y]
	resource_root.add_to_group("resource")
	resource_root.set_meta("resource_type", resource_type)
	resource_root.set_meta("resource_id", resource_type)
	resource_root.set_meta("chunk_id", chunk_id)
	resource_root.set_meta("required_tool", String(definition.get("required_tool", "")))
	resource_root.set_meta("item_id", String(definition.get("drop_item_id", "wood")))
	resource_root.set_meta("amount", int(definition.get("drop_amount", 1)))
	resource_root.set_meta("drop_min_amount", int(definition.get("drop_min_amount", definition.get("drop_amount", 1))))
	resource_root.set_meta("drop_max_amount", int(definition.get("drop_max_amount", definition.get("drop_amount", 1))))
	resource_root.set_meta("drop_table", definition.get("drop_table", []).duplicate(true))
	resource_root.set_meta("hit_points", float(definition.get("max_hp", 1.0)))
	resource_root.set_meta("max_hit_points", float(definition.get("max_hp", 1.0)))

func _configure_spawned_resource_root(resource_root: Node3D, resource_type: String, chunk_id: Vector2i, definition: Dictionary) -> void:
	if resource_root == null:
		return
	resource_root.name = "Resource_%s_%s_%s" % [resource_type, chunk_id.x, chunk_id.y]
	if resource_root.has_method("configure_from_definition"):
		resource_root.call("configure_from_definition", resource_type, chunk_id, definition)
	else:
		_configure_resource_root_metadata(resource_root, resource_type, chunk_id, definition)
		_ensure_resource_health_component(resource_root, definition)
	if resource_root.has_method("bind_resource_system"):
		resource_root.call("bind_resource_system", self)
	else:
		resource_root.set_meta("resource_system", self)

func _register_resource_in_chunk(chunk_id: Vector2i, resource_root: Node3D) -> void:
	if resource_root == null:
		return
	if not _resources_by_chunk.has(chunk_id):
		_resources_by_chunk[chunk_id] = []
	var resources_variant: Variant = _resources_by_chunk[chunk_id]
	var resources: Array = resources_variant if resources_variant is Array else []
	resources.append(resource_root)
	_resources_by_chunk[chunk_id] = resources

func _apply_inspector_resource_overrides() -> void:
	var tree_definition_variant: Variant = _resource_definitions.get("tree", {})
	if not (tree_definition_variant is Dictionary):
		return
	var tree_definition: Dictionary = Dictionary(tree_definition_variant).duplicate(true)
	tree_definition["collision_type"] = "tree"
	tree_definition["tree_collider_shape"] = tree_collider_shape
	tree_definition["collision_mode"] = tree_collision_mode
	tree_definition["trunk_radius"] = maxf(tree_trunk_radius, 0.05)
	tree_definition["trunk_height"] = maxf(tree_trunk_height, 0.1)
	tree_definition["trunk_offset_y"] = tree_trunk_offset_y
	tree_definition["base_block_enabled"] = tree_base_block_enabled
	tree_definition["base_block_radius"] = maxf(tree_base_block_radius, 0.05)
	tree_definition["base_block_height"] = maxf(tree_base_block_height, 0.1)
	tree_definition["base_block_offset_y"] = tree_base_block_offset_y
	tree_definition["debug_show_collision"] = tree_debug_show_collision
	tree_definition["debug_trunk_color"] = tree_debug_trunk_color
	tree_definition["debug_base_color"] = tree_debug_base_color
	tree_definition["visual_scale"] = maxf(tree_visual_scale, 0.01)
	tree_definition["visual_offset_y"] = tree_visual_offset_y
	if tree_visual_scene != null and not tree_visual_scene.resource_path.is_empty():
		var tree_scene_path: String = tree_visual_scene.resource_path
		if tree_scene_path.ends_with(".tscn") or tree_scene_path.ends_with(".scn"):
			tree_definition["scene_path"] = tree_scene_path
	_resource_definitions["tree"] = tree_definition

func _try_attach_custom_visual(resource_root: Node3D, definition: Dictionary) -> bool:
	var scene_path: String = String(definition.get("scene_path", ""))
	if scene_path.is_empty():
		return false
	var visual_scene: PackedScene = _resolve_visual_scene(scene_path)
	if visual_scene == null:
		return false
	var visual_variant: Variant = visual_scene.instantiate()
	if not (visual_variant is Node3D):
		return false
	var visual_root: Node3D = visual_variant as Node3D
	if visual_root == null:
		return false
	var visual_scale: float = float(definition.get("visual_scale", 1.0))
	var visual_offset_y: float = float(definition.get("visual_offset_y", 0.0))
	visual_root.scale = Vector3.ONE * visual_scale
	visual_root.position = Vector3.ZERO
	resource_root.add_child(visual_root)
	_align_visual_to_resource_origin(visual_root, visual_offset_y)
	var fallback_color: Color = _parse_color(definition.get("color", Color(0.2, 0.67, 0.26, 1.0)), Color(0.2, 0.67, 0.26, 1.0))
	_apply_fallback_material_if_missing(visual_root, fallback_color)
	return true

func _spawn_authored_resource_scene(
	chunk_root: Node3D,
	world_position: Vector3,
	resource_type: String,
	chunk_id: Vector2i,
	definition: Dictionary
) -> Node3D:
	if chunk_root == null:
		return null
	var scene_path: String = String(definition.get("scene_path", ""))
	if scene_path.is_empty():
		return null
	var visual_scene: PackedScene = _resolve_visual_scene(scene_path)
	if visual_scene == null:
		push_warning("Resource scene could not be loaded: %s" % scene_path)
		return null
	var scene_variant: Variant = visual_scene.instantiate()
	if not (scene_variant is Node3D):
		push_warning("Resource scene is not a Node3D: %s" % scene_path)
		return null
	var scene_root: Node3D = scene_variant as Node3D
	if scene_root == null:
		return null
	_configure_spawned_resource_root(scene_root, resource_type, chunk_id, definition)
	var visual_scale: float = float(definition.get("visual_scale", 1.0))
	var visual_offset_y: float = float(definition.get("visual_offset_y", 0.0))
	scene_root.scale = Vector3.ONE * visual_scale
	chunk_root.add_child(scene_root)
	if scene_root.is_inside_tree():
		scene_root.global_position = world_position
	else:
		scene_root.position = world_position
	scene_root.position += Vector3(0.0, visual_offset_y, 0.0)
	_refresh_authored_scene_runtime_collision(scene_root)
	if not _scene_has_authored_collision(scene_root):
		scene_root.queue_free()
		push_warning("Resource scene has no collision shapes: %s" % scene_path)
		return null
	scene_root.owner = chunk_root.owner
	scene_root.set_meta("resource_root", scene_root)
	scene_root.set_meta("authored_resource_scene", scene_root)
	var fallback_color: Color = _parse_color(definition.get("color", Color(0.2, 0.67, 0.26, 1.0)), Color(0.2, 0.67, 0.26, 1.0))
	_apply_fallback_material_if_missing(scene_root, fallback_color)
	_bind_resource_root_to_authored_scene(scene_root, scene_root)
	_register_authored_scene_drop_origin(scene_root, scene_root)
	_register_resource_in_chunk(chunk_id, scene_root)
	if DEBUG_RESOURCE_RUNTIME and resource_type == "tree":
		var script_resource: Script = scene_root.get_script() as Script
		_debug_resource_log(
			"spawn_tree scene_path=%s runtime_node=%s class=%s script=%s path=%s has_apply_resource_damage=%s has_meta_resource_root=%s" % [
				scene_path,
				scene_root.name,
				scene_root.get_class(),
				script_resource.resource_path if script_resource != null else "<no_script>",
				String(scene_root.get_path()),
				str(scene_root.has_method("apply_resource_damage")),
				str(scene_root.has_meta("resource_root"))
			]
		)
	return scene_root

func _ensure_resource_health_component(resource_root: Node3D, definition: Dictionary) -> void:
	if resource_root == null:
		return
	var max_hp: float = maxf(float(definition.get("max_hp", 1.0)), 0.1)
	var health_component: HealthComponent = resource_root.get_node_or_null("HealthComponent") as HealthComponent
	if health_component == null:
		health_component = HealthComponent.new()
		health_component.name = "HealthComponent"
		health_component.max_health = max_hp
		resource_root.add_child(health_component)
	else:
		health_component.max_health = max_hp
	health_component.current_health = max_hp
	if resource_root.has_meta("hit_points"):
		resource_root.set_meta("hit_points", max_hp)
	resource_root.set_meta("max_hit_points", max_hp)

func _get_resource_health_component(resource_root: Node3D) -> HealthComponent:
	if resource_root == null:
		return null
	return resource_root.get_node_or_null("HealthComponent") as HealthComponent

func _refresh_authored_scene_runtime_collision(scene_root: Node) -> void:
	if scene_root == null:
		return
	if scene_root.has_method("requires_runtime_collision_rebuild"):
		var needs_rebuild_variant: Variant = scene_root.call("requires_runtime_collision_rebuild")
		if needs_rebuild_variant is bool and not bool(needs_rebuild_variant):
			return
	if scene_root.has_method("rebuild_collision_now"):
		scene_root.call("rebuild_collision_now")

func _scene_has_authored_collision(root: Node) -> bool:
	if root == null:
		return false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is CollisionShape3D or current is CollisionPolygon3D:
			return true
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	return false

func _bind_resource_root_to_authored_scene(resource_root: Node3D, scene_root: Node) -> void:
	if resource_root == null or scene_root == null:
		return
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		current.set_meta("resource_root", resource_root)
		if current is CollisionObject3D:
			var collision_object: CollisionObject3D = current as CollisionObject3D
			collision_object.set_meta("resource_root", resource_root)
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)

func _register_authored_scene_drop_origin(resource_root: Node3D, scene_root: Node) -> void:
	if resource_root == null or scene_root == null:
		return
	var drop_origin: Node3D = _find_authored_scene_drop_origin(scene_root)
	if drop_origin == null:
		return
	resource_root.set_meta("drop_origin_path", resource_root.get_path_to(drop_origin))

func _find_authored_scene_drop_origin(root: Node) -> Node3D:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		var current_3d: Node3D = current as Node3D
		if current_3d != null:
			var lowered_name: String = String(current_3d.name).to_lower()
			if current_3d.is_in_group("resource_drop_origin") or lowered_name == "droporigin" or lowered_name == "drop_origin" or lowered_name == "lootorigin":
				return current_3d
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	return null

func _align_visual_to_resource_origin(visual_root: Node3D, additional_y_offset: float) -> void:
	if visual_root == null:
		return
	var bounds: Dictionary = _compute_visual_local_bounds(visual_root)
	if not bool(bounds.get("valid", false)):
		visual_root.position = Vector3(0.0, additional_y_offset, 0.0)
		return
	var min_v: Vector3 = bounds.get("min", Vector3.ZERO)
	var max_v: Vector3 = bounds.get("max", Vector3.ZERO)
	var center_x: float = (min_v.x + max_v.x) * 0.5
	var center_z: float = (min_v.z + max_v.z) * 0.5
	visual_root.position = Vector3(-center_x, -min_v.y + additional_y_offset, -center_z)

func _configure_primitive_resource_collider(
	collider: CollisionShape3D,
	resource_type: String,
	definition: Dictionary,
	mesh_kind: String,
	radius: float,
	height: float,
	resource_root: Node3D = null
) -> void:
	if collider == null:
		return
	var shape: Shape3D = _create_collision_shape_for_object_type(
		resource_type,
		definition,
		mesh_kind,
		radius,
		height,
		resource_root
	)
	if shape == null:
		shape = _create_sphere_collision_shape(radius)
	collider.shape = shape

func _create_collision_shape_for_object_type(
	resource_type: String,
	definition: Dictionary,
	mesh_kind: String,
	radius: float,
	height: float,
	resource_root: Node3D = null
) -> Shape3D:
	var collision_type: String = _resolve_collision_object_type(resource_type, definition)
	if collision_type == "tree":
		return _create_tree_collision_shape(definition, radius, height)
	if collision_type == "rock":
		var rock_shape_mode: String = String(definition.get("rock_collider_shape", "sphere"))
		if rock_shape_mode == "convex":
			var convex_shape: ConvexPolygonShape3D = _create_convex_collision_shape(resource_root)
			if convex_shape != null:
				return convex_shape
		return _create_sphere_collision_shape(radius)
	if collision_type == "box":
		return _create_box_collision_shape(definition, radius, height)
	if mesh_kind == "cylinder":
		return _create_cylinder_collision_shape(radius, height)
	return _create_sphere_collision_shape(radius)

func _resolve_collision_object_type(resource_type: String, definition: Dictionary) -> String:
	var explicit_type: String = String(definition.get("collision_type", "")).to_lower()
	if not explicit_type.is_empty():
		return explicit_type
	var resource_key: String = resource_type.to_lower()
	if TREE_RESOURCE_TYPES.has(resource_key):
		return "tree"
	if ROCK_RESOURCE_TYPES.has(resource_key):
		return "rock"
	if BOX_RESOURCE_TYPES.has(resource_key):
		return "box"
	return "default"

func _create_tree_collision_shape(definition: Dictionary, radius: float, height: float) -> Shape3D:
	var tree_shape_mode: String = String(definition.get("tree_collider_shape", "cylinder"))
	var trunk_radius: float = maxf(float(definition.get("trunk_radius", radius)), 0.1)
	var trunk_height: float = maxf(float(definition.get("trunk_height", height)), 0.3)
	if tree_shape_mode == "capsule":
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = trunk_radius
		capsule.height = trunk_height
		return capsule
	return _create_cylinder_collision_shape(trunk_radius, trunk_height)

func _create_box_collision_shape(definition: Dictionary, radius: float, height: float) -> BoxShape3D:
	var box_width: float = maxf(float(definition.get("box_width", radius * 2.0)), 0.2)
	var box_height: float = maxf(float(definition.get("box_height", height)), 0.2)
	var box_depth: float = maxf(float(definition.get("box_depth", radius * 2.0)), 0.2)
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(box_width, box_height, box_depth)
	return box

func _create_cylinder_collision_shape(radius: float, height: float) -> CylinderShape3D:
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = maxf(radius, 0.1)
	shape.height = maxf(height, 0.2)
	return shape

func _create_sphere_collision_shape(radius: float) -> SphereShape3D:
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = maxf(radius, 0.1)
	return shape

func _create_convex_collision_shape(resource_root: Node3D) -> ConvexPolygonShape3D:
	if resource_root == null:
		return null
	var points_array: Array[Vector3] = _collect_resource_mesh_points(resource_root)
	if points_array.size() < 4:
		return null
	var packed_points: PackedVector3Array = PackedVector3Array()
	for point in points_array:
		packed_points.append(point)
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	shape.points = packed_points
	return shape

func _add_tree_base_blocking_collider(
	body: StaticBody3D,
	definition: Dictionary,
	trunk_radius: float,
	base_radius_override: float = -1.0,
	base_height_override: float = -1.0,
	base_offset_y_override: float = -1.0
) -> void:
	if body == null:
		return
	if not bool(definition.get("base_block_enabled", true)):
		return
	var base_radius: float = base_radius_override if base_radius_override > 0.0 else float(definition.get("base_block_radius", trunk_radius * 1.25))
	var base_height: float = base_height_override if base_height_override > 0.0 else float(definition.get("base_block_height", 1.4))
	var base_offset_y: float = base_offset_y_override if base_offset_y_override >= 0.0 else float(definition.get("base_block_offset_y", base_height * 0.5))
	base_radius = maxf(base_radius, trunk_radius)
	base_height = maxf(base_height, 0.4)
	var blocker: CollisionShape3D = CollisionShape3D.new()
	blocker.name = "BaseBlocker"
	var blocker_shape: CylinderShape3D = CylinderShape3D.new()
	blocker_shape.radius = base_radius
	blocker_shape.height = base_height
	blocker.shape = blocker_shape
	blocker.position = Vector3(0.0, base_offset_y, 0.0)
	body.add_child(blocker)
	_maybe_add_tree_collision_debug_visual(
		body,
		definition,
		blocker.shape,
		blocker.position,
		"BaseBlockerDebug",
		Color(1.0, 0.72, 0.18, 0.22)
	)

func _apply_tree_profile_collision(
	body: StaticBody3D,
	primary_collider: CollisionShape3D,
	resource_root: Node3D,
	definition: Dictionary
) -> bool:
	if body == null or primary_collider == null or resource_root == null:
		return false
	var profile: Dictionary = _get_tree_collision_profile(resource_root, definition)
	if not bool(profile.get("valid", false)):
		return false
	var segments_variant: Variant = profile.get("segments", [])
	if not (segments_variant is Array):
		return false
	var segments: Array = segments_variant
	if segments.is_empty():
		return false
	var first_segment_variant: Variant = segments[0]
	if not (first_segment_variant is Dictionary):
		return false
	var first_segment: Dictionary = first_segment_variant
	primary_collider.shape = _create_cylinder_collision_shape(
		float(first_segment.get("radius", 0.2)),
		float(first_segment.get("height", 0.5))
	)
	primary_collider.position = Vector3(
		0.0,
		float(first_segment.get("offset_y", 0.25)),
		0.0
	)
	_maybe_add_tree_collision_debug_visual(
		body,
		definition,
		primary_collider.shape,
		primary_collider.position,
		"TreeProfileDebug0",
		Color(0.14, 0.86, 1.0, 0.26)
	)
	for segment_index in range(1, segments.size()):
		var segment_variant: Variant = segments[segment_index]
		if not (segment_variant is Dictionary):
			continue
		var segment: Dictionary = segment_variant
		var extra_collider: CollisionShape3D = CollisionShape3D.new()
		extra_collider.name = "TreeProfileCollider%d" % segment_index
		extra_collider.shape = _create_cylinder_collision_shape(
			float(segment.get("radius", 0.2)),
			float(segment.get("height", 0.5))
		)
		extra_collider.position = Vector3(
			0.0,
			float(segment.get("offset_y", 0.25)),
			0.0
		)
		body.add_child(extra_collider)
		_maybe_add_tree_collision_debug_visual(
			body,
			definition,
			extra_collider.shape,
			extra_collider.position,
			"TreeProfileDebug%d" % segment_index,
			Color(0.14, 0.86, 1.0, 0.26)
		)
	return true

func _get_tree_collision_profile(resource_root: Node3D, definition: Dictionary) -> Dictionary:
	var cache_key: String = _build_tree_collision_profile_cache_key(definition)
	if _tree_collision_profile_cache.has(cache_key):
		var cached_variant: Variant = _tree_collision_profile_cache[cache_key]
		if cached_variant is Dictionary:
			return cached_variant
	var computed: Dictionary = _compute_tree_collision_profile(resource_root, definition)
	_tree_collision_profile_cache[cache_key] = computed
	return computed

func _build_tree_collision_profile_cache_key(definition: Dictionary) -> String:
	var scene_path: String = String(definition.get("scene_path", ""))
	var visual_scale: float = float(definition.get("visual_scale", 1.0))
	var collision_mode: String = String(definition.get("collision_mode", "tree_profile"))
	var shape_mode: String = String(definition.get("tree_collider_shape", "cylinder"))
	var top_ratio: float = float(definition.get("trunk_height_ratio", 0.72))
	var base_ratio: float = float(definition.get("base_profile_end_ratio", 0.22))
	var mid_ratio: float = float(definition.get("mid_profile_end_ratio", 0.46))
	var overlap_ratio: float = float(definition.get("profile_band_overlap_ratio", 0.03))
	return "%s|%.3f|%s|%s|%.3f|%.3f|%.3f|%.3f" % [
		scene_path,
		visual_scale,
		collision_mode,
		shape_mode,
		top_ratio,
		base_ratio,
		mid_ratio,
		overlap_ratio
	]

func _maybe_add_tree_collision_debug_visual(
	body: StaticBody3D,
	definition: Dictionary,
	shape: Shape3D,
	shape_position: Vector3,
	debug_name: String,
	default_color: Color
) -> void:
	if body == null or shape == null:
		return
	if String(definition.get("collision_type", "")).to_lower() != "tree":
		return
	if not bool(definition.get("debug_show_collision", false)):
		return
	var color_key: String = "debug_base_color" if debug_name.begins_with("BaseBlocker") else "debug_trunk_color"
	var debug_color: Color = _parse_color(definition.get(color_key, default_color), default_color)
	var debug_mesh: Mesh = _create_debug_mesh_for_shape(shape)
	if debug_mesh == null:
		return
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = debug_name
	mesh_instance.mesh = debug_mesh
	mesh_instance.position = shape_position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.material_override = _create_collision_debug_material(debug_color)
	body.add_child(mesh_instance)

func _create_debug_mesh_for_shape(shape: Shape3D) -> Mesh:
	if shape is CylinderShape3D:
		var cylinder_shape: CylinderShape3D = shape as CylinderShape3D
		var cylinder_mesh: CylinderMesh = CylinderMesh.new()
		cylinder_mesh.top_radius = cylinder_shape.radius
		cylinder_mesh.bottom_radius = cylinder_shape.radius
		cylinder_mesh.height = cylinder_shape.height
		return cylinder_mesh
	if shape is CapsuleShape3D:
		var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
		var capsule_debug_mesh: CylinderMesh = CylinderMesh.new()
		capsule_debug_mesh.top_radius = capsule_shape.radius
		capsule_debug_mesh.bottom_radius = capsule_shape.radius
		capsule_debug_mesh.height = capsule_shape.height
		return capsule_debug_mesh
	if shape is SphereShape3D:
		var sphere_shape: SphereShape3D = shape as SphereShape3D
		var sphere_mesh: SphereMesh = SphereMesh.new()
		sphere_mesh.radius = sphere_shape.radius
		sphere_mesh.height = sphere_shape.radius * 2.0
		return sphere_mesh
	if shape is BoxShape3D:
		var box_shape: BoxShape3D = shape as BoxShape3D
		var box_mesh: BoxMesh = BoxMesh.new()
		box_mesh.size = box_shape.size
		return box_mesh
	return null

func _create_collision_debug_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.roughness = 1.0
	material.emission_enabled = true
	material.emission = color
	return material

func _compute_tree_collision_profile(resource_root: Node3D, definition: Dictionary) -> Dictionary:
	if resource_root == null or not resource_root.is_inside_tree():
		return {"valid": false}
	var points: Array[Vector3] = _collect_resource_mesh_points(resource_root)
	if points.is_empty():
		return {"valid": false}
	var min_v: Vector3 = points[0]
	var max_v: Vector3 = points[0]
	for point in points:
		min_v = Vector3(minf(min_v.x, point.x), minf(min_v.y, point.y), minf(min_v.z, point.z))
		max_v = Vector3(maxf(max_v.x, point.x), maxf(max_v.y, point.y), maxf(max_v.z, point.z))
	var total_height: float = maxf(max_v.y - min_v.y, 0.5)
	var collision_top_ratio: float = clampf(float(definition.get("trunk_height_ratio", 0.72)), 0.5, 0.9)
	var base_end_ratio: float = clampf(float(definition.get("base_profile_end_ratio", 0.22)), 0.12, 0.35)
	var mid_end_ratio: float = clampf(float(definition.get("mid_profile_end_ratio", 0.46)), base_end_ratio + 0.1, 0.62)
	var upper_end_ratio: float = clampf(collision_top_ratio, mid_end_ratio + 0.1, 0.82)
	var band_overlap_ratio: float = clampf(float(definition.get("profile_band_overlap_ratio", 0.03)), 0.0, 0.08)
	var overlap_height: float = total_height * band_overlap_ratio

	var base_start_y: float = min_v.y
	var base_end_y: float = min_v.y + total_height * base_end_ratio
	var mid_start_y: float = base_end_y - overlap_height
	var mid_end_y: float = min_v.y + total_height * mid_end_ratio
	var upper_start_y: float = mid_end_y - overlap_height
	var upper_end_y: float = min_v.y + total_height * upper_end_ratio

	var base_samples: Array[float] = _collect_radial_samples(points, base_start_y, base_end_y)
	var mid_samples: Array[float] = _collect_radial_samples(points, mid_start_y, mid_end_y)
	var upper_samples: Array[float] = _collect_radial_samples(points, upper_start_y, upper_end_y)

	var base_padding: float = maxf(float(definition.get("base_block_padding", 0.06)), 0.0)
	var trunk_padding: float = maxf(float(definition.get("trunk_padding", 0.03)), 0.0)
	var min_base_radius: float = maxf(float(definition.get("base_block_min_radius", 0.4)), 0.1)
	var min_trunk_radius: float = maxf(float(definition.get("trunk_min_radius", 0.22)), 0.1)
	var min_base_height: float = maxf(float(definition.get("base_block_min_height", 0.8)), 0.2)

	var base_radius: float = maxf(_compute_percentile_value(base_samples, 0.9) + base_padding, min_base_radius)
	var mid_radius: float = maxf(_compute_percentile_value(mid_samples, 0.78) + trunk_padding, min_trunk_radius)
	var upper_radius: float = maxf(_compute_percentile_value(upper_samples, 0.68) + trunk_padding, min_trunk_radius * 0.92)

	mid_radius = minf(mid_radius, base_radius * 0.92)
	upper_radius = minf(upper_radius, mid_radius * 0.9)
	upper_radius = maxf(upper_radius, min_trunk_radius * 0.85)

	var base_height: float = maxf(base_end_y - base_start_y, min_base_height)
	var mid_height: float = maxf(mid_end_y - mid_start_y, 0.35)
	var upper_height: float = maxf(upper_end_y - upper_start_y, 0.35)

	var base_offset_y: float = base_start_y + base_height * 0.5
	var mid_offset_y: float = mid_start_y + mid_height * 0.5
	var upper_offset_y: float = upper_start_y + upper_height * 0.5
	return {
		"valid": true,
		"segments": [
			{
				"name": "base",
				"radius": base_radius,
				"height": base_height,
				"offset_y": base_offset_y
			},
			{
				"name": "mid",
				"radius": mid_radius,
				"height": mid_height,
				"offset_y": mid_offset_y
			},
			{
				"name": "upper",
				"radius": upper_radius,
				"height": upper_height,
				"offset_y": upper_offset_y
			}
		]
	}

func _collect_radial_samples(points: Array[Vector3], min_y: float, max_y: float) -> Array[float]:
	var samples: Array[float] = []
	for point in points:
		if point.y < min_y or point.y > max_y:
			continue
		samples.append(Vector2(point.x, point.z).length())
	return samples

func _compute_percentile_value(samples: Array[float], percentile: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted_samples: Array[float] = []
	for sample in samples:
		sorted_samples.append(sample)
	sorted_samples.sort()
	var clamped_percentile: float = clampf(percentile, 0.0, 1.0)
	var index: int = int(roundf((sorted_samples.size() - 1) * clamped_percentile))
	return float(sorted_samples[index])

func _collect_resource_mesh_points(resource_root: Node3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if resource_root == null or not resource_root.is_inside_tree():
		return points
	var root_inv: Transform3D = resource_root.global_transform.affine_inverse()
	var stack: Array[Node] = [resource_root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		var mesh_node: MeshInstance3D = current as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			var local_transform: Transform3D = root_inv * mesh_node.global_transform
			var mesh: Mesh = mesh_node.mesh
			var surface_count: int = mesh.get_surface_count()
			var appended_vertices: bool = false
			for surface_idx in range(surface_count):
				var arrays_variant: Variant = mesh.surface_get_arrays(surface_idx)
				if not (arrays_variant is Array):
					continue
				var arrays: Array = arrays_variant
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var vertices_variant: Variant = arrays[Mesh.ARRAY_VERTEX]
				if not (vertices_variant is PackedVector3Array):
					continue
				var vertices: PackedVector3Array = vertices_variant
				for vertex in vertices:
					points.append(local_transform * vertex)
				appended_vertices = true
			if not appended_vertices:
				var aabb: AABB = _transform_aabb(mesh.get_aabb(), local_transform)
				points.append(aabb.position)
				points.append(aabb.position + Vector3(aabb.size.x, 0.0, 0.0))
				points.append(aabb.position + Vector3(0.0, aabb.size.y, 0.0))
				points.append(aabb.position + Vector3(0.0, 0.0, aabb.size.z))
				points.append(aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0))
				points.append(aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z))
				points.append(aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z))
				points.append(aabb.position + aabb.size)
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	return points

func _configure_collider_from_visual(collider: CollisionShape3D, resource_root: Node3D, definition: Dictionary) -> bool:
	if collider == null or resource_root == null:
		return false
	var bounds: Dictionary = _compute_visual_local_bounds(resource_root)
	if not bool(bounds.get("valid", false)):
		return false
	var min_v: Vector3 = bounds.get("min", Vector3.ZERO)
	var max_v: Vector3 = bounds.get("max", Vector3.ZERO)
	var size: Vector3 = max_v - min_v
	if size.length_squared() <= 0.0001:
		return false
	var radius_scale: float = clampf(float(definition.get("collision_radius_scale", 1.0)), 0.2, 2.0)
	var radius: float = maxf(maxf(size.x, size.z) * 0.5 * radius_scale, 0.2)
	var height: float = maxf(size.y, 0.5)
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collider.shape = shape
	collider.position = Vector3(
		(min_v.x + max_v.x) * 0.5,
		(min_v.y + max_v.y) * 0.5,
		(min_v.z + max_v.z) * 0.5
	)
	return true

func _compute_visual_local_bounds(root: Node3D) -> Dictionary:
	if root == null:
		return {"valid": false}
	if not root.is_inside_tree():
		return {"valid": false}
	var root_inv: Transform3D = root.global_transform.affine_inverse()
	var stack: Array[Node] = [root]
	var has_bounds: bool = false
	var min_v: Vector3 = Vector3.ZERO
	var max_v: Vector3 = Vector3.ZERO
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		var mesh_node: MeshInstance3D = current as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			var mesh_aabb: AABB = mesh_node.mesh.get_aabb()
			var local_transform: Transform3D = root_inv * mesh_node.global_transform
			var transformed_aabb: AABB = _transform_aabb(mesh_aabb, local_transform)
			var aabb_min: Vector3 = transformed_aabb.position
			var aabb_max: Vector3 = transformed_aabb.position + transformed_aabb.size
			if not has_bounds:
				min_v = aabb_min
				max_v = aabb_max
				has_bounds = true
			else:
				min_v = Vector3(minf(min_v.x, aabb_min.x), minf(min_v.y, aabb_min.y), minf(min_v.z, aabb_min.z))
				max_v = Vector3(maxf(max_v.x, aabb_max.x), maxf(max_v.y, aabb_max.y), maxf(max_v.z, aabb_max.z))
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	if not has_bounds:
		return {"valid": false}
	return {
		"valid": true,
		"min": min_v,
		"max": max_v
	}

func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var p0: Vector3 = aabb.position
	var p1: Vector3 = aabb.position + Vector3(aabb.size.x, 0.0, 0.0)
	var p2: Vector3 = aabb.position + Vector3(0.0, aabb.size.y, 0.0)
	var p3: Vector3 = aabb.position + Vector3(0.0, 0.0, aabb.size.z)
	var p4: Vector3 = aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0)
	var p5: Vector3 = aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z)
	var p6: Vector3 = aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z)
	var p7: Vector3 = aabb.position + aabb.size
	var points: Array[Vector3] = [
		xform * p0, xform * p1, xform * p2, xform * p3,
		xform * p4, xform * p5, xform * p6, xform * p7
	]
	var min_v: Vector3 = points[0]
	var max_v: Vector3 = points[0]
	for point in points:
		min_v = Vector3(minf(min_v.x, point.x), minf(min_v.y, point.y), minf(min_v.z, point.z))
		max_v = Vector3(maxf(max_v.x, point.x), maxf(max_v.y, point.y), maxf(max_v.z, point.z))
	return AABB(min_v, max_v - min_v)

func _resolve_visual_scene(scene_path: String) -> PackedScene:
	if _visual_scene_cache.has(scene_path):
		var cached_variant: Variant = _visual_scene_cache[scene_path]
		if cached_variant is PackedScene:
			return cached_variant as PackedScene
	var loaded: Variant = load(scene_path)
	if loaded is PackedScene:
		var packed: PackedScene = loaded as PackedScene
		_visual_scene_cache[scene_path] = packed
		return packed
	return null

func _apply_fallback_material_if_missing(root: Node, fallback_color: Color) -> void:
	if root == null:
		return
	var stack: Array[Node] = [root]
	var fallback_material: StandardMaterial3D = StandardMaterial3D.new()
	fallback_material.albedo_color = fallback_color
	fallback_material.roughness = 0.88
	fallback_material.metallic = 0.0
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		var mesh_node: MeshInstance3D = current as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			if mesh_node.material_override == null:
				mesh_node.material_override = fallback_material
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)


func on_chunk_unloaded(chunk_id: Vector2i) -> void:
	if _resources_by_chunk.has(chunk_id):
		_resources_by_chunk.erase(chunk_id)

func unregister_resource_node(resource_root: Node3D) -> void:
	_unregister_resource(resource_root)

func harvest_from_collider(collider: Object, harvester: Node, tool_context: Dictionary = {}) -> bool:
	if DEBUG_RESOURCE_RUNTIME:
		_debug_log_harvest_hit(collider)
	var resource_root: Node3D = _resolve_resource_root(collider)
	if resource_root == null or not is_instance_valid(resource_root):
		if DEBUG_RESOURCE_RUNTIME:
			_debug_resource_log("harvest_lookup_failed collider=%s" % _describe_object(collider))
		return false
	var required_tool: String = String(resource_root.get_meta("required_tool", ""))
	var resource_id: String = String(resource_root.get_meta("resource_id", ""))
	var tool_id: String = _extract_tool_id(tool_context)
	var damage: float = _calculate_harvest_damage(resource_id, required_tool, tool_id)
	var interaction_position: Vector3 = _resolve_resource_interaction_position(resource_root, collider)
	if DEBUG_RESOURCE_RUNTIME:
		_debug_resource_log(
			"harvest_resolved collider=%s resource_root=%s has_apply_resource_damage=%s hit_points=%s tool_id=%s damage=%s" % [
				_describe_object(collider),
				_describe_node(resource_root),
				str(resource_root.has_method("apply_resource_damage")),
				str(resource_root.get_meta("hit_points", "n/a")),
				tool_id,
				str(damage)
			]
		)
	if resource_root.has_method("apply_resource_damage"):
		if DEBUG_RESOURCE_RUNTIME:
			_debug_resource_log("calling apply_resource_damage on %s" % _describe_node(resource_root))
		var handled_variant: Variant = resource_root.call("apply_resource_damage", damage, harvester, tool_id, interaction_position)
		return bool(handled_variant)
	var max_hp: float = maxf(float(resource_root.get_meta("max_hit_points", 1.0)), 0.1)
	var current_hp: float = maxf(float(resource_root.get_meta("hit_points", max_hp)), 0.0)
	var health_component: HealthComponent = _get_resource_health_component(resource_root)
	current_hp = maxf(current_hp - damage, 0.0)
	resource_root.set_meta("hit_points", current_hp)
	if health_component != null:
		health_component.max_health = max_hp
		health_component.current_health = current_hp
		health_component.health_changed.emit(current_hp, max_hp)
	if current_hp > 0.0:
		return true
	if health_component != null:
		health_component.died.emit(resource_root)
	var drop_table_variant: Variant = resource_root.get_meta("drop_table", [])
	var drop_table: Array = drop_table_variant if drop_table_variant is Array else []
	if drop_table.is_empty():
		drop_table = [{
			"item_id": String(resource_root.get_meta("item_id", "wood")),
			"amount": int(resource_root.get_meta("amount", 1))
		}]
	var default_min_amount: int = maxi(int(resource_root.get_meta("drop_min_amount", 1)), 1)
	var default_max_amount: int = int(resource_root.get_meta("drop_max_amount", default_min_amount))
	default_max_amount = maxi(default_max_amount, default_min_amount)
	var drop_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	drop_rng.seed = int(Time.get_ticks_usec()) ^ int(resource_root.get_instance_id())
	var resolved_drops: Array[Dictionary] = []
	for drop_variant in drop_table:
		if not (drop_variant is Dictionary):
			continue
		var drop: Dictionary = drop_variant
		var drop_item_id: String = String(drop.get("item_id", ""))
		if drop_item_id.is_empty():
			continue
		var explicit_amount: int = int(drop.get("amount", -1))
		var min_amount: int = int(drop.get("min_amount", default_min_amount))
		var max_amount: int = int(drop.get("max_amount", default_max_amount))
		if max_amount < min_amount:
			var temp_amount: int = min_amount
			min_amount = max_amount
			max_amount = temp_amount
		min_amount = maxi(min_amount, 1)
		max_amount = maxi(max_amount, min_amount)
		var final_amount: int = explicit_amount if explicit_amount > 0 else drop_rng.randi_range(min_amount, max_amount)
		resolved_drops.append({
			"item_id": drop_item_id,
			"amount": final_amount
		})
	if resolved_drops.is_empty():
		resolved_drops.append({
			"item_id": String(resource_root.get_meta("item_id", "wood")),
			"amount": default_min_amount
		})
	var first_drop_variant: Variant = resolved_drops[0]
	var first_drop: Dictionary = first_drop_variant if first_drop_variant is Dictionary else {}
	var item_id: String = String(first_drop.get("item_id", "wood"))
	var amount: int = int(first_drop.get("amount", default_min_amount))
	EventBus.emit_game_event("resource_harvested", {
		"item_id": item_id,
		"amount": amount,
		"position": interaction_position,
		"harvester": harvester,
		"resource_id": resource_id,
		"tool_id": tool_id
	})
	for drop_variant in resolved_drops:
		if not (drop_variant is Dictionary):
			continue
		var drop: Dictionary = drop_variant
		var drop_item_id: String = String(drop.get("item_id", ""))
		var drop_amount: int = int(drop.get("amount", 0))
		if drop_item_id.is_empty() or drop_amount <= 0:
			continue
		EventBus.emit_game_event("loot_spawn_requested", {
			"position": interaction_position + Vector3(0.0, 0.6, 0.0),
			"item_id": drop_item_id,
			"amount": drop_amount
		})
	_unregister_resource(resource_root)
	resource_root.queue_free()
	return true

func _debug_log_harvest_hit(collider: Object) -> void:
	var node: Node = collider as Node
	var has_meta_root: bool = node != null and node.has_meta("resource_root")
	var meta_root_desc: String = "null"
	if has_meta_root:
		var meta_root: Variant = node.get_meta("resource_root")
		meta_root_desc = _describe_object(meta_root as Object)
	_debug_resource_log(
		"harvest_hit collider=%s has_meta_resource_root=%s meta_resource_root=%s" % [
			_describe_object(collider),
			str(has_meta_root),
			meta_root_desc
		]
	)

func _describe_object(obj: Object) -> String:
	if obj == null:
		return "null"
	if obj is Node:
		return _describe_node(obj as Node)
	return "%s#%d" % [obj.get_class(), obj.get_instance_id()]

func _describe_node(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "null"
	return "%s(name=%s,type=%s,path=%s)" % [
		node.get_class(),
		node.name,
		node.get_class(),
		String(node.get_path()) if node.is_inside_tree() else "<not_in_tree>"
	]

func _debug_resource_log(message: String) -> void:
	if not DEBUG_RESOURCE_RUNTIME:
		return
	print("[ResourceSystem] ", message)

func _extract_tool_id(tool_context: Dictionary) -> String:
	var tool_id_variant: Variant = tool_context.get("tool_id", "")
	return String(tool_id_variant)

func _calculate_harvest_damage(resource_id: String, required_tool: String, tool_id: String) -> float:
	if resource_id == "tree":
		if tool_id == "axe":
			return CORRECT_TOOL_DAMAGE
		# Trees must be harvestable by hand so the player can bootstrap into the first axe.
		return 1.0
	if required_tool.is_empty():
		return BASE_HAND_DAMAGE
	if tool_id == required_tool:
		if resource_id == "big_rock":
			return CORRECT_TOOL_DAMAGE + 0.5
		return CORRECT_TOOL_DAMAGE
	if tool_id.is_empty():
		return BASE_HAND_DAMAGE
	return WRONG_TOOL_DAMAGE

func _get_resource_definition(resource_type: String) -> Dictionary:
	if _resource_definitions.is_empty():
		_load_resource_definitions()
	var definition_variant: Variant = _resource_definitions.get(resource_type, {})
	if definition_variant is Dictionary:
		return Dictionary(definition_variant).duplicate(true)
	var fallback_variant: Variant = _resource_definitions.get("tree", {})
	if fallback_variant is Dictionary:
		return Dictionary(fallback_variant).duplicate(true)
	return {}

func _load_resource_definitions() -> void:
	_resource_definitions = DEFAULT_RESOURCE_DEFINITIONS.duplicate(true)
	var raw_definitions: Dictionary = JsonDataLoader.load_dictionary(RESOURCE_DATA_PATH)
	if raw_definitions.is_empty():
		return
	var parsed: Dictionary = {}
	for key_variant in raw_definitions.keys():
		var resource_id: String = String(key_variant)
		var entry_variant: Variant = raw_definitions[key_variant]
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = Dictionary(entry_variant).duplicate(true)
		var color_variant: Variant = entry.get("color", null)
		if color_variant != null:
			entry["color"] = _parse_color(color_variant, Color(0.6, 0.6, 0.6, 1.0))
		parsed[resource_id] = entry
	if parsed.is_empty():
		return
	_resource_definitions = parsed

func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var value_text: String = String(value)
	if value_text.is_empty():
		return fallback
	return Color.from_string(value_text, fallback)

func _resolve_resource_root(collider: Object) -> Node3D:
	if collider == null:
		return null
	if collider is Node:
		var current: Node = collider as Node
		while current != null:
			if not is_instance_valid(current):
				return null
			if current is Node3D and current.has_method("apply_resource_damage"):
				return current as Node3D
			if current.is_in_group("resource") and current is Node3D:
				return current as Node3D
			if current.has_meta("resource_root"):
				var meta_root: Variant = current.get_meta("resource_root")
				if meta_root is Node3D and is_instance_valid(meta_root):
					return meta_root as Node3D
			current = current.get_parent()
	return null

func _resolve_resource_interaction_position(resource_root: Node3D, collider: Object) -> Vector3:
	if resource_root == null:
		return Vector3.ZERO
	var drop_origin_path_variant: Variant = resource_root.get_meta("drop_origin_path", NodePath())
	if drop_origin_path_variant is NodePath:
		var drop_origin_path: NodePath = drop_origin_path_variant
		if not drop_origin_path.is_empty():
			var drop_origin: Node3D = resource_root.get_node_or_null(drop_origin_path) as Node3D
			if drop_origin != null and is_instance_valid(drop_origin):
				return drop_origin.global_position
	if collider is Node3D:
		var collider_node: Node3D = collider as Node3D
		if collider_node != null and is_instance_valid(collider_node):
			return collider_node.global_position
	var authored_scene_variant: Variant = resource_root.get_meta("authored_resource_scene", null)
	if authored_scene_variant is Node3D:
		var authored_scene: Node3D = authored_scene_variant as Node3D
		if authored_scene != null and is_instance_valid(authored_scene):
			return authored_scene.global_position
	return resource_root.global_position

func _unregister_resource(resource_root: Node3D) -> void:
	var chunk_id_variant: Variant = resource_root.get_meta("chunk_id", Vector2i.ZERO)
	var chunk_id: Vector2i = chunk_id_variant if chunk_id_variant is Vector2i else Vector2i.ZERO
	if not _resources_by_chunk.has(chunk_id):
		return
	var resources_variant: Variant = _resources_by_chunk[chunk_id]
	if not (resources_variant is Array):
		_resources_by_chunk.erase(chunk_id)
		return
	var resources: Array = resources_variant
	var index: int = resources.find(resource_root)
	if index >= 0:
		resources.remove_at(index)
	_resources_by_chunk[chunk_id] = resources
