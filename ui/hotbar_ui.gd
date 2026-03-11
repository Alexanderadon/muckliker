extends Control
class_name HotbarUI

const HOTBAR_SLOT_COUNT: int = 8
const SLOT_SIZE: Vector2 = Vector2(70.0, 70.0)

var _slot_scene: PackedScene = preload("res://ui/inventory_slot.tscn")

var _bound_player: Node = null
var _inventory_component: InventoryComponent = null
var _inventory_system: Node = null
var _inventory_ui_ref: Control = null

var _slots: Array[Control] = []
var _items: Array[Dictionary] = []
var _selected_index: int = 0

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS
	_initialize_items()
	_build_layout()
	_refresh_slots()

func _process(_delta: float) -> void:
	if _inventory_ui_ref != null and is_instance_valid(_inventory_ui_ref):
		return
	_resolve_inventory_ui_ref()
	_configure_slot_drag_sources()

func bind(player: Node, inventory_system: Node = null) -> void:
	_disconnect_player_signal()
	_bound_player = player
	set_inventory_system(inventory_system)
	_resolve_inventory_component()
	_connect_inventory_component()
	_connect_player_signal()
	_pull_items()
	_sync_selected_slot()
	_refresh_slots()

func set_inventory_system(inventory_system: Node) -> void:
	if _inventory_system == inventory_system:
		return
	var callback: Callable = Callable(self, "_on_inventory_system_changed")
	if _inventory_system != null and _inventory_system.has_signal("inventory_changed") and _inventory_system.is_connected("inventory_changed", callback):
		_inventory_system.disconnect("inventory_changed", callback)
	_inventory_system = inventory_system
	if _inventory_system != null and _inventory_system.has_signal("inventory_changed") and not _inventory_system.is_connected("inventory_changed", callback):
		_inventory_system.connect("inventory_changed", callback)
	_configure_slot_drag_sources()

func _initialize_items() -> void:
	_items.clear()
	for _i in range(HOTBAR_SLOT_COUNT):
		_items.append({})

func _build_layout() -> void:
	for child in get_children():
		child.queue_free()

	var screen_margin: MarginContainer = MarginContainer.new()
	screen_margin.anchor_right = 1.0
	screen_margin.anchor_bottom = 1.0
	screen_margin.add_theme_constant_override("margin_left", 24)
	screen_margin.add_theme_constant_override("margin_top", 24)
	screen_margin.add_theme_constant_override("margin_right", 24)
	screen_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(screen_margin)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_END
	screen_margin.add_child(vbox)

	var centered_row: HBoxContainer = HBoxContainer.new()
	centered_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(centered_row)

	var panel: PanelContainer = PanelContainer.new()
	centered_row.add_child(panel)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.08, 0.88)
	style.border_color = Color(0.24, 0.24, 0.28, 0.95)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)

	var panel_margin: MarginContainer = MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 8)
	panel_margin.add_theme_constant_override("margin_top", 8)
	panel_margin.add_theme_constant_override("margin_right", 8)
	panel_margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(panel_margin)

	var hotbar_grid: GridContainer = GridContainer.new()
	hotbar_grid.columns = HOTBAR_SLOT_COUNT
	hotbar_grid.add_theme_constant_override("h_separation", 6)
	panel_margin.add_child(hotbar_grid)

	_slots.clear()
	for slot_index in range(HOTBAR_SLOT_COUNT):
		var slot: Control = _create_slot(slot_index)
		hotbar_grid.add_child(slot)
		_slots.append(slot)
	_configure_slot_drag_sources()

func _create_slot(slot_index: int) -> Control:
	var slot: Control = null
	if _slot_scene != null:
		var slot_variant: Variant = _slot_scene.instantiate()
		slot = slot_variant as Control
	if slot == null:
		slot = PanelContainer.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.set_meta("slot_index", slot_index)
	_apply_slot_style(slot, false)
	_ensure_slot_visual_children(slot)
	return slot

func _apply_slot_style(slot: Control, is_selected: bool) -> void:
	if not (slot is PanelContainer):
		return
	var panel: PanelContainer = slot as PanelContainer
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.11, 0.14, 0.95)
	if is_selected:
		style.border_color = Color(0.94, 0.79, 0.25, 1.0)
		style.set_border_width_all(2)
	else:
		style.border_color = Color(0.34, 0.34, 0.42, 0.95)
		style.set_border_width_all(1)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)

func _ensure_slot_visual_children(slot: Control) -> void:
	var icon: ColorRect = slot.get_node_or_null("Icon") as ColorRect
	if icon == null:
		icon = ColorRect.new()
		icon.name = "Icon"
		icon.position = Vector2(10.0, 8.0)
		icon.size = Vector2(50.0, 30.0)
		icon.color = Color(0.25, 0.25, 0.25, 1.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

	var name_label: Label = slot.get_node_or_null("NameLabel") as Label
	if name_label == null:
		name_label = Label.new()
		name_label.name = "NameLabel"
		name_label.position = Vector2(5.0, 40.0)
		name_label.size = Vector2(60.0, 18.0)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(name_label)

	var amount_label: Label = slot.get_node_or_null("AmountLabel") as Label
	if amount_label == null:
		amount_label = Label.new()
		amount_label.name = "AmountLabel"
		amount_label.position = Vector2(40.0, 52.0)
		amount_label.size = Vector2(26.0, 16.0)
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount_label.add_theme_font_size_override("font_size", 11)
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(amount_label)

func _resolve_inventory_component() -> void:
	_inventory_component = null
	if _bound_player == null:
		return
	var inventory_node: Node = _bound_player.get_node_or_null("InventoryComponent")
	_inventory_component = inventory_node as InventoryComponent
	if _inventory_component == null and _bound_player.has_method("get_inventory_component"):
		var inventory_variant: Variant = _bound_player.call("get_inventory_component")
		_inventory_component = inventory_variant as InventoryComponent

func _connect_inventory_component() -> void:
	if _inventory_component == null:
		return
	var callback: Callable = Callable(self, "_on_inventory_component_changed")
	if _inventory_component.inventory_changed.is_connected(callback):
		return
	_inventory_component.inventory_changed.connect(callback)
	_configure_slot_drag_sources()

func _connect_player_signal() -> void:
	if _bound_player == null:
		return
	var callback: Callable = Callable(self, "_on_hotbar_slot_selected")
	if _bound_player.has_signal("hotbar_slot_selected") and not _bound_player.is_connected("hotbar_slot_selected", callback):
		_bound_player.connect("hotbar_slot_selected", callback)

func _disconnect_player_signal() -> void:
	if _bound_player == null:
		return
	var callback: Callable = Callable(self, "_on_hotbar_slot_selected")
	if _bound_player.has_signal("hotbar_slot_selected") and _bound_player.is_connected("hotbar_slot_selected", callback):
		_bound_player.disconnect("hotbar_slot_selected", callback)

func _sync_selected_slot() -> void:
	if _bound_player != null and _bound_player.has_method("get_selected_hotbar_index"):
		var index_variant: Variant = _bound_player.call("get_selected_hotbar_index")
		_selected_index = clampi(int(index_variant), 0, HOTBAR_SLOT_COUNT - 1)

func _pull_items() -> void:
	_initialize_items()
	if _inventory_system != null and _inventory_system.has_method("get_slot"):
		for i in range(HOTBAR_SLOT_COUNT):
			var slot_variant: Variant = _inventory_system.call("get_slot", i)
			if slot_variant is Dictionary:
				var slot_dict: Dictionary = Dictionary(slot_variant)
				if not slot_dict.is_empty():
					var normalized: Dictionary = {
						"item_id": String(slot_dict.get("id", slot_dict.get("item_id", ""))),
						"amount": int(slot_dict.get("amount", 0))
					}
					if int(normalized.get("amount", 0)) > 0 and not String(normalized.get("item_id", "")).is_empty():
						var metadata_variant: Variant = slot_dict.get("metadata", {})
						if metadata_variant is Dictionary and not Dictionary(metadata_variant).is_empty():
							normalized["metadata"] = Dictionary(metadata_variant).duplicate(true)
						_items[i] = normalized
		_configure_slot_drag_sources()
		return
	if _inventory_component != null:
		var source_items: Array[Dictionary] = _inventory_component.items
		var copy_count: int = mini(source_items.size(), HOTBAR_SLOT_COUNT)
		for i in range(copy_count):
			_items[i] = source_items[i].duplicate(true)
	_configure_slot_drag_sources()

func _refresh_slots() -> void:
	for i in range(mini(_slots.size(), HOTBAR_SLOT_COUNT)):
		var slot: Control = _slots[i]
		_apply_slot_style(slot, i == _selected_index)
		_refresh_slot(slot, _items[i], i)

func _refresh_slot(slot: Control, entry: Dictionary, slot_index: int) -> void:
	var icon: ColorRect = slot.get_node_or_null("Icon") as ColorRect
	var name_label: Label = slot.get_node_or_null("NameLabel") as Label
	var amount_label: Label = slot.get_node_or_null("AmountLabel") as Label
	if icon == null or name_label == null or amount_label == null:
		return
	if entry.is_empty():
		icon.color = Color(0.2, 0.2, 0.24, 1.0)
		name_label.text = str(slot_index + 1)
		amount_label.text = ""
		return
	var item_id: String = String(entry.get("item_id", ""))
	var amount: int = int(entry.get("amount", 1))
	icon.color = _get_item_color(item_id)
	name_label.text = _get_item_label(item_id)
	amount_label.text = "x%d" % [amount] if amount > 1 else ""

func _get_item_label(item_id: String) -> String:
	if _inventory_system != null and _inventory_system.has_method("get_item_label"):
		var label_variant: Variant = _inventory_system.call("get_item_label", item_id)
		return String(label_variant)
	return item_id.capitalize()

func _get_item_color(item_id: String) -> Color:
	if _inventory_system != null and _inventory_system.has_method("get_item_ui_color"):
		var color_variant: Variant = _inventory_system.call("get_item_ui_color", item_id)
		if color_variant is Color:
			return color_variant
	return Color(0.7, 0.7, 0.7, 1.0)

func _on_inventory_component_changed(_items_changed: Array) -> void:
	_pull_items()
	_refresh_slots()

func _on_inventory_system_changed(inventory_component: Node) -> void:
	if _inventory_component != null and inventory_component != null and inventory_component != _inventory_component:
		return
	_pull_items()
	_refresh_slots()

func _on_hotbar_slot_selected(slot_index: int) -> void:
	_selected_index = clampi(slot_index, 0, HOTBAR_SLOT_COUNT - 1)
	_refresh_slots()

func _resolve_inventory_ui_ref() -> void:
	if _inventory_ui_ref != null and is_instance_valid(_inventory_ui_ref):
		return
	_inventory_ui_ref = get_tree().get_first_node_in_group("inventory_ui") as Control

func _configure_slot_drag_sources() -> void:
	_resolve_inventory_ui_ref()
	for slot_variant in _slots:
		var slot: InventorySlotUI = slot_variant as InventorySlotUI
		if slot == null or not is_instance_valid(slot):
			continue
		var slot_idx: int = int(slot.get_meta("slot_index", -1))
		slot.configure_slot("hotbar", slot_idx, _inventory_system, _inventory_ui_ref, "")
		if not slot.swap_requested.is_connected(_on_slot_swap):
			slot.swap_requested.connect(_on_slot_swap)

func _on_slot_swap(_from_index: int, _to_index: int) -> void:
	_pull_items()
	_refresh_slots()
