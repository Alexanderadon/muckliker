extends Node
class_name AbilityManager

signal ability_collected(ability_id: StringName)
signal abilities_changed(abilities: Array)

@export var max_health_bonus_amount: float = 5.0
@export var movement_speed_bonus_amount: float = 1.2
@export var available_abilities: Array[StringName] = [&"max_hp_plus_5", &"move_speed_bonus"]

const RARITY_COLOR_BY_ID: Dictionary = {
	"common": "#8B8B8B",
	"rare": "#E2C14A",
	"epic": "#8A63FF",
	"legendary": "#C64242"
}

var collected_abilities: Array[StringName] = []
var _ability_stacks: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _ability_definitions: Dictionary = {
	"max_hp_plus_5": {
		"name": "Vitality +5 HP",
		"icon_text": "HP",
		"rarity": "common"
	},
	"move_speed_bonus": {
		"name": "Haste Move+",
		"icon_text": "SPD",
		"rarity": "rare"
	}
}

func _ready() -> void:
	_rng.randomize()

func collect_random_from_pool(pool: Array[StringName]) -> StringName:
	var candidates: Array[StringName] = []
	for entry in pool:
		var ability_id: StringName = StringName(String(entry).strip_edges())
		if ability_id == StringName(""):
			continue
		if not _is_known_ability(ability_id):
			continue
		candidates.append(ability_id)
	if candidates.is_empty():
		for fallback in available_abilities:
			var fallback_id: StringName = StringName(String(fallback).strip_edges())
			if _is_known_ability(fallback_id):
				candidates.append(fallback_id)
	if candidates.is_empty():
		return StringName("")
	var selected: StringName = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var granted: bool = collect_ability(selected)
	return selected if granted else StringName("")

func collect_ability(ability_id: StringName) -> bool:
	if not _is_known_ability(ability_id):
		return false
	if not _apply_ability(ability_id):
		return false
	var previous_stack: int = int(_ability_stacks.get(ability_id, 0))
	_ability_stacks[ability_id] = previous_stack + 1
	collected_abilities.append(ability_id)
	ability_collected.emit(ability_id)
	abilities_changed.emit(get_abilities_summary())
	var ui_data: Dictionary = get_ability_display(ability_id)
	EventBus.emit_game_event("ability_collected", {
		"ability_id": String(ability_id),
		"stack": previous_stack + 1,
		"name": String(ui_data.get("name", String(ability_id))),
		"rarity": String(ui_data.get("rarity", "common")),
		"icon_color": String(ui_data.get("icon_color", "#8A63FF"))
	})
	return true

func get_abilities_summary() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var appended: Dictionary = {}
	for configured_ability in available_abilities:
		var configured_id: String = String(configured_ability).strip_edges()
		if configured_id.is_empty():
			continue
		_append_summary_entry(configured_id, result, appended)
	for ability_key_variant in _ability_stacks.keys():
		var ability_id: String = String(ability_key_variant).strip_edges()
		_append_summary_entry(ability_id, result, appended)
	return result

func get_ability_stack(ability_id: StringName) -> int:
	return int(_ability_stacks.get(ability_id, 0))

func get_ability_display(ability_id: StringName) -> Dictionary:
	var normalized_id: String = String(ability_id).strip_edges()
	if normalized_id.is_empty():
		return {}
	var definition: Dictionary = _ability_definition(normalized_id)
	var rarity: String = String(definition.get("rarity", "common")).strip_edges().to_lower()
	if rarity.is_empty():
		rarity = "common"
	return {
		"id": normalized_id,
		"name": String(definition.get("name", normalized_id.capitalize())),
		"icon_text": String(definition.get("icon_text", "?")),
		"rarity": rarity,
		"icon_color": _rarity_color(rarity)
	}

func _is_known_ability(ability_id: StringName) -> bool:
	return _ability_definitions.has(String(ability_id))

func _ability_definition(ability_id: String) -> Dictionary:
	var definition_variant: Variant = _ability_definitions.get(ability_id, {})
	if definition_variant is Dictionary:
		return Dictionary(definition_variant)
	return {}

func _append_summary_entry(ability_id: String, into: Array[Dictionary], appended: Dictionary) -> void:
	var normalized_id: String = ability_id.strip_edges()
	if normalized_id.is_empty() or appended.has(normalized_id):
		return
	var stack_variant: Variant = _ability_stacks.get(StringName(normalized_id), _ability_stacks.get(normalized_id, 0))
	var stack: int = int(stack_variant)
	if stack <= 0:
		return
	var ui_data: Dictionary = get_ability_display(StringName(normalized_id))
	ui_data["stack"] = stack
	into.append(ui_data)
	appended[normalized_id] = true

func _rarity_color(rarity_id: String) -> String:
	var color_variant: Variant = RARITY_COLOR_BY_ID.get(rarity_id, "#8B8B8B")
	return String(color_variant)

func _apply_ability(ability_id: StringName) -> bool:
	match String(ability_id):
		"max_hp_plus_5":
			return _apply_max_health_bonus()
		"move_speed_bonus":
			return _apply_movement_speed_bonus()
		_:
			return false

func _apply_max_health_bonus() -> bool:
	var owner: Node = get_parent()
	if owner == null:
		return false
	var health: HealthComponent = owner.get_node_or_null("HealthComponent") as HealthComponent
	if health == null and owner.has_method("get_component"):
		var health_variant: Variant = owner.call("get_component", StringName("HealthComponent"))
		health = health_variant as HealthComponent
	if health == null:
		return false
	health.max_health += max_health_bonus_amount
	health.current_health = minf(health.current_health + max_health_bonus_amount, health.max_health)
	health.health_changed.emit(health.current_health, health.max_health)
	return true

func _apply_movement_speed_bonus() -> bool:
	var owner: Node = get_parent()
	if owner == null:
		return false
	if owner.has_method("add_permanent_move_speed_bonus"):
		owner.call("add_permanent_move_speed_bonus", movement_speed_bonus_amount)
		return true
	var movement: MovementComponent = owner.get_node_or_null("MovementComponent") as MovementComponent
	if movement == null and owner.has_method("get_component"):
		var movement_variant: Variant = owner.call("get_component", StringName("MovementComponent"))
		movement = movement_variant as MovementComponent
	if movement == null:
		return false
	movement.move_speed += movement_speed_bonus_amount
	return true
