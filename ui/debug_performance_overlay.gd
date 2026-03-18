extends CanvasLayer
class_name DebugPerformanceOverlay

@export var update_interval_seconds: float = 0.2
@export var worst_frame_window_seconds: float = 0.25
@export var start_visible_in_game: bool = false
@export var toggle_keycode: Key = KEY_F1

var _label: Label = null
var _update_accumulator: float = 0.0
var _frame_samples: Array[Vector2] = []
var _enemy_system: Node = null
var _debug_visible: bool = false

func _ready() -> void:
	layer = 120
	_ensure_overlay_ui()
	set_process_unhandled_input(true)
	set_debug_visible(start_visible_in_game)

func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo:
		return
	if key_event.physical_keycode != toggle_keycode:
		return
	set_debug_visible(not _debug_visible)
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _debug_visible:
		return
	var now_seconds: float = float(Time.get_ticks_usec()) / 1000000.0
	var frame_time_ms: float = delta * 1000.0
	_frame_samples.append(Vector2(now_seconds, frame_time_ms))
	_trim_frame_samples(now_seconds)
	_update_accumulator += delta
	if _update_accumulator < update_interval_seconds:
		return
	_update_accumulator = 0.0
	_refresh_label(frame_time_ms)

func _ensure_overlay_ui() -> void:
	var panel: PanelContainer = get_node_or_null("MetricsPanel") as PanelContainer
	if panel == null:
		panel = PanelContainer.new()
		panel.name = "MetricsPanel"
		panel.anchor_left = 1.0
		panel.anchor_right = 1.0
		panel.anchor_top = 0.0
		panel.anchor_bottom = 0.0
		panel.offset_left = -360.0
		panel.offset_right = -12.0
		panel.offset_top = 12.0
		panel.offset_bottom = 226.0
		var panel_style: StyleBoxFlat = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.03, 0.04, 0.05, 0.78)
		panel_style.border_color = Color(0.28, 0.31, 0.36, 0.95)
		panel_style.set_border_width_all(1)
		panel_style.corner_radius_top_left = 5
		panel_style.corner_radius_top_right = 5
		panel_style.corner_radius_bottom_left = 5
		panel_style.corner_radius_bottom_right = 5
		panel.add_theme_stylebox_override("panel", panel_style)
		add_child(panel)
	_label = panel.get_node_or_null("MetricsLabel") as Label
	if _label == null:
		_label = Label.new()
		_label.name = "MetricsLabel"
		_label.offset_left = 10.0
		_label.offset_top = 8.0
		_label.offset_right = 340.0
		_label.offset_bottom = 206.0
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.add_theme_font_size_override("font_size", 13)
		_label.add_theme_color_override("font_color", Color(0.86, 0.94, 0.98, 1.0))
		panel.add_child(_label)

func set_debug_visible(value: bool) -> void:
	_debug_visible = value
	visible = value
	set_process(value)
	if not value:
		_update_accumulator = 0.0
		_frame_samples.clear()

func _refresh_label(current_frame_ms: float) -> void:
	if _label == null:
		return
	var fps: float = Engine.get_frames_per_second()
	var worst_frame_ms: float = _worst_frame_ms_in_window()
	var node_count: int = _count_scene_nodes()
	var object_count: int = _monitor_int("OBJECT_COUNT", 0)
	var memory_bytes: int = _monitor_int("MEMORY_STATIC", 0)
	var active_enemies: int = _get_active_enemy_count()
	var eventbus_subscribers: int = _get_total_eventbus_subscribers()

	_label.text = "\n".join([
		"FPS: %.1f" % fps,
		"Frame Time: %.2f ms" % current_frame_ms,
		"Worst (0.25s): %.2f ms" % worst_frame_ms,
		"Scene Nodes: %d" % node_count,
		"Objects: %d" % object_count,
		"Memory: %.2f MB" % _bytes_to_megabytes(memory_bytes),
		"Active Enemies: %d" % active_enemies,
		"EventBus Subs: %d" % eventbus_subscribers
	])

func _trim_frame_samples(now_seconds: float) -> void:
	var min_time: float = now_seconds - worst_frame_window_seconds
	while not _frame_samples.is_empty() and _frame_samples[0].x < min_time:
		_frame_samples.pop_front()

func _worst_frame_ms_in_window() -> float:
	var worst: float = 0.0
	for sample in _frame_samples:
		if sample.y > worst:
			worst = sample.y
	return worst

func _count_scene_nodes() -> int:
	var monitor_node_count: int = _monitor_int("OBJECT_NODE_COUNT", -1)
	if monitor_node_count >= 0:
		return monitor_node_count
	var root: Node = get_tree().current_scene
	if root == null:
		return 0
	var total: int = 0
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		total += 1
		for child_variant in node.get_children():
			var child: Node = child_variant as Node
			if child != null:
				queue.append(child)
	return total

func _monitor_int(constant_name: String, default_value: int) -> int:
	var monitor_id: int = _performance_constant(constant_name)
	if monitor_id < 0:
		return default_value
	var value: Variant = Performance.get_monitor(monitor_id)
	return int(value)

func _performance_constant(constant_name: String) -> int:
	if not ClassDB.class_has_integer_constant("Performance", constant_name):
		return -1
	return ClassDB.class_get_integer_constant("Performance", constant_name)

func _bytes_to_megabytes(bytes: int) -> float:
	return float(maxi(bytes, 0)) / 1048576.0

func _get_active_enemy_count() -> int:
	var enemy_system: Node = _resolve_enemy_system()
	if enemy_system != null and enemy_system.has_method("get_active_enemy_count"):
		var base_enemies: int = int(enemy_system.call("get_active_enemy_count"))
		var wolves: int = get_tree().get_nodes_in_group("totem_wolf").size()
		return base_enemies + wolves
	return get_tree().get_nodes_in_group("enemy").size()

func _resolve_enemy_system() -> Node:
	if _enemy_system != null and is_instance_valid(_enemy_system):
		return _enemy_system
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	var by_name: Node = root.find_child("EnemySystem", true, false)
	if by_name != null:
		_enemy_system = by_name
	return _enemy_system

func _get_total_eventbus_subscribers() -> int:
	if EventBus == null or not EventBus.has_method("get_all_subscriber_counts"):
		return 0
	var counts_variant: Variant = EventBus.call("get_all_subscriber_counts")
	if not (counts_variant is Dictionary):
		return 0
	var counts: Dictionary = counts_variant
	var total: int = 0
	for value_variant in counts.values():
		total += int(value_variant)
	return total
