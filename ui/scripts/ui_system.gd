extends CanvasLayer

func _ready() -> void:
	# UI system isolated from gameplay systems; subscribes only to events.
	EventBus.game_event.connect(_on_event)

func _on_event(event_name: String, payload: Dictionary) -> void:
	if event_name == "player_damaged":
		# TODO: bind to HP bar widget.
		pass
