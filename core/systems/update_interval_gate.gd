extends RefCounted
class_name UpdateIntervalGate

var interval_seconds: float = 0.0
var _accumulator: float = 0.0

func _init(update_interval_seconds: float = 0.0) -> void:
	interval_seconds = maxf(update_interval_seconds, 0.0)

func set_interval(update_interval_seconds: float) -> void:
	interval_seconds = maxf(update_interval_seconds, 0.0)

func reset() -> void:
	_accumulator = 0.0

func should_run(delta: float) -> bool:
	if interval_seconds <= 0.0:
		return true
	_accumulator += delta
	if _accumulator < interval_seconds:
		return false
	_accumulator -= interval_seconds
	return true
