extends Node
class_name EnemySystem

@export var enemy_scene: PackedScene

func spawn_enemy(pos: Vector3) -> Node:
	if enemy_scene == null:
		return null
	var enemy_variant: Variant = enemy_scene.instantiate()
	var e: Node3D = enemy_variant as Node3D
	if e == null:
		return null
	if e is Node3D:
		e.global_position = pos
	get_tree().current_scene.add_child(e)
	return e
