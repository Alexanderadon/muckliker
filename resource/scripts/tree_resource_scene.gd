@tool
extends "res://resource/scripts/resource_node.gd"

@export_group("Collision")
@export_enum("manual_authored", "segmented_cylinder", "single_cylinder", "single_capsule", "mesh_convex", "mesh_trimesh") var collision_shape_type: String = "manual_authored"

@export_group("Segmented Profile")
@export_range(0.05, 5.0, 0.01) var lower_radius: float = 0.36
@export_range(0.1, 10.0, 0.01) var lower_height: float = 0.92
@export_range(-5.0, 10.0, 0.01) var lower_offset_y: float = 0.46
@export_range(0.05, 5.0, 0.01) var mid_radius: float = 0.28
@export_range(0.1, 10.0, 0.01) var mid_height: float = 0.86
@export_range(-5.0, 10.0, 0.01) var mid_offset_y: float = 1.26
@export_range(0.05, 5.0, 0.01) var upper_radius: float = 0.21
@export_range(0.1, 10.0, 0.01) var upper_height: float = 0.72
@export_range(-5.0, 10.0, 0.01) var upper_offset_y: float = 2.02

@export_group("Single Shape")
@export_range(0.05, 5.0, 0.01) var single_radius: float = 0.32
@export_range(0.1, 10.0, 0.01) var single_height: float = 2.35
@export_range(-5.0, 10.0, 0.01) var single_offset_y: float = 1.18

@export_group("Debug")
@export var show_debug_collision: bool = false
@export var debug_color: Color = Color(1.0, 0.2, 0.2, 0.28)

@export_group("Hit Reaction")
@export_range(0.7, 1.0, 0.01) var hit_scale_multiplier: float = 0.94
@export_range(0.01, 0.3, 0.01) var hit_shrink_duration: float = 0.08
@export_range(0.01, 0.4, 0.01) var hit_recover_duration: float = 0.16

var _last_signature: String = ""
var _visual_default_scale: Vector3 = Vector3.ONE
var _hit_tween: Tween = null

func _ready() -> void:
	super._ready()
	var visual_root: Node3D = _get_visual_root()
	if visual_root != null:
		_visual_default_scale = visual_root.scale
	var debug_root: Node3D = get_node_or_null("DebugCollision") as Node3D
	if not Engine.is_editor_hint():
		if debug_root != null:
			debug_root.visible = false
		set_process(false)
		return
	_rebuild_collision_if_needed(true)
	if debug_root != null:
		debug_root.visible = show_debug_collision
	set_process(true)

func apply_resource_damage(damage: float, harvester: Node, tool_id: String, interaction_position: Vector3) -> bool:
	if damage > 0.0:
		_play_hit_reaction()
	return super.apply_resource_damage(damage, harvester, tool_id, interaction_position)

func rebuild_collision_now() -> void:
	if collision_shape_type == "manual_authored":
		return
	_rebuild_collision_if_needed(true)

func requires_runtime_collision_rebuild() -> bool:
	return collision_shape_type != "manual_authored"

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_rebuild_collision_if_needed(false)

func _rebuild_collision_if_needed(force: bool) -> void:
	var body: Node3D = _get_collision_root()
	var debug_root: Node3D = get_node_or_null("DebugCollision") as Node3D
	var visual_root: Node3D = _get_visual_root()
	if body == null or debug_root == null or visual_root == null:
		return
	var signature: String = _build_signature()
	if not force and signature == _last_signature:
		return
	_clear_children(debug_root)
	match collision_shape_type:
		"manual_authored":
			_sync_manual_authored_colliders(body, debug_root)
		"single_cylinder":
			_clear_generated_collision_children(body)
			_add_single_primitive_collider(body, debug_root, false)
		"single_capsule":
			_clear_generated_collision_children(body)
			_add_single_primitive_collider(body, debug_root, true)
		"mesh_convex":
			_clear_generated_collision_children(body)
			_add_mesh_based_colliders(body, debug_root, visual_root, false)
		"mesh_trimesh":
			_clear_generated_collision_children(body)
			_add_mesh_based_colliders(body, debug_root, visual_root, true)
		_:
			_clear_generated_collision_children(body)
			_add_segmented_cylinder_colliders(body, debug_root)
	_sync_debug_visibility(debug_root)
	_last_signature = signature

func _build_signature() -> String:
	return "%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%s|%s|%.3f|%.3f|%.3f" % [
		collision_shape_type,
		lower_radius,
		lower_height,
		lower_offset_y,
		mid_radius,
		mid_height,
		mid_offset_y,
		upper_radius,
		upper_height,
		upper_offset_y,
		single_radius,
		single_height,
		single_offset_y,
		str(show_debug_collision),
		debug_color.to_html(true),
		hit_scale_multiplier,
		hit_shrink_duration,
		hit_recover_duration
	]

func _clear_children(parent: Node) -> void:
	for child_variant in parent.get_children():
		var child: Node = child_variant as Node
		if child != null:
			child.free()

func _clear_generated_collision_children(body: Node3D) -> void:
	if body == null:
		return
	var generated_body: StaticBody3D = body.get_node_or_null("GeneratedCollisionBody") as StaticBody3D
	if generated_body != null:
		generated_body.free()
	for child_variant in body.get_children():
		var child: Node = child_variant as Node
		if child == null:
			continue
		if not child.has_meta("generated_collision"):
			continue
		child.free()

func _get_visual_root() -> Node3D:
	var visual_root: Node3D = get_node_or_null("Visual") as Node3D
	if visual_root != null:
		return visual_root
	return get_node_or_null("Body/Visual") as Node3D

func _get_collision_root() -> Node3D:
	var hit_body: Node3D = get_node_or_null("HitBody") as Node3D
	if hit_body != null:
		return hit_body
	return get_node_or_null("Body") as Node3D

func _sync_manual_authored_colliders(body: Node3D, debug_root: Node3D) -> void:
	if body == null:
		return
	var collisions: Array[CollisionShape3D] = _collect_collision_shapes(body)
	var collision_index: int = 0
	for collision in collisions:
		var debug_mesh: Mesh = _build_mesh_for_shape(collision.shape)
		if debug_mesh == null:
			continue
		_add_debug_mesh(
			debug_root,
			"ManualDebug%d" % collision_index,
			debug_root.global_transform.affine_inverse() * collision.global_transform,
			debug_mesh
		)
		collision_index += 1

func _collect_collision_shapes(root: Node) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	if root == null:
		return result
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		var collision_shape: CollisionShape3D = current as CollisionShape3D
		if collision_shape != null and collision_shape.shape != null:
			result.append(collision_shape)
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	return result

func _add_segmented_cylinder_colliders(body: Node3D, debug_root: Node3D) -> void:
	var collision_body: StaticBody3D = _ensure_generated_collision_body(body)
	if collision_body == null:
		return
	var segments: Array[Dictionary] = [
		{"name": "LowerCollision", "radius": lower_radius, "height": lower_height, "offset_y": lower_offset_y},
		{"name": "MidCollision", "radius": mid_radius, "height": mid_height, "offset_y": mid_offset_y},
		{"name": "UpperCollision", "radius": upper_radius, "height": upper_height, "offset_y": upper_offset_y}
	]
	for segment in segments:
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.name = String(segment.get("name", "SegmentCollision"))
		collider.set_meta("generated_collision", true)
		var shape: CylinderShape3D = CylinderShape3D.new()
		shape.radius = float(segment.get("radius", 0.25))
		shape.height = float(segment.get("height", 0.5))
		collider.shape = shape
		collider.position = Vector3(0.0, float(segment.get("offset_y", 0.25)), 0.0)
		collision_body.add_child(collider)
		_add_debug_mesh(debug_root, collider.name.replace("Collision", "Debug"), collider.transform, _build_cylinder_mesh(shape.radius, shape.height))

func _add_single_primitive_collider(body: Node3D, debug_root: Node3D, use_capsule: bool) -> void:
	var collision_body: StaticBody3D = _ensure_generated_collision_body(body)
	if collision_body == null:
		return
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "SingleCollision"
	collider.set_meta("generated_collision", true)
	if use_capsule:
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = single_radius
		capsule.height = single_height
		collider.shape = capsule
		collider.position = Vector3(0.0, single_offset_y, 0.0)
		collision_body.add_child(collider)
		_add_debug_mesh(debug_root, "SingleDebug", collider.transform, _build_capsule_mesh(capsule.radius, capsule.height))
		return
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = single_radius
	cylinder.height = single_height
	collider.shape = cylinder
	collider.position = Vector3(0.0, single_offset_y, 0.0)
	collision_body.add_child(collider)
	_add_debug_mesh(debug_root, "SingleDebug", collider.transform, _build_cylinder_mesh(cylinder.radius, cylinder.height))

func _add_mesh_based_colliders(body: Node3D, debug_root: Node3D, visual_root: Node3D, use_trimesh: bool) -> void:
	var collision_body: StaticBody3D = _ensure_generated_collision_body(body)
	if collision_body == null:
		return
	var mesh_nodes: Array[MeshInstance3D] = _collect_mesh_nodes(visual_root)
	var body_inverse: Transform3D = collision_body.global_transform.affine_inverse()
	var mesh_index: int = 0
	for mesh_node in mesh_nodes:
		if mesh_node.mesh == null:
			continue
		var shape: Shape3D = mesh_node.mesh.create_trimesh_shape() if use_trimesh else mesh_node.mesh.create_convex_shape()
		if shape == null:
			continue
		var collider: CollisionShape3D = CollisionShape3D.new()
		collider.name = "MeshCollision%d" % mesh_index
		collider.set_meta("generated_collision", true)
		collider.shape = shape
		collider.transform = body_inverse * mesh_node.global_transform
		collision_body.add_child(collider)
		_add_debug_mesh(debug_root, "MeshDebug%d" % mesh_index, collider.transform, mesh_node.mesh)
		mesh_index += 1

func _ensure_generated_collision_body(body: Node3D) -> StaticBody3D:
	if body == null:
		return null
	var existing_static_body: StaticBody3D = body as StaticBody3D
	if existing_static_body != null:
		return existing_static_body
	var existing_body: StaticBody3D = body.get_node_or_null("GeneratedCollisionBody") as StaticBody3D
	if existing_body != null:
		return existing_body
	var generated_body: StaticBody3D = StaticBody3D.new()
	generated_body.name = "GeneratedCollisionBody"
	body.add_child(generated_body)
	return generated_body

func _collect_mesh_nodes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root == null:
		return result
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		var mesh_node: MeshInstance3D = current as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			result.append(mesh_node)
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	return result

func _add_debug_mesh(parent: Node3D, node_name: String, mesh_transform: Transform3D, mesh: Mesh) -> void:
	if parent == null or mesh == null:
		return
	var debug_mesh: MeshInstance3D = MeshInstance3D.new()
	debug_mesh.name = node_name
	debug_mesh.mesh = mesh
	debug_mesh.transform = mesh_transform
	debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	debug_mesh.material_override = _build_debug_material()
	parent.add_child(debug_mesh)

func _build_mesh_for_shape(shape: Shape3D) -> Mesh:
	if shape is CylinderShape3D:
		var cylinder_shape: CylinderShape3D = shape as CylinderShape3D
		return _build_cylinder_mesh(cylinder_shape.radius, cylinder_shape.height)
	if shape is CapsuleShape3D:
		var capsule_shape: CapsuleShape3D = shape as CapsuleShape3D
		return _build_capsule_mesh(capsule_shape.radius, capsule_shape.height)
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

func _build_cylinder_mesh(radius: float, height: float) -> CylinderMesh:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh

func _build_capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var mesh: CapsuleMesh = CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh

func _build_debug_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = debug_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.emission_enabled = true
	material.emission = debug_color
	return material

func _sync_debug_visibility(debug_root: Node3D) -> void:
	if debug_root == null:
		return
	debug_root.visible = show_debug_collision

func _play_hit_reaction() -> void:
	var visual_root: Node3D = _get_visual_root()
	if visual_root == null:
		return
	if _hit_tween != null and is_instance_valid(_hit_tween):
		_hit_tween.kill()
	visual_root.scale = _visual_default_scale
	var hit_scale: Vector3 = _visual_default_scale * hit_scale_multiplier
	_hit_tween = create_tween()
	_hit_tween.set_trans(Tween.TRANS_SINE)
	_hit_tween.set_ease(Tween.EASE_OUT)
	_hit_tween.tween_property(visual_root, "scale", hit_scale, hit_shrink_duration)
	_hit_tween.set_ease(Tween.EASE_IN_OUT)
	_hit_tween.tween_property(visual_root, "scale", _visual_default_scale, hit_recover_duration)
