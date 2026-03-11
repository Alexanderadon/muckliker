extends Node

signal inventory_changed(inventory_component: Node)

const ITEM_DB_PATH: String = "res://shared/items/item_db.json"
const MAX_SLOTS: int = 30
const HOTBAR_SLOTS: int = 8
const MAX_STACK: int = 64

var model: InventoryModel = InventoryModel.new(MAX_SLOTS, MAX_STACK)
var _item_definitions: Dictionary = {}
var _bound_inventory: InventoryComponent = null
var _is_syncing_bound_inventory: bool = false

func _ready() -> void:
	_load_item_definitions()
	_reset_model()

func bind_inventory(inventory_component: InventoryComponent) -> void:
	if _bound_inventory == inventory_component:
		return
	var callback: Callable = Callable(self, "_on_bound_inventory_changed")
	if _bound_inventory != null and _bound_inventory.inventory_changed.is_connected(callback):
		_bound_inventory.inventory_changed.disconnect(callback)
	_bound_inventory = inventory_component
	if _bound_inventory != null:
		if not _bound_inventory.inventory_changed.is_connected(callback):
			_bound_inventory.inventory_changed.connect(callback)
		_import_bound_inventory()
	else:
		_reset_model()
	_commit_slots_change()

func add_item(item_id: String, amount: int = 1) -> bool:
	var normalized_item_id: String = _normalize_item_id(item_id)
	if normalized_item_id.is_empty() or amount <= 0:
		return false
	if not _can_store_item(normalized_item_id, amount):
		return false
	var stack_limit: int = _stack_limit(normalized_item_id)
	var remaining: int = amount
	var hotbar_indices: Array[int] = _hotbar_indices()
	var inventory_indices: Array[int] = _inventory_indices()
	remaining = model.add_item_to_indices(normalized_item_id, remaining, stack_limit, hotbar_indices)
	remaining = model.add_item_to_indices(normalized_item_id, remaining, stack_limit, inventory_indices)
	if remaining > 0:
		return false
	_commit_slots_change()
	return true

func remove_item(item_id: String, amount: int = 1) -> bool:
	var normalized_item_id: String = _normalize_item_id(item_id)
	if normalized_item_id.is_empty() or amount <= 0:
		return false
	if not model.remove_item(normalized_item_id, amount):
		return false
	_commit_slots_change()
	return true

func remove_items(requirements: Dictionary) -> bool:
	if not _has_requirements(requirements):
		return false
	for item_id_variant in requirements.keys():
		var item_id: String = _normalize_item_id(String(item_id_variant))
		var amount: int = int(requirements[item_id_variant])
		if item_id.is_empty() or amount <= 0:
			continue
		var removed: bool = model.remove_item(item_id, amount)
		if not removed:
			return false
	_commit_slots_change()
	return true

func set_slot(slot_index: int, entry: Dictionary) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	var slot_data: Dictionary = _normalize_slot_dict(entry)
	var updated: bool = false
	if slot_data.is_empty():
		updated = model.set_slot(slot_index, null)
	else:
		var item_id: String = _normalize_item_id(String(slot_data.get("id", "")))
		var amount: int = int(slot_data.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			updated = model.set_slot(slot_index, null)
		else:
			var stack_limit: int = _stack_limit(item_id)
			var clamped_amount: int = clampi(amount, 1, stack_limit)
			var slot: InventoryModel.InventorySlot = InventoryModel.InventorySlot.new(item_id, clamped_amount)
			updated = model.set_slot(slot_index, slot)
	if not updated:
		return false
	_commit_slots_change()
	return true

func swap_slots(a: int, b: int) -> bool:
	if not model.swap_slots(a, b):
		return false
	_commit_slots_change()
	return true

func get_slot(slot_index: int) -> Dictionary:
	var slot: InventoryModel.InventorySlot = model.get_slot(slot_index)
	return _slot_to_dictionary(slot)

func extract_from_slot(slot_index: int, amount: int = 1) -> Dictionary:
	var extracted_slot: InventoryModel.InventorySlot = model.extract_from_slot(slot_index, amount)
	if extracted_slot == null:
		return {}
	_commit_slots_change()
	return _slot_to_dictionary(extracted_slot)

func get_slots_data() -> Array[Variant]:
	return model.to_dictionary_array()

func get_inventory_data() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_variant in model.to_dictionary_array():
		if not (slot_variant is Dictionary):
			result.append({})
			continue
		var slot_entry: Dictionary = Dictionary(slot_variant)
		var item_id: String = _normalize_item_id(String(slot_entry.get("id", "")))
		var amount: int = int(slot_entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			result.append({})
			continue
		var entry: Dictionary = {
			"item_id": item_id,
			"amount": amount
		}
		var metadata: Dictionary = _default_item_metadata(item_id)
		if not metadata.is_empty():
			entry["metadata"] = metadata
		result.append(entry)
	return result

func get_item_count(item_id: String) -> int:
	var normalized_item_id: String = _normalize_item_id(item_id)
	if normalized_item_id.is_empty():
		return 0
	return model.get_item_count(normalized_item_id)

func can_craft(recipe: Dictionary) -> bool:
	var requirements: Dictionary = _recipe_requirements(recipe)
	return _has_requirements(requirements)

func craft(recipe: Dictionary) -> bool:
	var requirements: Dictionary = _recipe_requirements(recipe)
	var output: Dictionary = _recipe_output(recipe)
	var output_item_id: String = _normalize_item_id(String(output.get("item_id", "")))
	var output_amount: int = int(output.get("amount", 0))
	if requirements.is_empty() or output_item_id.is_empty() or output_amount <= 0:
		return false
	if not _has_requirements(requirements):
		return false
	var removed_entries: Array[Dictionary] = []
	for item_id_variant in requirements.keys():
		var item_id: String = _normalize_item_id(String(item_id_variant))
		var amount: int = int(requirements[item_id_variant])
		if item_id.is_empty() or amount <= 0:
			continue
		if not model.remove_item(item_id, amount):
			_rollback_removed_entries(removed_entries)
			return false
		removed_entries.append({
			"id": item_id,
			"amount": amount
		})
	var output_stack_limit: int = _stack_limit(output_item_id)
	var remaining: int = model.add_item_to_indices(output_item_id, output_amount, output_stack_limit, _hotbar_indices())
	remaining = model.add_item_to_indices(output_item_id, remaining, output_stack_limit, _inventory_indices())
	if remaining > 0:
		_rollback_removed_entries(removed_entries)
		return false
	_commit_slots_change()
	return true

func notify_inventory_changed(inventory_component: InventoryComponent) -> void:
	if inventory_component != null and _bound_inventory == null:
		bind_inventory(inventory_component)
		return
	if inventory_component != null and inventory_component == _bound_inventory:
		_import_bound_inventory()
	_commit_slots_change()

func get_item_definition(item_id: String) -> Dictionary:
	if _item_definitions.is_empty():
		_load_item_definitions()
	var normalized_item_id: String = _normalize_item_id(item_id)
	var definition_variant: Variant = _item_definitions.get(normalized_item_id, {})
	if definition_variant is Dictionary:
		return Dictionary(definition_variant).duplicate(true)
	return {}

func get_item_label(item_id: String) -> String:
	var definition: Dictionary = get_item_definition(item_id)
	var label_variant: Variant = definition.get("display_name", "")
	var label: String = String(label_variant)
	if not label.is_empty():
		return label
	return String(item_id).capitalize()

func get_item_ui_color(item_id: String) -> Color:
	var definition: Dictionary = get_item_definition(item_id)
	var color_variant: Variant = definition.get("ui_color", "#A0A0A0")
	var color_hex: String = String(color_variant)
	return Color.from_string(color_hex, Color(0.63, 0.63, 0.63, 1.0))

func _reset_model() -> void:
	model = InventoryModel.new(MAX_SLOTS, MAX_STACK)

func _slot_to_dictionary(slot: InventoryModel.InventorySlot) -> Dictionary:
	if slot == null or slot.is_empty():
		return {}
	var item_id: String = _normalize_item_id(slot.id)
	var amount: int = int(slot.amount)
	if item_id.is_empty() or amount <= 0:
		return {}
	var result: Dictionary = {
		"id": item_id,
		"item_id": item_id,
		"amount": amount
	}
	var metadata: Dictionary = _default_item_metadata(item_id)
	if not metadata.is_empty():
		result["metadata"] = metadata
	return result

func _normalize_slot_dict(entry: Dictionary) -> Dictionary:
	if entry.is_empty():
		return {}
	var item_id: String = _normalize_item_id(String(entry.get("id", entry.get("item_id", ""))))
	var amount: int = int(entry.get("amount", 0))
	if item_id.is_empty() or amount <= 0:
		return {}
	return {
		"id": item_id,
		"amount": amount
	}

func _normalize_item_id(item_id: String) -> String:
	return item_id.strip_edges().to_lower()

func _stack_limit(item_id: String) -> int:
	var definition: Dictionary = get_item_definition(item_id)
	var stack_variant: Variant = definition.get("stack", MAX_STACK)
	var stack_limit: int = int(stack_variant)
	return clampi(stack_limit, 1, MAX_STACK)

func _can_store_item(item_id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	var stack_limit: int = _stack_limit(item_id)
	var capacity: int = 0
	for slot_index in range(MAX_SLOTS):
		var slot: InventoryModel.InventorySlot = model.get_slot(slot_index)
		if slot == null or slot.is_empty():
			capacity += stack_limit
			continue
		if _normalize_item_id(slot.id) != item_id:
			continue
		capacity += maxi(stack_limit - slot.amount, 0)
	return capacity >= amount

func _hotbar_indices() -> Array[int]:
	var result: Array[int] = []
	var count: int = mini(HOTBAR_SLOTS, MAX_SLOTS)
	for index in range(count):
		result.append(index)
	return result

func _inventory_indices() -> Array[int]:
	var result: Array[int] = []
	var start_index: int = mini(HOTBAR_SLOTS, MAX_SLOTS)
	for index in range(start_index, MAX_SLOTS):
		result.append(index)
	return result

func _has_requirements(requirements: Dictionary) -> bool:
	if requirements.is_empty():
		return false
	for item_id_variant in requirements.keys():
		var item_id: String = _normalize_item_id(String(item_id_variant))
		var needed: int = int(requirements[item_id_variant])
		if item_id.is_empty() or needed <= 0:
			continue
		if get_item_count(item_id) < needed:
			return false
	return true

func _recipe_requirements(recipe: Dictionary) -> Dictionary:
	var requirements_variant: Variant = recipe.get("requires", {})
	if requirements_variant is Dictionary:
		return Dictionary(requirements_variant)
	return {}

func _recipe_output(recipe: Dictionary) -> Dictionary:
	var output_variant: Variant = recipe.get("output", {})
	if output_variant is Dictionary:
		return Dictionary(output_variant)
	return {}

func _rollback_removed_entries(removed_entries: Array[Dictionary]) -> void:
	for removed_entry in removed_entries:
		var item_id: String = _normalize_item_id(String(removed_entry.get("id", "")))
		var amount: int = int(removed_entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		var stack_limit: int = _stack_limit(item_id)
		var remaining: int = model.add_item_to_indices(item_id, amount, stack_limit, _hotbar_indices())
		remaining = model.add_item_to_indices(item_id, remaining, stack_limit, _inventory_indices())
		if remaining > 0:
			push_warning("Inventory rollback overflow for item: %s" % item_id)

func _default_item_metadata(item_id: String) -> Dictionary:
	var definition: Dictionary = get_item_definition(item_id)
	if definition.is_empty():
		return {}
	var metadata: Dictionary = {}
	var item_type_variant: Variant = definition.get("item_type", "")
	var tool_type_variant: Variant = definition.get("tool_type", "")
	var item_type: String = String(item_type_variant)
	var tool_type: String = String(tool_type_variant)
	if not item_type.is_empty():
		metadata["item_type"] = item_type
	if not tool_type.is_empty():
		metadata["tool_type"] = tool_type
	return metadata

func _commit_slots_change() -> void:
	_sanitize_model_stacks()
	_sync_slots_to_bound_inventory()
	_sync_resource_store_from_slots()
	inventory_changed.emit(_bound_inventory)

func _sanitize_model_stacks() -> void:
	for slot_index in range(MAX_SLOTS):
		var slot: InventoryModel.InventorySlot = model.get_slot(slot_index)
		if slot == null or slot.is_empty():
			continue
		var item_id: String = _normalize_item_id(slot.id)
		if item_id.is_empty():
			model.set_slot(slot_index, null)
			continue
		var stack_limit: int = _stack_limit(item_id)
		var clamped_amount: int = clampi(int(slot.amount), 1, stack_limit)
		if item_id == slot.id and clamped_amount == int(slot.amount):
			continue
		model.set_slot(slot_index, InventoryModel.InventorySlot.new(item_id, clamped_amount))

func _import_bound_inventory() -> void:
	_reset_model()
	if _bound_inventory == null:
		return
	var source_items: Array[Dictionary] = _bound_inventory.items
	var source_as_variant: Array[Variant] = []
	for entry in source_items:
		source_as_variant.append(entry)
	model.from_dictionary_array(source_as_variant)

func _sync_slots_to_bound_inventory() -> void:
	if _bound_inventory == null:
		return
	var normalized_items: Array[Dictionary] = []
	for slot_index in range(MAX_SLOTS):
		var slot: InventoryModel.InventorySlot = model.get_slot(slot_index)
		if slot == null or slot.is_empty():
			normalized_items.append({})
			continue
		var item_id: String = _normalize_item_id(slot.id)
		var amount: int = int(slot.amount)
		if item_id.is_empty() or amount <= 0:
			normalized_items.append({})
			continue
		var entry: Dictionary = {
			"item_id": item_id,
			"amount": amount
		}
		var metadata: Dictionary = _default_item_metadata(item_id)
		if not metadata.is_empty():
			entry["metadata"] = metadata
		normalized_items.append(entry)
	_is_syncing_bound_inventory = true
	if _bound_inventory.has_method("overwrite_items"):
		_bound_inventory.call("overwrite_items", normalized_items)
	else:
		_bound_inventory.items = normalized_items
		if _bound_inventory.has_signal("inventory_changed"):
			_bound_inventory.emit_signal("inventory_changed", _bound_inventory.items.duplicate(true))
	_is_syncing_bound_inventory = false

func _load_item_definitions() -> void:
	_item_definitions.clear()
	var parsed: Dictionary = JsonDataLoader.load_dictionary(ITEM_DB_PATH)
	if parsed.is_empty():
		return
	var items_variant: Variant = parsed.get("items", [])
	if not (items_variant is Array):
		return
	var items: Array = items_variant
	for item_variant in items:
		if not (item_variant is Dictionary):
			continue
		var item_entry: Dictionary = Dictionary(item_variant)
		var item_id: String = _normalize_item_id(String(item_entry.get("id", "")))
		if item_id.is_empty():
			continue
		_item_definitions[item_id] = item_entry.duplicate(true)

func _on_bound_inventory_changed(_items: Array) -> void:
	if _is_syncing_bound_inventory:
		return
	_import_bound_inventory()
	inventory_changed.emit(_bound_inventory)

func _sync_resource_store_from_slots() -> void:
	var resource_store: Node = get_node_or_null("/root/ResourceStore")
	if resource_store == null or not resource_store.has_method("replace_all"):
		return
	var totals: Dictionary = {}
	for slot_index in range(MAX_SLOTS):
		var slot: InventoryModel.InventorySlot = model.get_slot(slot_index)
		if slot == null or slot.is_empty():
			continue
		var item_id: String = _normalize_item_id(slot.id)
		if item_id.is_empty() or not _is_resource_item(item_id):
			continue
		var current_total: int = int(totals.get(item_id, 0))
		totals[item_id] = current_total + int(slot.amount)
	resource_store.call("replace_all", totals)

func _is_resource_item(item_id: String) -> bool:
	var definition: Dictionary = get_item_definition(item_id)
	var item_type_variant: Variant = definition.get("item_type", "")
	var item_type: String = String(item_type_variant).to_lower()
	return item_type == "resource"
