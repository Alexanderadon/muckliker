extends Node
class_name HealthComponent

signal health_changed(current_health: float, max_health: float)
signal died(entity: Node)

@export var max_health: float = 100.0
var current_health: float = 100.0
var owner_entity: Node = null

func _ready() -> void:
	owner_entity = get_parent()
	current_health = max_health

func apply_damage(amount: float, source: Node = null) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return
	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)
	if owner_entity != null and owner_entity.is_in_group("player"):
		EventBus.emit_game_event("player_damaged", {
			"entity": owner_entity,
			"amount": amount,
			"source": source
		})
	if current_health <= 0.0:
		died.emit(owner_entity)
		EventBus.emit_game_event("entity_died", {
			"entity": owner_entity,
			"source": source
		})

func heal(amount: float) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return
	current_health = minf(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func reset_health() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)
