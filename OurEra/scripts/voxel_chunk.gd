class_name VoxelChunk
extends Node3D

const FACE_DIRS := [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1)
]

const FACE_VERTS := [
	[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1)],
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]
]

const FACE_NORMALS := [
	Vector3(1, 0, 0),
	Vector3(-1, 0, 0),
	Vector3(0, 1, 0),
	Vector3(0, -1, 0),
	Vector3(0, 0, 1),
	Vector3(0, 0, -1)
]

var world: VoxelWorld
var chunk_coord := Vector2i.ZERO
var blocks: PackedInt32Array
var mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D

func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	add_child(mesh_instance)

	static_body = StaticBody3D.new()
	add_child(static_body)

	collision_shape = CollisionShape3D.new()
	static_body.add_child(collision_shape)

func initialize(p_world: VoxelWorld, p_coord: Vector2i, p_blocks: PackedInt32Array) -> void:
	world = p_world
	chunk_coord = p_coord
	blocks = p_blocks
	position = Vector3(
		chunk_coord.x * VoxelWorld.CHUNK_WIDTH,
		0,
		chunk_coord.y * VoxelWorld.CHUNK_WIDTH
	)

func rebuild_mesh(with_collision: bool = true) -> void:
	if mesh_instance == null:
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(world.block_material)

	var chunk_origin_x := chunk_coord.x * VoxelWorld.CHUNK_WIDTH
	var chunk_origin_z := chunk_coord.y * VoxelWorld.CHUNK_WIDTH

	for y in range(VoxelWorld.WORLD_HEIGHT):
		for z in range(VoxelWorld.CHUNK_WIDTH):
			for x in range(VoxelWorld.CHUNK_WIDTH):
				var block_id := _get_local(x, y, z)
				if block_id == BlockDefs.AIR:
					continue

				var world_pos := Vector3i(chunk_origin_x + x, y, chunk_origin_z + z)

				for face_index in range(6):
					var neighbor_pos := world_pos + FACE_DIRS[face_index]
					if BlockDefs.is_solid(world.get_block_global(neighbor_pos)):
						continue
					_add_face(st, Vector3(x, y, z), block_id, face_index)

	var mesh := st.commit()
	mesh_instance.mesh = mesh

	if with_collision and mesh != null and mesh.get_faces().size() > 0:
		var shape := ConcavePolygonShape3D.new()
		shape.data = mesh.get_faces()
		collision_shape.shape = shape
	else:
		collision_shape.shape = null

func _add_face(st: SurfaceTool, base_pos: Vector3, block_id: int, face_index: int) -> void:
	var tile := BlockDefs.tile_for_face(block_id, face_index)
	var uv_quad := _atlas_uvs(tile)
	var verts: Array = FACE_VERTS[face_index]
	var normal: Vector3 = FACE_NORMALS[face_index]

	st.set_normal(normal)
	st.set_uv(uv_quad[0])
	st.add_vertex(base_pos + verts[0])
	st.set_normal(normal)
	st.set_uv(uv_quad[1])
	st.add_vertex(base_pos + verts[1])
	st.set_normal(normal)
	st.set_uv(uv_quad[2])
	st.add_vertex(base_pos + verts[2])

	st.set_normal(normal)
	st.set_uv(uv_quad[0])
	st.add_vertex(base_pos + verts[0])
	st.set_normal(normal)
	st.set_uv(uv_quad[2])
	st.add_vertex(base_pos + verts[2])
	st.set_normal(normal)
	st.set_uv(uv_quad[3])
	st.add_vertex(base_pos + verts[3])

func _atlas_uvs(tile: Vector2i) -> Array[Vector2]:
	var step := 1.0 / float(BlockDefs.ATLAS_SIZE)
	var eps := step * 0.001
	var u0 := tile.x * step + eps
	var v0 := tile.y * step + eps
	var u1 := (tile.x + 1) * step - eps
	var v1 := (tile.y + 1) * step - eps

	return [
		Vector2(u0, v1),
		Vector2(u1, v1),
		Vector2(u1, v0),
		Vector2(u0, v0)
	]

func _get_local(x: int, y: int, z: int) -> int:
	if y < 0 or y >= VoxelWorld.WORLD_HEIGHT:
		return BlockDefs.AIR
	var idx := VoxelWorld.to_index(x, y, z)
	return blocks[idx]
