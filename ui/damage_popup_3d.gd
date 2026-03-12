extends Label3D
class_name DamagePopup3D

signal expired(popup: DamagePopup3D)

@export var lifetime_seconds: float = 0.72
@export var rise_speed: float = 1.85
@export var drift_speed: float = 0.18
@export var start_scale: float = 0.88
@export var end_scale: float = 1.18

var _active: bool = false
var _elapsed: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
var _base_color: Color = Color(1.0, 0.36, 0.28, 1.0)

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pixel_size = 0.024
	no_depth_test = true
	font_size = 42
	outline_size = 10
	outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	deactivate_popup()

func activate_popup(world_position: Vector3, amount: float, color: Color, critical: bool = false) -> void:
	_active = true
	visible = true
	set_process(true)
	_elapsed = 0.0
	_base_color = color
	global_position = world_position
	var rounded_amount: int = maxi(int(round(amount)), 1)
	text = str(rounded_amount)
	modulate = color
	var scale_boost: float = 1.22 if critical else 1.0
	scale = Vector3.ONE * (start_scale * scale_boost)
	_build_random_velocity()

func deactivate_popup() -> void:
	_active = false
	visible = false
	set_process(false)
	_elapsed = 0.0
	modulate = _base_color

func is_active() -> bool:
	return _active

func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	position += _velocity * delta
	var t: float = clampf(_elapsed / maxf(lifetime_seconds, 0.01), 0.0, 1.0)
	var color: Color = _base_color
	color.a = 1.0 - t
	modulate = color
	var popup_scale: float = lerpf(start_scale, end_scale, t)
	scale = Vector3.ONE * popup_scale
	if _elapsed >= lifetime_seconds:
		_active = false
		expired.emit(self)

func _build_random_velocity() -> void:
	var horizontal: float = randf_range(-drift_speed, drift_speed)
	var forward: float = randf_range(-drift_speed * 0.35, drift_speed * 0.35)
	_velocity = Vector3(horizontal, rise_speed, forward)
