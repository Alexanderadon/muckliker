extends Node
class_name ResourceSystem

const RESOURCE_DATA_PATH: String = "res://data/resources/resource_types.json"
const DEFAULT_RESOURCE_DEFINITIONS: Dictionary = {
	"tree": {
		"required_tool": "axe",
		"drop_item_id": "wood",
		"drop_amount": 3,
		"drop_min_amount": 3,
		"drop_max_amount": 12,
		"drop_table": [
			{"item_id": "wood", "amount": 3}
		],
		"max_hp": 3.0,
		"mesh_kind": "cylinder",
		"radius": 0.42,
		"height": 2.3,
		"offset_y": 1.15,
		"color": Color(0.2, 0.67, 0.26, 1.0)
	},
	"rock": {
		"required_tool": "pickaxe",
		"drop_item_id": "stone",
		"drop_amount": 3,
		"drop_min_amount": 3,
		"drop_max_amount": 12,
		"drop_table": [
			{"item_id": "stone", "amount": 3}
		],
		"max_hp": 4.0,
		"mesh_kind": "sphere",
		"radius": 0.62,
		"height": 1.24,
		"offset_y": 0.62,
		"color": Color(0.53, 0.56, 0.61, 1.0)
	},
	"big_rock": {
		"required_tool": "pickaxe",
		"drop_item_id": "stone",
		"drop_amount": 3,
		"drop_min_amount": 3,
		"drop_max_amount": 12,
		"drop_table": [
			{"item_id": "stone", "amount": 3}
		],
		"max_hp": 8.0,
		"mesh_kind": "sphere",
		"radius": 1.0,
		"height": 2.0,
		"offset_y": 1.0,
		"color": Color(0.46, 0.49, 0.55, 1.0)
	}
}

const BASE_HAND_DAMAGE: float = 0.35
const CORRECT_TOOL_DAMAGE: float = 2.0
const WRONG_TOOL_DAMAGE: float = 0.2

var _resources_by_chunk: Dictionary = {}
var _resource_definitions: Dictionary = {}

func _ready() -> void:
	_load_resource_definitions()

func spawn_resource(chunk_root: Node3D, world_position: Vector3, resource_type: String, chunk_id: Vector2i) -> Node3D:
	if chunk_root == null:
		return null
	var definition: Dictionary = _get_resource_definition(resource_type)
	var resource_root: Node3D = Node3D.new()
	resource_root.name = "Resource_%s_%s_%s" % [resource_type, chunk_id.x, chunk_id.y]
	resource_root.add_to_group("resource")
	resource_root.set_meta("resource_type", resource_type)
	resource_root.set_meta("resource_id", resource_type)
	resource_root.set_meta("chunk_id", chunk_id)
	resource_root.set_meta("required_tool", String(definition.get("required_tool", "")))
	resource_root.set_meta("item_id", String(definition.get("drop_item_id", "wood")))
	resource_root.set_meta("amount", int(definition.get("drop_amount", 1)))
	resource_root.set_meta("drop_min_amount", int(definition.get("drop_min_amount", definition.get("drop_amount", 1))))
	resource_root.set_meta("drop_max_amount", int(definition.get("drop_max_amount", definition.get("drop_amount", 1))))
	resource_root.set_meta("drop_table", definition.get("drop_table", []).duplicate(true))
	resource_root.set_meta("hit_points", float(definition.get("max_hp", 1.0)))
	resource_root.set_meta("max_hit_points", float(definition.get("max_hp", 1.0)))
	chunk_root.add_child(resource_root)
	if resource_root.is_inside_tree():
		resource_root.global_position = world_position
	else:
		resource_root.position = world_position

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	body.set_meta("resource_root", resource_root)
	resource_root.add_child(body)

	var collider: CollisionShape3D = CollisionShape3D.new()
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = definition.get("color", Color(0.6, 0.6, 0.6, 1.0))
	material.roughness = 0.88

	var mesh_kind: String = String(definition.get("mesh_kind", "sphere"))
	var radius: float = float(definition.get("radius", 0.6))
	var height: float = float(definition.get("height", radius * 2.0))
	var offset_y: float = float(definition.get("offset_y", height * 0.5))
	body.position = Vector3(0.0, offset_y, 0.0)

	if mesh_kind == "cylinder":
		var shape: CylinderShape3D = CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		collider.shape = shape
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh_instance.mesh = mesh
	else:
		var sphere_shape: SphereShape3D = SphereShape3D.new()
		sphere_shape.radius = radius
		collider.shape = sphere_shape
		var sphere_mesh: SphereMesh = SphereMesh.new()
		sphere_mesh.radius = radius
		sphere_mesh.height = height
		mesh_instance.mesh = sphere_mesh

	mesh_instance.material_override = material
	body.add_child(collider)
	body.add_child(mesh_instance)

	if not _resources_by_chunk.has(chunk_id):
		_resources_by_chunk[chunk_id] = []
	var resources_variant: Variant = _resources_by_chunk[chunk_id]
	var resources: Array = resources_variant if resources_variant is Array else []
	resources.append(resource_root)
	_resources_by_chunk[chunk_id] = resources
	return resource_root

func on_chunk_unloaded(chunk_id: Vector2i) -> void:
	if _resources_by_chunk.has(chunk_id):
		_resources_by_chunk.erase(chunk_id)

func harvest_from_collider(collider: Object, harvester: Node, tool_context: Dictionary = {}) -> bool:
	var resource_root: Node3D = _resolve_resource_root(collider)
	if resource_root == null or not is_instance_valid(resource_root):
		return false
	var required_tool: String = String(resource_root.get_meta("required_tool", ""))
	var resource_id: String = String(resource_root.get_meta("resource_id", ""))
	var tool_id: String = _extract_tool_id(tool_context)
	var damage: float = _calculate_harvest_damage(resource_id, required_tool, tool_id)
	var current_hp: float = float(resource_root.get_meta("hit_points", 1.0))
	current_hp = maxf(current_hp - damage, 0.0)
	resource_root.set_meta("hit_points", current_hp)
	if current_hp > 0.0:
		return true
	var drop_table_variant: Variant = resource_root.get_meta("drop_table", [])
	var drop_table: Array = drop_table_variant if drop_table_variant is Array else []
	if drop_table.is_empty():
		drop_table = [{
			"item_id": String(resource_root.get_meta("item_id", "wood")),
			"amount": int(resource_root.get_meta("amount", 1))
		}]
	var default_min_amount: int = maxi(int(resource_root.get_meta("drop_min_amount", 1)), 1)
	var default_max_amount: int = int(resource_root.get_meta("drop_max_amount", default_min_amount))
	default_max_amount = maxi(default_max_amount, default_min_amount)
	var drop_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	drop_rng.seed = int(Time.get_ticks_usec()) ^ int(resource_root.get_instance_id())
	var resolved_drops: Array[Dictionary] = []
	for drop_variant in drop_table:
		if not (drop_variant is Dictionary):
			continue
		var drop: Dictionary = drop_variant
		var drop_item_id: String = String(drop.get("item_id", ""))
		if drop_item_id.is_empty():
			continue
		var min_amount: int = int(drop.get("min_amount", default_min_amount))
		var max_amount: int = int(drop.get("max_amount", default_max_amount))
		if max_amount < min_amount:
			var temp_amount: int = min_amount
			min_amount = max_amount
			max_amount = temp_amount
		min_amount = maxi(min_amount, 1)
		max_amount = maxi(max_amount, min_amount)
		var final_amount: int = drop_rng.randi_range(min_amount, max_amount)
		resolved_drops.append({
			"item_id": drop_item_id,
			"amount": final_amount
		})
	if resolved_drops.is_empty():
		resolved_drops.append({
			"item_id": String(resource_root.get_meta("item_id", "wood")),
			"amount": default_min_amount
		})
	var first_drop_variant: Variant = resolved_drops[0]
	var first_drop: Dictionary = first_drop_variant if first_drop_variant is Dictionary else {}
	var item_id: String = String(first_drop.get("item_id", "wood"))
	var amount: int = int(first_drop.get("amount", default_min_amount))
	EventBus.emit_game_event("resource_harvested", {
		"item_id": item_id,
		"amount": amount,
		"position": resource_root.global_position,
		"harvester": harvester,
		"resource_id": resource_id,
		"tool_id": tool_id
	})
	for drop_variant in resolved_drops:
		if not (drop_variant is Dictionary):
			continue
		var drop: Dictionary = drop_variant
		var drop_item_id: String = String(drop.get("item_id", ""))
		var drop_amount: int = int(drop.get("amount", 0))
		if drop_item_id.is_empty() or drop_amount <= 0:
			continue
		EventBus.emit_game_event("loot_spawn_requested", {
			"position": resource_root.global_position + Vector3(0.0, 0.6, 0.0),
			"item_id": drop_item_id,
			"amount": drop_amount
		})
	_unregister_resource(resource_root)
	resource_root.queue_free()
	return true

func _extract_tool_id(tool_context: Dictionary) -> String:
	var tool_id_variant: Variant = tool_context.get("tool_id", "")
	return String(tool_id_variant)

func _calculate_harvest_damage(resource_id: String, required_tool: String, tool_id: String) -> float:
	if required_tool.is_empty():
		return BASE_HAND_DAMAGE
	if tool_id == required_tool:
		if resource_id == "big_rock":
			return CORRECT_TOOL_DAMAGE + 0.5
		return CORRECT_TOOL_DAMAGE
	if tool_id.is_empty():
		return BASE_HAND_DAMAGE
	return WRONG_TOOL_DAMAGE

func _get_resource_definition(resource_type: String) -> Dictionary:
	if _resource_definitions.is_empty():
		_load_resource_definitions()
	var definition_variant: Variant = _resource_definitions.get(resource_type, {})
	if definition_variant is Dictionary:
		return Dictionary(definition_variant).duplicate(true)
	var fallback_variant: Variant = _resource_definitions.get("tree", {})
	if fallback_variant is Dictionary:
		return Dictionary(fallback_variant).duplicate(true)
	return {}

func _load_resource_definitions() -> void:
	_resource_definitions = DEFAULT_RESOURCE_DEFINITIONS.duplicate(true)
	var raw_definitions: Dictionary = JsonDataLoader.load_dictionary(RESOURCE_DATA_PATH)
	if raw_definitions.is_empty():
		return
	var parsed: Dictionary = {}
	for key_variant in raw_definitions.keys():
		var resource_id: String = String(key_variant)
		var entry_variant: Variant = raw_definitions[key_variant]
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = Dictionary(entry_variant).duplicate(true)
		var color_variant: Variant = entry.get("color", null)
		if color_variant != null:
			entry["color"] = _parse_color(color_variant, Color(0.6, 0.6, 0.6, 1.0))
		parsed[resource_id] = entry
	if parsed.is_empty():
		return
	_resource_definitions = parsed

func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var value_text: String = String(value)
	if value_text.is_empty():
		return fallback
	return Color.from_string(value_text, fallback)

func _resolve_resource_root(collider: Object) -> Node3D:
	if collider == null:
		return null
	if collider is Node:
		var node: Node = collider
		if node.is_in_group("resource") and node is Node3D:
			return node as Node3D
		if node.has_meta("resource_root"):
			var meta_root: Variant = node.get_meta("resource_root")
			if meta_root is Node3D:
				return meta_root as Node3D
		var parent: Node = node.get_parent()
		if parent is Node3D and parent.is_in_group("resource"):
			return parent as Node3D
	return null

func _unregister_resource(resource_root: Node3D) -> void:
	var chunk_id_variant: Variant = resource_root.get_meta("chunk_id", Vector2i.ZERO)
	var chunk_id: Vector2i = chunk_id_variant if chunk_id_variant is Vector2i else Vector2i.ZERO
	if not _resources_by_chunk.has(chunk_id):
		return
	var resources_variant: Variant = _resources_by_chunk[chunk_id]
	if not (resources_variant is Array):
		_resources_by_chunk.erase(chunk_id)
		return
	var resources: Array = resources_variant
	var index: int = resources.find(resource_root)
	if index >= 0:
		resources.remove_at(index)
	_resources_by_chunk[chunk_id] = resources
