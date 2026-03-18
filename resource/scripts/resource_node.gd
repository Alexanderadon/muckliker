extends Node3D
class_name ResourceNode

const DEBUG_RESOURCE_NODE: bool = false

signal depleted(resource: ResourceNode, harvester: Node, drops: Array, interaction_position: Vector3, tool_id: String)

@export var resource_id: String = "resource"
@export var required_tool: String = ""
@export var item_id: String = "wood"
@export var amount: int = 1
@export var drop_min_amount: int = 1
@export var drop_max_amount: int = 1
@export var max_health: float = 1.0
@export var destroy_on_depletion: bool = true
@export var health_component_path: NodePath = NodePath("HealthComponent")
@export var drop_origin_path: NodePath = NodePath("DropOrigin")

var chunk_id: Vector2i = Vector2i.ZERO
var drop_table: Array = []

var _current_health: float = 1.0
var _is_depleted: bool = false
var _resource_system: Node = null

func _ready() -> void:
	max_health = maxf(max_health, 0.1)
	if _current_health <= 0.0 or _current_health > max_health:
		_current_health = max_health
	_ensure_health_component_node()
	_apply_runtime_metadata()

func bind_resource_system(resource_system: Node) -> void:
	_resource_system = resource_system
	set_meta("resource_system", resource_system)

func configure_from_definition(resource_type: String, resource_chunk_id: Vector2i, definition: Dictionary) -> void:
	resource_id = resource_type
	chunk_id = resource_chunk_id
	required_tool = String(definition.get("required_tool", ""))
	item_id = String(definition.get("drop_item_id", item_id))
	amount = maxi(int(definition.get("drop_amount", amount)), 1)
	drop_min_amount = maxi(int(definition.get("drop_min_amount", amount)), 1)
	drop_max_amount = maxi(int(definition.get("drop_max_amount", drop_min_amount)), drop_min_amount)
	max_health = maxf(float(definition.get("max_hp", max_health)), 0.1)
	_current_health = max_health
	drop_table = _normalize_drop_table(definition.get("drop_table", []))
	_is_depleted = false
	_ensure_health_component_node()
	_apply_runtime_metadata()
	_debug_log("configured resource_id=%s chunk_id=%s max_health=%s drop_table=%s" % [resource_id, str(chunk_id), str(max_health), str(drop_table)])

func apply_resource_damage(damage: float, harvester: Node, tool_id: String, interaction_position: Vector3) -> bool:
	if _is_depleted:
		_debug_log("apply_resource_damage ignored: already depleted")
		return true
	if damage <= 0.0:
		_debug_log("apply_resource_damage ignored: non_positive damage=%s" % str(damage))
		return true
	var before_health: float = _current_health
	_current_health = maxf(_current_health - damage, 0.0)
	_debug_log(
		"apply_resource_damage damage=%s tool_id=%s hp_before=%s hp_after=%s harvester=%s interaction_position=%s" % [
			str(damage),
			tool_id,
			str(before_health),
			str(_current_health),
			_describe_node(harvester),
			str(interaction_position)
		]
	)
	_sync_health_component(true)
	set_meta("hit_points", _current_health)
	if _current_health > 0.0:
		return true
	_deplete_resource(harvester, tool_id, interaction_position)
	return true

func resolve_interaction_position(collider: Object = null) -> Vector3:
	var drop_origin: Node3D = _resolve_drop_origin()
	if drop_origin != null and is_instance_valid(drop_origin):
		return drop_origin.global_position
	if collider is Node3D:
		var collider_3d: Node3D = collider as Node3D
		if collider_3d != null and is_instance_valid(collider_3d):
			return collider_3d.global_position
	return global_position

func get_current_health() -> float:
	return _current_health

func _deplete_resource(harvester: Node, tool_id: String, interaction_position: Vector3) -> void:
	if _is_depleted:
		return
	_is_depleted = true
	_debug_log(
		"_deplete_resource harvester=%s tool_id=%s interaction_position=%s" % [
			_describe_node(harvester),
			tool_id,
			str(interaction_position)
		]
	)
	var health_component: HealthComponent = _get_health_component()
	if health_component != null:
		health_component.died.emit(self)
	var resolved_drops: Array = _resolve_drop_entries()
	var first_drop: Dictionary = resolved_drops[0] if not resolved_drops.is_empty() else {}
	EventBus.emit_game_event("resource_harvested", {
		"item_id": String(first_drop.get("item_id", item_id)),
		"amount": int(first_drop.get("amount", amount)),
		"position": interaction_position,
		"harvester": harvester,
		"resource_id": resource_id,
		"tool_id": tool_id,
		"drops": resolved_drops
	})
	for drop_variant in resolved_drops:
		if not (drop_variant is Dictionary):
			continue
		var drop: Dictionary = drop_variant
		var drop_item_id: String = String(drop.get("item_id", ""))
		var drop_amount: int = int(drop.get("amount", 0))
		if drop_item_id.is_empty() or drop_amount <= 0:
			continue
		_debug_log("emitting loot_spawn_requested item_id=%s amount=%d position=%s" % [drop_item_id, drop_amount, str(interaction_position + Vector3(0.0, 0.6, 0.0))])
		EventBus.emit_game_event("loot_spawn_requested", {
			"position": interaction_position + Vector3(0.0, 0.6, 0.0),
			"item_id": drop_item_id,
			"amount": drop_amount
		})
	depleted.emit(self, harvester, resolved_drops, interaction_position, tool_id)
	_unregister_from_resource_system()
	if destroy_on_depletion:
		queue_free()
		return
	_disable_resource_after_depletion()

func _disable_resource_after_depletion() -> void:
	visible = false
	for node_variant in _collect_tree_nodes():
		var node: Node = node_variant as Node
		if node == null:
			continue
		if node is CollisionShape3D:
			var collision_shape: CollisionShape3D = node as CollisionShape3D
			collision_shape.disabled = true
		elif node is CollisionObject3D:
			var collision_object: CollisionObject3D = node as CollisionObject3D
			collision_object.process_mode = Node.PROCESS_MODE_DISABLED

func _resolve_drop_entries() -> Array:
	if drop_table.is_empty():
		return [{
			"item_id": item_id,
			"amount": maxi(amount, 1)
		}]
	var default_min_amount: int = maxi(drop_min_amount, 1)
	var default_max_amount: int = maxi(drop_max_amount, default_min_amount)
	var drop_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	drop_rng.seed = int(Time.get_ticks_usec()) ^ int(get_instance_id())
	var resolved: Array = []
	for drop_variant in drop_table:
		if not (drop_variant is Dictionary):
			continue
		var drop: Dictionary = drop_variant
		var drop_item_id: String = String(drop.get("item_id", ""))
		if drop_item_id.is_empty():
			continue
		var explicit_amount: int = int(drop.get("amount", -1))
		var min_amount: int = maxi(int(drop.get("min_amount", default_min_amount)), 1)
		var max_amount: int = maxi(int(drop.get("max_amount", default_max_amount)), min_amount)
		var final_amount: int = explicit_amount if explicit_amount > 0 else drop_rng.randi_range(min_amount, max_amount)
		resolved.append({
			"item_id": drop_item_id,
			"amount": final_amount
		})
	if resolved.is_empty():
		resolved.append({
			"item_id": item_id,
			"amount": default_min_amount
		})
	return resolved

func _normalize_drop_table(value: Variant) -> Array:
	var normalized: Array = []
	if not (value is Array):
		return normalized
	var source: Array = value
	for entry_variant in source:
		if not (entry_variant is Dictionary):
			continue
		normalized.append(Dictionary(entry_variant).duplicate(true))
	return normalized

func _apply_runtime_metadata() -> void:
	add_to_group("resource")
	set_meta("resource_type", resource_id)
	set_meta("resource_id", resource_id)
	set_meta("chunk_id", chunk_id)
	set_meta("required_tool", required_tool)
	set_meta("item_id", item_id)
	set_meta("amount", amount)
	set_meta("drop_min_amount", drop_min_amount)
	set_meta("drop_max_amount", drop_max_amount)
	set_meta("drop_table", drop_table.duplicate(true))
	set_meta("max_hit_points", max_health)
	set_meta("hit_points", _current_health)
	set_meta("resource_root", self)
	var drop_origin: Node3D = _resolve_drop_origin()
	if drop_origin != null:
		set_meta("drop_origin_path", get_path_to(drop_origin))
	_bind_resource_hierarchy()

func _ensure_health_component_node() -> void:
	var health_component: HealthComponent = _get_health_component()
	if health_component == null:
		health_component = HealthComponent.new()
		health_component.name = "HealthComponent"
		add_child(health_component)
		health_component_path = get_path_to(health_component)
	health_component.max_health = max_health
	health_component.current_health = _current_health

func _sync_health_component(emit_changed: bool) -> void:
	var health_component: HealthComponent = _get_health_component()
	if health_component == null:
		return
	health_component.max_health = max_health
	health_component.current_health = _current_health
	if emit_changed:
		health_component.health_changed.emit(_current_health, max_health)

func _get_health_component() -> HealthComponent:
	var by_path: HealthComponent = get_node_or_null(health_component_path) as HealthComponent
	if by_path != null:
		return by_path
	return get_node_or_null("HealthComponent") as HealthComponent

func _resolve_drop_origin() -> Node3D:
	var by_path: Node3D = get_node_or_null(drop_origin_path) as Node3D
	if by_path != null:
		return by_path
	for node_variant in _collect_tree_nodes():
		var node_3d: Node3D = node_variant as Node3D
		if node_3d == null:
			continue
		var lowered_name: String = String(node_3d.name).to_lower()
		if node_3d.is_in_group("resource_drop_origin") or lowered_name == "droporigin" or lowered_name == "drop_origin" or lowered_name == "lootorigin":
			return node_3d
	return null

func _bind_resource_hierarchy() -> void:
	for node_variant in _collect_tree_nodes():
		var node: Node = node_variant as Node
		if node == null:
			continue
		node.set_meta("resource_root", self)

func _collect_tree_nodes() -> Array:
	var nodes: Array = []
	var stack: Array = [self]
	while not stack.is_empty():
		var current_variant: Variant = stack.pop_back()
		var current: Node = current_variant as Node
		if current == null:
			continue
		nodes.append(current)
		for child_variant in current.get_children():
			var child: Node = child_variant as Node
			if child != null:
				stack.append(child)
	return nodes

func _unregister_from_resource_system() -> void:
	if _resource_system == null or not is_instance_valid(_resource_system):
		var meta_system: Node = get_meta("resource_system", null) as Node
		if meta_system != null and is_instance_valid(meta_system):
			_resource_system = meta_system
	if _resource_system != null and is_instance_valid(_resource_system) and _resource_system.has_method("unregister_resource_node"):
		_resource_system.call("unregister_resource_node", self)

func _debug_log(message: String) -> void:
	if not DEBUG_RESOURCE_NODE:
		return
	print("[ResourceNode:", name, "] ", message)

func _describe_node(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "null"
	return "%s(name=%s,path=%s)" % [
		node.get_class(),
		node.name,
		String(node.get_path()) if node.is_inside_tree() else "<not_in_tree>"
	]
