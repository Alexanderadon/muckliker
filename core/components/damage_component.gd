extends Node
class_name DamageComponent

@export var base_damage: float = 10.0

func deal_damage(target: Node, source: Node = null, multiplier: float = 1.0) -> void:
	if target == null:
		return
	var health_node: Node = _find_health_component(target)
	if health_node == null:
		return
	var damage_amount: float = maxf(base_damage * multiplier, 0.0)
	var resolved_source: Node = source if source != null else get_parent()
	_apply_damage_to_health_node(health_node, damage_amount, resolved_source)

func _find_health_component(target: Node) -> Node:
	var from_target: Node = _extract_health_component(target)
	if from_target != null:
		return from_target
	var parent: Node = target.get_parent()
	var from_parent: Node = _extract_health_component(parent)
	if from_parent != null:
		return from_parent
	if parent != null:
		var grand_parent: Node = parent.get_parent()
		var from_grand_parent: Node = _extract_health_component(grand_parent)
		if from_grand_parent != null:
			return from_grand_parent
	return null

func _extract_health_component(candidate: Node) -> Node:
	if candidate == null:
		return null
	if _is_health_node(candidate):
		return candidate
	var by_name: Node = candidate.get_node_or_null("HealthComponent")
	if _is_health_node(by_name):
		return by_name
	var legacy_by_name: Node = candidate.get_node_or_null("Health")
	if _is_health_node(legacy_by_name):
		return legacy_by_name
	if candidate.has_method("get_component"):
		var from_entity: Variant = candidate.call("get_component", StringName("HealthComponent"))
		if from_entity is Node and _is_health_node(from_entity as Node):
			return from_entity as Node
	return null

func _is_health_node(candidate: Node) -> bool:
	if candidate == null:
		return false
	if candidate is HealthComponent:
		return true
	return candidate.has_method("apply_damage") and candidate.has_signal("health_changed")

func _apply_damage_to_health_node(health_node: Node, amount: float, source: Node) -> void:
	if health_node == null or not health_node.has_method("apply_damage"):
		return
	if health_node is HealthComponent:
		var typed_health: HealthComponent = health_node as HealthComponent
		if typed_health != null:
			typed_health.apply_damage(amount, source)
		return
	var arg_count: int = _method_argument_count(health_node, "apply_damage")
	if arg_count >= 2:
		health_node.call("apply_damage", amount, source)
	else:
		health_node.call("apply_damage", amount)

func _method_argument_count(node: Node, method_name: String) -> int:
	if node == null:
		return 0
	for method_info_variant in node.get_method_list():
		if not (method_info_variant is Dictionary):
			continue
		var method_info: Dictionary = method_info_variant
		if String(method_info.get("name", "")) != method_name:
			continue
		var args_variant: Variant = method_info.get("args", [])
		var args: Array = args_variant if args_variant is Array else []
		return args.size()
	return 0
