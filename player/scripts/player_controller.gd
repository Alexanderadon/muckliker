extends CharacterBody3D

@export var move_speed := 6.5
@export var turn_speed := 6.0

@onready var movement = $Movement

func _ready():
	_ensure_input_map()

func _physics_process(delta):
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if movement and movement.has_method("move_character"):
		movement.speed = move_speed
		movement.move_character(self, input_dir, delta)

	var look = Vector3(velocity.x, 0.0, velocity.z)
	if look.length() > 0.2:
		var target_yaw = atan2(look.x, look.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, delta * turn_speed)

func _ensure_input_map():
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)

func _add_key_action(action_name, key_code):
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if InputMap.action_get_events(action_name).is_empty():
		var key_event = InputEventKey.new()
		key_event.physical_keycode = key_code
		InputMap.action_add_event(action_name, key_event)
