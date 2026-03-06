class_name VoxelWorld
extends Node3D

# Based on Minecraft console logic: 16x16 columns, sea level ~63, finite height volume.
const CHUNK_WIDTH := 16
const WORLD_HEIGHT := 128
const SEA_LEVEL := 63
const CHUNK_VOLUME := CHUNK_WIDTH * CHUNK_WIDTH * WORLD_HEIGHT
const SAVE_FORMAT_VERSION := 1

@export var player_path: NodePath
@export var save_slot_name: String = "default"
@export_range(1, 16, 1) var load_radius_chunks := 4
@export_range(2, 20, 1) var unload_radius_chunks := 6
@export_range(1, 12, 1) var collision_radius_chunks := 2
@export_range(1, 32, 1) var max_chunk_generations_per_frame := 4
@export_range(1, 32, 1) var max_chunk_mesh_updates_per_frame := 2
@export_range(1, 8, 1) var generator_thread_count := 2
@export_range(1, 64, 1) var max_active_generation_jobs := 8
@export_range(1, 32, 1) var max_completed_chunk_integrations_per_frame := 4
@export_range(0, 4096, 1) var max_cached_clean_chunks := 256

var seed: int = 114514

var chunk_blocks: Dictionary = {}
var chunk_dirty: Dictionary = {}
var chunk_cache_stamp_msec: Dictionary = {}
var chunks: Dictionary = {}
var block_material: Material

var player: Node3D
var center_chunk: Vector2i = Vector2i(1 << 29, 1 << 29)

var pending_generation: Array[Vector2i] = []
var pending_generation_set: Dictionary = {}
var generation_active_set: Dictionary = {}

var pending_mesh: Array[Vector2i] = []
var pending_mesh_set: Dictionary = {}

var generation_queue_mutex: Mutex = Mutex.new()
var generation_result_mutex: Mutex = Mutex.new()
var generation_semaphore: Semaphore = Semaphore.new()
var generation_job_queue: Array[Vector2i] = []
var generation_results: Array[Dictionary] = []
var generation_threads: Array[Thread] = []
var generation_shutdown: bool = false

func _ready() -> void:
	unload_radius_chunks = maxi(unload_radius_chunks, load_radius_chunks + 1)
	_setup_material()
	_ensure_save_directories()
	_start_generation_workers()
	player = get_node_or_null(player_path)
	if player != null:
		_force_streaming_update()

func _exit_tree() -> void:
	_flush_dirty_chunks()
	_stop_generation_workers()

func _process(_delta: float) -> void:
	if player == null:
		player = get_node_or_null(player_path)
		if player == null:
			return
		_force_streaming_update()

	var new_center: Vector2i = _world_to_chunk(Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z)))
	if new_center != center_chunk:
		center_chunk = new_center
		_schedule_chunks_around_center(center_chunk)
		_refresh_pending_generation(center_chunk)
		_refresh_pending_mesh(center_chunk)
		_unload_far_chunks(center_chunk)

	_integrate_completed_generation_budget()
	_dispatch_generation_budget()
	_process_mesh_budget()
	_trim_chunk_cache()

func _setup_material() -> void:
	var atlas_texture: Texture2D = load("res://assets/textures/terrain.png")
	var shader: Shader = load("res://shaders/voxel_blocks.gdshader")
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("atlas_texture", atlas_texture)
	material.set_shader_parameter("atlas_size", float(BlockDefs.ATLAS_SIZE))
	if atlas_texture != null:
		material.set_shader_parameter(
			"tile_resolution",
			float(atlas_texture.get_width()) / float(BlockDefs.ATLAS_SIZE)
		)
	block_material = material

func _force_streaming_update() -> void:
	center_chunk = _world_to_chunk(Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z)))
	_ensure_chunk_immediate(center_chunk, true)
	_schedule_chunks_around_center(center_chunk)
	_refresh_pending_generation(center_chunk)
	_refresh_pending_mesh(center_chunk)
	_unload_far_chunks(center_chunk)
	_integrate_completed_generation_budget()
	_dispatch_generation_budget()
	_process_mesh_budget()
	_trim_chunk_cache()

func _schedule_chunks_around_center(center: Vector2i) -> void:
	for dz in range(-load_radius_chunks, load_radius_chunks + 1):
		for dx in range(-load_radius_chunks, load_radius_chunks + 1):
			var coord: Vector2i = Vector2i(center.x + dx, center.y + dz)
			if chunks.has(coord):
				continue
			if pending_generation_set.has(coord):
				continue
			if generation_active_set.has(coord):
				continue
			pending_generation.append(coord)
			pending_generation_set[coord] = true

func _refresh_pending_generation(center: Vector2i) -> void:
	var next_queue: Array[Vector2i] = []
	for coord_any in pending_generation_set.keys():
		var coord: Vector2i = coord_any
		if chunks.has(coord):
			continue
		if generation_active_set.has(coord):
			continue
		if _chunk_chebyshev_distance(center, coord) > unload_radius_chunks:
			continue
		next_queue.append(coord)

	next_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_distance_sq(center, a) < _chunk_distance_sq(center, b)
	)

	pending_generation = next_queue
	pending_generation_set.clear()
	for coord in pending_generation:
		pending_generation_set[coord] = true

func _dispatch_generation_budget() -> void:
	var dispatched: int = 0

	while dispatched < max_chunk_generations_per_frame:
		if pending_generation.is_empty():
			return
		if generation_active_set.size() >= max_active_generation_jobs:
			return

		var coord: Vector2i = pending_generation.pop_front()
		pending_generation_set.erase(coord)

		if _chunk_chebyshev_distance(center_chunk, coord) > unload_radius_chunks:
			continue
		if chunks.has(coord):
			continue

		if chunk_blocks.has(coord):
			_instantiate_chunk(coord)
			_queue_chunk_mesh(coord)
			_queue_neighbor_meshes(coord)
			dispatched += 1
			continue

		var saved_data: PackedInt32Array = _load_saved_chunk_data(coord)
		if saved_data.size() == CHUNK_VOLUME:
			_register_chunk_data(coord, saved_data, false)
			_instantiate_chunk(coord)
			_queue_chunk_mesh(coord)
			_queue_neighbor_meshes(coord)
			dispatched += 1
			continue

		generation_active_set[coord] = true
		generation_queue_mutex.lock()
		generation_job_queue.append(coord)
		generation_queue_mutex.unlock()
		generation_semaphore.post()
		dispatched += 1

func _integrate_completed_generation_budget() -> void:
	var results: Array[Dictionary] = []

	generation_result_mutex.lock()
	var count: int = mini(max_completed_chunk_integrations_per_frame, generation_results.size())
	for _i in range(count):
		results.append(generation_results.pop_front())
	generation_result_mutex.unlock()

	for result in results:
		var coord: Vector2i = result["coord"]
		var data: PackedInt32Array = result["data"]
		generation_active_set.erase(coord)

		if not chunk_blocks.has(coord):
			_register_chunk_data(coord, data, false)

		if _chunk_chebyshev_distance(center_chunk, coord) <= load_radius_chunks:
			_instantiate_chunk(coord)
			_queue_chunk_mesh(coord)
			_queue_neighbor_meshes(coord)

func _ensure_chunk_immediate(coord: Vector2i, with_collision: bool) -> void:
	if not chunk_blocks.has(coord):
		_register_chunk_data(coord, _load_or_generate_chunk_data(coord), false)

	_instantiate_chunk(coord)
	(chunks[coord] as VoxelChunk).rebuild_mesh(with_collision)

func _instantiate_chunk(coord: Vector2i) -> void:
	if chunks.has(coord):
		return
	if not chunk_blocks.has(coord):
		return

	var chunk: VoxelChunk = VoxelChunk.new()
	add_child(chunk)
	chunk.initialize(self, coord, chunk_blocks[coord])
	chunks[coord] = chunk

func _process_mesh_budget() -> void:
	var count: int = mini(max_chunk_mesh_updates_per_frame, pending_mesh.size())
	for _i in range(count):
		var coord: Vector2i = pending_mesh.pop_front()
		pending_mesh_set.erase(coord)

		if not chunks.has(coord):
			continue

		var chunk: VoxelChunk = chunks[coord] as VoxelChunk
		var collision_enabled: bool = _chunk_chebyshev_distance(center_chunk, coord) <= collision_radius_chunks
		chunk.rebuild_mesh(collision_enabled)

func _queue_chunk_mesh(coord: Vector2i) -> void:
	if not chunks.has(coord):
		return
	if pending_mesh_set.has(coord):
		return
	pending_mesh.append(coord)
	pending_mesh_set[coord] = true

func _refresh_pending_mesh(center: Vector2i) -> void:
	var next_queue: Array[Vector2i] = []
	for coord_any in pending_mesh_set.keys():
		var coord: Vector2i = coord_any
		if not chunks.has(coord):
			continue
		if _chunk_chebyshev_distance(center, coord) > unload_radius_chunks:
			continue
		next_queue.append(coord)

	next_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_distance_sq(center, a) < _chunk_distance_sq(center, b)
	)

	pending_mesh = next_queue
	pending_mesh_set.clear()
	for coord in pending_mesh:
		pending_mesh_set[coord] = true

func _queue_neighbor_meshes(coord: Vector2i) -> void:
	_queue_chunk_mesh(Vector2i(coord.x + 1, coord.y))
	_queue_chunk_mesh(Vector2i(coord.x - 1, coord.y))
	_queue_chunk_mesh(Vector2i(coord.x, coord.y + 1))
	_queue_chunk_mesh(Vector2i(coord.x, coord.y - 1))

func _unload_far_chunks(center: Vector2i) -> void:
	var keys: Array = chunks.keys()
	for coord_any in keys:
		var coord: Vector2i = coord_any
		if _chunk_chebyshev_distance(center, coord) <= unload_radius_chunks:
			continue

		if bool(chunk_dirty.get(coord, false)):
			_save_chunk_data(coord)

		var chunk: VoxelChunk = chunks[coord] as VoxelChunk
		chunk.queue_free()
		chunks.erase(coord)
		pending_mesh_set.erase(coord)
		chunk_cache_stamp_msec[coord] = Time.get_ticks_msec()

func _trim_chunk_cache() -> void:
	var clean_unloaded: Array[Vector2i] = []
	for coord_any in chunk_blocks.keys():
		var coord: Vector2i = coord_any
		if chunks.has(coord):
			continue
		if bool(chunk_dirty.get(coord, false)):
			continue
		clean_unloaded.append(coord)

	if clean_unloaded.size() <= max_cached_clean_chunks:
		return

	clean_unloaded.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _cache_stamp_for(a) < _cache_stamp_for(b)
	)

	var to_remove: int = clean_unloaded.size() - max_cached_clean_chunks
	for index in range(to_remove):
		_evict_chunk_data(clean_unloaded[index])

func _evict_chunk_data(coord: Vector2i) -> void:
	if chunks.has(coord):
		return
	chunk_blocks.erase(coord)
	chunk_dirty.erase(coord)
	chunk_cache_stamp_msec.erase(coord)

func _register_chunk_data(coord: Vector2i, data: PackedInt32Array, dirty: bool) -> void:
	chunk_blocks[coord] = data
	chunk_dirty[coord] = dirty
	chunk_cache_stamp_msec[coord] = Time.get_ticks_msec()

func _cache_stamp_for(coord: Vector2i) -> int:
	if chunk_cache_stamp_msec.has(coord):
		return int(chunk_cache_stamp_msec[coord])
	return 0

func _flush_dirty_chunks() -> void:
	for coord_any in chunk_dirty.keys():
		var coord: Vector2i = coord_any
		if bool(chunk_dirty.get(coord, false)):
			_save_chunk_data(coord)

func _ensure_save_directories() -> void:
	DirAccess.make_dir_recursive_absolute(_get_save_root_dir())

func _get_save_root_dir() -> String:
	return ProjectSettings.globalize_path('res://save_data/worlds/%s' % _normalized_save_slot_name())

func _normalized_save_slot_name() -> String:
	var normalized: String = save_slot_name.strip_edges()
	if normalized.is_empty():
		return "default"
	return normalized

func _chunk_save_path(coord: Vector2i) -> String:
	return "%s/%d_%d.chunk" % [_get_save_root_dir(), coord.x, coord.y]

func _load_or_generate_chunk_data(coord: Vector2i) -> PackedInt32Array:
	var saved_data: PackedInt32Array = _load_saved_chunk_data(coord)
	if saved_data.size() == CHUNK_VOLUME:
		return saved_data
	return _generate_chunk_blocks(coord)

func _load_saved_chunk_data(coord: Vector2i) -> PackedInt32Array:
	var empty: PackedInt32Array = PackedInt32Array()
	var path: String = _chunk_save_path(coord)
	if not FileAccess.file_exists(path):
		return empty

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return empty

	var loaded: Variant = file.get_var()
	if loaded is Dictionary:
		var payload: Dictionary = loaded
		if int(payload.get("version", -1)) != SAVE_FORMAT_VERSION:
			return empty
		var blocks_variant: Variant = payload.get("blocks", null)
		if blocks_variant is PackedInt32Array:
			var blocks_data: PackedInt32Array = blocks_variant
			if blocks_data.size() == CHUNK_VOLUME:
				chunk_cache_stamp_msec[coord] = Time.get_ticks_msec()
				return blocks_data

	return empty

func _save_chunk_data(coord: Vector2i) -> void:
	if not chunk_blocks.has(coord):
		return

	_ensure_save_directories()
	var path: String = _chunk_save_path(coord)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to save chunk %s" % [coord])
		return

	var payload: Dictionary = {
		"version": SAVE_FORMAT_VERSION,
		"blocks": chunk_blocks[coord],
	}
	file.store_var(payload)
	file.flush()
	chunk_dirty[coord] = false
	chunk_cache_stamp_msec[coord] = Time.get_ticks_msec()

func _start_generation_workers() -> void:
	generation_shutdown = false
	var thread_count: int = maxi(1, generator_thread_count)

	for _i in range(thread_count):
		var thread: Thread = Thread.new()
		thread.start(Callable(self, "_generation_worker_loop"))
		generation_threads.append(thread)

func _stop_generation_workers() -> void:
	if generation_threads.is_empty():
		return

	generation_queue_mutex.lock()
	generation_shutdown = true
	generation_queue_mutex.unlock()
	for _i in range(generation_threads.size()):
		generation_semaphore.post()

	for thread in generation_threads:
		thread.wait_to_finish()

	generation_threads.clear()

func _generation_worker_loop() -> void:
	var worker_height_noise: FastNoiseLite = _create_height_noise(seed)
	var worker_detail_noise: FastNoiseLite = _create_detail_noise(seed)

	while true:
		generation_semaphore.wait()

		var has_job: bool = false
		var coord: Vector2i = Vector2i.ZERO

		generation_queue_mutex.lock()
		if generation_shutdown:
			generation_queue_mutex.unlock()
			return
		if not generation_job_queue.is_empty():
			coord = generation_job_queue.pop_front()
			has_job = true
		generation_queue_mutex.unlock()

		if not has_job:
			continue

		var data: PackedInt32Array = _generate_chunk_blocks_with_noise(coord, worker_height_noise, worker_detail_noise)

		generation_result_mutex.lock()
		generation_results.append({
			"coord": coord,
			"data": data,
		})
		generation_result_mutex.unlock()

func _create_height_noise(noise_seed: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.0075
	return noise

func _create_detail_noise(noise_seed: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed ^ 0x6E624EB7
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.02
	return noise

func _generate_chunk_blocks(coord: Vector2i) -> PackedInt32Array:
	return _generate_chunk_blocks_with_noise(
		coord,
		_create_height_noise(seed),
		_create_detail_noise(seed)
	)

func _generate_chunk_blocks_with_noise(
	coord: Vector2i,
	height_noise: FastNoiseLite,
	detail_noise: FastNoiseLite
) -> PackedInt32Array:
	var data: PackedInt32Array = PackedInt32Array()
	data.resize(CHUNK_VOLUME)

	for z in range(CHUNK_WIDTH):
		for x in range(CHUNK_WIDTH):
			var wx: int = coord.x * CHUNK_WIDTH + x
			var wz: int = coord.y * CHUNK_WIDTH + z
			var height: int = _sample_height(wx, wz, height_noise, detail_noise)

			for y in range(height + 1):
				var id: int = BlockDefs.STONE
				if y == height:
					id = BlockDefs.GRASS
				elif y >= height - 3:
					id = BlockDefs.DIRT

				if y < SEA_LEVEL - 6 and y % 9 == 0:
					id = BlockDefs.COBBLE

				data[to_index(x, y, z)] = id

	return data

func _sample_height(
	wx: int,
	wz: int,
	height_noise: FastNoiseLite,
	detail_noise: FastNoiseLite
) -> int:
	var h0: float = height_noise.get_noise_2d(wx, wz) * 18.0
	var h1: float = detail_noise.get_noise_2d(wx, wz) * 6.0
	var h: int = int(round(SEA_LEVEL + h0 + h1))
	return clampi(h, 8, WORLD_HEIGHT - 2)

static func to_index(x: int, y: int, z: int) -> int:
	return x + z * CHUNK_WIDTH + y * CHUNK_WIDTH * CHUNK_WIDTH

func get_block_global(pos: Vector3i) -> int:
	if pos.y < 0 or pos.y >= WORLD_HEIGHT:
		return BlockDefs.AIR

	var chunk_coord: Vector2i = _world_to_chunk(pos)
	if not chunk_blocks.has(chunk_coord):
		return BlockDefs.AIR

	var local: Vector3i = _world_to_local(pos)
	var data: PackedInt32Array = chunk_blocks[chunk_coord]
	return data[to_index(local.x, local.y, local.z)]

func set_block_global(pos: Vector3i, block_id: int) -> void:
	if pos.y < 0 or pos.y >= WORLD_HEIGHT:
		return

	var chunk_coord: Vector2i = _world_to_chunk(pos)
	if not chunk_blocks.has(chunk_coord):
		_register_chunk_data(chunk_coord, _load_or_generate_chunk_data(chunk_coord), false)

	_instantiate_chunk(chunk_coord)

	var local: Vector3i = _world_to_local(pos)
	var data: PackedInt32Array = chunk_blocks[chunk_coord]
	var block_index: int = to_index(local.x, local.y, local.z)
	if data[block_index] == block_id:
		return

	data[block_index] = block_id
	chunk_dirty[chunk_coord] = true
	chunk_cache_stamp_msec[chunk_coord] = Time.get_ticks_msec()

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
	var lx: int = pos.x - _floor_div(pos.x, CHUNK_WIDTH) * CHUNK_WIDTH
	var lz: int = pos.z - _floor_div(pos.z, CHUNK_WIDTH) * CHUNK_WIDTH
	return Vector3i(lx, pos.y, lz)

func _floor_div(a: int, b: int) -> int:
	return floori(float(a) / float(b))

func _chunk_distance_sq(center: Vector2i, coord: Vector2i) -> int:
	var dx: int = coord.x - center.x
	var dz: int = coord.y - center.y
	return dx * dx + dz * dz

func _chunk_chebyshev_distance(center: Vector2i, coord: Vector2i) -> int:
	return maxi(absi(coord.x - center.x), absi(coord.y - center.y))

