class_name MeshBuilderGreedy
extends RefCounted

const FACE_NORMALS: Array[Vector3] = [
	Vector3(1, 0, 0),
	Vector3(-1, 0, 0),
	Vector3(0, 1, 0),
	Vector3(0, -1, 0),
	Vector3(0, 0, 1),
	Vector3(0, 0, -1)
]

const POSITIVE_FACE_FOR_AXIS: Array[int] = [0, 2, 4]
const NEGATIVE_FACE_FOR_AXIS: Array[int] = [1, 3, 5]
const QUAD_TRIANGLE_INDICES: Array[int] = [0, 2, 1, 0, 3, 2]
const FACE_SIGNATURE_MULTIPLIER := 8
const NEIGHBOR_NEG_X := "neg_x"
const NEIGHBOR_POS_X := "pos_x"
const NEIGHBOR_NEG_Z := "neg_z"
const NEIGHBOR_POS_Z := "pos_z"

func build(context: Dictionary) -> Dictionary:
	var block_sampler: Callable = context.get("block_sampler", Callable())
	var dims: Vector3i = context.get("dimensions", Vector3i.ONE)
	var chunk_blocks: PackedInt32Array = context.get("chunk_blocks", PackedInt32Array())
	var neighbor_columns: Dictionary = context.get("neighbor_columns", {})
	var use_cached_blocks := chunk_blocks.size() == dims.x * dims.y * dims.z
	if not block_sampler.is_valid() and not use_cached_blocks:
		return {
			"mesh": null,
			"stats": _empty_stats(),
			"collision_faces": PackedVector3Array(),
		}

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var material: Material = context.get("material", null)
	if material != null:
		st.set_material(material)

	var stats := _empty_stats()
	var chunk_origin: Vector3i = context.get("chunk_origin", Vector3i.ZERO)
	var light_sampler: Callable = context.get("light_sampler", Callable())
	var collect_collision_faces := bool(context.get("collect_collision_faces", false))
	var collect_timing_stats := bool(context.get("collect_timing_stats", false))
	var collision_faces := PackedVector3Array()
	var solid_cache := {BlockDefs.AIR: false}
	var geometry_started_usec := Time.get_ticks_usec() if collect_timing_stats else 0

	for axis in range(3):
		_build_axis_quads(
			st,
			chunk_origin,
			dims,
			axis,
			chunk_blocks,
			neighbor_columns,
			block_sampler,
			light_sampler,
			collect_collision_faces,
			collision_faces,
			stats,
			solid_cache
		)

	stats["mesh_geometry_usec"] = Time.get_ticks_usec() - geometry_started_usec if collect_timing_stats else 0
	if int(stats["quad_count"]) == 0:
		return {
			"mesh": null,
			"stats": stats,
			"collision_faces": collision_faces,
		}

	var commit_started_usec := Time.get_ticks_usec() if collect_timing_stats else 0
	var mesh := st.commit()
	stats["mesh_commit_usec"] = Time.get_ticks_usec() - commit_started_usec if collect_timing_stats else 0
	return {
		"mesh": mesh,
		"stats": stats,
		"collision_faces": collision_faces,
	}

func _build_axis_quads(
	st: SurfaceTool,
	chunk_origin: Vector3i,
	dims: Vector3i,
	axis: int,
	chunk_blocks: PackedInt32Array,
	neighbor_columns: Dictionary,
	block_sampler: Callable,
	light_sampler: Callable,
	collect_collision_faces: bool,
	collision_faces: PackedVector3Array,
	stats: Dictionary,
	solid_cache: Dictionary
) -> void:
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var axis_size := _axis_size(dims, axis)
	var u_size := _axis_size(dims, u)
	var v_size := _axis_size(dims, v)
	var mask := PackedInt32Array()
	mask.resize(u_size * v_size)

	var cursor := Vector3i.ZERO
	var step := _with_axis(Vector3i.ZERO, axis, 1)

	for axis_pos in range(-1, axis_size):
		cursor = _with_axis(cursor, axis, axis_pos)

		var mask_index := 0
		for vv in range(v_size):
			cursor = _with_axis(cursor, v, vv)
			for uu in range(u_size):
				cursor = _with_axis(cursor, u, uu)

				var a := _sample_block(cursor, dims, chunk_blocks, neighbor_columns, block_sampler)
				var b := _sample_block(cursor + step, dims, chunk_blocks, neighbor_columns, block_sampler)
				var a_solid := _is_solid_cached(a, solid_cache)
				var b_solid := _is_solid_cached(b, solid_cache)

				if a_solid == b_solid:
					mask[mask_index] = 0
				elif a_solid:
					mask[mask_index] = _encode_face_signature(a, POSITIVE_FACE_FOR_AXIS[axis])
				else:
					mask[mask_index] = _encode_face_signature(b, NEGATIVE_FACE_FOR_AXIS[axis])

				mask_index += 1

		cursor = _with_axis(cursor, axis, axis_pos + 1)

		for vv in range(v_size):
			var uu := 0
			while uu < u_size:
				var index := uu + vv * u_size
				var signature := mask[index]
				if signature == 0:
					uu += 1
					continue

				var quad_width := 1
				while uu + quad_width < u_size and mask[index + quad_width] == signature:
					quad_width += 1

				var quad_height := 1
				var keep_expanding := true
				while vv + quad_height < v_size and keep_expanding:
					for offset in range(quad_width):
						if mask[index + offset + quad_height * u_size] != signature:
							keep_expanding = false
							break
					if keep_expanding:
						quad_height += 1

				cursor = _with_axis(cursor, u, uu)
				cursor = _with_axis(cursor, v, vv)

				var du := _axis_vector(u, quad_width)
				var dv := _axis_vector(v, quad_height)
				_add_quad(
					st,
					chunk_origin,
					Vector3(cursor.x, cursor.y, cursor.z),
					du,
					dv,
					_decode_block_id(signature),
					_decode_face_index(signature),
					light_sampler,
					collect_collision_faces,
					collision_faces,
					stats
				)

				for clear_v in range(quad_height):
					for clear_u in range(quad_width):
						mask[index + clear_u + clear_v * u_size] = 0

				uu += quad_width

func _add_quad(
	st: SurfaceTool,
	chunk_origin: Vector3i,
	base_pos: Vector3,
	du: Vector3,
	dv: Vector3,
	block_id: int,
	face_index: int,
	light_sampler: Callable,
	collect_collision_faces: bool,
	collision_faces: PackedVector3Array,
	stats: Dictionary
) -> void:
	var tile := BlockDefs.tile_for_face(block_id, face_index)
	var tile_uv := Vector2(tile.x, tile.y)
	var repeat_u := du.length()
	var repeat_v := dv.length()
	var normal: Vector3 = FACE_NORMALS[face_index]
	var vertices: Array[Vector3]
	var repeat_uvs: Array[Vector2]
	var vertex_color := _sample_face_color(light_sampler, chunk_origin, base_pos, du, dv, block_id, face_index)

	if _is_positive_face(face_index):
		vertices = [
			base_pos,
			base_pos + du,
			base_pos + du + dv,
			base_pos + dv
		]
		repeat_uvs = [
			Vector2(0.0, 0.0),
			Vector2(repeat_u, 0.0),
			Vector2(repeat_u, repeat_v),
			Vector2(0.0, repeat_v)
		]
	else:
		vertices = [
			base_pos,
			base_pos + dv,
			base_pos + du + dv,
			base_pos + du
		]
		repeat_uvs = [
			Vector2(0.0, 0.0),
			Vector2(0.0, repeat_v),
			Vector2(repeat_u, repeat_v),
			Vector2(repeat_u, 0.0)
		]

	for vertex_index in QUAD_TRIANGLE_INDICES:
		st.set_normal(normal)
		st.set_color(vertex_color)
		st.set_uv(repeat_uvs[vertex_index])
		st.set_uv2(tile_uv)
		st.add_vertex(vertices[vertex_index])
		if collect_collision_faces:
			collision_faces.append(vertices[vertex_index])

	stats["quad_count"] = int(stats["quad_count"]) + 1
	stats["triangle_count"] = int(stats["triangle_count"]) + 2
	stats["vertex_count"] = int(stats["vertex_count"]) + 6

func _sample_face_color(
	light_sampler: Callable,
	chunk_origin: Vector3i,
	base_pos: Vector3,
	du: Vector3,
	dv: Vector3,
	block_id: int,
	face_index: int
) -> Color:
	if not light_sampler.is_valid():
		return Color.WHITE

	var sample_position := Vector3(
		chunk_origin.x + base_pos.x + du.x * 0.5 + dv.x * 0.5,
		chunk_origin.y + base_pos.y + du.y * 0.5 + dv.y * 0.5,
		chunk_origin.z + base_pos.z + du.z * 0.5 + dv.z * 0.5
	)
	var sampled: Variant = light_sampler.call(sample_position, FACE_NORMALS[face_index], block_id, face_index)
	if sampled is Color:
		return sampled
	return Color.WHITE

func _encode_face_signature(block_id: int, face_index: int) -> int:
	return 1 + block_id * FACE_SIGNATURE_MULTIPLIER + face_index

func _decode_block_id(signature: int) -> int:
	return int((signature - 1) / FACE_SIGNATURE_MULTIPLIER)

func _decode_face_index(signature: int) -> int:
	return (signature - 1) % FACE_SIGNATURE_MULTIPLIER

func _is_positive_face(face_index: int) -> bool:
	return (face_index % 2) == 0

func _axis_size(dims: Vector3i, axis: int) -> int:
	match axis:
		0:
			return dims.x
		1:
			return dims.y
		_:
			return dims.z

func _axis_vector(axis: int, length: int) -> Vector3:
	match axis:
		0:
			return Vector3(length, 0, 0)
		1:
			return Vector3(0, length, 0)
		_:
			return Vector3(0, 0, length)

func _with_axis(vec: Vector3i, axis: int, value: int) -> Vector3i:
	match axis:
		0:
			vec.x = value
		1:
			vec.y = value
		_:
			vec.z = value
	return vec

func _sample_block(
	local_pos: Vector3i,
	dims: Vector3i,
	chunk_blocks: PackedInt32Array,
	neighbor_columns: Dictionary,
	block_sampler: Callable
) -> int:
	if local_pos.y < 0 or local_pos.y >= dims.y:
		return BlockDefs.AIR

	if local_pos.x >= 0 and local_pos.x < dims.x and local_pos.z >= 0 and local_pos.z < dims.z:
		if chunk_blocks.size() == dims.x * dims.y * dims.z:
			return chunk_blocks[local_pos.x + local_pos.z * dims.x + local_pos.y * dims.x * dims.z]
		if block_sampler.is_valid():
			return int(block_sampler.call(local_pos))
		return BlockDefs.AIR

	if local_pos.x == -1 and local_pos.z >= 0 and local_pos.z < dims.z:
		return _read_neighbor_column(neighbor_columns.get(NEIGHBOR_NEG_X, PackedInt32Array()), local_pos.z, local_pos.y, dims.z)
	if local_pos.x == dims.x and local_pos.z >= 0 and local_pos.z < dims.z:
		return _read_neighbor_column(neighbor_columns.get(NEIGHBOR_POS_X, PackedInt32Array()), local_pos.z, local_pos.y, dims.z)
	if local_pos.z == -1 and local_pos.x >= 0 and local_pos.x < dims.x:
		return _read_neighbor_column(neighbor_columns.get(NEIGHBOR_NEG_Z, PackedInt32Array()), local_pos.x, local_pos.y, dims.x)
	if local_pos.z == dims.z and local_pos.x >= 0 and local_pos.x < dims.x:
		return _read_neighbor_column(neighbor_columns.get(NEIGHBOR_POS_Z, PackedInt32Array()), local_pos.x, local_pos.y, dims.x)
	if block_sampler.is_valid():
		return int(block_sampler.call(local_pos))
	return BlockDefs.AIR

func _read_neighbor_column(column: PackedInt32Array, lateral_index: int, y: int, stride: int) -> int:
	if stride <= 0 or column.is_empty():
		return BlockDefs.AIR
	var index := lateral_index + y * stride
	if index < 0 or index >= column.size():
		return BlockDefs.AIR
	return column[index]

func _is_solid_cached(block_id: int, solid_cache: Dictionary) -> bool:
	if solid_cache.has(block_id):
		return bool(solid_cache[block_id])
	var solid := BlockDefs.is_solid(block_id)
	solid_cache[block_id] = solid
	return solid

func _empty_stats() -> Dictionary:
	return {
		"quad_count": 0,
		"triangle_count": 0,
		"vertex_count": 0,
		"mesh_geometry_usec": 0,
		"mesh_commit_usec": 0,
	}
