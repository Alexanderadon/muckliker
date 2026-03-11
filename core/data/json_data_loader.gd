extends RefCounted
class_name JsonDataLoader

static func load_dictionary(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed_variant: Variant = JSON.parse_string(file.get_as_text())
	if parsed_variant is Dictionary:
		return Dictionary(parsed_variant)
	return {}

static func load_array(path: String) -> Array:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed_variant: Variant = JSON.parse_string(file.get_as_text())
	if parsed_variant is Array:
		return Array(parsed_variant)
	return []
