extends Node
class_name PlayerSystem

@export var player_scene: PackedScene
var player_instance: Node = null

func spawn_player(at_position: Vector3) -> void:
	if player_scene == null:
		push_error("Player scene missing")
		return
	var player_variant: Variant = player_scene.instantiate()
	player_instance = player_variant as Node
	if player_instance == null:
		return
	if player_instance is Node3D:
		player_instance.global_position = at_position
	get_tree().current_scene.add_child(player_instance)
