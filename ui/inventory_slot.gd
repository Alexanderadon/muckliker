extends PanelContainer
class_name InventorySlotUI

signal swap_requested(from_index: int, to_index: int)
const ENABLE_INVENTORY_SLOT_DEBUG_LOGS: bool = false

var slot_kind: String = ""
var slot_index: int = -1
var equipment_type: String = ""
var _inventory_system: Node = null
var _inventory_ui: Control = null
var _last_drag_payload: Dictionary = {}

func configure_slot(new_slot_kind: String, new_slot_index: int, inventory_system: Node, inventory_ui: Control, new_equipment_type: String = "") -> void:
	slot_kind = new_slot_kind
	slot_index = new_slot_index
	equipment_type = new_equipment_type
	_inventory_system = inventory_system
	_inventory_ui = inventory_ui

func get_drag_data(_at_position: Vector2) -> Variant:
	if slot_index < 0:
		return null
	if _inventory_ui == null:
		_inventory_ui = get_tree().get_first_node_in_group("inventory_ui") as Control
	if _inventory_ui == null or not _inventory_ui.has_method("get_slot_drag_payload"):
		return null
	var payload_variant: Variant = _inventory_ui.call("get_slot_drag_payload", slot_kind, slot_index, equipment_type)
	if not (payload_variant is Dictionary):
		return null
	var payload: Dictionary = Dictionary(payload_variant)
	if payload.is_empty():
		return null
	_last_drag_payload = payload.duplicate(true)
	_debug_log("Drag payload: kind=%s index=%d item=%s amount=%d" % [slot_kind, slot_index, String(payload.get("item_id", "")), int(payload.get("amount", 0))])
	return payload

func can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if slot_index < 0:
		return false
	if not (data is Dictionary):
		return false
	if _inventory_ui == null:
		_inventory_ui = get_tree().get_first_node_in_group("inventory_ui") as Control
	if _inventory_ui == null or not _inventory_ui.has_method("can_slot_accept_drop"):
		return false
	var payload: Dictionary = Dictionary(data)
	var accepted_variant: Variant = _inventory_ui.call("can_slot_accept_drop", slot_kind, slot_index, equipment_type, payload)
	var accepted: bool = bool(accepted_variant)
	if not accepted:
		_debug_log("Drop rejected: target_kind=%s target_index=%d from_kind=%s from_index=%d" % [slot_kind, slot_index, String(payload.get("from_kind", "")), int(payload.get("from_index", -1))])
	return accepted

func drop_data(_at_position: Vector2, data: Variant) -> void:
	if not can_drop_data(_at_position, data):
		return
	var payload: Dictionary = Dictionary(data)
	_debug_log("Drop attempt: target_kind=%s target_index=%d from_kind=%s from_index=%d" % [slot_kind, slot_index, String(payload.get("from_kind", "")), int(payload.get("from_index", -1))])
	var handled: bool = false
	if _inventory_ui != null and _inventory_ui.has_method("handle_slot_drop"):
		var handled_variant: Variant = _inventory_ui.call("handle_slot_drop", slot_kind, slot_index, equipment_type, payload)
		handled = bool(handled_variant)
	if not handled and _inventory_system != null and _inventory_system.has_method("swap_slots"):
		var from_kind: String = String(payload.get("from_kind", ""))
		var from_index: int = int(payload.get("from_index", -1))
		if _is_inventory_slot_kind(from_kind) and _is_inventory_slot_kind(slot_kind) and from_index >= 0:
			var swapped_variant: Variant = _inventory_system.call("swap_slots", from_index, slot_index)
			handled = bool(swapped_variant)
	if not handled:
		_debug_log("Drop failed: target_kind=%s target_index=%d" % [slot_kind, slot_index])
		return
	_debug_log("Drop success: target_kind=%s target_index=%d" % [slot_kind, slot_index])
	var from_index: int = int(payload.get("from_index", -1))
	if from_index >= 0:
		swap_requested.emit(from_index, slot_index)

func _get_drag_data(at_position: Vector2) -> Variant:
	return get_drag_data(at_position)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return can_drop_data(at_position, data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	drop_data(at_position, data)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event
	if not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _inventory_ui == null:
		_inventory_ui = get_tree().get_first_node_in_group("inventory_ui") as Control
	if _inventory_ui == null or not _inventory_ui.has_method("quick_move_slot"):
		return
	var moved_variant: Variant = _inventory_ui.call("quick_move_slot", slot_kind, slot_index, equipment_type)
	if bool(moved_variant):
		accept_event()

func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	if _last_drag_payload.is_empty():
		return
	if _inventory_ui == null:
		_inventory_ui = get_tree().get_first_node_in_group("inventory_ui") as Control
	var viewport_ref: Viewport = get_viewport()
	var drag_success: bool = viewport_ref != null and viewport_ref.gui_is_drag_successful()
	if not drag_success and _inventory_ui != null:
		var payload_copy: Dictionary = _last_drag_payload.duplicate(true)
		var cursor_position: Vector2 = get_global_mouse_position()
		if _inventory_ui.has_method("handle_manual_drag_end"):
			var handled_variant: Variant = _inventory_ui.call("handle_manual_drag_end", payload_copy, cursor_position)
			if bool(handled_variant):
				_last_drag_payload.clear()
				return
		if _inventory_ui.has_method("handle_failed_slot_drag"):
			_inventory_ui.call("handle_failed_slot_drag", payload_copy, cursor_position)
	_last_drag_payload.clear()

func _build_drag_preview(payload: Dictionary) -> Control:
	if _inventory_ui != null and _inventory_ui.has_method("create_inventory_drag_preview"):
		var preview_variant: Variant = _inventory_ui.call("create_inventory_drag_preview", payload)
		var preview_control: Control = preview_variant as Control
		if preview_control != null:
			return preview_control
	var fallback: PanelContainer = PanelContainer.new()
	fallback.custom_minimum_size = Vector2(72.0, 72.0)
	var label: Label = Label.new()
	label.text = "%s x%d" % [String(payload.get("item_id", "")), int(payload.get("amount", 1))]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fallback.add_child(label)
	return fallback

func _is_inventory_slot_kind(kind: String) -> bool:
	return kind == "inventory" or kind == "hotbar"

func _debug_log(message: String) -> void:
	if not ENABLE_INVENTORY_SLOT_DEBUG_LOGS:
		return
	print("[InventorySlotUI] %s" % message)
