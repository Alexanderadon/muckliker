extends RefCounted
class_name InventoryModel

class InventorySlot:
	var id: String = ""
	var amount: int = 0

	func _init(item_id: String = "", item_amount: int = 0) -> void:
		id = item_id
		amount = item_amount

	func is_empty() -> bool:
		return id.is_empty() or amount <= 0

	func duplicate_slot() -> InventorySlot:
		return InventorySlot.new(id, amount)

var max_stack: int = 64
var slot_count: int = 30
var slots: Array[Variant] = []

func _init(initial_slot_count: int = 30, initial_max_stack: int = 64) -> void:
	slot_count = maxi(initial_slot_count, 1)
	max_stack = maxi(initial_max_stack, 1)
	_reset_slots()

func clear() -> void:
	_reset_slots()

func get_slot(slot_index: int) -> InventorySlot:
	if slot_index < 0 or slot_index >= slots.size():
		return null
	var slot_variant: Variant = slots[slot_index]
	if slot_variant is InventorySlot:
		var slot: InventorySlot = slot_variant as InventorySlot
		return slot.duplicate_slot()
	return null

func set_slot(slot_index: int, slot: InventorySlot) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false
	if slot == null or slot.is_empty():
		slots[slot_index] = null
	else:
		slots[slot_index] = slot.duplicate_slot()
	return true

func swap_slots(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= slots.size() or b >= slots.size():
		return false
	if a == b:
		return true
	var temp: Variant = slots[a]
	slots[a] = slots[b]
	slots[b] = temp
	return true

func get_item_count(item_id: String) -> int:
	var normalized_id: String = item_id.strip_edges().to_lower()
	if normalized_id.is_empty():
		return 0
	var total: int = 0
	for slot_variant in slots:
		if not (slot_variant is InventorySlot):
			continue
		var slot: InventorySlot = slot_variant as InventorySlot
		if slot == null or slot.is_empty():
			continue
		if slot.id != normalized_id:
			continue
		total += slot.amount
	return total

func add_item_to_indices(item_id: String, amount: int, stack_limit: int, indices: Array[int]) -> int:
	var normalized_id: String = item_id.strip_edges().to_lower()
	var normalized_stack_limit: int = maxi(stack_limit, 1)
	var remaining: int = maxi(amount, 0)
	if normalized_id.is_empty() or remaining <= 0:
		return 0
	remaining = _fill_existing_stacks(normalized_id, remaining, normalized_stack_limit, indices)
	remaining = _fill_empty_slots(normalized_id, remaining, normalized_stack_limit, indices)
	return remaining

func remove_item(item_id: String, amount: int) -> bool:
	var normalized_id: String = item_id.strip_edges().to_lower()
	var remaining: int = maxi(amount, 0)
	if normalized_id.is_empty() or remaining <= 0:
		return false
	if get_item_count(normalized_id) < remaining:
		return false
	for index in range(slots.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var slot_variant: Variant = slots[index]
		if not (slot_variant is InventorySlot):
			continue
		var slot: InventorySlot = slot_variant as InventorySlot
		if slot == null or slot.is_empty():
			continue
		if slot.id != normalized_id:
			continue
		var remove_amount: int = mini(slot.amount, remaining)
		var next_amount: int = slot.amount - remove_amount
		if next_amount <= 0:
			slots[index] = null
		else:
			slots[index] = InventorySlot.new(slot.id, next_amount)
		remaining -= remove_amount
	return remaining <= 0

func extract_from_slot(slot_index: int, amount: int) -> InventorySlot:
	if slot_index < 0 or slot_index >= slots.size():
		return null
	var take_amount: int = maxi(amount, 0)
	if take_amount <= 0:
		return null
	var slot_variant: Variant = slots[slot_index]
	if not (slot_variant is InventorySlot):
		return null
	var slot: InventorySlot = slot_variant as InventorySlot
	if slot == null or slot.is_empty():
		return null
	var extracted_amount: int = mini(slot.amount, take_amount)
	var remaining_amount: int = slot.amount - extracted_amount
	if remaining_amount <= 0:
		slots[slot_index] = null
	else:
		slots[slot_index] = InventorySlot.new(slot.id, remaining_amount)
	return InventorySlot.new(slot.id, extracted_amount)

func to_dictionary_array() -> Array[Variant]:
	var result: Array[Variant] = []
	for slot_variant in slots:
		if not (slot_variant is InventorySlot):
			result.append(null)
			continue
		var slot: InventorySlot = slot_variant as InventorySlot
		if slot == null or slot.is_empty():
			result.append(null)
			continue
		result.append({
			"id": slot.id,
			"amount": slot.amount
		})
	return result

func from_dictionary_array(data: Array[Variant]) -> void:
	_reset_slots()
	var copy_count: int = mini(data.size(), slots.size())
	for index in range(copy_count):
		var entry_variant: Variant = data[index]
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		var item_id: String = String(entry.get("id", entry.get("item_id", ""))).strip_edges().to_lower()
		var amount: int = int(entry.get("amount", 0))
		if item_id.is_empty() or amount <= 0:
			continue
		var clamped_amount: int = clampi(amount, 1, max_stack)
		slots[index] = InventorySlot.new(item_id, clamped_amount)

func _reset_slots() -> void:
	slots.clear()
	for _i in range(slot_count):
		slots.append(null)

func _fill_existing_stacks(item_id: String, amount: int, stack_limit: int, indices: Array[int]) -> int:
	var remaining: int = amount
	for index in indices:
		if remaining <= 0:
			break
		if index < 0 or index >= slots.size():
			continue
		var slot_variant: Variant = slots[index]
		if not (slot_variant is InventorySlot):
			continue
		var slot: InventorySlot = slot_variant as InventorySlot
		if slot == null or slot.is_empty():
			continue
		if slot.id != item_id:
			continue
		if slot.amount >= stack_limit:
			continue
		var free_space: int = stack_limit - slot.amount
		var add_amount: int = mini(free_space, remaining)
		slots[index] = InventorySlot.new(item_id, slot.amount + add_amount)
		remaining -= add_amount
	return remaining

func _fill_empty_slots(item_id: String, amount: int, stack_limit: int, indices: Array[int]) -> int:
	var remaining: int = amount
	for index in indices:
		if remaining <= 0:
			break
		if index < 0 or index >= slots.size():
			continue
		var slot_variant: Variant = slots[index]
		if slot_variant != null:
			continue
		var stack_amount: int = mini(remaining, stack_limit)
		slots[index] = InventorySlot.new(item_id, stack_amount)
		remaining -= stack_amount
	return remaining
