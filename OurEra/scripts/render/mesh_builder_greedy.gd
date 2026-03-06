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
const QUAD_TRIANGLE_INDICES: Array[int] = [0, 1, 2, 0, 2, 3]
const FACE_SIGNATURE_MULTIPLIER := 8

func build(context: Dictionary) -> Dictionary:
	var block_sampler: Callable = context.get("block_sampler", Callable())
	if not block_sampler.is_valid():
		return {
			"mesh": null,
			"stats": _empty_stats(),
		}

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var material: Material = context.get("material", null)
	if material != null:
		st.set_material(material)

	var stats := _empty_stats()
	var dims: Vector3i = context.get("dimensions", Vector3i.ONE)
	var chunk_origin: Vector3i = context.get("chunk_origin", Vector3i.ZERO)
	var light_sampler: Callable = context.get("light_sampler", Callable())

	for axis in range(3):
		_build_axis_quads(st, chunk_origin, dims, axis, block_sampler, light_sampler, stats)

	if int(stats["quad_count"]) == 0:
		return {
			"mesh": null,
			"stats": stats,
		}

	return {
		"mesh": st.commit(),
		"stats": stats,
	}

func _build_axis_quads(
	st: SurfaceTool,
	chunk_origin: Vector3i,
	dims: Vector3i,
	axis: int,
	block_sampler: Callable,
	light_sampler: Callable,
	stats: Dictionary
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

				var a := int(block_sampler.call(cursor))
				var b := int(block_sampler.call(cursor + step))

				if BlockDefs.is_solid(a) == BlockDefs.is_solid(b):
					mask[mask_index] = 0
				elif BlockDefs.is_solid(a):
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

func _empty_stats() -> Dictionary:
	return {
		"quad_count": 0,
		"triangle_count": 0,
		"vertex_count": 0,
	}
