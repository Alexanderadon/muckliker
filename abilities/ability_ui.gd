extends Control
class_name AbilityUI

const ICON_SIZE: Vector2 = Vector2(40.0, 40.0)
const ENTRY_MIN_SIZE: Vector2 = Vector2(280.0, 52.0)
const POP_SCALE: float = 1.05
const POP_DURATION: float = 0.12
const CENTER_SHOW_TIME: float = 1.1

var _bound_player: Node = null
var _ability_manager: AbilityManager = null
var _container: VBoxContainer = null
var _entry_by_id: Dictionary = {}

var _center_popup: PanelContainer = null
var _center_icon_panel: PanelContainer = null
var _center_icon_label: Label = null
var _center_name_label: Label = null
var _center_rarity_label: Label = null
var _center_tween: Tween = null
var _ignore_next_changed_event: bool = false

func _ready() -> void:
	name = "AbilityUI"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = 0.0
	_ensure_container()
	_ensure_center_popup()

func bind(player: Node) -> void:
	_bound_player = player
	_disconnect_manager()
	_ability_manager = _resolve_ability_manager(player)
	_connect_manager()
	_rebuild_from_manager()

func _ensure_container() -> void:
	if _container != null and is_instance_valid(_container):
		return
	_container = VBoxContainer.new()
	_container.name = "AbilityEntryStack"
	_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_container.anchor_left = 0.0
	_container.anchor_right = 0.0
	_container.anchor_top = 0.5
	_container.anchor_bottom = 0.5
	_container.offset_left = 14.0
	_container.offset_right = 324.0
	_container.offset_top = -220.0
	_container.offset_bottom = 220.0
	_container.add_theme_constant_override("separation", 8)
	add_child(_container)

func _ensure_center_popup() -> void:
	if _center_popup != null and is_instance_valid(_center_popup):
		return
	_center_popup = PanelContainer.new()
	_center_popup.name = "AbilityPickupPopup"
	_center_popup.anchor_left = 0.5
	_center_popup.anchor_right = 0.5
	_center_popup.anchor_top = 0.5
	_center_popup.anchor_bottom = 0.5
	_center_popup.offset_left = -170.0
	_center_popup.offset_right = 170.0
	_center_popup.offset_top = -74.0
	_center_popup.offset_bottom = -18.0
	_center_popup.visible = false
	_center_popup.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var popup_style: StyleBoxFlat = StyleBoxFlat.new()
	popup_style.bg_color = Color(0.04, 0.04, 0.06, 0.9)
	popup_style.border_color = Color(0.75, 0.75, 0.8, 0.35)
	popup_style.corner_radius_top_left = 8
	popup_style.corner_radius_top_right = 8
	popup_style.corner_radius_bottom_left = 8
	popup_style.corner_radius_bottom_right = 8
	popup_style.set_border_width_all(1)
	_center_popup.add_theme_stylebox_override("panel", popup_style)
	add_child(_center_popup)

	var root_row: HBoxContainer = HBoxContainer.new()
	root_row.add_theme_constant_override("separation", 10)
	_center_popup.add_child(root_row)

	_center_icon_panel = _build_icon_panel("?")
	root_row.add_child(_center_icon_panel)
	_center_icon_label = _center_icon_panel.get_node_or_null("IconLabel") as Label

	var text_column: VBoxContainer = VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 2)
	root_row.add_child(text_column)

	_center_name_label = Label.new()
	_center_name_label.text = "Ability"
	_center_name_label.add_theme_font_size_override("font_size", 16)
	_center_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	text_column.add_child(_center_name_label)

	_center_rarity_label = Label.new()
	_center_rarity_label.text = "COMMON"
	_center_rarity_label.add_theme_font_size_override("font_size", 12)
	text_column.add_child(_center_rarity_label)

func _resolve_ability_manager(player: Node) -> AbilityManager:
	if player == null:
		return null
	if player.has_method("get_ability_manager"):
		var manager_variant: Variant = player.call("get_ability_manager")
		var manager: AbilityManager = manager_variant as AbilityManager
		if manager != null:
			return manager
	var by_name: Node = player.get_node_or_null("AbilityManager")
	return by_name as AbilityManager

func _connect_manager() -> void:
	if _ability_manager == null:
		return
	var collected_callback: Callable = Callable(self, "_on_ability_collected")
	if not _ability_manager.ability_collected.is_connected(collected_callback):
		_ability_manager.ability_collected.connect(collected_callback)
	var changed_callback: Callable = Callable(self, "_on_abilities_changed")
	if not _ability_manager.abilities_changed.is_connected(changed_callback):
		_ability_manager.abilities_changed.connect(changed_callback)

func _disconnect_manager() -> void:
	if _ability_manager == null:
		return
	var collected_callback: Callable = Callable(self, "_on_ability_collected")
	if _ability_manager.ability_collected.is_connected(collected_callback):
		_ability_manager.ability_collected.disconnect(collected_callback)
	var changed_callback: Callable = Callable(self, "_on_abilities_changed")
	if _ability_manager.abilities_changed.is_connected(changed_callback):
		_ability_manager.abilities_changed.disconnect(changed_callback)

func _on_ability_collected(ability_id: StringName) -> void:
	_ignore_next_changed_event = true
	_rebuild_from_manager()
	var ability_key: String = String(ability_id)
	_play_pop_animation(ability_key)
	_show_center_popup(ability_key)

func _on_abilities_changed(_abilities: Array) -> void:
	if _ignore_next_changed_event:
		_ignore_next_changed_event = false
		return
	_rebuild_from_manager()

func _rebuild_from_manager() -> void:
	_ensure_container()
	for child in _container.get_children():
		child.queue_free()
	_entry_by_id.clear()
	if _ability_manager == null:
		return
	var summary: Array[Dictionary] = _ability_manager.get_abilities_summary()
	for entry in summary:
		var ability_id: String = String(entry.get("id", ""))
		var stack: int = int(entry.get("stack", 0))
		if ability_id.is_empty() or stack <= 0:
			continue
		var row: PanelContainer = _build_entry(entry)
		_container.add_child(row)
		_entry_by_id[ability_id] = row

func _build_entry(entry: Dictionary) -> PanelContainer:
	var ability_name: String = String(entry.get("name", "Ability"))
	var stack: int = int(entry.get("stack", 1))
	var rarity: String = String(entry.get("rarity", "common"))
	var color_hex: String = String(entry.get("icon_color", "#8B8B8B"))
	var icon_text: String = String(entry.get("icon_text", "?"))

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = ENTRY_MIN_SIZE
	panel.pivot_offset = ENTRY_MIN_SIZE * 0.5
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.04, 0.06, 0.82)
	panel_style.border_color = _color_from_hex(color_hex, Color(0.55, 0.55, 0.55, 1.0))
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", panel_style)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var icon: PanelContainer = _build_icon_panel(icon_text)
	_apply_icon_color(icon, color_hex)
	row.add_child(icon)

	var text_column: VBoxContainer = VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.add_theme_constant_override("separation", 1)
	row.add_child(text_column)

	var title: Label = Label.new()
	title.text = ability_name
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	text_column.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "%s  x%d" % [_rarity_label(rarity), stack]
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", _color_from_hex(color_hex, Color(0.7, 0.7, 0.7, 1.0)))
	text_column.add_child(subtitle)

	return panel

func _build_icon_panel(icon_text: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = ICON_SIZE
	panel.pivot_offset = ICON_SIZE * 0.5
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.35, 0.35, 0.35, 1.0)
	style.border_color = Color(0.95, 0.95, 0.95, 0.42)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

	var label: Label = Label.new()
	label.name = "IconLabel"
	label.text = icon_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.07, 0.07, 0.08, 1.0))
	panel.add_child(label)
	return panel

func _apply_icon_color(icon_panel: PanelContainer, color_hex: String) -> void:
	if icon_panel == null:
		return
	var style: StyleBoxFlat = icon_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return
	var color: Color = _color_from_hex(color_hex, Color(0.35, 0.35, 0.35, 1.0))
	style.bg_color = color
	style.border_color = color.lightened(0.24)

func _play_pop_animation(ability_id: String) -> void:
	if not _entry_by_id.has(ability_id):
		return
	var entry_variant: Variant = _entry_by_id[ability_id]
	var entry: PanelContainer = entry_variant as PanelContainer
	if entry == null:
		return
	entry.scale = Vector2.ONE
	var tween: Tween = create_tween()
	tween.tween_property(entry, "scale", Vector2.ONE * POP_SCALE, POP_DURATION)
	tween.tween_property(entry, "scale", Vector2.ONE, POP_DURATION)

func _show_center_popup(ability_id: String) -> void:
	if _center_popup == null:
		return
	var ui_data: Dictionary = {}
	if _ability_manager != null:
		ui_data = _ability_manager.get_ability_display(StringName(ability_id))
	var ability_name: String = String(ui_data.get("name", ability_id.capitalize()))
	var rarity: String = String(ui_data.get("rarity", "common"))
	var color_hex: String = String(ui_data.get("icon_color", "#8B8B8B"))
	var icon_text: String = String(ui_data.get("icon_text", "?"))

	if _center_name_label != null:
		_center_name_label.text = ability_name
	if _center_rarity_label != null:
		_center_rarity_label.text = "Received: %s" % _rarity_label(rarity)
		_center_rarity_label.add_theme_color_override("font_color", _color_from_hex(color_hex, Color(0.7, 0.7, 0.7, 1.0)))
	if _center_icon_label != null:
		_center_icon_label.text = icon_text
	if _center_icon_panel != null:
		_apply_icon_color(_center_icon_panel, color_hex)

	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()
	_center_popup.visible = true
	_center_popup.scale = Vector2(0.95, 0.95)
	_center_popup.modulate = Color(1.0, 1.0, 1.0, 0.0)

	_center_tween = create_tween()
	_center_tween.tween_property(_center_popup, "modulate:a", 1.0, 0.14)
	_center_tween.parallel().tween_property(_center_popup, "scale", Vector2.ONE, 0.14)
	_center_tween.tween_interval(CENTER_SHOW_TIME)
	_center_tween.tween_property(_center_popup, "modulate:a", 0.0, 0.22)
	_center_tween.tween_callback(Callable(self, "_hide_center_popup"))

func _hide_center_popup() -> void:
	if _center_popup == null:
		return
	_center_popup.visible = false

func _rarity_label(rarity: String) -> String:
	match rarity.to_lower():
		"common":
			return "GRAY"
		"rare":
			return "YELLOW"
		"epic":
			return "PURPLE"
		"legendary":
			return "RED"
		_:
			return "GRAY"

func _color_from_hex(color_hex: String, fallback: Color) -> Color:
	return Color.from_string(color_hex, fallback)
