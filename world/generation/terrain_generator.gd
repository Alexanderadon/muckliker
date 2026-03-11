extends RefCounted
class_name TerrainGenerator

var terrain_height_scale: float = 10.0
var terrain_height_bias: float = 2.0
var island_radius: float = 1100.0
var island_falloff: float = 0.6
var shoreline_drop_scale: float = 5.0
var mountain_height_scale: float = 25.0
var river_threshold: float = 0.08
var river_depth_scale: float = 1.5
var lake_max_elevation: float = 0.4
var lake_noise_threshold: float = 0.9
var lake_depth_scale: float = 0.75
var _base_noise: FastNoiseLite = FastNoiseLite.new()
var _mountain_noise: FastNoiseLite = FastNoiseLite.new()
var _river_noise: FastNoiseLite = FastNoiseLite.new()
var _lake_noise: FastNoiseLite = FastNoiseLite.new()

func configure(seed_value: int, height_scale: float = 10.0, frequency: float = 0.005) -> void:
	terrain_height_scale = height_scale
	_base_noise.seed = seed_value
	_base_noise.frequency = frequency
	_base_noise.fractal_octaves = 4
	_base_noise.fractal_gain = 0.5
	_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_mountain_noise.seed = seed_value + 1349
	_mountain_noise.frequency = 0.003
	_mountain_noise.fractal_octaves = 3
	_mountain_noise.fractal_gain = 0.55
	_mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_river_noise.seed = seed_value + 7331
	_river_noise.frequency = 0.0045
	_river_noise.fractal_octaves = 2
	_river_noise.fractal_gain = 0.35
	_river_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_lake_noise.seed = seed_value + 3907
	_lake_noise.frequency = 0.02
	_lake_noise.fractal_octaves = 2
	_lake_noise.fractal_gain = 0.45
	_lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

func terrain_height(x: float, z: float) -> float:
	var distance_from_center: float = Vector2(x, z).length()
	if distance_from_center > island_radius:
		var outside_distance: float = distance_from_center - island_radius
		return -8.0 - minf(outside_distance * 0.02, 6.0)
	var base_noise: float = _base_noise.get_noise_2d(x, z)
	var mountain_noise: float = _mountain_noise.get_noise_2d(x, z)
	var river_noise_abs: float = absf(_river_noise.get_noise_2d(x, z))
	var lake_noise: float = _lake_noise.get_noise_2d(x, z)
	var mask: float = _island_mask(x, z)
	var terrain_base: float = base_noise * terrain_height_scale
	var mountain_factor: float = pow(maxf(mountain_noise, 0.0), 2.0)
	var mountain_height: float = mountain_factor * mountain_height_scale
	var island_height: float = (terrain_base + mountain_height) * mask
	if river_noise_abs < river_threshold:
		var river_ratio: float = 1.0 - (river_noise_abs / maxf(river_threshold, 0.0001))
		island_height -= river_depth_scale * river_ratio * mask
	if island_height < lake_max_elevation and lake_noise > lake_noise_threshold:
		var lake_ratio: float = (lake_noise - lake_noise_threshold) / maxf(1.0 - lake_noise_threshold, 0.0001)
		island_height -= lake_depth_scale * clampf(lake_ratio, 0.0, 1.0) * mask
	var shoreline_drop: float = (1.0 - mask) * shoreline_drop_scale
	return island_height + terrain_height_bias - shoreline_drop

func _island_mask(x: float, z: float) -> float:
	var distance_from_center: float = Vector2(x, z).length()
	var edge_ratio: float = clampf(distance_from_center / island_radius, 0.0, 1.0)
	return 1.0 - pow(edge_ratio, 1.8 + island_falloff)

func get_island_radius() -> float:
	return island_radius

func build_chunk_mesh(chunk_id: Vector2i, chunk_size: int, resolution: int) -> ArrayMesh:
	var local_resolution: int = maxi(resolution, 2)
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(float(chunk_size), float(chunk_size))
	plane.subdivide_width = local_resolution
	plane.subdivide_depth = local_resolution

	var source_arrays: Array = plane.get_mesh_arrays()
	var vertices_variant: Variant = source_arrays[Mesh.ARRAY_VERTEX]
	var uvs_variant: Variant = source_arrays[Mesh.ARRAY_TEX_UV]
	var indices_variant: Variant = source_arrays[Mesh.ARRAY_INDEX]
	if not (vertices_variant is PackedVector3Array) or not (uvs_variant is PackedVector2Array) or not (indices_variant is PackedInt32Array):
		return ArrayMesh.new()
	var vertices: PackedVector3Array = PackedVector3Array(vertices_variant)
	var uvs: PackedVector2Array = PackedVector2Array(uvs_variant)
	var indices: PackedInt32Array = PackedInt32Array(indices_variant)

	var half_size: float = float(chunk_size) * 0.5
	var base_x: float = float(chunk_id.x * chunk_size)
	var base_z: float = float(chunk_id.y * chunk_size)

	for vertex_idx in range(vertices.size()):
		var vertex: Vector3 = vertices[vertex_idx]
		var local_x: float = vertex.x + half_size
		var local_z: float = vertex.z + half_size
		var world_x: float = base_x + local_x
		var world_z: float = base_z + local_z
		var world_y: float = terrain_height(world_x, world_z)
		vertices[vertex_idx] = Vector3(local_x, world_y, local_z)

	var normals: PackedVector3Array = _calculate_normals(vertices, indices)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _calculate_normals(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var accum_normals: Array[Vector3] = []
	accum_normals.resize(vertices.size())
	for idx in range(accum_normals.size()):
		accum_normals[idx] = Vector3.ZERO

	for tri_idx in range(0, indices.size(), 3):
		var ia: int = indices[tri_idx]
		var ib: int = indices[tri_idx + 1]
		var ic: int = indices[tri_idx + 2]
		var a: Vector3 = vertices[ia]
		var b: Vector3 = vertices[ib]
		var c: Vector3 = vertices[ic]
		var normal: Vector3 = (b - a).cross(c - a)
		if normal.length_squared() > 0.0:
			normal = normal.normalized()
		else:
			normal = Vector3.UP
		accum_normals[ia] = accum_normals[ia] + normal
		accum_normals[ib] = accum_normals[ib] + normal
		accum_normals[ic] = accum_normals[ic] + normal

	var packed_normals: PackedVector3Array = PackedVector3Array()
	packed_normals.resize(accum_normals.size())
	for normal_idx in range(accum_normals.size()):
		var final_normal: Vector3 = accum_normals[normal_idx]
		if final_normal.length_squared() > 0.0:
			packed_normals[normal_idx] = final_normal.normalized()
		else:
			packed_normals[normal_idx] = Vector3.UP
	return packed_normals
