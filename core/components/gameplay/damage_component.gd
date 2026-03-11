extends "res://core/components/base_component.gd"

@export var base_damage := 10.0

func deal_damage(target, scale := 1.0):
	if target == null:
		return
	var health = target.get_node_or_null("Health")
	if health and health.has_method("apply_damage"):
		health.apply_damage(base_damage * scale)
