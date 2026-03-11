extends RefCounted
class_name ChunkMath

static func chunk_id_from_position(world_position: Vector3, chunk_size: int) -> Vector2i:
	var size_value: float = maxf(float(chunk_size), 1.0)
	return Vector2i(
		int(floor(world_position.x / size_value)),
		int(floor(world_position.z / size_value))
	)

static func build_required_chunks(center_chunk: Vector2i, view_distance_chunks: int) -> Array[Vector2i]:
	var required_chunks: Array[Vector2i] = []
	for x in range(center_chunk.x - view_distance_chunks, center_chunk.x + view_distance_chunks + 1):
		for z in range(center_chunk.y - view_distance_chunks, center_chunk.y + view_distance_chunks + 1):
			required_chunks.append(Vector2i(x, z))
	required_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(center_chunk) < b.distance_squared_to(center_chunk)
	)
	return required_chunks
