extends Node3D
class_name Entity

@export var entity_id: String = ""

func get_component(type_name: StringName) -> Node:
	for child in get_children():
		if child.is_class(type_name):
			return child
	return null
