extends Control
class_name InventoryUI

const TOTAL_SLOTS: int = 30
const HOTBAR_SLOT_COUNT: int = 8
const INVENTORY_GRID_SLOTS: int = TOTAL_SLOTS - HOTBAR_SLOT_COUNT
const EQUIPMENT_TYPES: Array[String] = ["helmet", "chest", "legs", "boots", "weapon"]
const SLOT_SIZE: Vector2 = Vector2(72.0, 72.0)
const INVENTORY_TOGGLE_ACTION: StringName = &"inventory_toggle"
const CRAFTING_TOGGLE_ACTION: StringName = &"crafting_toggle"
const DROP_ONE_ACTION: StringName = &"drop_item_one"
const CRAFT_CLICK_COOLDOWN_MS: int = 220
const ENABLE_SLOT_CRAFT_FALLBACK: bool = false
const ENABLE_INVENTORY_UI_DEBUG_LOGS: bool = false
const DRAG_PREVIEW_Z_INDEX: int = 4096

var _slot_scene: PackedScene = preload("res://ui/inventory_slot.tscn")

var _bound_player: Node = null
var _inventory_component: InventoryComponent = null
var _inventory_system: Node = null
var _crafting_system: Node = null
var _selected_hotbar_index: int = 0

var _inventory_slots: Array[Control] = []
var _equipment_slots: Dictionary = {}
var _all_slots: Array[Control] = []

var _equipment_items: Dictionary = {
	"helmet": {},
	"chest": {},
	"legs": {},
	"boots": {},
	"weapon": {}
}

var _root_panel: PanelContainer = null
var _inventory_column: VBoxContainer = null
var _crafting_column: VBoxContainer = null
var _craft_status_label: Label = null
var _resource_summary_label: Label = null
var _craft_axe_button: Button = null
var _craft_pickaxe_button: Button = null
var _is_crafting_mode: bool = false
var _last_craft_request_time_ms: int = 0
var _craft_in_progress: bool = false
var _suspend_inventory_refresh: bool = false
var _pending_inventory_refresh: bool = false
var _manual_drag_active: bool = false
var _manual_drag_payload: Dictionary = {}
var _manual_drag_preview: Control = null

func _ready() -> void:
	add_to_group("inventory_ui")
	add_to_group("crafting_ui")
	mouse_filter = Control.MOUSE_FILTER_PASS
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = true
	_ensure_input_actions()
	_build_layout()
	_set_window_open(false)
	_resolve_runtime_system_refs()
	update_ui()

func _process(_delta: float) -> void:
	if not _manual_drag_active:
		return
	_update_manual_drag_preview_position()

func _input(event: InputEvent) -> void:
	if not is_inventory_panel_open():
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var cursor_position: Vector2 = get_global_mouse_position()
	if mouse_event.pressed:
		if _manual_drag_active:
			return
		if _is_crafting_mode:
			if _craft_axe_button != null and _craft_axe_button.get_global_rect().has_point(cursor_position):
				return
			if _craft_pickaxe_button != null and _craft_pickaxe_button.get_global_rect().has_point(cursor_position):
				return
		var source_slot: Control = _find_slot_at_position(cursor_position)
		if source_slot == null:
			return
		var source_kind: String = String(source_slot.get_meta("slot_kind", ""))
		var source_index: int = int(source_slot.get_meta("slot_index", -1))
		var source_equipment_type: String = String(source_slot.get_meta("equipment_type", ""))
		var payload: Dictionary = get_slot_drag_payload(source_kind, source_index, source_equipment_type)
		if payload.is_empty():
			return
		if begin_manual_drag(payload):
			get_viewport().set_input_as_handled()
		return
	if _manual_drag_active:
		end_manual_drag(cursor_position)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_TAB:
			_toggle_inventory(false)
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_I:
			_toggle_inventory(true)
			get_viewport().set_input_as_handled()
			return
	if not is_inventory_panel_open():
		return
	if event is InputEventKey:
		var drop_key_event: InputEventKey = event
		if drop_key_event.pressed and not drop_key_event.echo and drop_key_event.physical_keycode == KEY_Q:
			_drop_one_item_under_cursor()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var cursor_position: Vector2 = get_global_mouse_position()
			if _is_crafting_mode:
				if _craft_axe_button != null and _craft_axe_button.get_global_rect().has_point(cursor_position):
					_debug_log("Fallback craft click: axe")
					_craft_recipe("axe")
					get_viewport().set_input_as_handled()
					return
				if _craft_pickaxe_button != null and _craft_pickaxe_button.get_global_rect().has_point(cursor_position):
					_debug_log("Fallback craft click: pickaxe")
					_craft_recipe("pickaxe")
					get_viewport().set_input_as_handled()
					return

func bind(player: Node, inventory_system: Node = null, crafting_system: Node = null) -> void:
	_disconnect_player_hotbar_signal()
	_bound_player = player
	_connect_player_hotbar_signal()
	_sync_selected_hotbar_index()
	_resolve_inventory_component_from_player()
	set_inventory_system(inventory_system)
	set_crafting_system(crafting_system)
	_try_bind_inventory_component()
	_load_equipment_state()
	update_ui()

func set_inventory_system(inventory_system: Node) -> void:
	if _inventory_system == inventory_system:
		return
	var callback: Callable = Callable(self, "_on_inventory_system_changed")
	if _inventory_system != null and _inventory_system.has_signal("inventory_changed") and _inventory_system.is_connected("inventory_changed", callback):
		_inventory_system.disconnect("inventory_changed", callback)
	_inventory_system = inventory_system
	if _inventory_system != null and _inventory_system.has_signal("inventory_changed") and not _inventory_system.is_connected("inventory_changed", callback):
		_inventory_system.connect("inventory_changed", callback)
	_try_bind_inventory_component()
	_configure_slot_drag_sources()

func set_crafting_system(crafting_system: Node) -> void:
	_crafting_system = crafting_system
	if _crafting_system != null and _inventory_system != null and _crafting_system.has_method("set_inventory_system"):
		_crafting_system.call("set_inventory_system", _inventory_system)

func update_ui() -> void:
	_resolve_runtime_system_refs()
	_refresh_all_slots()
	_refresh_resource_summary()
	_refresh_craft_buttons_state()
	_configure_slot_drag_sources()

func is_inventory_panel_open() -> bool:
	return _root_panel != null and is_instance_valid(_root_panel) and _root_panel.visible

func _toggle_inventory(open_crafting: bool) -> void:
	_resolve_runtime_system_refs()
	if is_inventory_panel_open():
		_set_window_open(false)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	_set_window_open(true)
	_set_ui_mode(open_crafting)
	_load_equipment_state()
	_set_craft_status("")
	update_ui()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _set_window_open(open: bool) -> void:
	if _root_panel != null and is_instance_valid(_root_panel):
		_root_panel.visible = open
	if not open:
		var viewport_ref: Viewport = get_viewport()
		if viewport_ref != null:
			viewport_ref.gui_release_focus()
		_clear_manual_drag()

func _set_ui_mode(crafting_mode: bool) -> void:
	_is_crafting_mode = crafting_mode
	if _inventory_column != null:
		_inventory_column.visible = not crafting_mode
	if _crafting_column != null:
		_crafting_column.visible = crafting_mode

func _build_layout() -> void:
	_inventory_slots.clear()
	_equipment_slots.clear()
	_all_slots.clear()
	for child in get_children():
		child.queue_free()

	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)

	var layout_root: Control = Control.new()
	layout_root.anchor_right = 1.0
	layout_root.anchor_bottom = 1.0
	layout_root.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(layout_root)

	var center: CenterContainer = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	layout_root.add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(1020.0, 620.0)
	_root_panel.visible = false
	center.add_child(_root_panel)

	var root_style: StyleBoxFlat = StyleBoxFlat.new()
	root_style.bg_color = Color(0.07, 0.07, 0.09, 0.95)
	root_style.border_color = Color(0.24, 0.24, 0.3, 0.95)
	root_style.set_border_width_all(2)
	root_style.corner_radius_top_left = 8
	root_style.corner_radius_top_right = 8
	root_style.corner_radius_bottom_left = 8
	root_style.corner_radius_bottom_right = 8
	_root_panel.add_theme_stylebox_override("panel", root_style)

	var content_margin: MarginContainer = MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 18)
	content_margin.add_theme_constant_override("margin_top", 18)
	content_margin.add_theme_constant_override("margin_right", 18)
	content_margin.add_theme_constant_override("margin_bottom", 18)
	_root_panel.add_child(content_margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	content_margin.add_child(row)

	var equipment_column: VBoxContainer = VBoxContainer.new()
	equipment_column.custom_minimum_size = Vector2(220.0, 0.0)
	equipment_column.add_theme_constant_override("separation", 10)
	row.add_child(equipment_column)

	var equipment_title: Label = Label.new()
	equipment_title.text = "Equipment"
	equipment_column.add_child(equipment_title)

	var equipment_grid: GridContainer = GridContainer.new()
	equipment_grid.columns = 1
	equipment_grid.add_theme_constant_override("v_separation", 8)
	equipment_column.add_child(equipment_grid)

	for equipment_type in EQUIPMENT_TYPES:
		var slot_block: VBoxContainer = VBoxContainer.new()
		slot_block.add_theme_constant_override("separation", 3)
		var slot_label: Label = Label.new()
		slot_label.text = equipment_type.capitalize()
		slot_block.add_child(slot_label)
		var slot_control: Control = _create_slot("equipment", 0, equipment_type)
		slot_block.add_child(slot_control)
		equipment_grid.add_child(slot_block)
		_equipment_slots[equipment_type] = slot_control

	_inventory_column = VBoxContainer.new()
	_inventory_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_column.add_theme_constant_override("separation", 8)
	row.add_child(_inventory_column)

	var inventory_title: Label = Label.new()
	inventory_title.text = "Inventory"
	_inventory_column.add_child(inventory_title)

	var inventory_hint: Label = Label.new()
	inventory_hint.text = "Hotbar is shown at bottom and mirrored here."
	_inventory_column.add_child(inventory_hint)

	var hotbar_label: Label = Label.new()
	hotbar_label.text = "Hotbar"
	_inventory_column.add_child(hotbar_label)

	var panel_hotbar_grid: GridContainer = GridContainer.new()
	panel_hotbar_grid.columns = HOTBAR_SLOT_COUNT
	panel_hotbar_grid.add_theme_constant_override("h_separation", 8)
	_inventory_column.add_child(panel_hotbar_grid)

	for hotbar_index in range(HOTBAR_SLOT_COUNT):
		var panel_hotbar_slot: Control = _create_slot("hotbar", hotbar_index)
		panel_hotbar_grid.add_child(panel_hotbar_slot)

	var inventory_grid: GridContainer = GridContainer.new()
	inventory_grid.columns = 6
	inventory_grid.add_theme_constant_override("h_separation", 8)
	inventory_grid.add_theme_constant_override("v_separation", 8)
	_inventory_column.add_child(inventory_grid)

	for local_index in range(INVENTORY_GRID_SLOTS):
		var global_slot_index: int = HOTBAR_SLOT_COUNT + local_index
		var inventory_slot: Control = _create_slot("inventory", global_slot_index)
		inventory_grid.add_child(inventory_slot)
		_inventory_slots.append(inventory_slot)

	_crafting_column = VBoxContainer.new()
	_crafting_column.visible = false
	_crafting_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crafting_column.add_theme_constant_override("separation", 8)
	row.add_child(_crafting_column)

	var crafting_title: Label = Label.new()
	crafting_title.text = "Crafting"
	_crafting_column.add_child(crafting_title)

	_resource_summary_label = Label.new()
	_resource_summary_label.text = "Resources: Wood 0, Stone 0, Stick 0"
	_crafting_column.add_child(_resource_summary_label)

	_craft_axe_button = Button.new()
	_craft_axe_button.text = "Craft Axe (3 Stone, 2 Wood)"
	_craft_axe_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_craft_axe_button.focus_mode = Control.FOCUS_NONE
	_craft_axe_button.custom_minimum_size = Vector2(280.0, 34.0)
	_craft_axe_button.pressed.connect(Callable(self, "_on_craft_axe_pressed"))
	_crafting_column.add_child(_craft_axe_button)

	_craft_pickaxe_button = Button.new()
	_craft_pickaxe_button.text = "Craft Pickaxe (3 Stone, 2 Wood)"
	_craft_pickaxe_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_craft_pickaxe_button.focus_mode = Control.FOCUS_NONE
	_craft_pickaxe_button.custom_minimum_size = Vector2(280.0, 34.0)
	_craft_pickaxe_button.pressed.connect(Callable(self, "_on_craft_pickaxe_pressed"))
	_crafting_column.add_child(_craft_pickaxe_button)

	_craft_status_label = Label.new()
	_craft_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_status_label.text = ""
	_crafting_column.add_child(_craft_status_label)

	var hud_anchor: CenterContainer = CenterContainer.new()
	hud_anchor.anchor_left = 0.0
	hud_anchor.anchor_right = 1.0
	hud_anchor.anchor_top = 1.0
	hud_anchor.anchor_bottom = 1.0
	hud_anchor.offset_top = -120.0
	hud_anchor.offset_bottom = -16.0
	layout_root.add_child(hud_anchor)

	var hud_panel: PanelContainer = PanelContainer.new()
	hud_anchor.add_child(hud_panel)

	var hud_style: StyleBoxFlat = StyleBoxFlat.new()
	hud_style.bg_color = Color(0.06, 0.06, 0.08, 0.88)
	hud_style.border_color = Color(0.24, 0.24, 0.28, 0.95)
	hud_style.set_border_width_all(2)
	hud_style.corner_radius_top_left = 8
	hud_style.corner_radius_top_right = 8
	hud_style.corner_radius_bottom_left = 8
	hud_style.corner_radius_bottom_right = 8
	hud_panel.add_theme_stylebox_override("panel", hud_style)

	var hud_margin: MarginContainer = MarginContainer.new()
	hud_margin.add_theme_constant_override("margin_left", 8)
	hud_margin.add_theme_constant_override("margin_top", 8)
	hud_margin.add_theme_constant_override("margin_right", 8)
	hud_margin.add_theme_constant_override("margin_bottom", 8)
	hud_panel.add_child(hud_margin)

	var hud_grid: GridContainer = GridContainer.new()
	hud_grid.columns = HOTBAR_SLOT_COUNT
	hud_grid.add_theme_constant_override("h_separation", 6)
	hud_margin.add_child(hud_grid)

	for hud_hotbar_index in range(HOTBAR_SLOT_COUNT):
		var hud_hotbar_slot: Control = _create_slot("hotbar", hud_hotbar_index, "", true)
		hud_grid.add_child(hud_hotbar_slot)

	_configure_slot_drag_sources()
	_refresh_craft_buttons_state()

func _create_slot(slot_kind: String, slot_index: int, equipment_type: String = "", show_slot_number: bool = false) -> Control:
	var slot_control: Control = null
	if _slot_scene != null:
		var slot_variant: Variant = _slot_scene.instantiate()
		slot_control = slot_variant as Control
	if slot_control == null:
		slot_control = PanelContainer.new()
	slot_control.custom_minimum_size = SLOT_SIZE
	slot_control.mouse_filter = Control.MOUSE_FILTER_STOP
	slot_control.set_meta("slot_kind", slot_kind)
	slot_control.set_meta("slot_index", slot_index)
	slot_control.set_meta("equipment_type", equipment_type)
	slot_control.set_meta("show_slot_number", show_slot_number)
	_apply_slot_style(slot_control, slot_kind, false)
	_ensure_slot_visual_children(slot_control)
	_all_slots.append(slot_control)
	return slot_control

func _apply_slot_style(slot_control: Control, slot_kind: String, is_selected: bool = false) -> void:
	var panel: PanelContainer = slot_control as PanelContainer
	if panel == null:
		return
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.11, 0.14, 0.95)
	if slot_kind == "equipment":
		style.border_color = Color(0.28, 0.6, 0.9, 0.95)
		style.set_border_width_all(1)
	elif slot_kind == "hotbar" and is_selected:
		style.border_color = Color(0.94, 0.79, 0.25, 1.0)
		style.set_border_width_all(2)
	else:
		style.border_color = Color(0.35, 0.35, 0.42, 0.95)
		style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

func _ensure_slot_visual_children(slot_control: Control) -> void:
	var icon: ColorRect = slot_control.get_node_or_null("Icon") as ColorRect
	if icon == null:
		icon = ColorRect.new()
		icon.name = "Icon"
		icon.position = Vector2(11.0, 7.0)
		icon.size = Vector2(50.0, 28.0)
		icon.color = Color(0.24, 0.24, 0.27, 1.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_control.add_child(icon)

	var name_label: Label = slot_control.get_node_or_null("NameLabel") as Label
	if name_label == null:
		name_label = Label.new()
		name_label.name = "NameLabel"
		name_label.position = Vector2(5.0, 38.0)
		name_label.size = Vector2(62.0, 18.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_control.add_child(name_label)

	var amount_label: Label = slot_control.get_node_or_null("AmountLabel") as Label
	if amount_label == null:
		amount_label = Label.new()
		amount_label.name = "AmountLabel"
		amount_label.position = Vector2(38.0, 54.0)
		amount_label.size = Vector2(30.0, 14.0)
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount_label.add_theme_font_size_override("font_size", 11)
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_control.add_child(amount_label)

func _configure_slot_drag_sources() -> void:
	for slot_variant in _all_slots:
		var slot_control: Control = slot_variant as Control
		if slot_control == null or not is_instance_valid(slot_control):
			continue
		var inventory_slot: InventorySlotUI = slot_control as InventorySlotUI
		if inventory_slot == null:
			continue
		var slot_kind: String = String(slot_control.get_meta("slot_kind", ""))
		var slot_index: int = int(slot_control.get_meta("slot_index", -1))
		var equipment_type: String = String(slot_control.get_meta("equipment_type", ""))
		inventory_slot.configure_slot(slot_kind, slot_index, _inventory_system, self, equipment_type)
		if not inventory_slot.swap_requested.is_connected(_on_slot_swap):
			inventory_slot.swap_requested.connect(_on_slot_swap)

func _on_slot_swap(_from_index: int, _to_index: int) -> void:
	update_ui()

func _refresh_all_slots() -> void:
	for slot_variant in _all_slots:
		var slot_control: Control = slot_variant as Control
		if slot_control == null or not is_instance_valid(slot_control):
			continue
		_refresh_slot(slot_control)

func _refresh_slot(slot_control: Control) -> void:
	var icon: ColorRect = slot_control.get_node_or_null("Icon") as ColorRect
	var name_label: Label = slot_control.get_node_or_null("NameLabel") as Label
	var amount_label: Label = slot_control.get_node_or_null("AmountLabel") as Label
	if icon == null or name_label == null or amount_label == null:
		return
	var slot_kind: String = String(slot_control.get_meta("slot_kind", ""))
	var slot_index: int = int(slot_control.get_meta("slot_index", -1))
	var equipment_type: String = String(slot_control.get_meta("equipment_type", ""))
	var is_selected_hotbar: bool = slot_kind == "hotbar" and slot_index == _selected_hotbar_index
	_apply_slot_style(slot_control, slot_kind, is_selected_hotbar)
	var item: Dictionary = _get_slot_item_by_ref(slot_kind, slot_index, equipment_type)
	if item.is_empty():
		icon.color = Color(0.24, 0.24, 0.27, 1.0)
		var show_slot_number: bool = bool(slot_control.get_meta("show_slot_number", false))
		name_label.text = str(slot_index + 1) if show_slot_number and _is_inventory_slot_kind(slot_kind) else ""
		amount_label.text = ""
		return
	var item_id: String = String(item.get("id", item.get("item_id", "")))
	var amount: int = int(item.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		icon.color = Color(0.24, 0.24, 0.27, 1.0)
		name_label.text = ""
		amount_label.text = ""
		return
	icon.color = _get_item_color(item_id)
	name_label.text = _get_item_label(item_id)
	amount_label.text = "x%d" % amount if amount > 1 else ""

func get_slot_drag_payload(slot_kind: String, slot_index: int, equipment_type: String = "") -> Dictionary:
	var item: Dictionary = _get_slot_item_by_ref(slot_kind, slot_index, equipment_type)
	if item.is_empty():
		return {}
	var item_id: String = String(item.get("id", item.get("item_id", "")))
	var amount: int = int(item.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return {}
	return {
		"type": "slot_item",
		"from_kind": slot_kind,
		"from_index": slot_index,
		"from_equipment_type": equipment_type,
		"item_id": item_id,
		"amount": amount,
		"item": item.duplicate(true)
	}

func can_slot_accept_drop(target_kind: String, target_index: int, target_equipment_type: String, payload: Dictionary) -> bool:
	if String(payload.get("type", "")) != "slot_item":
		return false
	var from_kind: String = String(payload.get("from_kind", ""))
	var from_index: int = int(payload.get("from_index", -1))
	var from_equipment_type: String = String(payload.get("from_equipment_type", ""))
	if from_index < 0:
		return false
	if from_kind == target_kind and from_index == target_index and from_equipment_type == target_equipment_type:
		return false
	var source_item: Dictionary = {}
	var source_item_variant: Variant = payload.get("item", {})
	if source_item_variant is Dictionary:
		source_item = Dictionary(source_item_variant)
	if source_item.is_empty():
		source_item = _get_slot_item_by_ref(from_kind, from_index, from_equipment_type)
	if source_item.is_empty():
		return false
	if not _can_slot_ref_accept_item(target_kind, target_equipment_type, source_item):
		return false
	var target_item: Dictionary = _get_slot_item_by_ref(target_kind, target_index, target_equipment_type)
	if target_item.is_empty():
		return true
	return _can_slot_ref_accept_item(from_kind, from_equipment_type, target_item)

func handle_slot_drop(target_kind: String, target_index: int, target_equipment_type: String, payload: Dictionary) -> bool:
	if not can_slot_accept_drop(target_kind, target_index, target_equipment_type, payload):
		return false
	var from_kind: String = String(payload.get("from_kind", ""))
	var from_index: int = int(payload.get("from_index", -1))
	var from_equipment_type: String = String(payload.get("from_equipment_type", ""))
	if from_index < 0:
		return false
	if _is_inventory_slot_kind(from_kind) and _is_inventory_slot_kind(target_kind):
		if _inventory_system == null or not _inventory_system.has_method("swap_slots"):
			return false
		_debug_log("swap_slots request: %d -> %d" % [from_index, target_index])
		var swapped_variant: Variant = _inventory_system.call("swap_slots", from_index, target_index)
		var swapped: bool = bool(swapped_variant)
		_debug_log("swap_slots result: %s" % str(swapped))
		if swapped:
			update_ui()
		return swapped
	var source_item: Dictionary = _get_slot_item_by_ref(from_kind, from_index, from_equipment_type)
	var target_item: Dictionary = _get_slot_item_by_ref(target_kind, target_index, target_equipment_type)
	_set_slot_item_by_ref(target_kind, target_index, target_equipment_type, source_item)
	_set_slot_item_by_ref(from_kind, from_index, from_equipment_type, target_item)
	update_ui()
	return true

func create_inventory_drag_preview(payload: Dictionary) -> Control:
	var item_id: String = String(payload.get("item_id", ""))
	var amount: int = int(payload.get("amount", 0))
	var preview: PanelContainer = PanelContainer.new()
	preview.custom_minimum_size = SLOT_SIZE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22, 0.92)
	style.border_color = Color(0.86, 0.86, 0.9, 0.9)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	preview.add_theme_stylebox_override("panel", style)
	var label: Label = Label.new()
	label.text = "%s x%d" % [_get_item_label(item_id), maxi(amount, 1)]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.add_child(label)
	return preview

func handle_failed_slot_drag(payload: Dictionary, cursor_global_position: Vector2) -> void:
	if not is_inventory_panel_open():
		return
	if String(payload.get("type", "")) != "slot_item":
		return
	if _is_point_inside_inventory_window(cursor_global_position):
		return
	var from_kind: String = String(payload.get("from_kind", ""))
	var from_index: int = int(payload.get("from_index", -1))
	var from_equipment_type: String = String(payload.get("from_equipment_type", ""))
	if from_index < 0:
		return
	var extracted: Dictionary = {}
	if _is_inventory_slot_kind(from_kind):
		if _inventory_system == null or not _inventory_system.has_method("extract_from_slot"):
			return
		var amount: int = int(payload.get("amount", 1))
		var extracted_variant: Variant = _inventory_system.call("extract_from_slot", from_index, maxi(amount, 1))
		if extracted_variant is Dictionary:
			extracted = Dictionary(extracted_variant)
	else:
		extracted = _get_slot_item_by_ref(from_kind, from_index, from_equipment_type)
		if extracted.is_empty():
			return
		_set_slot_item_by_ref(from_kind, from_index, from_equipment_type, {})
	if extracted.is_empty():
		return
	_drop_item_to_world(extracted)
	update_ui()

func handle_manual_drag_end(payload: Dictionary, cursor_global_position: Vector2) -> bool:
	if String(payload.get("type", "")) != "slot_item":
		return false
	var target_slot: Control = _find_slot_at_position(cursor_global_position)
	if target_slot == null:
		return false
	var target_kind: String = String(target_slot.get_meta("slot_kind", ""))
	var target_index: int = int(target_slot.get_meta("slot_index", -1))
	var target_equipment_type: String = String(target_slot.get_meta("equipment_type", ""))
	if target_index < 0:
		return false
	var handled: bool = handle_slot_drop(target_kind, target_index, target_equipment_type, payload)
	if handled:
		update_ui()
	return handled

func begin_manual_drag(payload: Dictionary) -> bool:
	if String(payload.get("type", "")) != "slot_item":
		return false
	_clear_manual_drag()
	_manual_drag_payload = payload.duplicate(true)
	var preview: Control = create_inventory_drag_preview(_manual_drag_payload)
	if preview == null:
		_manual_drag_payload.clear()
		return false
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.top_level = true
	preview.z_index = clampi(DRAG_PREVIEW_Z_INDEX, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX)
	add_child(preview)
	_manual_drag_preview = preview
	_manual_drag_active = true
	_update_manual_drag_preview_position()
	return true

func end_manual_drag(cursor_global_position: Vector2) -> bool:
	if not _manual_drag_active:
		return false
	var payload: Dictionary = _manual_drag_payload.duplicate(true)
	var handled: bool = false
	if String(payload.get("type", "")) == "slot_item":
		var target_slot: Control = _find_slot_at_position(cursor_global_position)
		if target_slot != null:
			var target_kind: String = String(target_slot.get_meta("slot_kind", ""))
			var target_index: int = int(target_slot.get_meta("slot_index", -1))
			var target_equipment_type: String = String(target_slot.get_meta("equipment_type", ""))
			if target_index >= 0:
				handled = handle_slot_drop(target_kind, target_index, target_equipment_type, payload)
		if not handled:
			handle_failed_slot_drag(payload, cursor_global_position)
			handled = true
	_clear_manual_drag()
	if handled:
		update_ui()
	return handled

func _update_manual_drag_preview_position() -> void:
	if _manual_drag_preview == null or not is_instance_valid(_manual_drag_preview):
		return
	var cursor_position: Vector2 = get_global_mouse_position()
	_manual_drag_preview.global_position = cursor_position + Vector2(14.0, 14.0)

func _clear_manual_drag() -> void:
	_manual_drag_active = false
	_manual_drag_payload.clear()
	if _manual_drag_preview != null and is_instance_valid(_manual_drag_preview):
		_manual_drag_preview.queue_free()
	_manual_drag_preview = null

func _drop_one_item_under_cursor() -> void:
	var hovered_slot: Control = _find_slot_at_position(get_global_mouse_position())
	if hovered_slot == null:
		return
	var slot_kind: String = String(hovered_slot.get_meta("slot_kind", ""))
	var slot_index: int = int(hovered_slot.get_meta("slot_index", -1))
	var equipment_type: String = String(hovered_slot.get_meta("equipment_type", ""))
	var extracted: Dictionary = {}
	if _is_inventory_slot_kind(slot_kind):
		if _inventory_system == null or not _inventory_system.has_method("extract_from_slot"):
			return
		var extracted_variant: Variant = _inventory_system.call("extract_from_slot", slot_index, 1)
		if extracted_variant is Dictionary:
			extracted = Dictionary(extracted_variant)
	else:
		var equipment_item: Dictionary = _get_slot_item_by_ref(slot_kind, slot_index, equipment_type)
		if equipment_item.is_empty():
			return
		var item_id: String = String(equipment_item.get("id", equipment_item.get("item_id", "")))
		var amount: int = int(equipment_item.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			return
		extracted = {
			"id": item_id,
			"amount": 1
		}
		if amount <= 1:
			_set_slot_item_by_ref(slot_kind, slot_index, equipment_type, {})
		else:
			_set_slot_item_by_ref(slot_kind, slot_index, equipment_type, {
				"id": item_id,
				"amount": amount - 1
			})
	if extracted.is_empty():
		return
	_drop_item_to_world(extracted)
	update_ui()

func _drop_item_to_world(item: Dictionary) -> void:
	if item.is_empty() or _bound_player == null:
		return
	var item_id: String = String(item.get("id", item.get("item_id", "")))
	var amount: int = int(item.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return
	var player_body: Node3D = _bound_player as Node3D
	if player_body == null:
		return
	var forward: Vector3 = -player_body.global_transform.basis.z
	var drop_position: Vector3 = player_body.global_position + forward * 1.2 + Vector3(0.0, 0.7, 0.0)
	EventBus.emit_game_event("loot_spawn_requested", {
		"position": drop_position,
		"item_id": item_id,
		"amount": amount
	})

func _find_slot_at_position(cursor_global_position: Vector2) -> Control:
	for slot_variant in _all_slots:
		var slot_control: Control = slot_variant as Control
		if slot_control == null or not is_instance_valid(slot_control):
			continue
		if not slot_control.is_visible_in_tree():
			continue
		var rect: Rect2 = slot_control.get_global_rect()
		if rect.has_point(cursor_global_position):
			return slot_control
	return null

func _is_point_inside_inventory_window(cursor_global_position: Vector2) -> bool:
	if _root_panel == null or not is_instance_valid(_root_panel):
		return false
	if not is_inventory_panel_open():
		return false
	return _root_panel.get_global_rect().has_point(cursor_global_position)

func _on_craft_axe_pressed() -> void:
	_craft_recipe("axe")

func _on_craft_pickaxe_pressed() -> void:
	_craft_recipe("pickaxe")

func _craft_recipe(recipe_id: String) -> void:
	_resolve_runtime_system_refs()
	if _craft_in_progress:
		_debug_log("Craft skipped (busy): %s" % recipe_id)
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_craft_request_time_ms < CRAFT_CLICK_COOLDOWN_MS:
		_debug_log("Craft skipped (cooldown): %s" % recipe_id)
		return
	_last_craft_request_time_ms = now_ms
	_craft_in_progress = true
	_suspend_inventory_refresh = true
	_pending_inventory_refresh = false
	_debug_log("Craft requested: %s" % recipe_id)
	if _inventory_system != null and _inventory_system.has_method("get_item_count"):
		var dbg_wood: int = int(_inventory_system.call("get_item_count", "wood"))
		var dbg_stone: int = int(_inventory_system.call("get_item_count", "stone"))
		var dbg_stick: int = int(_inventory_system.call("get_item_count", "stick"))
		_debug_log("Resources before craft (%s): wood=%d stone=%d stick=%d" % [recipe_id, dbg_wood, dbg_stone, dbg_stick])
	var crafted: bool = _craft_via_inventory_system(recipe_id)
	if not crafted:
		crafted = _craft_via_crafting_system(recipe_id)
	if not crafted:
		crafted = _manual_craft_via_inventory(recipe_id)
	if not crafted and ENABLE_SLOT_CRAFT_FALLBACK:
		crafted = _hard_craft_via_slots(recipe_id)
	_debug_log("Craft result for %s: %s" % [recipe_id, str(crafted)])
	if crafted:
		var crafted_text: String = "Crafted %s" % _get_item_label(recipe_id)
		_set_craft_status(crafted_text)
		_push_crafting_notification(crafted_text)
	else:
		var has_resources: bool = _can_craft_recipe(recipe_id)
		var fail_text: String = "Inventory full" if has_resources else "Not enough resources"
		_set_craft_status(fail_text)
		_push_crafting_notification(fail_text)
	_craft_in_progress = false
	_suspend_inventory_refresh = false
	if _pending_inventory_refresh:
		_pending_inventory_refresh = false
	update_ui()

func _debug_log(message: String) -> void:
	if not ENABLE_INVENTORY_UI_DEBUG_LOGS:
		return
	print("[InventoryUI] %s" % message)

func _craft_via_inventory_system(recipe_id: String) -> bool:
	if _inventory_system == null:
		return false
	if not _inventory_system.has_method("craft"):
		return false
	var recipe: Dictionary = _inline_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if _inventory_system.has_method("can_craft"):
		var can_craft_variant: Variant = _inventory_system.call("can_craft", recipe)
		if not bool(can_craft_variant):
			return false
	var crafted_variant: Variant = _inventory_system.call("craft", recipe)
	return bool(crafted_variant)

func _craft_via_crafting_system(recipe_id: String) -> bool:
	if _crafting_system == null:
		return false
	if _crafting_system.has_method("set_inventory_system") and _inventory_system != null:
		_crafting_system.call("set_inventory_system", _inventory_system)
	if _crafting_system.has_method("craft_item"):
		var crafted_item_variant: Variant = _crafting_system.call("craft_item", recipe_id, _inventory_system)
		if bool(crafted_item_variant):
			return true
	if _crafting_system.has_method("craft"):
		var crafted_variant: Variant = _crafting_system.call("craft", recipe_id, _inventory_system)
		return bool(crafted_variant)
	return false

func _manual_craft_via_inventory(recipe_id: String) -> bool:
	if _inventory_system == null:
		return false
	if not _inventory_system.has_method("get_item_count"):
		return false
	if not _inventory_system.has_method("remove_item"):
		return false
	if not _inventory_system.has_method("add_item"):
		return false
	var recipe: Dictionary = _inline_recipe(recipe_id)
	if recipe.is_empty():
		return false
	var requires_variant: Variant = recipe.get("requires", {})
	var output_variant: Variant = recipe.get("output", {})
	if not (requires_variant is Dictionary):
		return false
	if not (output_variant is Dictionary):
		return false
	var requires: Dictionary = Dictionary(requires_variant)
	var output: Dictionary = Dictionary(output_variant)
	for item_id_variant in requires.keys():
		var item_id: String = String(item_id_variant).strip_edges().to_lower()
		var need_amount: int = int(requires[item_id_variant])
		if item_id.is_empty() or need_amount <= 0:
			continue
		var count_variant: Variant = _inventory_system.call("get_item_count", item_id)
		if int(count_variant) < need_amount:
			return false
	var removed_entries: Array[Dictionary] = []
	for item_id_variant in requires.keys():
		var item_id: String = String(item_id_variant).strip_edges().to_lower()
		var need_amount: int = int(requires[item_id_variant])
		if item_id.is_empty() or need_amount <= 0:
			continue
		var removed_variant: Variant = _inventory_system.call("remove_item", item_id, need_amount)
		var removed: bool = bool(removed_variant)
		if not removed:
			for rollback_entry in removed_entries:
				var rollback_id: String = String(rollback_entry.get("id", ""))
				var rollback_amount: int = int(rollback_entry.get("amount", 0))
				if rollback_id.is_empty() or rollback_amount <= 0:
					continue
				_inventory_system.call("add_item", rollback_id, rollback_amount)
			return false
		removed_entries.append({
			"id": item_id,
			"amount": need_amount
		})
	var output_id: String = String(output.get("item_id", "")).strip_edges().to_lower()
	var output_amount: int = int(output.get("amount", 0))
	if output_id.is_empty() or output_amount <= 0:
		return false
	var added_variant: Variant = _inventory_system.call("add_item", output_id, output_amount)
	var added: bool = bool(added_variant)
	if added:
		return true
	for rollback_entry in removed_entries:
		var rollback_id: String = String(rollback_entry.get("id", ""))
		var rollback_amount: int = int(rollback_entry.get("amount", 0))
		if rollback_id.is_empty() or rollback_amount <= 0:
			continue
		_inventory_system.call("add_item", rollback_id, rollback_amount)
	return false

func _hard_craft_via_slots(recipe_id: String) -> bool:
	if _inventory_system == null:
		return false
	if not _inventory_system.has_method("get_item_count"):
		return false
	if not _inventory_system.has_method("get_slot"):
		return false
	if not _inventory_system.has_method("set_slot"):
		return false
	if not _inventory_system.has_method("add_item"):
		return false
	var recipe: Dictionary = _inline_recipe(recipe_id)
	if recipe.is_empty():
		return false
	var requires_variant: Variant = recipe.get("requires", {})
	var output_variant: Variant = recipe.get("output", {})
	if not (requires_variant is Dictionary) or not (output_variant is Dictionary):
		return false
	var requires: Dictionary = Dictionary(requires_variant)
	var output: Dictionary = Dictionary(output_variant)
	for item_id_variant in requires.keys():
		var item_id: String = String(item_id_variant).strip_edges().to_lower()
		var need_amount: int = int(requires[item_id_variant])
		if item_id.is_empty() or need_amount <= 0:
			continue
		var count_variant: Variant = _inventory_system.call("get_item_count", item_id)
		if int(count_variant) < need_amount:
			return false
	var snapshot: Array[Dictionary] = []
	for slot_index in range(TOTAL_SLOTS):
		var snapshot_slot_variant: Variant = _inventory_system.call("get_slot", slot_index)
		if snapshot_slot_variant is Dictionary:
			snapshot.append(Dictionary(snapshot_slot_variant).duplicate(true))
		else:
			snapshot.append({})
	for item_id_variant in requires.keys():
		var remaining: int = int(requires[item_id_variant])
		var consume_id: String = String(item_id_variant).strip_edges().to_lower()
		if consume_id.is_empty() or remaining <= 0:
			continue
		for slot_index in range(TOTAL_SLOTS):
			if remaining <= 0:
				break
			var slot_variant: Variant = _inventory_system.call("get_slot", slot_index)
			if not (slot_variant is Dictionary):
				continue
			var slot_dict: Dictionary = Dictionary(slot_variant)
			var slot_item_id: String = String(slot_dict.get("id", slot_dict.get("item_id", ""))).strip_edges().to_lower()
			if slot_item_id != consume_id:
				continue
			var slot_amount: int = int(slot_dict.get("amount", 0))
			if slot_amount <= 0:
				continue
			var consume_amount: int = mini(slot_amount, remaining)
			var next_amount: int = slot_amount - consume_amount
			remaining -= consume_amount
			if next_amount <= 0:
				_inventory_system.call("set_slot", slot_index, {})
			else:
				_inventory_system.call("set_slot", slot_index, {
					"id": slot_item_id,
					"item_id": slot_item_id,
					"amount": next_amount
				})
		if remaining > 0:
			for restore_index in range(mini(snapshot.size(), TOTAL_SLOTS)):
				_inventory_system.call("set_slot", restore_index, snapshot[restore_index])
			return false
	var output_id: String = String(output.get("item_id", "")).strip_edges().to_lower()
	var output_amount: int = int(output.get("amount", 0))
	if output_id.is_empty() or output_amount <= 0:
		for restore_index in range(mini(snapshot.size(), TOTAL_SLOTS)):
			_inventory_system.call("set_slot", restore_index, snapshot[restore_index])
		return false
	var add_variant: Variant = _inventory_system.call("add_item", output_id, output_amount)
	if bool(add_variant):
		return true
	for restore_index in range(mini(snapshot.size(), TOTAL_SLOTS)):
		_inventory_system.call("set_slot", restore_index, snapshot[restore_index])
	return false

func _inline_recipe(recipe_id: String) -> Dictionary:
	var normalized_id: String = recipe_id.strip_edges().to_lower()
	if normalized_id == "axe":
		return {
			"requires": {
				"stone": 3,
				"wood": 2
			},
			"output": {
				"item_id": "axe",
				"amount": 1
			}
		}
	if normalized_id == "pickaxe":
		return {
			"requires": {
				"stone": 3,
				"wood": 2
			},
			"output": {
				"item_id": "pickaxe",
				"amount": 1
			}
		}
	return {}

func _get_slot_item_by_ref(slot_kind: String, slot_index: int, equipment_type: String) -> Dictionary:
	if _is_inventory_slot_kind(slot_kind):
		return _get_inventory_slot_data(slot_index)
	if slot_kind == "equipment" and _equipment_items.has(equipment_type):
		var item_variant: Variant = _equipment_items[equipment_type]
		if item_variant is Dictionary:
			return Dictionary(item_variant).duplicate(true)
	return {}

func _set_slot_item_by_ref(slot_kind: String, slot_index: int, equipment_type: String, item: Dictionary) -> void:
	if _is_inventory_slot_kind(slot_kind):
		_set_inventory_slot_data(slot_index, item)
		return
	if slot_kind == "equipment":
		_equipment_items[equipment_type] = item.duplicate(true)
		_save_equipment_state()

func _get_inventory_slot_data(slot_index: int) -> Dictionary:
	if slot_index < 0:
		return {}
	if _inventory_system != null and _inventory_system.has_method("get_slot"):
		var slot_variant: Variant = _inventory_system.call("get_slot", slot_index)
		if slot_variant is Dictionary:
			return _normalize_slot_dict(Dictionary(slot_variant))
	return {}

func _set_inventory_slot_data(slot_index: int, item: Dictionary) -> void:
	if slot_index < 0:
		return
	if _inventory_system == null or not _inventory_system.has_method("set_slot"):
		return
	var normalized: Dictionary = _normalize_slot_dict(item)
	_inventory_system.call("set_slot", slot_index, normalized)

func _normalize_slot_dict(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}
	var item_id: String = String(item.get("id", item.get("item_id", ""))).strip_edges().to_lower()
	var amount: int = int(item.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return {}
	return {
		"id": item_id,
		"item_id": item_id,
		"amount": amount
	}

func _is_inventory_slot_kind(slot_kind: String) -> bool:
	return slot_kind == "inventory" or slot_kind == "hotbar"

func quick_move_slot(slot_kind: String, slot_index: int, equipment_type: String = "") -> bool:
	if not _is_inventory_slot_kind(slot_kind):
		return false
	if _inventory_system == null:
		return false
	if not _inventory_system.has_method("swap_slots"):
		return false
	var item: Dictionary = _get_slot_item_by_ref(slot_kind, slot_index, equipment_type)
	if item.is_empty():
		return false
	var target_range_from: int = HOTBAR_SLOT_COUNT
	var target_range_to: int = TOTAL_SLOTS - 1
	if slot_kind == "inventory":
		target_range_from = 0
		target_range_to = HOTBAR_SLOT_COUNT - 1
	var target_index: int = _find_first_empty_slot_in_range(target_range_from, target_range_to)
	if target_index < 0:
		return false
	var swapped_variant: Variant = _inventory_system.call("swap_slots", slot_index, target_index)
	var swapped: bool = bool(swapped_variant)
	if swapped:
		update_ui()
	return swapped

func _find_first_empty_slot_in_range(from_index: int, to_index: int) -> int:
	for index in range(from_index, to_index + 1):
		var slot_item: Dictionary = _get_inventory_slot_data(index)
		if slot_item.is_empty():
			return index
	return -1

func _can_slot_ref_accept_item(slot_kind: String, slot_equipment_type: String, item: Dictionary) -> bool:
	if slot_kind != "equipment":
		return true
	return _item_matches_equipment_slot(item, slot_equipment_type)

func _item_matches_equipment_slot(item: Dictionary, equipment_type: String) -> bool:
	var item_id: String = String(item.get("id", item.get("item_id", ""))).to_lower()
	if item_id.is_empty():
		return false
	var item_definition: Dictionary = {}
	if _inventory_system != null and _inventory_system.has_method("get_item_definition"):
		var definition_variant: Variant = _inventory_system.call("get_item_definition", item_id)
		if definition_variant is Dictionary:
			item_definition = Dictionary(definition_variant)
	var item_type: String = String(item_definition.get("item_type", "")).to_lower()
	if equipment_type == "weapon":
		if item_type == "tool" or item_type == "weapon":
			return true
		return item_id.find("axe") >= 0 or item_id.find("sword") >= 0
	return item_id.find(equipment_type) >= 0

func _get_item_label(item_id: String) -> String:
	if _inventory_system != null and _inventory_system.has_method("get_item_label"):
		var label_variant: Variant = _inventory_system.call("get_item_label", item_id)
		var label: String = String(label_variant)
		if not label.is_empty():
			return label
	return item_id.capitalize()

func _get_item_color(item_id: String) -> Color:
	if _inventory_system != null and _inventory_system.has_method("get_item_ui_color"):
		var color_variant: Variant = _inventory_system.call("get_item_ui_color", item_id)
		if color_variant is Color:
			return color_variant
	return Color(0.67, 0.67, 0.67, 1.0)

func _resolve_runtime_system_refs() -> void:
	if _inventory_system == null:
		var inventory_node: Node = _find_system_node_by_name("InventorySystem")
		if inventory_node != null:
			set_inventory_system(inventory_node)
	if _crafting_system == null:
		var crafting_node: Node = _find_system_node_by_name("CraftingSystem")
		if crafting_node != null:
			set_crafting_system(crafting_node)
	if _crafting_system != null and _inventory_system != null and _crafting_system.has_method("set_inventory_system"):
		_crafting_system.call("set_inventory_system", _inventory_system)
	_try_bind_inventory_component()

func _find_system_node_by_name(node_name: String) -> Node:
	var tree_ref: SceneTree = get_tree()
	if tree_ref == null:
		return null
	if tree_ref.current_scene != null:
		var from_scene: Node = tree_ref.current_scene.find_child(node_name, true, false)
		if from_scene != null:
			return from_scene
	var root_node: Node = tree_ref.root
	if root_node != null:
		return root_node.find_child(node_name, true, false)
	return null

func _resolve_inventory_component_from_player() -> void:
	_inventory_component = null
	if _bound_player == null:
		return
	var inventory_node: Node = _bound_player.get_node_or_null("InventoryComponent")
	_inventory_component = inventory_node as InventoryComponent
	if _inventory_component == null and _bound_player.has_method("get_inventory_component"):
		var inventory_variant: Variant = _bound_player.call("get_inventory_component")
		_inventory_component = inventory_variant as InventoryComponent

func _try_bind_inventory_component() -> void:
	if _inventory_system == null or _inventory_component == null:
		return
	if _inventory_system.has_method("bind_inventory"):
		_inventory_system.call("bind_inventory", _inventory_component)

func _load_equipment_state() -> void:
	if _inventory_component == null:
		return
	if not _inventory_component.has_meta("ui_equipment_items"):
		return
	var equipment_variant: Variant = _inventory_component.get_meta("ui_equipment_items")
	if not (equipment_variant is Dictionary):
		return
	var equipment_dict: Dictionary = Dictionary(equipment_variant)
	for equipment_type in EQUIPMENT_TYPES:
		var entry_variant: Variant = equipment_dict.get(equipment_type, {})
		if entry_variant is Dictionary:
			_equipment_items[equipment_type] = Dictionary(entry_variant).duplicate(true)

func _save_equipment_state() -> void:
	if _inventory_component == null:
		return
	_inventory_component.set_meta("ui_equipment_items", _equipment_items.duplicate(true))

func _on_inventory_system_changed(_inventory_component_node: Node) -> void:
	if _suspend_inventory_refresh:
		_pending_inventory_refresh = true
		return
	update_ui()

func _set_craft_status(text: String) -> void:
	if _craft_status_label != null:
		_craft_status_label.text = text

func _push_crafting_notification(text: String) -> void:
	if text.is_empty():
		return
	var ui_system: Node = get_tree().get_first_node_in_group("ui_system")
	if ui_system != null and ui_system.has_method("show_crafting_notification"):
		ui_system.call("show_crafting_notification", text)

func _refresh_resource_summary() -> void:
	if _resource_summary_label == null:
		return
	if _inventory_system == null or not _inventory_system.has_method("get_item_count"):
		_resource_summary_label.text = "Resources: Wood 0, Stone 0, Stick 0"
		return
	var wood_variant: Variant = _inventory_system.call("get_item_count", "wood")
	var stone_variant: Variant = _inventory_system.call("get_item_count", "stone")
	var stick_variant: Variant = _inventory_system.call("get_item_count", "stick")
	var wood_count: int = maxi(int(wood_variant), 0)
	var stone_count: int = maxi(int(stone_variant), 0)
	var stick_count: int = maxi(int(stick_variant), 0)
	_resource_summary_label.text = "Resources: Wood %d, Stone %d, Stick %d" % [wood_count, stone_count, stick_count]

func _refresh_craft_buttons_state() -> void:
	var axe_ready: bool = _can_craft_recipe("axe")
	var pickaxe_ready: bool = _can_craft_recipe("pickaxe")
	if _craft_axe_button != null:
		var axe_state: String = "READY" if axe_ready else "MISSING"
		_craft_axe_button.text = "Craft Axe (3 Stone, 2 Wood) [%s]" % [axe_state]
	if _craft_pickaxe_button != null:
		var pickaxe_state: String = "READY" if pickaxe_ready else "MISSING"
		_craft_pickaxe_button.text = "Craft Pickaxe (3 Stone, 2 Wood) [%s]" % [pickaxe_state]
	_apply_craft_button_state(_craft_axe_button, axe_ready)
	_apply_craft_button_state(_craft_pickaxe_button, pickaxe_ready)

func _can_craft_recipe(recipe_id: String) -> bool:
	var recipe: Dictionary = _inline_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if _inventory_system != null and _inventory_system.has_method("can_craft"):
		var can_craft_variant: Variant = _inventory_system.call("can_craft", recipe)
		return bool(can_craft_variant)
	var requires_variant: Variant = recipe.get("requires", {})
	if not (requires_variant is Dictionary):
		return false
	if _inventory_system == null or not _inventory_system.has_method("get_item_count"):
		return false
	var requires: Dictionary = Dictionary(requires_variant)
	for item_id_variant in requires.keys():
		var item_id: String = String(item_id_variant).strip_edges().to_lower()
		var required_amount: int = int(requires[item_id_variant])
		if item_id.is_empty() or required_amount <= 0:
			continue
		var count_variant: Variant = _inventory_system.call("get_item_count", item_id)
		if int(count_variant) < required_amount:
			return false
	return true

func _apply_craft_button_state(button: Button, can_craft: bool) -> void:
	if button == null:
		return
	button.disabled = false
	button.modulate = Color(1.0, 1.0, 1.0, 1.0)
	var normal_style: StyleBoxFlat = StyleBoxFlat.new()
	var hover_style: StyleBoxFlat = StyleBoxFlat.new()
	var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
	if can_craft:
		normal_style.bg_color = Color(0.1, 0.4, 0.2, 0.98)
		normal_style.border_color = Color(0.45, 0.98, 0.58, 1.0)
		hover_style.bg_color = Color(0.14, 0.5, 0.26, 1.0)
		hover_style.border_color = Color(0.62, 1.0, 0.74, 1.0)
		pressed_style.bg_color = Color(0.08, 0.32, 0.17, 1.0)
		pressed_style.border_color = Color(0.35, 0.88, 0.5, 1.0)
	else:
		normal_style.bg_color = Color(0.3, 0.12, 0.12, 0.94)
		normal_style.border_color = Color(0.72, 0.3, 0.3, 0.96)
		hover_style.bg_color = Color(0.35, 0.14, 0.14, 0.97)
		hover_style.border_color = Color(0.82, 0.36, 0.36, 1.0)
		pressed_style.bg_color = Color(0.24, 0.1, 0.1, 1.0)
		pressed_style.border_color = Color(0.62, 0.26, 0.26, 1.0)
	for style_box in [normal_style, hover_style, pressed_style]:
		style_box.set_border_width_all(1)
		style_box.corner_radius_top_left = 4
		style_box.corner_radius_top_right = 4
		style_box.corner_radius_bottom_left = 4
		style_box.corner_radius_bottom_right = 4
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)

func _ensure_input_actions() -> void:
	_ensure_key_action(INVENTORY_TOGGLE_ACTION, KEY_TAB)
	_ensure_key_action(CRAFTING_TOGGLE_ACTION, KEY_I)
	_ensure_key_action(DROP_ONE_ACTION, KEY_Q)

func _ensure_key_action(action_name: StringName, key_code: int) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event_variant in InputMap.action_get_events(action_name):
		var key_event: InputEventKey = event_variant as InputEventKey
		if key_event != null and key_event.physical_keycode == key_code:
			return
	var new_event: InputEventKey = InputEventKey.new()
	new_event.physical_keycode = key_code
	InputMap.action_add_event(action_name, new_event)

func _connect_player_hotbar_signal() -> void:
	if _bound_player == null:
		return
	var callback: Callable = Callable(self, "_on_player_hotbar_slot_selected")
	if _bound_player.has_signal("hotbar_slot_selected") and not _bound_player.is_connected("hotbar_slot_selected", callback):
		_bound_player.connect("hotbar_slot_selected", callback)

func _disconnect_player_hotbar_signal() -> void:
	if _bound_player == null:
		return
	var callback: Callable = Callable(self, "_on_player_hotbar_slot_selected")
	if _bound_player.has_signal("hotbar_slot_selected") and _bound_player.is_connected("hotbar_slot_selected", callback):
		_bound_player.disconnect("hotbar_slot_selected", callback)

func _sync_selected_hotbar_index() -> void:
	if _bound_player == null:
		return
	if _bound_player.has_method("get_selected_hotbar_index"):
		var selected_variant: Variant = _bound_player.call("get_selected_hotbar_index")
		_selected_hotbar_index = clampi(int(selected_variant), 0, HOTBAR_SLOT_COUNT - 1)

func _on_player_hotbar_slot_selected(slot_index: int) -> void:
	_selected_hotbar_index = clampi(slot_index, 0, HOTBAR_SLOT_COUNT - 1)
	_refresh_all_slots()
