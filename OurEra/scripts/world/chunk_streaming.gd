class_name ChunkStreaming
extends RefCounted

const WorldConstants = preload("res://scripts/world/world_constants.gd")
const VoxelChunkScript = preload("res://scripts/voxel_chunk.gd")
const CHUNK_RENDER_NONE := 0
const CHUNK_RENDER_MESH := 1
const CHUNK_RENDER_MESH_WITH_COLLISION := 2
const MESH_PRIORITY_PRIMARY := 0
const MESH_PRIORITY_NEIGHBOR := 1

var world: Node3D
var storage: WorldStorage
var generator: WorldGenerator
var events: WorldEvents

var load_radius_chunks := 4
var unload_radius_chunks := 6
var collision_radius_chunks := 2
var mesh_priority_radius_chunks := 3
var center_change_mesh_cooldown_frames := 12
var movement_mesh_updates_per_frame := 1
var mesh_stage_target_usec := 280000
var max_chunk_generations_per_frame := 4
var max_chunk_mesh_updates_per_frame := 2
var max_chunk_collision_updates_per_frame := 1
var startup_mesh_warmup_frames := 1
var startup_mesh_updates_per_frame := 0
var startup_collision_updates_per_frame := 0
var max_active_generation_jobs := 8
var max_completed_chunk_integrations_per_frame := 4
var max_cached_clean_chunks := 256
var collect_runtime_profile := false

var _chunk_blocks: Dictionary = {}
var _chunk_dirty: Dictionary = {}
var _chunk_cache_stamp_msec: Dictionary = {}
var _chunk_collision_state: Dictionary = {}
var _chunk_render_state: Dictionary = {}
var _chunks: Dictionary = {}

var _pending_generation: Array[Vector2i] = []
var _pending_generation_set: Dictionary = {}
var _generation_active_set: Dictionary = {}

var _pending_mesh: Array[Vector2i] = []
var _pending_mesh_set: Dictionary = {}
var _pending_mesh_priority: Dictionary = {}
var _pending_collision: Array[Vector2i] = []
var _pending_collision_set: Dictionary = {}

var _startup_mesh_warmup_frames_left := 0
var _center_change_mesh_cooldown_left := 0
var _recent_mesh_usec_per_chunk := 0.0
var _last_profile_frame: Dictionary = {}
var _last_immediate_profile: Dictionary = {}

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
	mesh_priority_radius_chunks = mini(
		load_radius_chunks,
		maxi(1, int(settings.get("mesh_priority_radius_chunks", mesh_priority_radius_chunks)))
	)
	center_change_mesh_cooldown_frames = maxi(0, int(settings.get("center_change_mesh_cooldown_frames", center_change_mesh_cooldown_frames)))
	movement_mesh_updates_per_frame = maxi(1, int(settings.get("movement_mesh_updates_per_frame", movement_mesh_updates_per_frame)))
	mesh_stage_target_usec = maxi(0, int(settings.get("mesh_stage_target_usec", mesh_stage_target_usec)))
	max_chunk_generations_per_frame = int(
		settings.get("max_chunk_generations_per_frame", max_chunk_generations_per_frame)
	)
	max_chunk_mesh_updates_per_frame = int(
		settings.get("max_chunk_mesh_updates_per_frame", max_chunk_mesh_updates_per_frame)
	)
	max_chunk_collision_updates_per_frame = int(
		settings.get("max_chunk_collision_updates_per_frame", max_chunk_collision_updates_per_frame)
	)
	startup_mesh_warmup_frames = int(
		settings.get("startup_mesh_warmup_frames", startup_mesh_warmup_frames)
	)
	startup_mesh_updates_per_frame = int(
		settings.get("startup_mesh_updates_per_frame", startup_mesh_updates_per_frame)
	)
	startup_collision_updates_per_frame = int(
		settings.get("startup_collision_updates_per_frame", startup_collision_updates_per_frame)
	)
	max_active_generation_jobs = int(settings.get("max_active_generation_jobs", max_active_generation_jobs))
	max_completed_chunk_integrations_per_frame = int(
		settings.get(
			"max_completed_chunk_integrations_per_frame",
			max_completed_chunk_integrations_per_frame
		)
	)
	max_cached_clean_chunks = int(settings.get("max_cached_clean_chunks", max_cached_clean_chunks))
	collect_runtime_profile = bool(settings.get("collect_runtime_profile", collect_runtime_profile))

func has_chunk_data(coord: Vector2i) -> bool:
	return _chunk_blocks.has(coord)

func is_chunk_loaded(coord: Vector2i) -> bool:
	return _chunks.has(coord)

func get_loaded_chunk(coord: Vector2i):
	if not _chunks.has(coord):
		return null
	return _chunks[coord]

func get_loaded_chunk_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord_any in _chunks.keys():
		coords.append(coord_any)
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y
	)
	return coords

func get_chunk_state(coord: Vector2i) -> Dictionary:
	return {
		"coord": coord,
		"has_data": _chunk_blocks.has(coord),
		"loaded": _chunks.has(coord),
		"dirty": bool(_chunk_dirty.get(coord, false)),
		"render_state": _get_chunk_render_state(coord),
		"collision_enabled": bool(_chunk_collision_state.get(coord, false)),
		"ready": is_chunk_ready(coord, false),
		"ready_for_entities": is_chunk_ready(coord, true),
	}

func is_chunk_ready(coord: Vector2i, require_collision: bool = false) -> bool:
	if not _chunks.has(coord):
		return false
	if _get_chunk_render_state(coord) < CHUNK_RENDER_MESH:
		return false
	if require_collision:
		return bool(_chunk_collision_state.get(coord, false))
	return true

func get_last_profile_frame() -> Dictionary:
	return _last_profile_frame.duplicate(true)

func get_debug_snapshot() -> Dictionary:
	return {
		"pending_generation": _pending_generation.size(),
		"pending_generation_set": _pending_generation_set.size(),
		"pending_mesh": _pending_mesh.size(),
		"pending_mesh_set": _pending_mesh_set.size(),
		"pending_mesh_priority": _pending_mesh_priority.size(),
		"pending_collision": _pending_collision.size(),
		"pending_collision_set": _pending_collision_set.size(),
		"loaded_chunks": _chunks.size(),
		"cached_chunks": _chunk_blocks.size(),
	}

func consume_last_immediate_profile() -> Dictionary:
	var profile := _last_immediate_profile.duplicate(true)
	_last_immediate_profile = {}
	return profile

func get_chunk_meshing_neighbors(coord: Vector2i) -> Dictionary:
	return {
		"neg_x": _extract_chunk_border(Vector2i(coord.x - 1, coord.y), 0, WorldConstants.CHUNK_WIDTH - 1),
		"pos_x": _extract_chunk_border(Vector2i(coord.x + 1, coord.y), 0, 0),
		"neg_z": _extract_chunk_border(Vector2i(coord.x, coord.y - 1), 1, WorldConstants.CHUNK_WIDTH - 1),
		"pos_z": _extract_chunk_border(Vector2i(coord.x, coord.y + 1), 1, 0),
	}

func begin_startup_warmup() -> void:
	_startup_mesh_warmup_frames_left = maxi(_startup_mesh_warmup_frames_left, startup_mesh_warmup_frames)

func ensure_chunk_immediate(coord: Vector2i, with_collision: bool = true) -> void:
	var profile := _new_profile_frame("immediate", coord) if collect_runtime_profile else {}
	_ensure_chunk_immediate(coord, with_collision, profile)
	if collect_runtime_profile:
		_last_immediate_profile = profile.duplicate(true)


func ensure_chunk_collision_immediate(coord: Vector2i) -> void:
	var profile := _new_profile_frame("immediate_collision", coord) if collect_runtime_profile else {}
	_ensure_chunk_collision_immediate(coord, profile)
	if collect_runtime_profile:
		_last_immediate_profile = profile.duplicate(true)

func force_streaming_update(center: Vector2i) -> void:
	var frame_profile := _new_profile_frame("force_streaming", center) if collect_runtime_profile else {}
	var frame_started_usec := Time.get_ticks_usec() if collect_runtime_profile else 0
	_ensure_chunk_immediate(center, true, frame_profile)
	on_center_chunk_changed(center)
	_integrate_completed_generation_budget(center, frame_profile)
	_dispatch_generation_budget(center, frame_profile)
	_sync_collision_targets(center, _allow_collision_updates(), frame_profile)
	_process_mesh_budget(center, _allow_collision_updates(), frame_profile)
	_sync_collision_targets(center, _allow_collision_updates(), frame_profile)
	_process_collision_budget(center, _allow_collision_updates(), frame_profile)
	_trim_chunk_cache()
	_advance_startup_warmup()
	_advance_center_change_cooldown()
	if collect_runtime_profile:
		frame_profile["queues"] = get_debug_snapshot()
		frame_profile["frame_total_usec"] = Time.get_ticks_usec() - frame_started_usec
		_last_profile_frame = frame_profile.duplicate(true)

func on_center_chunk_changed(center: Vector2i) -> void:
	_center_change_mesh_cooldown_left = center_change_mesh_cooldown_frames
	_schedule_chunks_around_center(center)
	_refresh_pending_generation(center)
	_refresh_pending_mesh(center)
	_unload_far_chunks(center)
	_sync_collision_targets(center, _allow_collision_updates())

func process_frame(center: Vector2i) -> void:
	var allow_collision := _allow_collision_updates()
	var frame_profile := _new_profile_frame("process", center) if collect_runtime_profile else {}
	var frame_started_usec := Time.get_ticks_usec() if collect_runtime_profile else 0
	_integrate_completed_generation_budget(center, frame_profile)
	_dispatch_generation_budget(center, frame_profile)
	_sync_collision_targets(center, allow_collision, frame_profile)
	_process_mesh_budget(center, allow_collision, frame_profile)
	_sync_collision_targets(center, allow_collision, frame_profile)
	_process_collision_budget(center, allow_collision, frame_profile)
	_trim_chunk_cache()
	_advance_startup_warmup()
	_advance_center_change_cooldown()
	if collect_runtime_profile:
		frame_profile["queues"] = get_debug_snapshot()
		frame_profile["frame_total_usec"] = Time.get_ticks_usec() - frame_started_usec
		_last_profile_frame = frame_profile.duplicate(true)

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

func _dispatch_generation_budget(center: Vector2i, profile: Dictionary = {}) -> void:
	var dispatched: int = 0
	var stage_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0

	while dispatched < max_chunk_generations_per_frame:
		if _pending_generation.is_empty():
			break
		if _generation_active_set.size() >= max_active_generation_jobs:
			break

		var coord: Vector2i = _pending_generation.pop_front()
		_pending_generation_set.erase(coord)

		if WorldConstants.chunk_chebyshev_distance(center, coord) > unload_radius_chunks:
			continue
		if _chunks.has(coord):
			continue

		if _chunk_blocks.has(coord):
			var instantiate_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
			_instantiate_chunk(coord)
			_add_profile_usec(profile, "dispatch_instantiate_usec", Time.get_ticks_usec() - instantiate_started_usec)
			_add_profile_count(profile, "dispatch_chunk_count", 1)
			_queue_chunk_mesh(coord, MESH_PRIORITY_PRIMARY)
			_queue_neighbor_meshes(coord, center)
			dispatched += 1
			continue

		var sync_load_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
		var saved_data: PackedInt32Array = storage.load_chunk_data(coord)
		_add_profile_usec(profile, "dispatch_sync_load_usec", Time.get_ticks_usec() - sync_load_started_usec)
		if saved_data.size() == WorldConstants.CHUNK_VOLUME:
			_register_chunk_data(coord, saved_data, false)
			var saved_instantiate_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
			_instantiate_chunk(coord)
			_add_profile_usec(profile, "dispatch_instantiate_usec", Time.get_ticks_usec() - saved_instantiate_started_usec)
			_add_profile_count(profile, "dispatch_chunk_count", 1)
			_queue_chunk_mesh(coord, MESH_PRIORITY_PRIMARY)
			_queue_neighbor_meshes(coord, center)
			dispatched += 1
			continue

		_generation_active_set[coord] = true
		generator.queue_chunk(coord)
		_add_profile_count(profile, "generation_queue_count", 1)
		dispatched += 1

	_add_profile_usec(profile, "dispatch_usec", Time.get_ticks_usec() - stage_started_usec)

func _integrate_completed_generation_budget(center: Vector2i, profile: Dictionary = {}) -> void:
	var stage_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
	for result in generator.consume_completed(max_completed_chunk_integrations_per_frame):
		var coord: Vector2i = result["coord"]
		var data: PackedInt32Array = result["data"]
		_generation_active_set.erase(coord)
		_add_profile_count(profile, "integrated_chunk_count", 1)

		if not _chunk_blocks.has(coord):
			_register_chunk_data(coord, data, false)

		if WorldConstants.chunk_chebyshev_distance(center, coord) <= load_radius_chunks:
			var instantiate_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
			_instantiate_chunk(coord)
			_add_profile_usec(profile, "integrate_instantiate_usec", Time.get_ticks_usec() - instantiate_started_usec)
			_queue_chunk_mesh(coord, MESH_PRIORITY_PRIMARY)
			_queue_neighbor_meshes(coord, center)

	_add_profile_usec(profile, "integrate_usec", Time.get_ticks_usec() - stage_started_usec)

func _ensure_chunk_immediate(coord: Vector2i, with_collision: bool, profile: Dictionary = {}) -> void:
	var stage_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
	if not _chunk_blocks.has(coord):
		var load_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
		_register_chunk_data(coord, _load_or_generate_chunk_data(coord), false)
		_add_profile_usec(profile, "immediate_load_or_generate_usec", Time.get_ticks_usec() - load_started_usec)

	var instantiate_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
	_instantiate_chunk(coord)
	_add_profile_usec(profile, "immediate_instantiate_usec", Time.get_ticks_usec() - instantiate_started_usec)
	var chunk = _chunks[coord]
	var requires_mesh_rebuild := _pending_mesh_set.has(coord) or _get_chunk_render_state(coord) < CHUNK_RENDER_MESH
	if requires_mesh_rebuild:
		_pending_mesh_set.erase(coord)
		_pending_mesh.erase(coord)
		_pending_mesh_priority.erase(coord)
		var render_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
		chunk.refresh_render(with_collision)
		_add_profile_usec(profile, "immediate_mesh_stage_usec", Time.get_ticks_usec() - render_started_usec)
		_set_chunk_render_state(coord, CHUNK_RENDER_MESH_WITH_COLLISION if with_collision else CHUNK_RENDER_MESH)
	elif with_collision and _get_chunk_render_state(coord) < CHUNK_RENDER_MESH_WITH_COLLISION:
		_ensure_chunk_collision_immediate(coord, profile)
	_chunk_collision_state[coord] = chunk.has_collision_enabled()
	_add_chunk_render_profile(profile, "immediate", chunk.get_render_stats())
	_add_profile_count(profile, "immediate_chunk_count", 1)
	_add_profile_usec(profile, "immediate_total_usec", Time.get_ticks_usec() - stage_started_usec)

func _ensure_chunk_collision_immediate(coord: Vector2i, profile: Dictionary = {}) -> void:
	if not _chunks.has(coord):
		return
	if _pending_mesh_set.has(coord):
		_ensure_chunk_immediate(coord, true, profile)
		return
	if _get_chunk_render_state(coord) < CHUNK_RENDER_MESH:
		_ensure_chunk_immediate(coord, true, profile)
		return
	if _chunk_collision_state.get(coord, false):
		_set_chunk_render_state(coord, CHUNK_RENDER_MESH_WITH_COLLISION)
		return

	_pending_collision_set.erase(coord)
	_pending_collision.erase(coord)
	var chunk = _chunks[coord]
	var collision_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
	chunk.sync_collision(true)
	_add_profile_usec(profile, "immediate_collision_stage_usec", Time.get_ticks_usec() - collision_started_usec)
	_add_chunk_render_profile(profile, "immediate", chunk.get_render_stats())
	_chunk_collision_state[coord] = chunk.has_collision_enabled()
	if _chunk_collision_state[coord]:
		_set_chunk_render_state(coord, CHUNK_RENDER_MESH_WITH_COLLISION)

func _instantiate_chunk(coord: Vector2i) -> void:
	if _chunks.has(coord):
		return
	if not _chunk_blocks.has(coord):
		return

	var chunk = VoxelChunkScript.new()
	world.add_child(chunk)
	chunk.initialize(world, coord, _chunk_blocks[coord])
	_chunks[coord] = chunk
	_chunk_collision_state[coord] = false
	_chunk_render_state[coord] = CHUNK_RENDER_NONE
	events.chunk_loaded.emit(coord, chunk)

func _process_mesh_budget(center: Vector2i, allow_collision: bool, profile: Dictionary = {}) -> void:
	var count: int = mini(_mesh_budget_for_frame(), _pending_mesh.size())
	var stage_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
	for _i in range(count):
		var coord: Vector2i = _pending_mesh.pop_front()
		_pending_mesh_set.erase(coord)
		_pending_mesh_priority.erase(coord)

		if not _chunks.has(coord):
			continue

		var chunk = _chunks[coord]
		var had_collision := bool(_chunk_collision_state.get(coord, false))
		var render_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
		chunk.refresh_render(false)
		_add_profile_usec(profile, "mesh_stage_usec", Time.get_ticks_usec() - render_started_usec)
		_add_chunk_render_profile(profile, "mesh", chunk.get_render_stats())
		_add_profile_count(profile, "mesh_chunk_count", 1)
		_set_chunk_render_state(coord, CHUNK_RENDER_MESH)
		_chunk_collision_state[coord] = had_collision
		var wants_collision := _desired_collision_state(center, coord, allow_collision)
		if had_collision or wants_collision:
			_queue_collision_sync(coord, had_collision)

	if count > 0 and not profile.is_empty() and int(profile.get("mesh_chunk_count", 0)) > 0:
		var chunk_count := int(profile.get("mesh_chunk_count", 0))
		var per_chunk_usec := float(int(profile.get("mesh_stage_usec", 0))) / float(chunk_count)
		_recent_mesh_usec_per_chunk = per_chunk_usec if _recent_mesh_usec_per_chunk <= 0.0 else lerpf(_recent_mesh_usec_per_chunk, per_chunk_usec, 0.35)

	_add_profile_usec(profile, "mesh_queue_usec", Time.get_ticks_usec() - stage_started_usec)

func _process_collision_budget(center: Vector2i, allow_collision: bool, profile: Dictionary = {}) -> void:
	var count: int = mini(_collision_budget_for_frame(allow_collision), _pending_collision.size())
	var stage_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
	for _i in range(count):
		var coord: Vector2i = _pending_collision.pop_front()
		_pending_collision_set.erase(coord)

		if not _chunks.has(coord):
			continue

		var desired := _desired_collision_state(center, coord, allow_collision)
		var chunk = _chunks[coord]
		var collision_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
		chunk.sync_collision(desired)
		_add_profile_usec(profile, "collision_stage_usec", Time.get_ticks_usec() - collision_started_usec)
		_add_chunk_render_profile(profile, "collision", chunk.get_render_stats())
		_add_profile_count(profile, "collision_chunk_count", 1)
		_chunk_collision_state[coord] = chunk.has_collision_enabled()
		if _chunk_collision_state[coord]:
			_set_chunk_render_state(coord, CHUNK_RENDER_MESH_WITH_COLLISION)
		elif _get_chunk_render_state(coord) >= CHUNK_RENDER_MESH:
			_set_chunk_render_state(coord, CHUNK_RENDER_MESH)

	_add_profile_usec(profile, "collision_queue_usec", Time.get_ticks_usec() - stage_started_usec)

func _queue_chunk_mesh(coord: Vector2i, priority: int = MESH_PRIORITY_PRIMARY) -> void:
	if not _chunks.has(coord):
		return
	if _pending_mesh_set.has(coord):
		var existing_priority := int(_pending_mesh_priority.get(coord, priority))
		if priority < existing_priority:
			_pending_mesh_priority[coord] = priority
		return
	_pending_mesh.append(coord)
	_pending_mesh_set[coord] = true
	_pending_mesh_priority[coord] = priority

func _queue_collision_sync(coord: Vector2i, prioritize: bool = false) -> void:
	if not _chunks.has(coord):
		return
	if _pending_collision_set.has(coord):
		return
	if prioritize:
		_pending_collision.push_front(coord)
	else:
		_pending_collision.append(coord)
	_pending_collision_set[coord] = true

func _refresh_pending_mesh(center: Vector2i) -> void:
	var next_queue: Array[Vector2i] = []
	var next_priority: Dictionary = {}
	for coord_any in _pending_mesh_set.keys():
		var coord: Vector2i = coord_any
		if not _chunks.has(coord):
			continue
		if WorldConstants.chunk_chebyshev_distance(center, coord) > unload_radius_chunks:
			continue
		next_queue.append(coord)
		next_priority[coord] = int(_pending_mesh_priority.get(coord, MESH_PRIORITY_PRIMARY))

	next_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_bucket := _mesh_distance_bucket(center, a)
		var b_bucket := _mesh_distance_bucket(center, b)
		if a_bucket != b_bucket:
			return a_bucket < b_bucket
		var a_priority := int(next_priority.get(a, MESH_PRIORITY_PRIMARY))
		var b_priority := int(next_priority.get(b, MESH_PRIORITY_PRIMARY))
		if a_priority != b_priority:
			return a_priority < b_priority
		return WorldConstants.chunk_distance_sq(center, a) < WorldConstants.chunk_distance_sq(center, b)
	)

	_pending_mesh = next_queue
	_pending_mesh_set.clear()
	_pending_mesh_priority.clear()
	for coord in _pending_mesh:
		_pending_mesh_set[coord] = true
		_pending_mesh_priority[coord] = int(next_priority.get(coord, MESH_PRIORITY_PRIMARY))

func _refresh_pending_collision(center: Vector2i) -> void:
	var next_queue: Array[Vector2i] = []
	for coord_any in _pending_collision_set.keys():
		var coord: Vector2i = coord_any
		if not _chunks.has(coord):
			continue
		if WorldConstants.chunk_chebyshev_distance(center, coord) > unload_radius_chunks:
			continue
		next_queue.append(coord)

	next_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return WorldConstants.chunk_distance_sq(center, a) < WorldConstants.chunk_distance_sq(center, b)
	)

	_pending_collision = next_queue
	_pending_collision_set.clear()
	for coord in _pending_collision:
		_pending_collision_set[coord] = true

func _queue_neighbor_meshes(coord: Vector2i, center: Vector2i) -> void:
	_queue_neighbor_mesh(coord, Vector2i(coord.x + 1, coord.y), center)
	_queue_neighbor_mesh(coord, Vector2i(coord.x - 1, coord.y), center)
	_queue_neighbor_mesh(coord, Vector2i(coord.x, coord.y + 1), center)
	_queue_neighbor_mesh(coord, Vector2i(coord.x, coord.y - 1), center)

func _sync_collision_targets(center: Vector2i, allow_collision: bool, profile: Dictionary = {}) -> void:
	var stage_started_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
	for coord_any in _chunks.keys():
		var coord: Vector2i = coord_any
		var current := bool(_chunk_collision_state.get(coord, false))
		var desired := _desired_collision_state(center, coord, allow_collision)
		if not allow_collision and current:
			desired = true
		if desired == current:
			continue
		_queue_collision_sync(coord, current)

	_refresh_pending_collision(center)
	_add_profile_usec(profile, "collision_target_sync_usec", Time.get_ticks_usec() - stage_started_usec)

func _desired_collision_state(center: Vector2i, coord: Vector2i, allow_collision: bool) -> bool:
	if not allow_collision:
		return false
	return WorldConstants.chunk_chebyshev_distance(center, coord) <= collision_radius_chunks

func _allow_collision_updates() -> bool:
	return _startup_mesh_warmup_frames_left <= 0

func _mesh_budget_for_frame() -> int:
	if _startup_mesh_warmup_frames_left > 0:
		return mini(max_chunk_mesh_updates_per_frame, startup_mesh_updates_per_frame)
	var budget := max_chunk_mesh_updates_per_frame
	if _center_change_mesh_cooldown_left > 0:
		budget = mini(budget, movement_mesh_updates_per_frame)
	if mesh_stage_target_usec > 0 and _recent_mesh_usec_per_chunk > 0.0:
		var adaptive_budget := maxi(1, int(floor(float(mesh_stage_target_usec) / _recent_mesh_usec_per_chunk)))
		budget = mini(budget, adaptive_budget)
	return maxi(1, budget)

func _collision_budget_for_frame(allow_collision: bool) -> int:
	if allow_collision:
		return max_chunk_collision_updates_per_frame
	return startup_collision_updates_per_frame

func _advance_startup_warmup() -> void:
	if _startup_mesh_warmup_frames_left > 0:
		_startup_mesh_warmup_frames_left -= 1

func _advance_center_change_cooldown() -> void:
	if _center_change_mesh_cooldown_left > 0:
		_center_change_mesh_cooldown_left -= 1

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
		_pending_mesh_priority.erase(coord)
		_pending_collision_set.erase(coord)
		_chunk_collision_state.erase(coord)
		_chunk_render_state.erase(coord)
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
	_chunk_collision_state.erase(coord)
	_chunk_render_state.erase(coord)
	_pending_mesh_priority.erase(coord)
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

func _extract_chunk_border(coord: Vector2i, border_axis: int, fixed_index: int) -> PackedInt32Array:
	if not _chunk_blocks.has(coord):
		return PackedInt32Array()

	var data: PackedInt32Array = _chunk_blocks[coord]
	if data.size() != WorldConstants.CHUNK_VOLUME:
		return PackedInt32Array()

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

func _mesh_distance_bucket(center: Vector2i, coord: Vector2i) -> int:
	return 0 if WorldConstants.chunk_chebyshev_distance(center, coord) <= mesh_priority_radius_chunks else 1

func _neighbor_mesh_priority(center: Vector2i, coord: Vector2i) -> int:
	if WorldConstants.chunk_chebyshev_distance(center, coord) <= mesh_priority_radius_chunks:
		return MESH_PRIORITY_PRIMARY
	return MESH_PRIORITY_NEIGHBOR

func _queue_neighbor_mesh(source_coord: Vector2i, neighbor_coord: Vector2i, center: Vector2i) -> void:
	if not _chunks.has(neighbor_coord):
		return
	if _get_chunk_render_state(neighbor_coord) < CHUNK_RENDER_MESH:
		return
	if WorldConstants.chunk_chebyshev_distance(center, neighbor_coord) > load_radius_chunks:
		return
	_queue_chunk_mesh(neighbor_coord, _neighbor_mesh_priority(center, neighbor_coord))

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

func _new_profile_frame(frame_kind: String, center: Vector2i) -> Dictionary:
	return {
		"frame_kind": frame_kind,
		"center_chunk": center,
		"frame_total_usec": 0,
		"immediate_total_usec": 0,
		"immediate_load_or_generate_usec": 0,
		"immediate_instantiate_usec": 0,
		"immediate_mesh_stage_usec": 0,
		"immediate_chunk_count": 0,
		"immediate_coords": [],
		"immediate_mesh_build_usec": 0,
		"immediate_mesh_geometry_usec": 0,
		"immediate_mesh_commit_usec": 0,
		"immediate_mesh_apply_usec": 0,
		"immediate_mesh_submission_usec": 0,
		"immediate_collision_build_usec": 0,
		"immediate_collision_shape_build_usec": 0,
		"immediate_collision_apply_usec": 0,
		"dispatch_usec": 0,
		"dispatch_chunk_count": 0,
		"dispatch_instantiate_usec": 0,
		"dispatch_sync_load_usec": 0,
		"generation_queue_count": 0,
		"integrate_usec": 0,
		"integrated_chunk_count": 0,
		"integrate_instantiate_usec": 0,
		"collision_target_sync_usec": 0,
		"mesh_queue_usec": 0,
		"mesh_stage_usec": 0,
		"mesh_chunk_count": 0,
		"mesh_coords": [],
		"mesh_mesh_build_usec": 0,
		"mesh_mesh_geometry_usec": 0,
		"mesh_mesh_commit_usec": 0,
		"mesh_mesh_apply_usec": 0,
		"mesh_mesh_submission_usec": 0,
		"mesh_collision_build_usec": 0,
		"mesh_collision_shape_build_usec": 0,
		"mesh_collision_apply_usec": 0,
		"collision_queue_usec": 0,
		"collision_stage_usec": 0,
		"collision_chunk_count": 0,
		"collision_coords": [],
		"collision_mesh_build_usec": 0,
		"collision_mesh_geometry_usec": 0,
		"collision_mesh_commit_usec": 0,
		"collision_mesh_apply_usec": 0,
		"collision_mesh_submission_usec": 0,
		"collision_collision_build_usec": 0,
		"collision_collision_shape_build_usec": 0,
		"collision_collision_apply_usec": 0,
	}

func _add_profile_usec(profile: Dictionary, key: String, value: int) -> void:
	if profile.is_empty() or value <= 0:
		return
	profile[key] = int(profile.get(key, 0)) + value

func _add_profile_count(profile: Dictionary, key: String, value: int) -> void:
	if profile.is_empty() or value == 0:
		return
	profile[key] = int(profile.get(key, 0)) + value

func _add_chunk_render_profile(profile: Dictionary, prefix: String, render_stats: Dictionary) -> void:
	if profile.is_empty() or render_stats.is_empty():
		return

	_add_profile_usec(profile, "%s_mesh_build_usec" % prefix, int(render_stats.get("mesh_build_usec", 0)))
	_add_profile_usec(profile, "%s_mesh_geometry_usec" % prefix, int(render_stats.get("mesh_geometry_usec", 0)))
	_add_profile_usec(profile, "%s_mesh_commit_usec" % prefix, int(render_stats.get("mesh_commit_usec", 0)))
	_add_profile_usec(profile, "%s_mesh_apply_usec" % prefix, int(render_stats.get("mesh_apply_usec", 0)))
	_add_profile_usec(profile, "%s_mesh_submission_usec" % prefix, int(render_stats.get("mesh_submission_usec", 0)))
	_add_profile_usec(profile, "%s_collision_build_usec" % prefix, int(render_stats.get("collision_build_usec", 0)))
	_add_profile_usec(profile, "%s_collision_shape_build_usec" % prefix, int(render_stats.get("collision_shape_build_usec", 0)))
	_add_profile_usec(profile, "%s_collision_apply_usec" % prefix, int(render_stats.get("collision_apply_usec", render_stats.get("collision_sync_apply_usec", 0))))

func _get_chunk_render_state(coord: Vector2i) -> int:
	return int(_chunk_render_state.get(coord, CHUNK_RENDER_NONE))

func _set_chunk_render_state(coord: Vector2i, state: int) -> void:
	_chunk_render_state[coord] = state




