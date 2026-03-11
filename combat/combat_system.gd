extends Node

@export var default_attack_distance: float = 4.0

func raycast_attack(
	attacker: Node,
	origin: Vector3,
	direction: Vector3,
	space_state: PhysicsDirectSpaceState3D,
	exclude: Array = [],
	attack_distance: float = -1.0
) -> Dictionary:
	if attacker == null or space_state == null or direction.length_squared() == 0.0:
		return {}
	var distance: float = default_attack_distance if attack_distance <= 0.0 else attack_distance
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * distance)
	query.exclude = exclude
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Variant = hit.get("collider")
	if collider == null:
		return {}
	var damage_component: DamageComponent = _find_damage_component(attacker)
	if damage_component != null:
		if collider is Node:
			damage_component.deal_damage(collider as Node, attacker)
	return hit

func _find_damage_component(attacker: Node) -> DamageComponent:
	if attacker is DamageComponent:
		return attacker as DamageComponent
	var by_name: Node = attacker.get_node_or_null("DamageComponent")
	if by_name is DamageComponent:
		return by_name as DamageComponent
	if attacker.has_method("get_component"):
		var by_entity: Variant = attacker.call("get_component", StringName("DamageComponent"))
		if by_entity is DamageComponent:
			return by_entity as DamageComponent
	return null
