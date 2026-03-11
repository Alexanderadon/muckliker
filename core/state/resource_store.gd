extends Node

signal resource_changed(resource_id: String, amount: int)
signal resources_changed(snapshot: Dictionary)

var _amounts: Dictionary = {}

func get_amount(resource_id: String) -> int:
	var normalized_id: String = resource_id.strip_edges().to_lower()
	if normalized_id.is_empty():
		return 0
	return maxi(int(_amounts.get(normalized_id, 0)), 0)

func add(resource_id: String, amount: int = 1) -> int:
	var normalized_id: String = resource_id.strip_edges().to_lower()
	if normalized_id.is_empty() or amount <= 0:
		return get_amount(normalized_id)
	var next_amount: int = get_amount(normalized_id) + amount
	_amounts[normalized_id] = next_amount
	resource_changed.emit(normalized_id, next_amount)
	resources_changed.emit(_amounts.duplicate(true))
	return next_amount

func remove(resource_id: String, amount: int = 1) -> bool:
	var normalized_id: String = resource_id.strip_edges().to_lower()
	if normalized_id.is_empty() or amount <= 0:
		return false
	var current_amount: int = get_amount(normalized_id)
	if current_amount < amount:
		return false
	var next_amount: int = current_amount - amount
	if next_amount <= 0:
		_amounts.erase(normalized_id)
		next_amount = 0
	else:
		_amounts[normalized_id] = next_amount
	resource_changed.emit(normalized_id, next_amount)
	resources_changed.emit(_amounts.duplicate(true))
	return true

func has(resource_id: String, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	return get_amount(resource_id) >= amount

func replace_all(resource_amounts: Dictionary) -> void:
	_amounts.clear()
	for key_variant in resource_amounts.keys():
		var resource_id: String = String(key_variant).strip_edges().to_lower()
		if resource_id.is_empty():
			continue
		var value: int = maxi(int(resource_amounts.get(key_variant, 0)), 0)
		if value <= 0:
			continue
		_amounts[resource_id] = value
	resources_changed.emit(_amounts.duplicate(true))

func get_snapshot() -> Dictionary:
	return _amounts.duplicate(true)
