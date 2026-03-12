extends RefCounted
class_name ChunkData

enum TotemState {
	UNSET,
	NONE,
	SPAWNED,
	COMPLETED
}

var chunk_id: Vector2i = Vector2i.ZERO
var seed: int = 0
var totem_state: TotemState = TotemState.UNSET
var totem_position: Vector3 = Vector3.ZERO
var has_runtime_changes: bool = false
var last_touched_usec: int = 0

func touch() -> void:
	last_touched_usec = Time.get_ticks_usec()

func set_totem_spawned(position: Vector3) -> void:
	totem_state = TotemState.SPAWNED
	totem_position = position
	touch()

func set_totem_completed() -> void:
	totem_state = TotemState.COMPLETED
	has_runtime_changes = true
	touch()

func set_totem_none() -> void:
	totem_state = TotemState.NONE
	totem_position = Vector3.ZERO
	touch()
