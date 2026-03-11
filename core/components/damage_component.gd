extends Node
class_name DamageComponent

@export var base_damage: float = 10.0

func deal_damage(target: Node, source: Node = null, multiplier: float = 1.0) -> void:
	if target == null:
		return
	var health_component: HealthComponent = _find_health_component(target)
	if health_component == null:
		return
	var damage_amount: float = maxf(base_damage * multiplier, 0.0)
	health_component.apply_damage(damage_amount, source if source != null else get_parent())

func _find_health_component(target: Node) -> HealthComponent:
	var from_target: HealthComponent = _extract_health_component(target)
	if from_target != null:
		return from_target
	var parent: Node = target.get_parent()
	var from_parent: HealthComponent = _extract_health_component(parent)
	if from_parent != null:
		return from_parent
	if parent != null:
		var grand_parent: Node = parent.get_parent()
		var from_grand_parent: HealthComponent = _extract_health_component(grand_parent)
		if from_grand_parent != null:
			return from_grand_parent
	return null

func _extract_health_component(candidate: Node) -> HealthComponent:
	if candidate == null:
		return null
	if candidate is HealthComponent:
		return candidate as HealthComponent
	var by_name: Node = candidate.get_node_or_null("HealthComponent")
	if by_name is HealthComponent:
		return by_name as HealthComponent
	if candidate.has_method("get_component"):
		var from_entity: Variant = candidate.call("get_component", StringName("HealthComponent"))
		if from_entity is HealthComponent:
			return from_entity as HealthComponent
	return null
