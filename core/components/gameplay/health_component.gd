extends "res://core/components/base_component.gd"

signal health_changed(current, max_health)
signal died(entity)

@export var max_health := 100.0
var current_health := 100.0

func _ready():
	current_health = max_health

func apply_damage(amount):
	if amount <= 0.0:
		return
	current_health = clamp(current_health - amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
	EventBus.emit_game_event("player_damaged", {"entity": owner_entity, "amount": amount})
	if current_health <= 0.0:
		died.emit(owner_entity)
		EventBus.emit_game_event("entity_died", {"entity": owner_entity})

func heal(amount):
	if amount <= 0.0:
		return
	current_health = clamp(current_health + amount, 0.0, max_health)
	health_changed.emit(current_health, max_health)
