extends "res://core/components/base_component.gd"

@export var max_slots := 20
var items := []

func add_item(item):
	if items.size() >= max_slots:
		return false
	items.append(item)
	return true

func remove_item(item_id):
	for i in range(items.size()):
		if items[i].get("id", "") == item_id:
			items.remove_at(i)
			return true
	return false
