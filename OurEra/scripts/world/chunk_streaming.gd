class_name ChunkStreaming
extends RefCounted

const WorldConstants = preload("res://scripts/world/world_constants.gd")
const VoxelChunkScript = preload("res://scripts/voxel_chunk.gd")

var world: Node3D
var storage: WorldStorage
var generator: WorldGenerator
var events: WorldEvents

var load_radius_chunks := 4
var unload_radius_chunks := 6
var collision_radius_chunks := 2
var max_chunk_generations_per_frame := 4
var max_chunk_mesh_updates_per_frame := 2
var max_active_generation_jobs := 8
var max_completed_chunk_integrations_per_frame := 4
var max_cached_clean_chunks := 256

var _chunk_blocks: Dictionary = {}
var _chunk_dirty: Dictionary = {}
var _chunk_cache_stamp_msec: Dictionary = {}
var _chunks: Dictionary = {}

var _pending_generation: Array[Vector2i] = []
var _pending_generation_set: Dictionary = {}
var _generation_active_set: Dictionary = {}

var _pending_mesh: Array[Vector2i] = []
var _pending_mesh_set: Dictionary = {}

func setup(
	p_world: Node3D,
	p_storage: WorldStorage,
	p_generator: WorldGenerator,
	p_events: WorldEvents
) -> void:
	world = p_world
	storage = p_storage
	generator = p_generator
	events = p_events

func apply_settings(settings: Dictionary) -> void:
	load_radius_chunks = int(settings.get("load_radius_chunks", load_radius_chunks))
	unload_radius_chunks = maxi(
		int(settings.get("unload_radius_chunks", unload_radius_chunks)),
		load_radius_chunks + 1
	)
	collision_radius_chunks = int(settings.get("collision_radius_chunks", collision_radius_chunks))
	max_chunk_generations_per_frame = int(
		settings.get("max_chunk_generations_per_frame", max_chunk_generations_per_frame)
	)
	max_chunk_mesh_updates_per_frame = int(
		settings.get("max_chunk_mesh_updates_per_frame", max_chunk_mesh_updates_per_frame)
	)
	max_active_generation_jobs = int(settings.get("max_active_generation_jobs", max_active_generation_jobs))
	max_completed_chunk_integrations_per_frame = int(
		settings.get(
			"max_completed_chunk_integrations_per_frame",
			max_completed_chunk_integrations_per_frame
		)
	)
	max_cached_clean_chunks = int(settings.get("max_cached_clean_chunks", max_cached_clean_chunks))

func has_chunk_data(coord: Vector2i) -> bool:
	return _chunk_blocks.has(coord)

func is_chunk_loaded(coord: Vector2i) -> bool:
	return _chunks.has(coord)

func get_loaded_chunk(coord: Vector2i):
	if not _chunks.has(coord):
		return null
	return _chunks[coord]

func force_streaming_update(center: Vector2i) -> void:
	_ensure_chunk_immediate(center, true)
	on_center_chunk_changed(center)
	_integrate_completed_generation_budget(center)
	_dispatch_generation_budget(center)
	_process_mesh_budget(center)
	_trim_chunk_cache()

func on_center_chunk_changed(center: Vector2i) -> void:
	_schedule_chunks_around_center(center)
	_refresh_pending_generation(center)
	_refresh_pending_mesh(center)
	_unload_far_chunks(center)

func process_frame(center: Vector2i) -> void:
	_integrate_completed_generation_budget(center)
	_dispatch_generation_budget(center)
	_process_mesh_budget(center)
	_trim_chunk_cache()

func flush_dirty_chunks() -> void:
	for coord_any in _chunk_dirty.keys():
		var coord: Vector2i = coord_any
		if bool(_chunk_dirty.get(coord, false)):
			_save_chunk_data(coord)

func get_block_global(pos: Vector3i) -> int:
	if pos.y < 0 or pos.y >= WorldConstants.WORLD_HEIGHT:
		return BlockDefs.AIR

	var chunk_coord: Vector2i = WorldConstants.world_to_chunk(pos)
	if not _chunk_blocks.has(chunk_coord):
		return BlockDefs.AIR

	var local: Vector3i = WorldConstants.world_to_local(pos)
	var data: PackedInt32Array = _chunk_blocks[chunk_coord]
	return data[WorldConstants.to_index(local.x, local.y, local.z)]

func set_block_global(pos: Vector3i, block_id: int) -> void:
	if pos.y < 0 or pos.y >= WorldConstants.WORLD_HEIGHT:
		return

	var chunk_coord: Vector2i = WorldConstants.world_to_chunk(pos)
	if not _chunk_blocks.has(chunk_coord):
		_register_chunk_data(chunk_coord, _load_or_generate_chunk_data(chunk_coord), false)

	_instantiate_chunk(chunk_coord)

	var local: Vector3i = WorldConstants.world_to_local(pos)
	var data: PackedInt32Array = _chunk_blocks[chunk_coord]
	var block_index: int = WorldConstants.to_index(local.x, local.y, local.z)
	if data[block_index] == block_id:
		return

	data[block_index] = block_id
	_chunk_dirty[chunk_coord] = true
	_chunk_cache_stamp_msec[chunk_coord] = Time.get_ticks_msec()
	events.chunk_changed.emit(chunk_coord)

	_queue_chunk_mesh(chunk_coord)
	if local.x == 0:
		_queue_chunk_mesh(Vector2i(chunk_coord.x - 1, chunk_coord.y))
	elif local.x == WorldConstants.CHUNK_WIDTH - 1:
		_queue_chunk_mesh(Vector2i(chunk_coord.x + 1, chunk_coord.y))

	if local.z == 0:
		_queue_chunk_mesh(Vector2i(chunk_coord.x, chunk_coord.y - 1))
	elif local.z == WorldConstants.CHUNK_WIDTH - 1:
		_queue_chunk_mesh(Vector2i(chunk_coord.x, chunk_coord.y + 1))

func _schedule_chunks_around_center(center: Vector2i) -> void:
	for dz in range(-load_radius_chunks, load_radius_chunks + 1):
		for dx in range(-load_radius_chunks, load_radius_chunks + 1):
			var coord: Vector2i = Vector2i(center.x + dx, center.y + dz)
			if _chunks.has(coord):
				continue
			if _pending_generation_set.has(coord):
				continue
			if _generation_active_set.has(coord):
				continue
			_pending_generation.append(coord)
			_pending_generation_set[coord] = true

func _refresh_pending_generation(center: Vector2i) -> void:
	var next_queue: Array[Vector2i] = []
	for coord_any in _pending_generation_set.keys():
		var coord: Vector2i = coord_any
		if _chunks.has(coord):
			continue
		if _generation_active_set.has(coord):
			continue
		if WorldConstants.chunk_chebyshev_distance(center, coord) > unload_radius_chunks:
			continue
		next_queue.append(coord)

	next_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return WorldConstants.chunk_distance_sq(center, a) < WorldConstants.chunk_distance_sq(center, b)
	)

	_pending_generation = next_queue
	_pending_generation_set.clear()
	for coord in _pending_generation:
		_pending_generation_set[coord] = true

func _dispatch_generation_budget(center: Vector2i) -> void:
	var dispatched: int = 0

	while dispatched < max_chunk_generations_per_frame:
		if _pending_generation.is_empty():
			return
		if _generation_active_set.size() >= max_active_generation_jobs:
			return

		var coord: Vector2i = _pending_generation.pop_front()
		_pending_generation_set.erase(coord)

		if WorldConstants.chunk_chebyshev_distance(center, coord) > unload_radius_chunks:
			continue
		if _chunks.has(coord):
			continue

		if _chunk_blocks.has(coord):
			_instantiate_chunk(coord)
			_queue_chunk_mesh(coord)
			_queue_neighbor_meshes(coord)
			dispatched += 1
			continue

		var saved_data: PackedInt32Array = storage.load_chunk_data(coord)
		if saved_data.size() == WorldConstants.CHUNK_VOLUME:
			_register_chunk_data(coord, saved_data, false)
			_instantiate_chunk(coord)
			_queue_chunk_mesh(coord)
			_queue_neighbor_meshes(coord)
			dispatched += 1
			continue

		_generation_active_set[coord] = true
		generator.queue_chunk(coord)
		dispatched += 1

func _integrate_completed_generation_budget(center: Vector2i) -> void:
	for result in generator.consume_completed(max_completed_chunk_integrations_per_frame):
		var coord: Vector2i = result["coord"]
		var data: PackedInt32Array = result["data"]
		_generation_active_set.erase(coord)

		if not _chunk_blocks.has(coord):
			_register_chunk_data(coord, data, false)

		if WorldConstants.chunk_chebyshev_distance(center, coord) <= load_radius_chunks:
			_instantiate_chunk(coord)
			_queue_chunk_mesh(coord)
			_queue_neighbor_meshes(coord)

func _ensure_chunk_immediate(coord: Vector2i, with_collision: bool) -> void:
	if not _chunk_blocks.has(coord):
		_register_chunk_data(coord, _load_or_generate_chunk_data(coord), false)

	_instantiate_chunk(coord)
	var chunk = _chunks[coord]
	chunk.refresh_render(with_collision)

func _instantiate_chunk(coord: Vector2i) -> void:
	if _chunks.has(coord):
		return
	if not _chunk_blocks.has(coord):
		return

	var chunk = VoxelChunkScript.new()
	world.add_child(chunk)
	chunk.initialize(world, coord, _chunk_blocks[coord])
	_chunks[coord] = chunk
	events.chunk_loaded.emit(coord, chunk)

func _process_mesh_budget(center: Vector2i) -> void:
	var count: int = mini(max_chunk_mesh_updates_per_frame, _pending_mesh.size())
	for _i in range(count):
		var coord: Vector2i = _pending_mesh.pop_front()
		_pending_mesh_set.erase(coord)

		if not _chunks.has(coord):
			continue

		var chunk = _chunks[coord]
		var collision_enabled: bool = (
			WorldConstants.chunk_chebyshev_distance(center, coord) <= collision_radius_chunks
		)
		chunk.refresh_render(collision_enabled)

func _queue_chunk_mesh(coord: Vector2i) -> void:
	if not _chunks.has(coord):
		return
	if _pending_mesh_set.has(coord):
		return
	_pending_mesh.append(coord)
	_pending_mesh_set[coord] = true

func _refresh_pending_mesh(center: Vector2i) -> void:
	var next_queue: Array[Vector2i] = []
	for coord_any in _pending_mesh_set.keys():
		var coord: Vector2i = coord_any
		if not _chunks.has(coord):
			continue
		if WorldConstants.chunk_chebyshev_distance(center, coord) > unload_radius_chunks:
			continue
		next_queue.append(coord)

	next_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return WorldConstants.chunk_distance_sq(center, a) < WorldConstants.chunk_distance_sq(center, b)
	)

	_pending_mesh = next_queue
	_pending_mesh_set.clear()
	for coord in _pending_mesh:
		_pending_mesh_set[coord] = true

func _queue_neighbor_meshes(coord: Vector2i) -> void:
	_queue_chunk_mesh(Vector2i(coord.x + 1, coord.y))
	_queue_chunk_mesh(Vector2i(coord.x - 1, coord.y))
	_queue_chunk_mesh(Vector2i(coord.x, coord.y + 1))
	_queue_chunk_mesh(Vector2i(coord.x, coord.y - 1))

func _unload_far_chunks(center: Vector2i) -> void:
	var keys: Array = _chunks.keys()
	for coord_any in keys:
		var coord: Vector2i = coord_any
		if WorldConstants.chunk_chebyshev_distance(center, coord) <= unload_radius_chunks:
			continue

		if bool(_chunk_dirty.get(coord, false)):
			_save_chunk_data(coord)

		var chunk = _chunks[coord]
		chunk.queue_free()
		_chunks.erase(coord)
		_pending_mesh_set.erase(coord)
		_chunk_cache_stamp_msec[coord] = Time.get_ticks_msec()
		events.chunk_unloaded.emit(coord)

func _trim_chunk_cache() -> void:
	var clean_unloaded: Array[Vector2i] = []
	for coord_any in _chunk_blocks.keys():
		var coord: Vector2i = coord_any
		if _chunks.has(coord):
			continue
		if bool(_chunk_dirty.get(coord, false)):
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
	if _chunks.has(coord):
		return
	_chunk_blocks.erase(coord)
	_chunk_dirty.erase(coord)
	_chunk_cache_stamp_msec.erase(coord)
	events.chunk_data_evicted.emit(coord)

func _register_chunk_data(coord: Vector2i, data: PackedInt32Array, dirty: bool) -> void:
	_chunk_blocks[coord] = data
	_chunk_dirty[coord] = dirty
	_chunk_cache_stamp_msec[coord] = Time.get_ticks_msec()
	events.chunk_data_registered.emit(coord, dirty)

func _cache_stamp_for(coord: Vector2i) -> int:
	if _chunk_cache_stamp_msec.has(coord):
		return int(_chunk_cache_stamp_msec[coord])
	return 0

func _load_or_generate_chunk_data(coord: Vector2i) -> PackedInt32Array:
	var saved_data: PackedInt32Array = storage.load_chunk_data(coord)
	if saved_data.size() == WorldConstants.CHUNK_VOLUME:
		return saved_data
	return generator.generate_chunk(coord)

func _save_chunk_data(coord: Vector2i) -> void:
	if not _chunk_blocks.has(coord):
		return

	if not storage.save_chunk_data(coord, _chunk_blocks[coord]):
		return

	_chunk_dirty[coord] = false
	_chunk_cache_stamp_msec[coord] = Time.get_ticks_msec()
	events.chunk_saved.emit(coord)
