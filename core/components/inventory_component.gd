extends Node
class_name InventoryComponent

signal inventory_changed(items: Array)

@export var max_slots: int = 30
var items: Array[Dictionary] = []
const ITEM_DB_PATH: String = "res://shared/items/item_db.json"
const MAX_STACK: int = 64
var _item_definitions: Dictionary = {}

func _ready() -> void:
	_load_item_definitions()
	_ensure_slot_capacity()

func add_item(item_id: String, amount: int = 1, metadata: Dictionary = {}) -> bool:
	if item_id.is_empty() or amount <= 0:
		return false
	if _item_definitions.is_empty():
		_load_item_definitions()
	_ensure_slot_capacity()
	if not _can_store_item(item_id, amount):
		return false
	var stack_limit: int = _stack_limit(item_id)
	var remaining: int = amount
	for index in range(items.size()):
		var entry: Dictionary = items[index]
		if entry.is_empty():
			continue
		var existing_id: String = String(entry.get("item_id", ""))
		if existing_id != item_id:
			continue
		var current_amount: int = int(entry.get("amount", 0))
		if current_amount >= stack_limit:
			continue
		var space: int = stack_limit - current_amount
		var add_amount: int = mini(space, remaining)
		entry["amount"] = current_amount + add_amount
		if not metadata.is_empty():
			var merged_metadata: Dictionary = _build_item_metadata(item_id, metadata)
			entry["metadata"] = merged_metadata
		items[index] = entry
		remaining -= add_amount
		if remaining <= 0:
			break
	while remaining > 0:
		var stack_amount: int = mini(remaining, stack_limit)
		var empty_slot_index: int = _find_first_empty_slot()
		if empty_slot_index < 0:
			return false
		items[empty_slot_index] = {
			"item_id": item_id,
			"amount": stack_amount,
			"metadata": _build_item_metadata(item_id, metadata)
		}
		remaining -= stack_amount
	inventory_changed.emit(items.duplicate(true))
	return true

func remove_item(item_id: String, amount: int = 1) -> bool:
	if item_id.is_empty() or amount <= 0:
		return false
	_ensure_slot_capacity()
	var total_available: int = _total_amount(item_id)
	if total_available < amount:
		return false
	var remaining: int = amount
	for index in range(items.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var entry: Dictionary = items[index]
		var existing_id: String = String(entry.get("item_id", ""))
		if existing_id != item_id:
			continue
		var current_amount: int = int(entry.get("amount", 0))
		var remove_amount: int = mini(current_amount, remaining)
		var next_amount: int = current_amount - remove_amount
		if next_amount <= 0:
			items[index] = {}
		else:
			entry["amount"] = next_amount
			items[index] = entry
		remaining -= remove_amount
	inventory_changed.emit(items.duplicate(true))
	return true

func overwrite_items(new_items: Array[Dictionary]) -> void:
	items.resize(max_slots)
	for slot_index in range(max_slots):
		items[slot_index] = {}
	var copy_count: int = mini(new_items.size(), max_slots)
	for slot_index in range(copy_count):
		var entry: Dictionary = new_items[slot_index]
		if entry.is_empty():
			items[slot_index] = {}
			continue
		items[slot_index] = entry.duplicate(true)
	inventory_changed.emit(items.duplicate(true))

func get_item_definition(item_id: String) -> Dictionary:
	if _item_definitions.is_empty():
		_load_item_definitions()
	var definition_variant: Variant = _item_definitions.get(item_id, {})
	if definition_variant is Dictionary:
		return Dictionary(definition_variant).duplicate(true)
	return {}

func _can_store_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	_ensure_slot_capacity()
	var stack_limit: int = _stack_limit(item_id)
	var free_capacity: int = 0
	for entry in items:
		if entry.is_empty():
			free_capacity += stack_limit
			continue
		var existing_id: String = String(entry.get("item_id", ""))
		if existing_id != item_id:
			continue
		var current_amount: int = int(entry.get("amount", 0))
		free_capacity += maxi(stack_limit - current_amount, 0)
	return free_capacity >= amount

func _stack_limit(item_id: String) -> int:
	var definition: Dictionary = get_item_definition(item_id)
	var stack_variant: Variant = definition.get("stack", 99)
	var stack: int = int(stack_variant)
	return clampi(stack, 1, MAX_STACK)

func _build_item_metadata(item_id: String, metadata: Dictionary) -> Dictionary:
	var result: Dictionary = metadata.duplicate(true)
	var definition: Dictionary = get_item_definition(item_id)
	var item_type_variant: Variant = definition.get("item_type", "")
	var tool_type_variant: Variant = definition.get("tool_type", "")
	if String(item_type_variant) != "":
		result["item_type"] = String(item_type_variant)
	if String(tool_type_variant) != "":
		result["tool_type"] = String(tool_type_variant)
	return result

func _total_amount(item_id: String) -> int:
	var total: int = 0
	for entry in items:
		if entry.is_empty():
			continue
		var existing_id: String = String(entry.get("item_id", ""))
		if existing_id != item_id:
			continue
		total += int(entry.get("amount", 0))
	return total

func _find_first_empty_slot() -> int:
	for index in range(items.size()):
		if items[index].is_empty():
			return index
	return -1

func _ensure_slot_capacity() -> void:
	if max_slots < 1:
		max_slots = 1
	if items.size() < max_slots:
		var missing: int = max_slots - items.size()
		for _i in range(missing):
			items.append({})
	elif items.size() > max_slots:
		items.resize(max_slots)

func _load_item_definitions() -> void:
	_item_definitions.clear()
	var parsed: Dictionary = JsonDataLoader.load_dictionary(ITEM_DB_PATH)
	if parsed.is_empty():
		return
	var items_variant: Variant = parsed.get("items", [])
	if not (items_variant is Array):
		return
	var definitions: Array = items_variant
	for definition_variant in definitions:
		if not (definition_variant is Dictionary):
			continue
		var definition: Dictionary = Dictionary(definition_variant)
		var id_variant: Variant = definition.get("id", "")
		var item_id: String = String(id_variant)
		if item_id.is_empty():
			continue
		_item_definitions[item_id] = definition.duplicate(true)
