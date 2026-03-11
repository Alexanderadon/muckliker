extends Node
class_name CombatSystem

func attack(attacker: Node, target: Node) -> void:
	if attacker == null or target == null:
		return
	var dmg: Node = attacker.get_node_or_null("Damage")
	if dmg and dmg.has_method("deal_damage"):
		dmg.deal_damage(target, 1.0)
