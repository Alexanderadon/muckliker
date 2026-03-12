extends CanvasLayer
class_name UISystem

const DAMAGE_FLASH_FADE_DURATION: float = 0.3
const DAMAGE_FLASH_MAX_ALPHA: float = 0.0
const LOOT_NOTIFICATION_LIFETIME: float = 3.0
const LOOT_NOTIFICATION_FADE_DURATION: float = 0.6
const HEALTH_BIND_RETRY_INTERVAL: float = 0.25
const HP_HIT_FLASH_DURATION: float = 1.0
const HP_HIT_FLASH_PULSES_PER_SECOND: float = 6.0
const HP_BAR_BASE_FILL_COLOR: Color = Color(0.94, 0.14, 0.16, 1.0)
const HP_BAR_FLASH_FILL_COLOR: Color = Color(0.98, 0.52, 0.52, 1.0)
const HP_BAR_TRACK_COLOR: Color = Color(0.30, 0.30, 0.32, 1.0)

var _bound_player: Node = null
var _bound_health: HealthComponent = null
var _inventory_system: Node = null
var _world_system: Node = null
var _crafting_system: Node = null

var _health_panel: PanelContainer = null
var _health_bar_track: PanelContainer = null
var _health_fill: PanelContainer = null
var _health_fill_style: StyleBoxFlat = null
var _health_label: Label = null
var _gold_label: Label = null
var _water_tint: ColorRect = null
var _damage_tint: ColorRect = null
var _damage_flash_alpha: float = 0.0
var _inventory_ui: Control = null
var _minimap_ui: Control = null
var _ability_ui: Control = null
var _crosshair_dot: Panel = null
var _interaction_prompt: Label = null
var _loot_notifications: VBoxContainer = null
var _health_bind_retry_timer: float = 0.0
var _gold_bound_player: Node = null
var _health_fill_ratio: float = 1.0
var _hp_hit_flash_time_left: float = 0.0

func _ready() -> void:
	layer = 10
	add_to_group("ui_system")
	_ensure_widgets()
	_ensure_inventory_ui()
	_ensure_minimap_ui()
	_ensure_ability_ui()
	EventBus.subscribe("player_damaged", Callable(self, "_on_player_damaged"))
	EventBus.subscribe("loot_picked", Callable(self, "_on_loot_picked"))

func _exit_tree() -> void:
	if EventBus != null and EventBus.has_method("unsubscribe"):
		EventBus.call("unsubscribe", "player_damaged", Callable(self, "_on_player_damaged"))
		EventBus.call("unsubscribe", "loot_picked", Callable(self, "_on_loot_picked"))

func _process(delta: float) -> void:
	_try_rebind_health_component(delta)
	_sync_health_ui_from_component()
	_update_health_hit_flash(delta)
	if _damage_flash_alpha <= 0.0 or _damage_tint == null:
		_update_loot_notifications(delta)
		return
	_damage_flash_alpha = maxf(_damage_flash_alpha - (delta / DAMAGE_FLASH_FADE_DURATION) * DAMAGE_FLASH_MAX_ALPHA, 0.0)
	var color: Color = _damage_tint.color
	color.a = _damage_flash_alpha
	_damage_tint.color = color
	_update_loot_notifications(delta)

func bind(player: Node) -> void:
	_bound_player = player
	_ensure_widgets()
	_ensure_inventory_ui()
	_ensure_minimap_ui()
	_ensure_ability_ui()
	_bind_health_component()
	_bind_gold_source()
	_bind_inventory_ui()
	_bind_minimap_ui()
	_bind_ability_ui()

func set_world_system(world_system: Node) -> void:
	_world_system = world_system
	_bind_minimap_ui()

func set_inventory_system(inventory_system: Node) -> void:
	_inventory_system = inventory_system
	_bind_inventory_ui()

func set_crafting_system(crafting_system: Node) -> void:
	_crafting_system = crafting_system
	_bind_inventory_ui()

func _bind_health_component() -> void:
	if _bound_player == null:
		return
	var health_node: Node = _bound_player.get_node_or_null("HealthComponent")
	var health: HealthComponent = health_node as HealthComponent
	if health == null and _bound_player.has_method("get_component"):
		var health_variant: Variant = _bound_player.call("get_component", StringName("HealthComponent"))
		health = health_variant as HealthComponent
	if health == null:
		var fallback_health_node: Node = _bound_player.find_child("HealthComponent", true, false)
		health = fallback_health_node as HealthComponent
	if health == null:
		return

	if _bound_health != null:
		var old_callback: Callable = Callable(self, "_on_health_changed")
		if _bound_health.health_changed.is_connected(old_callback):
			_bound_health.health_changed.disconnect(old_callback)

	_bound_health = health
	var callback: Callable = Callable(self, "_on_health_changed")
	if not _bound_health.health_changed.is_connected(callback):
		_bound_health.health_changed.connect(callback)
	_on_health_changed(_bound_health.current_health, _bound_health.max_health)

func _on_health_changed(current_health: float, max_health: float) -> void:
	if _health_fill == null or _health_label == null:
		return
	var max_value: float = maxf(max_health, 1.0)
	var clamped_health: float = clampf(current_health, 0.0, max_value)
	_health_fill_ratio = clamped_health / max_value
	_apply_health_fill_ratio()
	_health_label.text = "HP %d/%d" % [int(round(clamped_health)), int(round(max_value))]

func _apply_health_fill_ratio() -> void:
	if _health_fill == null:
		return
	var ratio: float = clampf(_health_fill_ratio, 0.0, 1.0)
	_health_fill.visible = ratio > 0.0
	_health_fill.anchor_right = maxf(ratio, 0.001)
	_health_fill.offset_right = 0.0

func _update_health_hit_flash(delta: float) -> void:
	if _health_fill_style == null:
		return
	if _hp_hit_flash_time_left <= 0.0:
		_set_health_fill_color(HP_BAR_BASE_FILL_COLOR)
		return
	_hp_hit_flash_time_left = maxf(_hp_hit_flash_time_left - delta, 0.0)
	var elapsed: float = HP_HIT_FLASH_DURATION - _hp_hit_flash_time_left
	var pulse_wave: float = 0.5 + 0.5 * sin(elapsed * TAU * HP_HIT_FLASH_PULSES_PER_SECOND)
	var blend: float = 0.2 + pulse_wave * 0.7
	_set_health_fill_color(HP_BAR_BASE_FILL_COLOR.lerp(HP_BAR_FLASH_FILL_COLOR, blend))

func _set_health_fill_color(color: Color) -> void:
	if _health_fill_style == null:
		return
	if _health_fill_style.bg_color == color:
		return
	_health_fill_style.bg_color = color
	if _health_fill != null:
		_health_fill.add_theme_stylebox_override("panel", _health_fill_style)

func _ensure_widgets() -> void:
	if _health_panel != null:
		return
	_water_tint = ColorRect.new()
	_water_tint.name = "WaterTint"
	_water_tint.anchor_right = 1.0
	_water_tint.anchor_bottom = 1.0
	_water_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_tint.color = Color(0.08, 0.25, 0.6, 0.0)
	add_child(_water_tint)

	_damage_tint = ColorRect.new()
	_damage_tint.name = "DamageTint"
	_damage_tint.anchor_right = 1.0
	_damage_tint.anchor_bottom = 1.0
	_damage_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_tint.color = Color(0.95, 0.08, 0.08, 0.0)
	add_child(_damage_tint)

	_health_panel = PanelContainer.new()
	_health_panel.name = "HealthPanel"
	_health_panel.offset_left = 16.0
	_health_panel.offset_top = 16.0
	_health_panel.offset_right = 520.0
	_health_panel.offset_bottom = 132.0
	add_child(_health_panel)

	var background_style: StyleBoxFlat = StyleBoxFlat.new()
	background_style.bg_color = Color(0.08, 0.09, 0.1, 0.82)
	background_style.border_color = Color(0.18, 0.18, 0.19, 0.95)
	background_style.set_border_width_all(1)
	background_style.corner_radius_top_left = 12
	background_style.corner_radius_top_right = 12
	background_style.corner_radius_bottom_left = 12
	background_style.corner_radius_bottom_right = 12
	_health_panel.add_theme_stylebox_override("panel", background_style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	_health_panel.add_child(vbox)

	_health_bar_track = PanelContainer.new()
	_health_bar_track.name = "HealthBarTrack"
	_health_bar_track.custom_minimum_size = Vector2(470.0, 58.0)
	_health_bar_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track_style: StyleBoxFlat = StyleBoxFlat.new()
	track_style.bg_color = HP_BAR_TRACK_COLOR
	track_style.corner_radius_top_left = 14
	track_style.corner_radius_top_right = 14
	track_style.corner_radius_bottom_left = 14
	track_style.corner_radius_bottom_right = 14
	track_style.set_content_margin_all(10.0)
	_health_bar_track.add_theme_stylebox_override("panel", track_style)
	vbox.add_child(_health_bar_track)

	var track_content: Control = Control.new()
	track_content.name = "TrackContent"
	track_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	track_content.anchor_right = 1.0
	track_content.anchor_bottom = 1.0
	_health_bar_track.add_child(track_content)

	_health_fill = PanelContainer.new()
	_health_fill.name = "HealthFill"
	_health_fill.anchor_left = 0.0
	_health_fill.anchor_right = 1.0
	_health_fill.anchor_top = 0.0
	_health_fill.anchor_bottom = 1.0
	_health_fill.offset_left = 0.0
	_health_fill.offset_top = 0.0
	_health_fill.offset_right = 0.0
	_health_fill.offset_bottom = 0.0
	_health_fill_style = StyleBoxFlat.new()
	_health_fill_style.bg_color = HP_BAR_BASE_FILL_COLOR
	_health_fill_style.corner_radius_top_left = 12
	_health_fill_style.corner_radius_top_right = 12
	_health_fill_style.corner_radius_bottom_left = 12
	_health_fill_style.corner_radius_bottom_right = 12
	_health_fill.add_theme_stylebox_override("panel", _health_fill_style)
	track_content.add_child(_health_fill)

	_health_label = Label.new()
	_health_label.text = "HP 100/100"
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_label.anchor_right = 1.0
	_health_label.anchor_bottom = 1.0
	_health_label.add_theme_font_size_override("font_size", 30)
	_health_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_health_fill.add_child(_health_label)
	_health_fill_ratio = 1.0
	_apply_health_fill_ratio()
	_set_health_fill_color(HP_BAR_BASE_FILL_COLOR)

	_gold_label = Label.new()
	_gold_label.text = "Coins: 0"
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.28, 1.0))
	vbox.add_child(_gold_label)

	_interaction_prompt = Label.new()
	_interaction_prompt.name = "InteractionPrompt"
	_interaction_prompt.anchor_left = 0.5
	_interaction_prompt.anchor_right = 0.5
	_interaction_prompt.anchor_top = 1.0
	_interaction_prompt.anchor_bottom = 1.0
	_interaction_prompt.offset_left = -120.0
	_interaction_prompt.offset_right = 120.0
	_interaction_prompt.offset_top = -92.0
	_interaction_prompt.offset_bottom = -62.0
	_interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_interaction_prompt.add_theme_font_size_override("font_size", 22)
	_interaction_prompt.visible = false
	add_child(_interaction_prompt)

	_crosshair_dot = Panel.new()
	_crosshair_dot.name = "CrosshairDot"
	_crosshair_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_dot.anchor_left = 0.5
	_crosshair_dot.anchor_right = 0.5
	_crosshair_dot.anchor_top = 0.5
	_crosshair_dot.anchor_bottom = 0.5
	_crosshair_dot.offset_left = -3.0
	_crosshair_dot.offset_right = 3.0
	_crosshair_dot.offset_top = -3.0
	_crosshair_dot.offset_bottom = 3.0
	var crosshair_style: StyleBoxFlat = StyleBoxFlat.new()
	crosshair_style.bg_color = Color(1.0, 1.0, 1.0, 0.95)
	crosshair_style.border_color = Color(0.04, 0.04, 0.04, 0.85)
	crosshair_style.set_border_width_all(1)
	crosshair_style.corner_radius_top_left = 3
	crosshair_style.corner_radius_top_right = 3
	crosshair_style.corner_radius_bottom_left = 3
	crosshair_style.corner_radius_bottom_right = 3
	_crosshair_dot.add_theme_stylebox_override("panel", crosshair_style)
	add_child(_crosshair_dot)

	_loot_notifications = VBoxContainer.new()
	_loot_notifications.name = "LootNotifications"
	_loot_notifications.anchor_left = 1.0
	_loot_notifications.anchor_right = 1.0
	_loot_notifications.anchor_top = 1.0
	_loot_notifications.anchor_bottom = 1.0
	_loot_notifications.offset_left = -330.0
	_loot_notifications.offset_right = -20.0
	_loot_notifications.offset_top = -220.0
	_loot_notifications.offset_bottom = -40.0
	_loot_notifications.alignment = BoxContainer.ALIGNMENT_END
	_loot_notifications.add_theme_constant_override("separation", 4)
	add_child(_loot_notifications)

func _ensure_inventory_ui() -> void:
	if _inventory_ui != null and is_instance_valid(_inventory_ui):
		return
	var inventory_ui_scene: PackedScene = load("res://ui/inventory_ui.tscn")
	if inventory_ui_scene == null:
		return
	var inventory_ui_variant: Variant = inventory_ui_scene.instantiate()
	var inventory_ui_control: Control = inventory_ui_variant as Control
	if inventory_ui_control == null:
		return
	_inventory_ui = inventory_ui_control
	add_child(_inventory_ui)

func _bind_inventory_ui() -> void:
	if _inventory_ui == null or not is_instance_valid(_inventory_ui):
		return
	if _bound_player == null:
		return
	if _inventory_ui.has_method("bind"):
		_inventory_ui.call("bind", _bound_player, _inventory_system, _crafting_system)

func _ensure_minimap_ui() -> void:
	if _minimap_ui != null and is_instance_valid(_minimap_ui):
		return
	var minimap_scene: PackedScene = load("res://ui/minimap_ui.tscn")
	if minimap_scene == null:
		return
	var minimap_variant: Variant = minimap_scene.instantiate()
	var minimap_control: Control = minimap_variant as Control
	if minimap_control == null:
		return
	_minimap_ui = minimap_control
	add_child(_minimap_ui)

func _ensure_ability_ui() -> void:
	if _ability_ui != null and is_instance_valid(_ability_ui):
		return
	var ability_ui_script: Script = load("res://abilities/ability_ui.gd")
	if ability_ui_script == null:
		return
	var ability_ui_control: Control = Control.new()
	ability_ui_control.set_script(ability_ui_script)
	_ability_ui = ability_ui_control
	add_child(_ability_ui)

func _bind_minimap_ui() -> void:
	if _minimap_ui == null or not is_instance_valid(_minimap_ui):
		return
	if _bound_player == null or _world_system == null:
		return
	if _minimap_ui.has_method("bind"):
		_minimap_ui.call("bind", _bound_player, _world_system)

func _bind_ability_ui() -> void:
	if _ability_ui == null or not is_instance_valid(_ability_ui):
		return
	if _bound_player == null:
		return
	if _ability_ui.has_method("bind"):
		_ability_ui.call("bind", _bound_player)

func _bind_gold_source() -> void:
	if _gold_bound_player != null and is_instance_valid(_gold_bound_player):
		var old_callback: Callable = Callable(self, "_on_player_gold_changed")
		if _gold_bound_player.has_signal("gold_changed") and _gold_bound_player.is_connected("gold_changed", old_callback):
			_gold_bound_player.disconnect("gold_changed", old_callback)
	_gold_bound_player = _bound_player
	if _gold_bound_player == null or not is_instance_valid(_gold_bound_player):
		_update_gold_label(0)
		return
	var callback: Callable = Callable(self, "_on_player_gold_changed")
	if _gold_bound_player.has_signal("gold_changed") and not _gold_bound_player.is_connected("gold_changed", callback):
		_gold_bound_player.connect("gold_changed", callback)
	var current_gold: int = 0
	var economy: PlayerEconomy = null
	if _gold_bound_player.has_method("get_player_economy"):
		var economy_variant: Variant = _gold_bound_player.call("get_player_economy")
		economy = economy_variant as PlayerEconomy
	if economy != null:
		current_gold = economy.gold
	else:
		var gold_variant: Variant = _gold_bound_player.get("gold")
		if gold_variant != null:
			current_gold = int(gold_variant)
	_update_gold_label(current_gold)

func _on_player_gold_changed(_old_value: int, new_value: int) -> void:
	_update_gold_label(new_value)

func _update_gold_label(value: int) -> void:
	if _gold_label == null:
		return
	_gold_label.text = "Coins: %d" % maxi(value, 0)

func set_water_tint(intensity: float) -> void:
	if _water_tint == null:
		return
	var clamped_intensity: float = clampf(intensity, 0.0, 1.0)
	var tint_color: Color = _water_tint.color
	tint_color.a = clamped_intensity * 0.55
	_water_tint.color = tint_color

func set_interaction_prompt(text: String, visible_prompt: bool) -> void:
	if _interaction_prompt == null:
		return
	_interaction_prompt.text = text
	_interaction_prompt.visible = visible_prompt and not text.is_empty()

func _on_player_damaged(payload: Dictionary) -> void:
	if _damage_tint == null:
		return
	var entity_variant: Variant = payload.get("entity")
	if _bound_player != null and entity_variant != _bound_player:
		return
	_hp_hit_flash_time_left = HP_HIT_FLASH_DURATION
	_damage_flash_alpha = DAMAGE_FLASH_MAX_ALPHA
	var color: Color = _damage_tint.color
	color.a = _damage_flash_alpha
	_damage_tint.color = color

func _on_loot_picked(payload: Dictionary) -> void:
	if _loot_notifications == null:
		return
	var item_id: String = String(payload.get("item_id", "item"))
	var amount: int = int(payload.get("amount", 1))
	var display_name: String = _item_display_name(item_id)
	_push_notification("+%d %s" % [amount, display_name])

func show_crafting_notification(text: String) -> void:
	if text.is_empty():
		return
	_push_notification(text)

func _push_notification(text: String) -> void:
	if _loot_notifications == null or text.is_empty():
		return
	var message_label: Label = Label.new()
	message_label.text = text
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	message_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	message_label.set_meta("life_left", LOOT_NOTIFICATION_LIFETIME)
	_loot_notifications.add_child(message_label)
	_loot_notifications.move_child(message_label, 0)
	while _loot_notifications.get_child_count() > 6:
		var oldest: Node = _loot_notifications.get_child(_loot_notifications.get_child_count() - 1)
		# queue_free() is deferred; remove the node now to avoid an endless loop here.
		_loot_notifications.remove_child(oldest)
		oldest.queue_free()

func _update_loot_notifications(delta: float) -> void:
	if _loot_notifications == null:
		return
	for child_variant in _loot_notifications.get_children():
		var child_node: Node = child_variant
		var message_label: Label = child_node as Label
		if message_label == null:
			continue
		var life_left_variant: Variant = message_label.get_meta("life_left", 0.0)
		var life_left: float = float(life_left_variant) - delta
		if life_left <= 0.0:
			message_label.queue_free()
			continue
		message_label.set_meta("life_left", life_left)
		if life_left < LOOT_NOTIFICATION_FADE_DURATION:
			var alpha: float = clampf(life_left / LOOT_NOTIFICATION_FADE_DURATION, 0.0, 1.0)
			message_label.modulate = Color(1.0, 1.0, 1.0, alpha)
		else:
			message_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _item_display_name(item_id: String) -> String:
	if _inventory_system != null and _inventory_system.has_method("get_item_label"):
		var label_variant: Variant = _inventory_system.call("get_item_label", item_id)
		var label: String = String(label_variant)
		if not label.is_empty():
			return label
	return item_id.capitalize()

func _try_rebind_health_component(delta: float) -> void:
	if _bound_player == null:
		_health_bind_retry_timer = 0.0
		return
	if _bound_health != null and is_instance_valid(_bound_health):
		_health_bind_retry_timer = 0.0
		return
	_health_bind_retry_timer += delta
	if _health_bind_retry_timer < HEALTH_BIND_RETRY_INTERVAL:
		return
	_health_bind_retry_timer = 0.0
	_bind_health_component()

func _sync_health_ui_from_component() -> void:
	if _bound_health == null or not is_instance_valid(_bound_health):
		return
	_on_health_changed(_bound_health.current_health, _bound_health.max_health)
