extends Node
class_name BaseComponent

var owner_entity: Node = null

func initialize(entity: Node) -> void:
	owner_entity = entity
