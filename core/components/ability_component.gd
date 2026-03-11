extends Node
class_name AbilityComponent

var _next_ready_time_by_id: Dictionary = {}

func can_use(ability_id: StringName, time_now: float) -> bool:
	if String(ability_id).is_empty():
		return false
	var ready_at: float = float(_next_ready_time_by_id.get(ability_id, 0.0))
	return time_now >= ready_at

func use_ability(ability_id: StringName, cooldown_seconds: float, time_now: float) -> bool:
	if not can_use(ability_id, time_now):
		return false
	_next_ready_time_by_id[ability_id] = time_now + max(cooldown_seconds, 0.0)
	return true
