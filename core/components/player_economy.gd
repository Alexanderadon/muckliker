extends Node
class_name PlayerEconomy

signal gold_changed(old_value: int, new_value: int)

@export var starting_gold: int = 0

var gold: int = 0

func _ready() -> void:
	gold = maxi(starting_gold, 0)
	EventBus.subscribe("enemy_killed", Callable(self, "_on_enemy_killed"))
	EventBus.subscribe("totem_completed", Callable(self, "_on_totem_completed"))

func add_gold(amount: int, source: StringName = &"unknown") -> void:
	if amount <= 0:
		return
	var old_value: int = gold
	gold += amount
	gold_changed.emit(old_value, gold)
	EventBus.emit_game_event("gold_changed", {
		"old_value": old_value,
		"new_value": gold,
		"source": String(source)
	})

func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	var old_value: int = gold
	gold -= amount
	gold_changed.emit(old_value, gold)
	EventBus.emit_game_event("gold_changed", {
		"old_value": old_value,
		"new_value": gold,
		"source": "spend"
	})
	return true

func _on_enemy_killed(payload: Dictionary) -> void:
	var owner: Node = get_parent()
	var killer_variant: Variant = payload.get("killer", null)
	if owner == null or killer_variant != owner:
		return
	var reward: int = int(payload.get("gold_reward", 0))
	add_gold(reward, &"enemy_kill")

func _on_totem_completed(payload: Dictionary) -> void:
	var owner: Node = get_parent()
	var activator_variant: Variant = payload.get("activator", null)
	if owner == null or activator_variant != owner:
		return
	var bonus: int = int(payload.get("bonus_gold", 0))
	add_gold(bonus, &"totem_complete")
