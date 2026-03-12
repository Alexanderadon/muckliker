extends Node

signal game_event(event_name: String, payload: Dictionary)

const EVENT_WHITELIST := {
	"player_damaged": true,
	"entity_died": true,
	"resource_harvested": true,
	"loot_spawn_requested": true,
	"loot_picked": true,
	"chunk_loaded": true,
	"chunk_unloaded": true,
	"enemy_killed": true,
	"gold_changed": true,
	"totem_activated": true,
	"totem_completed": true,
	"ability_collected": true
}

var REQUIRED_FIELDS: Dictionary = {
	"player_damaged": ["entity", "amount"],
	"entity_died": ["entity"],
	"resource_harvested": ["item_id", "amount", "position"],
	"loot_spawn_requested": ["position", "item_id", "amount"],
	"loot_picked": ["item_id", "amount"],
	"chunk_loaded": ["chunk_id", "seed"],
	"chunk_unloaded": ["chunk_id"],
	"enemy_killed": ["enemy_type", "gold_reward"],
	"gold_changed": ["old_value", "new_value"],
	"totem_activated": ["totem_id"],
	"totem_completed": ["totem_id"],
	"ability_collected": ["ability_id"]
}

var _subscribers: Dictionary = {}

func _ready() -> void:
	for event_name in EVENT_WHITELIST.keys():
		_subscribers[String(event_name)] = []

func subscribe(event_name: String, listener: Callable) -> bool:
	if not EVENT_WHITELIST.has(event_name):
		push_warning("EventBus.subscribe rejected unknown event: %s" % event_name)
		return false
	if not listener.is_valid():
		push_warning("EventBus.subscribe rejected invalid callable for %s" % event_name)
		return false
	var listeners: Array = _compact_valid_listeners(_listeners_for(event_name))
	for existing in listeners:
		if existing == listener:
			_subscribers[event_name] = listeners
			return true
	listeners.append(listener)
	_subscribers[event_name] = listeners
	return true

func unsubscribe(event_name: String, listener: Callable) -> bool:
	if not EVENT_WHITELIST.has(event_name):
		return false
	var listeners: Array = _listeners_for(event_name)
	var retained: Array = []
	var removed: bool = false
	for existing_variant in listeners:
		if typeof(existing_variant) != TYPE_CALLABLE:
			removed = true
			continue
		var existing: Callable = existing_variant
		if not existing.is_valid():
			removed = true
			continue
		if existing == listener:
			removed = true
			continue
		retained.append(existing)
	_subscribers[event_name] = retained
	return removed

func emit_game_event(event_name: String, payload: Dictionary = {}) -> bool:
	if not EVENT_WHITELIST.has(event_name):
		push_warning("EventBus.emit_game_event blocked non-whitelisted event: %s" % event_name)
		return false
	if not _validate_payload(event_name, payload):
		push_warning("EventBus.emit_game_event blocked invalid payload for event: %s" % event_name)
		return false
	game_event.emit(event_name, payload)
	var listeners: Array = _compact_valid_listeners(_listeners_for(event_name))
	_subscribers[event_name] = listeners
	for listener in listeners:
		if typeof(listener) == TYPE_CALLABLE and listener.is_valid():
			listener.call(payload)
	return true

func get_subscriber_count(event_name: String) -> int:
	if not EVENT_WHITELIST.has(event_name):
		return 0
	var listeners: Array = _compact_valid_listeners(_listeners_for(event_name))
	_subscribers[event_name] = listeners
	return listeners.size()

func get_all_subscriber_counts() -> Dictionary:
	var result: Dictionary = {}
	for event_name_variant in EVENT_WHITELIST.keys():
		var event_name: String = String(event_name_variant)
		var listeners: Array = _compact_valid_listeners(_listeners_for(event_name))
		_subscribers[event_name] = listeners
		result[event_name] = listeners.size()
	return result

func _validate_payload(event_name: String, payload: Dictionary) -> bool:
	if typeof(payload) != TYPE_DICTIONARY:
		return false
	for key in payload.keys():
		var key_type := typeof(key)
		if key_type != TYPE_STRING and key_type != TYPE_STRING_NAME:
			return false
	var required_variant: Variant = REQUIRED_FIELDS.get(event_name, [])
	var required: Array = required_variant if required_variant is Array else []
	for field_name in required:
		if not payload.has(field_name):
			return false
	return true

func _listeners_for(event_name: String) -> Array:
	var listeners_variant: Variant = _subscribers.get(event_name, [])
	return listeners_variant if listeners_variant is Array else []

func _compact_valid_listeners(listeners: Array) -> Array:
	var retained: Array = []
	for listener_variant in listeners:
		if typeof(listener_variant) != TYPE_CALLABLE:
			continue
		var listener: Callable = listener_variant
		if not listener.is_valid():
			continue
		retained.append(listener)
	return retained
