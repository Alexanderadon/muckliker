extends CharacterBody3D

@export var speed := 3.5
@export var aggro_distance := 20.0

var _target = null

func _physics_process(_delta):
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player")
	if _target == null:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var to_target = _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > aggro_distance:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var dir = to_target.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = -0.1
	move_and_slide()
