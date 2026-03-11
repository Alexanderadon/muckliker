extends RefCounted
class_name ObjectPool

var _objects: Array = []
var _is_active_callable: Callable = Callable()

func setup(objects: Array, is_active_callable: Callable) -> void:
	_objects = objects
	_is_active_callable = is_active_callable

func acquire() -> Node:
	for object_variant in _objects:
		if not (object_variant is Node):
			continue
		var node: Node = object_variant
		if not is_instance_valid(node):
			continue
		if _is_active(node):
			continue
		return node
	return null

func all() -> Array:
	return _objects

func _is_active(node: Node) -> bool:
	if _is_active_callable.is_valid():
		return bool(_is_active_callable.call(node))
	if node.has_meta("active"):
		return bool(node.get_meta("active", false))
	return false
