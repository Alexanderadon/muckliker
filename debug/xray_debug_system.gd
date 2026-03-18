extends Node3D
class_name XRayDebugSystem

const TREE_COLOR: Color = Color(1.0, 0.2, 0.2, 0.28)
const ROCK_COLOR: Color = Color(0.66, 0.69, 0.74, 0.28)
const DEFAULT_COLOR: Color = Color(0.9, 0.92, 0.98, 0.24)

@export var toggle_keycode: Key = KEY_F2
@export var scan_root_path: NodePath = NodePath("../WorldRoot")
@export_range(0.1, 2.0, 0.05) var refresh_interval_seconds: float = 0.45
@export_range(0.05, 1.0, 0.01) var overlay_alpha: float = 0.28
@export var start_enabled: bool = false

var _active: bool = false
var _refresh_accumulator: float = 0.0
var _overlay_root: Node3D = null
var _tracked_entries: Dictionary = {}

func _ready() -> void:
	set_process(false)
	set_process_unhandled_input(true)
	if start_enabled:
		_set_active(true)

func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode != toggle_keycode:
		return
	_set_active(not _active)
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _active:
		return
	_refresh_accumulator += delta
	if _refresh_accumulator >= refresh_interval_seconds:
		_refresh_accumulator = 0.0
		_sync_targets()
	_update_tracked_entries()

func _set_active(value: bool) -> void:
	if _active == value:
		return
	_active = value
	_refresh_accumulator = 0.0
	if not value:
		_clear_all_overlays()
		set_process(false)
		return
	_ensure_overlay_root()
	_sync_targets()
	_update_tracked_entries()
	set_process(true)

func _ensure_overlay_root() -> Node3D:
	if _overlay_root != null and is_instance_valid(_overlay_root):
		return _overlay_root
	_overlay_root = Node3D.new()
	_overlay_root.name = "XRayOverlayRoot"
	add_child(_overlay_root)
	return _overlay_root

func _clear_all_overlays() -> void:
	for entry_variant in _tracked_entries.values():
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var overlay: Node3D = entry.get("overlay", null) as Node3D
		if overlay != null and is_instance_valid(overlay):
			overlay.queue_free()
	_tracked_entries.clear()
	if _overlay_root != null and is_instance_valid(_overlay_root):
		_overlay_root.queue_free()
	_overlay_root = null

func _sync_targets() -> void:
	var desired_targets: Dictionary = _collect_targets()
	for tracked_id_variant in _tracked_entries.keys().duplicate():
		var tracked_id: int = int(tracked_id_variant)
		if desired_targets.has(tracked_id):
			continue
		_remove_entry(tracked_id)
	for target_id_variant in desired_targets.keys():
		var target_id: int = int(target_id_variant)
		var info_variant: Variant = desired_targets[target_id_variant]
		if not (info_variant is Dictionary):
			continue
		var info: Dictionary = info_variant
		var target: Node3D = info.get("target", null) as Node3D
		var target_type: String = String(info.get("type", ""))
		if target == null or not is_instance_valid(target):
			continue
		if _tracked_entries.has(target_id):
			_refresh_entry(target_id, target, target_type)
			continue
		_create_entry(target_id, target, target_type)

func _collect_targets() -> Dictionary:
	var result: Dictionary = {}
	var tree_ref: SceneTree = get_tree()
	if tree_ref == null:
		return result
	for node_variant in tree_ref.get_nodes_in_group("resource"):
		var node: Node3D = node_variant as Node3D
		if not _should_track_node(node):
			continue
		var target_type: String = _classify_target(node)
		if target_type == "tree" or target_type == "rock":
			result[node.get_instance_id()] = {"target": node, "type": target_type}
	for node_variant in tree_ref.get_nodes_in_group("totem"):
		var node: Node3D = node_variant as Node3D
		if not _should_track_node(node):
			continue
		result[node.get_instance_id()] = {"target": node, "type": "totem"}
	for node_variant in tree_ref.get_nodes_in_group("enemy"):
		var node: Node3D = node_variant as Node3D
		if not _should_track_node(node):
			continue
		var target_type: String = "totem_wolf" if node.is_in_group("totem_wolf") else "enemy"
		result[node.get_instance_id()] = {"target": node, "type": target_type}
	return result

func _should_track_node(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not node.is_inside_tree():
		return false
	var scan_root: Node = get_node_or_null(scan_root_path)
	if scan_root != null and not scan_root.is_ancestor_of(node):
		return false
	if not node.visible:
		return false
	return true

func _classify_target(node: Node3D) -> String:
	if node == null:
		return ""
	if node.is_in_group("totem"):
		return "totem"
	if node.is_in_group("totem_wolf"):
		return "totem_wolf"
	if node.is_in_group("enemy"):
		return "enemy"
	var resource_id: String = String(node.get_meta("resource_id", ""))
	if resource_id == "tree":
		return "tree"
	if resource_id == "rock" or resource_id == "big_rock":
		return "rock"
	return ""

func _create_entry(target_id: int, target: Node3D, target_type: String) -> void:
	var overlay_parent: Node3D = _ensure_overlay_root()
	var overlay_root: Node3D = Node3D.new()
	overlay_root.name = "XRay_%d" % target_id
	overlay_parent.add_child(overlay_root)
	var has_overlay: bool = _build_overlay_geometry(target, overlay_root, target_type)
	if not has_overlay:
		overlay_root.queue_free()
		return
	_tracked_entries[target_id] = {
		"target_id": target_id,
		"overlay": overlay_root,
		"type": target_type
	}

func _refresh_entry(target_id: int, target: Node3D, target_type: String) -> void:
	var entry_variant: Variant = _tracked_entries.get(target_id, {})
	if not (entry_variant is Dictionary):
		return
	var entry: Dictionary = entry_variant
	entry["target_id"] = target_id
	var existing_type: String = String(entry.get("type", ""))
	if existing_type != target_type:
		var overlay: Node3D = entry.get("overlay", null) as Node3D
		if overlay != null and is_instance_valid(overlay):
			overlay.queue_free()
		_tracked_entries.erase(target_id)
		_create_entry(target_id, target, target_type)
		return
	_refresh_entry_materials(target, entry)
	_tracked_entries[target_id] = entry

func _remove_entry(target_id: int) -> void:
	var entry_variant: Variant = _tracked_entries.get(target_id, {})
	if entry_variant is Dictionary:
		var entry: Dictionary = entry_variant
		var overlay: Node3D = entry.get("overlay", null) as Node3D
		if overlay != null and is_instance_valid(overlay):
			overlay.queue_free()
	_tracked_entries.erase(target_id)

func _update_tracked_entries() -> void:
	for target_id_variant in _tracked_entries.keys().duplicate():
		var target_id: int = int(target_id_variant)
		var entry_variant: Variant = _tracked_entries.get(target_id_variant, {})
		if not (entry_variant is Dictionary):
			_tracked_entries.erase(target_id_variant)
			continue
		var entry: Dictionary = entry_variant
		var stored_target_id: int = int(entry.get("target_id", -1))
		var target_object: Object = instance_from_id(stored_target_id)
		var target: Node3D = target_object as Node3D
		var overlay: Node3D = entry.get("overlay", null) as Node3D
		if target == null or overlay == null or not is_instance_valid(target) or not is_instance_valid(overlay):
			_remove_entry(target_id)
			continue
		overlay.global_transform = target.global_transform

func _build_overlay_geometry(target: Node3D, overlay_root: Node3D, target_type: String) -> bool:
	var color: Color = _resolve_overlay_color(target, target_type)
	var collision_shapes: Array = _collect_collision_shapes(target)
	var target_inverse: Transform3D = target.global_transform.affine_inverse()
	var created: bool = false
	for collision_variant in collision_shapes:
		var collision_shape: CollisionShape3D = collision_variant as CollisionShape3D
		if collision_shape == null or collision_shape.shape == null:
			continue
		var debug_mesh: Mesh = _build_mesh_for_shape(collision_shape.shape)
		if debug_mesh == null:
			continue
		var overlay_mesh: MeshInstance3D = MeshInstance3D.new()
		overlay_mesh.name = "Overlay_%s" % collision_shape.name
		overlay_mesh.mesh = debug_mesh
		overlay_mesh.transform = target_inverse * collision_shape.global_transform
		overlay_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overlay_mesh.material_override = _build_overlay_material(color)
		overlay_root.add_child(overlay_mesh)
		created = true
	return created

func _refresh_entry_materials(target: Node3D, entry: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_type: String = String(entry.get("type", ""))
	var color: Color = _resolve_overlay_color(target, target_type)
	var overlay_root: Node3D = entry.get("overlay", null) as Node3D
	if overlay_root == null or not is_instance_valid(overlay_root):
		return
	for child_variant in overlay_root.get_children():
		var overlay_mesh: MeshInstance3D = child_variant as MeshInstance3D
		if overlay_mesh == null:
			continue
		overlay_mesh.material_override = _build_overlay_material(color)

func _collect_collision_shapes(root: Node) -> Array:
	var result: Array = []
	if root == null:
		return result
	var stack: Array = [root]
	while not stack.is_empty():
		var current_variant: Variant = stack.pop_back()
		var current: Node = current_variant as Node
		if current == null:
			continue
		var collision_shape: CollisionShape3D = current as CollisionShape3D
		if collision_shape != null and collision_shape.shape != null and not collision_shape.disabled:
			result.append(collision_shape)
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	return result

func _resolve_overlay_color(target: Node3D, target_type: String) -> Color:
	if target_type == "tree":
		return TREE_COLOR
	if target_type == "rock":
		return ROCK_COLOR
	var fallback: Color = DEFAULT_COLOR
	if target_type == "enemy":
		fallback = Color(0.88, 0.21, 0.2, overlay_alpha)
	elif target_type == "totem_wolf":
		fallback = Color(0.33, 0.31, 0.64, overlay_alpha)
	elif target_type == "totem":
		fallback = Color(0.26, 0.58, 0.96, overlay_alpha)
	var extracted: Color = _extract_visual_color(target, fallback)
	extracted.a = overlay_alpha
	return extracted

func _extract_visual_color(target: Node3D, fallback: Color) -> Color:
	var mesh_nodes: Array = []
	var stack: Array = [target]
	while not stack.is_empty():
		var current_variant: Variant = stack.pop_back()
		var current: Node = current_variant as Node
		if current == null:
			continue
		if current == self or current == _overlay_root or current.name == "DebugCollision":
			continue
		var mesh_node: MeshInstance3D = current as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null and mesh_node.visible:
			mesh_nodes.append(mesh_node)
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	for mesh_node_variant in mesh_nodes:
		var mesh_node: MeshInstance3D = mesh_node_variant as MeshInstance3D
		if mesh_node == null:
			continue
		var material: Material = mesh_node.material_override
		if material == null and mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
			material = mesh_node.mesh.surface_get_material(0)
		var standard_material: StandardMaterial3D = material as StandardMaterial3D
		if standard_material != null:
			var color: Color = standard_material.albedo_color
			color.a = overlay_alpha
			return color
		var base_material: BaseMaterial3D = material as BaseMaterial3D
		if base_material != null:
			var base_color: Color = base_material.albedo_color
			base_color.a = overlay_alpha
			return base_color
	return fallback

func _build_overlay_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	return material

func _build_mesh_for_shape(shape: Shape3D) -> Mesh:
	if shape is CylinderShape3D:
		var cylinder_shape: CylinderShape3D = shape as CylinderShape3D
		var cylinder_mesh: CylinderMesh = CylinderMesh.new()
		cylinder_mesh.top_radius = cylinder_shape.radius
		cylinder_mesh.bottom_radius = cylinder_shape.radius
		cylinder_mesh.height = cylinder_shape.height
		return cylinder_mesh
	if shape is CapsuleShape3D:
		var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
		var capsule_mesh: CapsuleMesh = CapsuleMesh.new()
		capsule_mesh.radius = capsule_shape.radius
		capsule_mesh.height = capsule_shape.height
		return capsule_mesh
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
