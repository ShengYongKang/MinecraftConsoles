class_name VoxelChunk
extends Node3D

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
const FACE_SIGNATURE_MULTIPLIER := 8

var world: VoxelWorld
var chunk_coord: Vector2i = Vector2i.ZERO
var blocks: PackedInt32Array
var mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	_ensure_render_nodes()

func initialize(p_world: VoxelWorld, p_coord: Vector2i, p_blocks: PackedInt32Array) -> void:
	_ensure_render_nodes()
	world = p_world
	chunk_coord = p_coord
	blocks = p_blocks
	position = Vector3(
		chunk_coord.x * VoxelWorld.CHUNK_WIDTH,
		0,
		chunk_coord.y * VoxelWorld.CHUNK_WIDTH
	)

func rebuild_mesh(with_collision: bool = true) -> void:
	_ensure_render_nodes()
	if world == null:
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(world.block_material)

	var chunk_origin := Vector3i(
		chunk_coord.x * VoxelWorld.CHUNK_WIDTH,
		0,
		chunk_coord.y * VoxelWorld.CHUNK_WIDTH
	)
	var dims := Vector3i(
		VoxelWorld.CHUNK_WIDTH,
		VoxelWorld.WORLD_HEIGHT,
		VoxelWorld.CHUNK_WIDTH
	)

	for axis in range(3):
		_build_axis_quads(st, chunk_origin, dims, axis)

	var mesh := st.commit()
	mesh_instance.mesh = mesh

	if with_collision and mesh != null and mesh.get_faces().size() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.data = mesh.get_faces()
		collision_shape.shape = shape
	else:
		collision_shape.shape = null

func _build_axis_quads(st: SurfaceTool, chunk_origin: Vector3i, dims: Vector3i, axis: int) -> void:
	# Sweep one axis at a time and merge adjacent exposed faces into larger quads.
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var axis_size := _axis_size(dims, axis)
	var u_size := _axis_size(dims, u)
	var v_size := _axis_size(dims, v)
	var mask := PackedInt32Array()
	mask.resize(u_size * v_size)

	var cursor := Vector3i.ZERO
	var step := Vector3i.ZERO
	step = _with_axis(cursor, axis, 1)

	for axis_pos in range(-1, axis_size):
		cursor = _with_axis(cursor, axis, axis_pos)

		var mask_index := 0
		for vv in range(v_size):
			cursor = _with_axis(cursor, v, vv)
			for uu in range(u_size):
				cursor = _with_axis(cursor, u, uu)

				var a := _get_block_for_meshing(chunk_origin, cursor)
				var b := _get_block_for_meshing(chunk_origin, cursor + step)

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
					Vector3(cursor.x, cursor.y, cursor.z),
					du,
					dv,
					_decode_block_id(signature),
					_decode_face_index(signature)
				)

				for clear_v in range(quad_height):
					for clear_u in range(quad_width):
						mask[index + clear_u + clear_v * u_size] = 0

				uu += quad_width

func _add_quad(
	st: SurfaceTool,
	base_pos: Vector3,
	du: Vector3,
	dv: Vector3,
	block_id: int,
	face_index: int
) -> void:
	var tile := BlockDefs.tile_for_face(block_id, face_index)
	var tile_uv := Vector2(tile.x, tile.y)
	var repeat_u := du.length()
	var repeat_v := dv.length()
	var normal: Vector3 = FACE_NORMALS[face_index]
	var vertices: Array[Vector3]
	var repeat_uvs: Array[Vector2]

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

	for vertex_index in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(repeat_uvs[vertex_index])
		st.set_uv2(tile_uv)
		st.add_vertex(vertices[vertex_index])

func _get_block_for_meshing(chunk_origin: Vector3i, local_pos: Vector3i) -> int:
	if local_pos.y < 0 or local_pos.y >= VoxelWorld.WORLD_HEIGHT:
		return BlockDefs.AIR

	if (
		local_pos.x >= 0 and local_pos.x < VoxelWorld.CHUNK_WIDTH and
		local_pos.z >= 0 and local_pos.z < VoxelWorld.CHUNK_WIDTH
	):
		return blocks[VoxelWorld.to_index(local_pos.x, local_pos.y, local_pos.z)]

	return world.get_block_global(chunk_origin + local_pos)

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

func _ensure_render_nodes() -> void:
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)

	if static_body == null:
		static_body = StaticBody3D.new()
		add_child(static_body)

	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		static_body.add_child(collision_shape)

