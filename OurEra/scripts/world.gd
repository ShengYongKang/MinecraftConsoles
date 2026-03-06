class_name VoxelWorld
extends Node3D

# Based on Minecraft console logic: 16x16 columns, sea level ~63, finite height volume.
const CHUNK_WIDTH := 16
const WORLD_HEIGHT := 128
const SEA_LEVEL := 63

@export var player_path: NodePath
@export_range(1, 16, 1) var load_radius_chunks := 4
@export_range(2, 20, 1) var unload_radius_chunks := 6
@export_range(1, 12, 1) var collision_radius_chunks := 2
@export_range(1, 32, 1) var max_chunk_generations_per_frame := 2
@export_range(1, 32, 1) var max_chunk_mesh_updates_per_frame := 1

var seed: int = 114514
var height_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()

var chunk_blocks: Dictionary = {}
var chunks: Dictionary = {}
var block_material: StandardMaterial3D

var player: Node3D
var center_chunk := Vector2i(1 << 29, 1 << 29)

var pending_generation: Array[Vector2i] = []
var pending_generation_set: Dictionary = {}

var pending_mesh: Array[Vector2i] = []
var pending_mesh_set: Dictionary = {}

func _ready() -> void:
	_setup_material()
	_setup_noise()
	player = get_node_or_null(player_path)
	if player != null:
		_force_streaming_update()

func _process(_delta: float) -> void:
	if player == null:
		player = get_node_or_null(player_path)
		if player == null:
			return
		_force_streaming_update()

	var new_center := _world_to_chunk(Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z)))
	if new_center != center_chunk:
		center_chunk = new_center
		_schedule_chunks_around_center(center_chunk)
		_unload_far_chunks(center_chunk)

	_process_generation_budget()
	_process_mesh_budget()

func _setup_material() -> void:
	block_material = StandardMaterial3D.new()
	block_material.albedo_texture = load("res://assets/textures/terrain.png")
	block_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	block_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	block_material.roughness = 1.0

func _setup_noise() -> void:
	height_noise.seed = seed
	height_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	height_noise.frequency = 0.0075

	detail_noise.seed = seed ^ 0x6E624EB7
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.frequency = 0.02

func _force_streaming_update() -> void:
	center_chunk = _world_to_chunk(Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z)))
	_ensure_chunk_immediate(center_chunk, true)
	_schedule_chunks_around_center(center_chunk)
	_unload_far_chunks(center_chunk)
	_process_generation_budget()
	_process_mesh_budget()

func _schedule_chunks_around_center(center: Vector2i) -> void:
	var coords: Array[Vector2i] = []
	for dz in range(-load_radius_chunks, load_radius_chunks + 1):
		for dx in range(-load_radius_chunks, load_radius_chunks + 1):
			coords.append(Vector2i(center.x + dx, center.y + dz))

	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_distance_sq(center, a) < _chunk_distance_sq(center, b)
	)

	for coord in coords:
		if chunks.has(coord):
			continue
		if pending_generation_set.has(coord):
			continue
		pending_generation.append(coord)
		pending_generation_set[coord] = true

func _process_generation_budget() -> void:
	var count := mini(max_chunk_generations_per_frame, pending_generation.size())
	for _i in range(count):
		var coord := pending_generation.pop_front()
		pending_generation_set.erase(coord)
		if _chunk_chebyshev_distance(center_chunk, coord) > unload_radius_chunks:
			continue

		if not chunk_blocks.has(coord):
			chunk_blocks[coord] = _generate_chunk_blocks(coord)

		if not chunks.has(coord):
			var chunk := VoxelChunk.new()
			add_child(chunk)
			chunk.initialize(self, coord, chunk_blocks[coord])
			chunks[coord] = chunk

		_queue_chunk_mesh(coord)
		_queue_neighbor_meshes(coord)

func _ensure_chunk_immediate(coord: Vector2i, with_collision: bool) -> void:
	if not chunk_blocks.has(coord):
		chunk_blocks[coord] = _generate_chunk_blocks(coord)
	if not chunks.has(coord):
		var chunk := VoxelChunk.new()
		add_child(chunk)
		chunk.initialize(self, coord, chunk_blocks[coord])
		chunks[coord] = chunk
	(chunks[coord] as VoxelChunk).rebuild_mesh(with_collision)

func _process_mesh_budget() -> void:
	var count := mini(max_chunk_mesh_updates_per_frame, pending_mesh.size())
	for _i in range(count):
		var coord := pending_mesh.pop_front()
		pending_mesh_set.erase(coord)

		if not chunks.has(coord):
			continue

		var chunk := chunks[coord] as VoxelChunk
		var collision_enabled := _chunk_chebyshev_distance(center_chunk, coord) <= collision_radius_chunks
		chunk.rebuild_mesh(collision_enabled)

func _queue_chunk_mesh(coord: Vector2i) -> void:
	if not chunks.has(coord):
		return
	if pending_mesh_set.has(coord):
		return
	pending_mesh.append(coord)
	pending_mesh_set[coord] = true

func _queue_neighbor_meshes(coord: Vector2i) -> void:
	_queue_chunk_mesh(Vector2i(coord.x + 1, coord.y))
	_queue_chunk_mesh(Vector2i(coord.x - 1, coord.y))
	_queue_chunk_mesh(Vector2i(coord.x, coord.y + 1))
	_queue_chunk_mesh(Vector2i(coord.x, coord.y - 1))

func _unload_far_chunks(center: Vector2i) -> void:
	var keys := chunks.keys()
	for coord_any in keys:
		var coord: Vector2i = coord_any
		if _chunk_chebyshev_distance(center, coord) <= unload_radius_chunks:
			continue

		var chunk := chunks[coord] as VoxelChunk
		chunk.queue_free()
		chunks.erase(coord)
		pending_mesh_set.erase(coord)

func _generate_chunk_blocks(coord: Vector2i) -> PackedInt32Array:
	var data := PackedInt32Array()
	data.resize(CHUNK_WIDTH * CHUNK_WIDTH * WORLD_HEIGHT)

	for z in range(CHUNK_WIDTH):
		for x in range(CHUNK_WIDTH):
			var wx := coord.x * CHUNK_WIDTH + x
			var wz := coord.y * CHUNK_WIDTH + z
			var height := _sample_height(wx, wz)

			for y in range(height + 1):
				var id := BlockDefs.STONE
				if y == height:
					id = BlockDefs.GRASS
				elif y >= height - 3:
					id = BlockDefs.DIRT

				if y < SEA_LEVEL - 6 and y % 9 == 0:
					id = BlockDefs.COBBLE

				data[to_index(x, y, z)] = id

	return data

func _sample_height(wx: int, wz: int) -> int:
	var h0 := height_noise.get_noise_2d(wx, wz) * 18.0
	var h1 := detail_noise.get_noise_2d(wx, wz) * 6.0
	var h := int(round(SEA_LEVEL + h0 + h1))
	return clampi(h, 8, WORLD_HEIGHT - 2)

static func to_index(x: int, y: int, z: int) -> int:
	return x + z * CHUNK_WIDTH + y * CHUNK_WIDTH * CHUNK_WIDTH

func get_block_global(pos: Vector3i) -> int:
	if pos.y < 0 or pos.y >= WORLD_HEIGHT:
		return BlockDefs.AIR

	var chunk_coord := _world_to_chunk(pos)
	if not chunk_blocks.has(chunk_coord):
		return BlockDefs.AIR

	var local := _world_to_local(pos)
	var data: PackedInt32Array = chunk_blocks[chunk_coord]
	return data[to_index(local.x, local.y, local.z)]

func set_block_global(pos: Vector3i, block_id: int) -> void:
	if pos.y < 0 or pos.y >= WORLD_HEIGHT:
		return

	var chunk_coord := _world_to_chunk(pos)
	if not chunk_blocks.has(chunk_coord):
		chunk_blocks[chunk_coord] = _generate_chunk_blocks(chunk_coord)
	if not chunks.has(chunk_coord):
		var chunk := VoxelChunk.new()
		add_child(chunk)
		chunk.initialize(self, chunk_coord, chunk_blocks[chunk_coord])
		chunks[chunk_coord] = chunk

	var local := _world_to_local(pos)
	var data: PackedInt32Array = chunk_blocks[chunk_coord]
	data[to_index(local.x, local.y, local.z)] = block_id

	_queue_chunk_mesh(chunk_coord)
	if local.x == 0:
		_queue_chunk_mesh(Vector2i(chunk_coord.x - 1, chunk_coord.y))
	elif local.x == CHUNK_WIDTH - 1:
		_queue_chunk_mesh(Vector2i(chunk_coord.x + 1, chunk_coord.y))

	if local.z == 0:
		_queue_chunk_mesh(Vector2i(chunk_coord.x, chunk_coord.y - 1))
	elif local.z == CHUNK_WIDTH - 1:
		_queue_chunk_mesh(Vector2i(chunk_coord.x, chunk_coord.y + 1))

func _world_to_chunk(pos: Vector3i) -> Vector2i:
	return Vector2i(
		_floor_div(pos.x, CHUNK_WIDTH),
		_floor_div(pos.z, CHUNK_WIDTH)
	)

func _world_to_local(pos: Vector3i) -> Vector3i:
	var lx := pos.x - _floor_div(pos.x, CHUNK_WIDTH) * CHUNK_WIDTH
	var lz := pos.z - _floor_div(pos.z, CHUNK_WIDTH) * CHUNK_WIDTH
	return Vector3i(lx, pos.y, lz)

func _floor_div(a: int, b: int) -> int:
	return floori(float(a) / float(b))

func _chunk_distance_sq(center: Vector2i, coord: Vector2i) -> int:
	var dx := coord.x - center.x
	var dz := coord.y - center.y
	return dx * dx + dz * dz

func _chunk_chebyshev_distance(center: Vector2i, coord: Vector2i) -> int:
	return maxi(absi(coord.x - center.x), absi(coord.y - center.y))
