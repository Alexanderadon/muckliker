extends Node3D

@export var item_id := "wood"
@export var amount := 1

func harvest(by_entity):
	EventBus.emit_game_event("resource_harvested", {
		"item_id": item_id,
		"amount": amount,
		"position": global_position,
		"by": by_entity
	})
	queue_free()
