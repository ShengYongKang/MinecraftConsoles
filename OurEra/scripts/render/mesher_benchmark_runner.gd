extends SceneTree

const WorldConstants = preload("res://scripts/world/world_constants.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const BackendScript = preload("res://scripts/render/mesh_builder_backend.gd")
const GDScriptBuilderScript = preload("res://scripts/render/mesh_builder_greedy.gd")
const BenchmarkScript = preload("res://scripts/render/mesher_benchmark.gd")

func _initialize() -> void:
	var output_path := OS.get_environment("OURERA_MESHER_BENCHMARK_OUTPUT")
	var iterations := maxi(1, int(OS.get_environment("OURERA_MESHER_BENCHMARK_ITERATIONS")))
	if iterations <= 0:
		iterations = 3

	var generator = WorldGeneratorScript.new()
	generator.seed = 114514
	var center := Vector2i(-3, -1)
	var center_blocks: PackedInt32Array = generator.generate_chunk(center)
	var context := {
		"dimensions": Vector3i(WorldConstants.CHUNK_WIDTH, WorldConstants.WORLD_HEIGHT, WorldConstants.CHUNK_WIDTH),
		"chunk_origin": WorldConstants.chunk_origin(center),
		"chunk_blocks": center_blocks,
		"neighbor_columns": {
			"neg_x": _extract_chunk_border(generator.generate_chunk(Vector2i(center.x - 1, center.y)), 0, WorldConstants.CHUNK_WIDTH - 1),
			"pos_x": _extract_chunk_border(generator.generate_chunk(Vector2i(center.x + 1, center.y)), 0, 0),
			"neg_z": _extract_chunk_border(generator.generate_chunk(Vector2i(center.x, center.y - 1)), 1, WorldConstants.CHUNK_WIDTH - 1),
			"pos_z": _extract_chunk_border(generator.generate_chunk(Vector2i(center.x, center.y + 1)), 1, 0),
		},
		"collect_collision_faces": true,
		"collect_timing_stats": true,
	}

	var gd_builder = GDScriptBuilderScript.new()
	var backend = BackendScript.new()
	var benchmark = BenchmarkScript.new()

	var gd_result: Dictionary = gd_builder.build(context)
	var native_runtime_result: Dictionary = backend.build(context)
	var native_result: Dictionary = backend.build_native_raw(context)
	var gd_stats: Dictionary = gd_result.get("stats", {})
	var native_stats: Dictionary = native_result.get("stats", {})
	var gd_mesh: Mesh = gd_result.get("mesh", null)
	var gd_arrays: Array = gd_mesh.surface_get_arrays(0) if gd_mesh != null and gd_mesh.get_surface_count() > 0 else []
	var native_arrays: Array = native_result.get("arrays", [])

	var comparison := {
		"native_available": backend.has_native_backend(),
		"backend_name": backend.get_backend_name(),
		"runtime_mesh_available": native_runtime_result.get("mesh", null) != null,
		"gd_stats": gd_stats,
		"native_stats": native_stats,
		"collision_faces_match": _packed_vec3_equal(
			gd_result.get("collision_faces", PackedVector3Array()),
			native_result.get("collision_faces", PackedVector3Array())
		),
		"vertex_arrays_match": _packed_vec3_equal(_surface_vec3(gd_arrays, Mesh.ARRAY_VERTEX), _surface_vec3(native_arrays, Mesh.ARRAY_VERTEX)),
		"normal_arrays_match": _packed_vec3_equal(_surface_vec3(gd_arrays, Mesh.ARRAY_NORMAL), _surface_vec3(native_arrays, Mesh.ARRAY_NORMAL)),
		"uv_arrays_match": _packed_vec2_equal(_surface_vec2(gd_arrays, Mesh.ARRAY_TEX_UV), _surface_vec2(native_arrays, Mesh.ARRAY_TEX_UV)),
		"uv2_arrays_match": _packed_vec2_equal(_surface_vec2(gd_arrays, Mesh.ARRAY_TEX_UV2), _surface_vec2(native_arrays, Mesh.ARRAY_TEX_UV2)),
		"index_arrays_match": _packed_int_semantic_equal(_surface_int(gd_arrays, Mesh.ARRAY_INDEX), _surface_int(native_arrays, Mesh.ARRAY_INDEX)),
		"benchmark": benchmark.compare(context, iterations),
	}

	var json := JSON.stringify(comparison, "	")
	print(json)
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file != null:
			file.store_string(json)
			file.close()
	quit()

func _extract_chunk_border(data: PackedInt32Array, border_axis: int, fixed_index: int) -> PackedInt32Array:
	var border := PackedInt32Array()
	border.resize(WorldConstants.CHUNK_WIDTH * WorldConstants.WORLD_HEIGHT)
	var write_index := 0
	if border_axis == 0:
		for y in range(WorldConstants.WORLD_HEIGHT):
			for z in range(WorldConstants.CHUNK_WIDTH):
				border[write_index] = data[WorldConstants.to_index(fixed_index, y, z)]
				write_index += 1
		return border

	for y in range(WorldConstants.WORLD_HEIGHT):
		for x in range(WorldConstants.CHUNK_WIDTH):
			border[write_index] = data[WorldConstants.to_index(x, y, fixed_index)]
			write_index += 1
	return border

func _surface_vec3(arrays: Array, index: int) -> PackedVector3Array:
	if arrays.size() <= index:
		return PackedVector3Array()
	var value: Variant = arrays[index]
	return value if value is PackedVector3Array else PackedVector3Array()

func _surface_vec2(arrays: Array, index: int) -> PackedVector2Array:
	if arrays.size() <= index:
		return PackedVector2Array()
	var value: Variant = arrays[index]
	return value if value is PackedVector2Array else PackedVector2Array()

func _surface_int(arrays: Array, index: int) -> PackedInt32Array:
	if arrays.size() <= index:
		return PackedInt32Array()
	var value: Variant = arrays[index]
	return value if value is PackedInt32Array else PackedInt32Array()

func _packed_vec3_equal(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true

func _packed_vec2_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true

func _packed_int_semantic_equal(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a.is_empty() and b.is_empty():
		return true
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] != b[i]:
			return false
	return true
