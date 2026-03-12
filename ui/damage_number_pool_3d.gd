extends Node3D
class_name DamageNumberPool3D

@export var popup_script: Script = preload("res://ui/damage_popup_3d.gd")
@export var initial_pool_size: int = 40
@export var max_pool_size: int = 96
@export var max_active_popups: int = 64
@export var max_active_per_target: int = 3
@export var reuse_oldest_when_full: bool = true
@export var damage_log_capacity: int = 64
@export var normal_damage_color: Color = Color(1.0, 0.36, 0.28, 1.0)
@export var critical_damage_color: Color = Color(1.0, 0.88, 0.3, 1.0)

var _available_popups: Array[DamagePopup3D] = []
var _active_popups: Array[DamagePopup3D] = []
var _target_popup_lookup: Dictionary = {}
var _popup_target_lookup: Dictionary = {}
var _damage_log: Array[Dictionary] = []
var _total_popup_count: int = 0

func _ready() -> void:
	add_to_group("damage_number_pool_3d")
	_prewarm_pool(maxi(initial_pool_size, 0))

func spawn_damage(target: Node3D, world_position: Vector3, amount: float, critical: bool = false, color_override: Color = Color(0.0, 0.0, 0.0, 0.0)) -> void:
	if amount <= 0.0:
		return
	var target_id: int = target.get_instance_id() if is_instance_valid(target) else 0
	_enforce_per_target_limit(target_id)
	if _active_popups.size() >= max_active_popups:
		if reuse_oldest_when_full:
			_recycle_oldest_popup()
		else:
			_append_damage_log(target_id, amount, critical, true)
			return
	var popup: DamagePopup3D = _acquire_popup()
	if popup == null:
		_append_damage_log(target_id, amount, critical, true)
		return
	var popup_color: Color = _resolve_popup_color(critical, color_override)
	popup.activate_popup(world_position, amount, popup_color, critical)
	_active_popups.append(popup)
	var popup_id: int = popup.get_instance_id()
	_popup_target_lookup[popup_id] = target_id
	if target_id != 0:
		var target_popups: Array = _target_popup_lookup.get(target_id, [])
		target_popups.append(popup_id)
		_target_popup_lookup[target_id] = target_popups
	_append_damage_log(target_id, amount, critical, false)

func get_debug_counts() -> Dictionary:
	return {
		"pool_total": _total_popup_count,
		"pool_available": _available_popups.size(),
		"active": _active_popups.size(),
		"tracked_targets": _target_popup_lookup.size(),
		"log_size": _damage_log.size()
	}

func get_recent_damage_log() -> Array[Dictionary]:
	return _damage_log.duplicate(true)

func _prewarm_pool(count: int) -> void:
	for _i in range(count):
		var popup: DamagePopup3D = _create_popup()
		if popup == null:
			break
		_available_popups.append(popup)

func _create_popup() -> DamagePopup3D:
	if popup_script == null:
		return null
	var popup_variant: Variant = popup_script.new()
	var popup: DamagePopup3D = popup_variant as DamagePopup3D
	if popup == null:
		return null
	popup.name = "DamagePopup3D_%d" % _total_popup_count
	popup.deactivate_popup()
	var expired_callback: Callable = Callable(self, "_on_popup_expired")
	if not popup.expired.is_connected(expired_callback):
		popup.expired.connect(expired_callback)
	add_child(popup)
	_total_popup_count += 1
	return popup

func _acquire_popup() -> DamagePopup3D:
	if not _available_popups.is_empty():
		return _available_popups.pop_back()
	if _total_popup_count < max_pool_size:
		return _create_popup()
	if reuse_oldest_when_full:
		return _recycle_oldest_popup()
	return null

func _on_popup_expired(popup: DamagePopup3D) -> void:
	_release_popup(popup)

func _release_popup(popup: DamagePopup3D) -> void:
	if popup == null:
		return
	var active_index: int = _active_popups.find(popup)
	if active_index >= 0:
		_active_popups.remove_at(active_index)
	var popup_id: int = popup.get_instance_id()
	var target_id: int = int(_popup_target_lookup.get(popup_id, 0))
	_popup_target_lookup.erase(popup_id)
	if target_id != 0:
		var target_popups: Array = _target_popup_lookup.get(target_id, [])
		var popup_index: int = target_popups.find(popup_id)
		if popup_index >= 0:
			target_popups.remove_at(popup_index)
		if target_popups.is_empty():
			_target_popup_lookup.erase(target_id)
		else:
			_target_popup_lookup[target_id] = target_popups
	popup.deactivate_popup()
	if not _available_popups.has(popup):
		_available_popups.append(popup)

func _recycle_oldest_popup() -> DamagePopup3D:
	if _active_popups.is_empty():
		return null
	var oldest: DamagePopup3D = _active_popups[0]
	_release_popup(oldest)
	if _available_popups.is_empty():
		return null
	return _available_popups.pop_back()

func _enforce_per_target_limit(target_id: int) -> void:
	if target_id == 0 or max_active_per_target <= 0:
		return
	var target_popups: Array = _target_popup_lookup.get(target_id, [])
	while target_popups.size() >= max_active_per_target:
		var oldest_popup_id: int = int(target_popups[0])
		_release_popup_by_id(oldest_popup_id)
		target_popups = _target_popup_lookup.get(target_id, [])

func _release_popup_by_id(popup_id: int) -> void:
	var popup_obj: Object = instance_from_id(popup_id)
	var popup: DamagePopup3D = popup_obj as DamagePopup3D
	if popup != null and is_instance_valid(popup):
		_release_popup(popup)
		return
	var target_id: int = int(_popup_target_lookup.get(popup_id, 0))
	_popup_target_lookup.erase(popup_id)
	if target_id == 0:
		return
	var target_popups: Array = _target_popup_lookup.get(target_id, [])
	var popup_index: int = target_popups.find(popup_id)
	if popup_index >= 0:
		target_popups.remove_at(popup_index)
	if target_popups.is_empty():
		_target_popup_lookup.erase(target_id)
	else:
		_target_popup_lookup[target_id] = target_popups

func _resolve_popup_color(critical: bool, color_override: Color) -> Color:
	if color_override.a > 0.001:
		return color_override
	return critical_damage_color if critical else normal_damage_color

func _append_damage_log(target_id: int, amount: float, critical: bool, dropped: bool) -> void:
	if damage_log_capacity <= 0:
		return
	if _damage_log.size() >= damage_log_capacity:
		_damage_log.pop_front()
	_damage_log.append({
		"time_msec": Time.get_ticks_msec(),
		"target_id": target_id,
		"amount": amount,
		"critical": critical,
		"dropped": dropped
	})
