extends Node

var enabled: bool = false
var _active_samples: Dictionary = {}
var _sample_durations_ms: Dictionary = {}

func _ready() -> void:
	enabled = GameConfig.ENABLE_DEBUG_PROFILER

func begin_frame() -> void:
	if not enabled:
		return
	_active_samples.clear()
	_sample_durations_ms.clear()

func start_sample(sample_name: String) -> void:
	if not enabled:
		return
	_active_samples[sample_name] = Time.get_ticks_usec()

func end_sample(sample_name: String) -> void:
	if not enabled:
		return
	var started_variant: Variant = _active_samples.get(sample_name, null)
	if started_variant == null:
		return
	var started_us: int = int(started_variant)
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_us) / 1000.0
	_sample_durations_ms[sample_name] = elapsed_ms
	_active_samples.erase(sample_name)

func print_frame_report(min_duration_ms: float = 0.0) -> void:
	if not enabled:
		return
	if _sample_durations_ms.is_empty():
		return
	var keys: Array = _sample_durations_ms.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float(_sample_durations_ms.get(a, 0.0)) > float(_sample_durations_ms.get(b, 0.0))
	)
	var report_lines: PackedStringArray = []
	for key_variant in keys:
		var key: String = String(key_variant)
		var duration_ms: float = float(_sample_durations_ms.get(key, 0.0))
		if duration_ms < min_duration_ms:
			continue
		report_lines.append("%s=%.3fms" % [key, duration_ms])
	if report_lines.is_empty():
		return
	print("[DebugProfiler] ", ", ".join(report_lines))
