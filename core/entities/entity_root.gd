extends Node3D
class_name EntityRoot

func get_component(component_name: StringName) -> Node:
	for child in get_children():
		if child.name == component_name:
			return child
		var child_script: Script = child.get_script()
		if child_script != null and child_script.get_global_name() == String(component_name):
			return child
	return null
