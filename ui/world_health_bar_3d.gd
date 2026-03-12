extends Node3D
class_name WorldHealthBar3D
const DAMAGE_POOL_SCRIPT: Script = preload("res://ui/damage_number_pool_3d.gd")

@export var bar_width: float = 1.0
@export var bar_height: float = 0.11
@export var y_offset: float = 1.95
@export var fill_color: Color = Color(0.2, 0.86, 0.33, 0.98)
@export var mid_health_color: Color = Color(0.95, 0.78, 0.22, 0.98)
@export var low_health_color: Color = Color(0.9, 0.26, 0.2, 0.98)
@export var background_color: Color = Color(0.18, 0.2, 0.23, 0.88)
@export var hide_when_full_health: bool = false
@export var full_health_hide_delay: float = 1.75
@export var show_damage_popups: bool = true
@export var popup_spawn_y_offset: float = 0.0
@export var popup_color: Color = Color(1.0, 0.36, 0.28, 1.0)
@export var health_poll_interval_seconds: float = 0.1

var _health_component: Node = null
var _billboard_pivot: Node3D = null
var _bar_background: MeshInstance3D = null
var _bar_fill: MeshInstance3D = null
var _bar_fill_anchor: Node3D = null
var _damage_pool: Node = null
var _last_health: float = -1.0
var _last_max_health: float = -1.0
var _health_ratio: float = 1.0
var _full_health_hide_time_left: float = 0.0
var _health_poll_accum: float = 0.0

func _ready() -> void:
	_ensure_bar_nodes()
	_sync_y_offset()
	_update_bar_visual(1.0)
	_apply_visibility(1.0, 1.0)
	set_process(true)

func _exit_tree() -> void:
	_disconnect_health_component()

func _process(delta: float) -> void:
	_sync_y_offset()
	_face_camera()
	_poll_health_fallback(delta)
	if _full_health_hide_time_left <= 0.0:
		return
	_full_health_hide_time_left = maxf(_full_health_hide_time_left - delta, 0.0)
	if _full_health_hide_time_left <= 0.0 and hide_when_full_health and _health_ratio >= 0.999:
		visible = false

func bind_health_component(component: Node) -> void:
	_disconnect_health_component()
	_health_component = component
	if _health_component == null:
		visible = false
		_last_health = -1.0
		_last_max_health = -1.0
		_health_ratio = 1.0
		_full_health_hide_time_left = 0.0
		_health_poll_accum = 0.0
		return
	var changed_callback: Callable = Callable(self, "_on_health_changed")
	if _health_component.has_signal("health_changed"):
		if not _health_component.is_connected("health_changed", changed_callback):
			_health_component.connect("health_changed", changed_callback)
	var died_callback: Callable = Callable(self, "_on_died")
	if _health_component.has_signal("died"):
		if not _health_component.is_connected("died", died_callback):
			_health_component.connect("died", died_callback)
	_last_health = -1.0
	_last_max_health = -1.0
	_health_poll_accum = 0.0
	set_process(true)
	_on_health_changed(_read_current_health(), _read_max_health())

func _on_health_changed(current_health: float, max_health: float) -> void:
	var took_damage: bool = _last_health >= 0.0 and current_health < _last_health
	if show_damage_popups and took_damage:
		_spawn_damage_popup(_last_health - current_health)
	if took_damage:
		_full_health_hide_time_left = maxf(full_health_hide_delay, 0.0)
	_last_health = current_health
	_last_max_health = max_health
	var safe_max: float = maxf(max_health, 1.0)
	_health_ratio = clampf(current_health / safe_max, 0.0, 1.0)
	_update_bar_visual(_health_ratio)
	_apply_visibility(current_health, _health_ratio)

func _on_died(_entity: Node) -> void:
	_full_health_hide_time_left = 0.0
	visible = false

func _ensure_bar_nodes() -> void:
	position = Vector3(0.0, y_offset, 0.0)
	_billboard_pivot = get_node_or_null("BillboardPivot") as Node3D
	if _billboard_pivot == null:
		_billboard_pivot = Node3D.new()
		_billboard_pivot.name = "BillboardPivot"
		add_child(_billboard_pivot)
	_bar_background = _billboard_pivot.get_node_or_null("BarBackground") as MeshInstance3D
	if _bar_background == null:
		_bar_background = _create_bar_plane("BarBackground", background_color, bar_width, bar_height)
		_billboard_pivot.add_child(_bar_background)
	_bar_fill_anchor = _billboard_pivot.get_node_or_null("BarFillAnchor") as Node3D
	if _bar_fill_anchor == null:
		_bar_fill_anchor = Node3D.new()
		_bar_fill_anchor.name = "BarFillAnchor"
		_bar_fill_anchor.position = Vector3(-bar_width * 0.5, 0.0, 0.0015)
		_billboard_pivot.add_child(_bar_fill_anchor)
	_bar_fill = _bar_fill_anchor.get_node_or_null("BarFill") as MeshInstance3D
	if _bar_fill == null:
		_bar_fill = _create_bar_plane("BarFill", fill_color, bar_width, bar_height * 0.72)
		_bar_fill_anchor.add_child(_bar_fill)
	_refresh_bar_geometry()

func _create_bar_plane(node_name: String, color: Color, width: float, height: float) -> MeshInstance3D:
	var plane_node: MeshInstance3D = MeshInstance3D.new()
	plane_node.name = node_name
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(width, height)
	plane_node.mesh = mesh
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.no_depth_test = false
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	plane_node.material_override = material
	plane_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return plane_node

func _update_bar_visual(health_ratio: float) -> void:
	if _bar_fill == null:
		return
	var ratio: float = clampf(health_ratio, 0.0, 1.0)
	_bar_fill.visible = ratio > 0.0
	_bar_fill.scale = Vector3(maxf(ratio, 0.0001), 1.0, 1.0)
	_bar_fill.position = Vector3(bar_width * 0.5 * ratio, 0.0, 0.0)
	var fill_material: StandardMaterial3D = _bar_fill.material_override as StandardMaterial3D
	if fill_material != null:
		fill_material.albedo_color = _compute_fill_color(ratio)

func _disconnect_health_component() -> void:
	if _health_component == null:
		_last_health = -1.0
		_last_max_health = -1.0
		_health_ratio = 1.0
		_full_health_hide_time_left = 0.0
		_health_poll_accum = 0.0
		return
	var changed_callback: Callable = Callable(self, "_on_health_changed")
	if _health_component.has_signal("health_changed"):
		if _health_component.is_connected("health_changed", changed_callback):
			_health_component.disconnect("health_changed", changed_callback)
	var died_callback: Callable = Callable(self, "_on_died")
	if _health_component.has_signal("died"):
		if _health_component.is_connected("died", died_callback):
			_health_component.disconnect("died", died_callback)
	_health_component = null
	_last_health = -1.0
	_last_max_health = -1.0
	_health_ratio = 1.0
	_full_health_hide_time_left = 0.0
	_health_poll_accum = 0.0

func _spawn_damage_popup(amount: float) -> void:
	if amount <= 0.0:
		return
	var pool: Node = _resolve_damage_pool()
	if pool == null or not pool.has_method("spawn_damage"):
		return
	var target: Node3D = get_parent() as Node3D
	if target == null:
		target = self
	var popup_position: Vector3 = _resolve_target_center_world_position(target) + Vector3(0.0, popup_spawn_y_offset, 0.0)
	pool.call("spawn_damage", target, popup_position, amount, false, popup_color)

func _resolve_damage_pool() -> Node:
	if is_instance_valid(_damage_pool):
		return _damage_pool
	var tree_ref: SceneTree = get_tree()
	if tree_ref == null:
		return null
	var existing_pool: Node = tree_ref.get_first_node_in_group("damage_number_pool_3d")
	if existing_pool != null:
		_damage_pool = existing_pool
		return _damage_pool
	var pool_variant: Variant = DAMAGE_POOL_SCRIPT.new()
	var pool_node: Node = pool_variant as Node
	if pool_node == null:
		return null
	pool_node.name = "DamageNumberPool3D"
	var host: Node = tree_ref.current_scene
	if host == null:
		host = tree_ref.root
	host.add_child(pool_node)
	_damage_pool = pool_node
	return _damage_pool

func _apply_visibility(current_health: float, ratio: float) -> void:
	if current_health <= 0.0:
		visible = false
		return
	if not hide_when_full_health:
		visible = true
		return
	if ratio < 0.999:
		visible = true
		return
	if _full_health_hide_time_left > 0.0:
		visible = true
	else:
		visible = false

func _poll_health_fallback(delta: float) -> void:
	if _health_component == null:
		return
	_health_poll_accum += delta
	var interval: float = maxf(health_poll_interval_seconds, 0.02)
	if _health_poll_accum < interval:
		return
	_health_poll_accum = 0.0
	var current_health: float = _read_current_health()
	var max_health: float = _read_max_health()
	if not is_equal_approx(current_health, _last_health) or not is_equal_approx(max_health, _last_max_health):
		_on_health_changed(current_health, max_health)

func _read_current_health() -> float:
	if _health_component == null:
		return 0.0
	var value: Variant = _health_component.get("current_health")
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return 0.0

func _read_max_health() -> float:
	if _health_component == null:
		return 1.0
	var value: Variant = _health_component.get("max_health")
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return maxf(float(value), 1.0)
	return 1.0

func _resolve_target_center_world_position(target: Node3D) -> Vector3:
	if target == null:
		return global_position
	var collision: CollisionShape3D = target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape != null:
		var half_height: float = _shape_half_height(collision.shape)
		if half_height > 0.0:
			return target.global_position + Vector3(0.0, collision.position.y + half_height * 0.5, 0.0)
	var visual: MeshInstance3D = target.get_node_or_null("Visual") as MeshInstance3D
	if visual != null and visual.mesh != null:
		var aabb: AABB = visual.mesh.get_aabb()
		var center_local: Vector3 = visual.position + aabb.position + aabb.size * 0.5
		return target.to_global(center_local)
	return target.global_position + Vector3(0.0, y_offset * 0.55, 0.0)

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

func _sync_y_offset() -> void:
	if not is_equal_approx(position.y, y_offset):
		position = Vector3(0.0, y_offset, 0.0)

func _face_camera() -> void:
	if _billboard_pivot == null:
		return
	var viewport_ref: Viewport = get_viewport()
	if viewport_ref == null:
		return
	var camera: Camera3D = viewport_ref.get_camera_3d()
	if camera == null:
		return
	var to_camera: Vector3 = camera.global_position - _billboard_pivot.global_position
	to_camera.y = 0.0
	if to_camera.length_squared() <= 0.000001:
		return
	var yaw: float = atan2(to_camera.x, to_camera.z)
	_billboard_pivot.global_rotation = Vector3(0.0, yaw, 0.0)

func _refresh_bar_geometry() -> void:
	if _bar_background != null:
		var background_mesh: QuadMesh = _bar_background.mesh as QuadMesh
		if background_mesh != null:
			background_mesh.size = Vector2(bar_width, bar_height)
		var background_material: StandardMaterial3D = _bar_background.material_override as StandardMaterial3D
		if background_material != null:
			background_material.albedo_color = background_color
	if _bar_fill_anchor != null:
		_bar_fill_anchor.position = Vector3(-bar_width * 0.5, 0.0, 0.002)
	if _bar_fill != null:
		var fill_mesh: QuadMesh = _bar_fill.mesh as QuadMesh
		if fill_mesh != null:
			fill_mesh.size = Vector2(bar_width, bar_height * 0.72)
		var fill_material: StandardMaterial3D = _bar_fill.material_override as StandardMaterial3D
		if fill_material != null:
			fill_material.albedo_color = _compute_fill_color(_health_ratio)

func _compute_fill_color(ratio: float) -> Color:
	var clamped_ratio: float = clampf(ratio, 0.0, 1.0)
	if clamped_ratio >= 0.5:
		var high_t: float = (clamped_ratio - 0.5) / 0.5
		return mid_health_color.lerp(fill_color, high_t)
	var low_t: float = clamped_ratio / 0.5
	return low_health_color.lerp(mid_health_color, low_t)
