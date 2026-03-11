extends Node
class_name LootSystem

@export var loot_scene: PackedScene

func _ready() -> void:
	EventBus.game_event.connect(_on_event)

func _on_event(event_name: String, payload: Dictionary) -> void:
	if event_name != "loot_spawn_requested":
		return
	var pos_variant: Variant = payload.get("position", Vector3.ZERO)
	var pos: Vector3 = pos_variant if pos_variant is Vector3 else Vector3.ZERO
	if loot_scene == null:
		return
	var loot_variant: Variant = loot_scene.instantiate()
	var loot: Node3D = loot_variant as Node3D
	if loot != null:
		loot.global_position = pos
		get_tree().current_scene.add_child(loot)
