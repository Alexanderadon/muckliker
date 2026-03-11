extends "res://core/components/base_component.gd"

@export var speed := 6.0
@export var gravity := 18.0
var velocity := Vector3.ZERO

func move_character(body, input_dir, delta):
	var wish_dir = (body.transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	velocity.x = wish_dir.x * speed
	velocity.z = wish_dir.z * speed
	if not body.is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.1
	body.velocity = velocity
	body.move_and_slide()
	velocity = body.velocity
