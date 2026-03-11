extends Node

signal state_changed(new_state: String, previous_state: String)

const VALID_STATES := {
	"loading": true,
	"playing": true,
	"paused": true
}

var current_state: String = "loading"

func set_state(new_state: String) -> bool:
	if not VALID_STATES.has(new_state):
		push_warning("GameState rejected unknown state: %s" % new_state)
		return false
	if current_state == new_state:
		return true
	var previous_state := current_state
	current_state = new_state
	state_changed.emit(current_state, previous_state)
	return true

func pause_game() -> void:
	if get_tree() != null:
		get_tree().paused = true
	set_state("paused")

func resume_game() -> void:
	if get_tree() != null:
		get_tree().paused = false
	set_state("playing")
