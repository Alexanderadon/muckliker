extends Node
class_name MovementComponent

@export var move_speed: float = 6.0
@export var jump_velocity: float = 6.0
@export var gravity: float = 18.0

func move_character(
	body: CharacterBody3D,
	input_vector: Vector2,
	wants_jump: bool,
	delta: float,
	orientation_basis: Basis = Basis.IDENTITY
) -> void:
	if body == null:
		return
	var local_direction: Vector3 = Vector3(input_vector.x, 0.0, input_vector.y)
	var world_direction: Vector3 = orientation_basis * local_direction
	world_direction.y = 0.0
	if world_direction.length() > 1.0:
		world_direction = world_direction.normalized()
	body.velocity.x = world_direction.x * move_speed
	body.velocity.z = world_direction.z * move_speed
	if body.is_on_floor():
		if wants_jump:
			body.velocity.y = jump_velocity
		elif body.velocity.y < 0.0:
			body.velocity.y = -0.1
	else:
		body.velocity.y -= gravity * delta
	body.move_and_slide()
