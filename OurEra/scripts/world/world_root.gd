class_name WorldRoot
extends Node3D

const WorldConstants = preload("res://scripts/world/world_constants.gd")
const ContentDBScript = preload("res://scripts/content/content_db.gd")
const WorldEventsScript = preload("res://scripts/world/world_events.gd")
const WorldStorageScript = preload("res://scripts/world/world_storage.gd")
const WorldGeneratorScript = preload("res://scripts/world/world_generator.gd")
const ChunkStreamingScript = preload("res://scripts/world/chunk_streaming.gd")
const MaterialRegistryScript = preload("res://scripts/render/material_registry.gd")

const CHUNK_WIDTH := WorldConstants.CHUNK_WIDTH
const WORLD_HEIGHT := WorldConstants.WORLD_HEIGHT
const SEA_LEVEL := WorldConstants.SEA_LEVEL
const CHUNK_VOLUME := WorldConstants.CHUNK_VOLUME
const SAVE_FORMAT_VERSION := WorldConstants.SAVE_FORMAT_VERSION
const WORLD_META_FORMAT_VERSION := WorldConstants.WORLD_META_FORMAT_VERSION
const PRIMARY_PLAYER_ENTITY_ID := "player"
const PLAYER_SPAWN_CELL_OFFSET := 0.5
const PLAYER_SPAWN_FLOOR_OFFSET := 0.05
const PLAYER_EXTRA_SPAWN_HEIGHT := 20.0

signal world_meta_loaded(seed: int, player_state: Dictionary)
signal player_state_applied(state: Dictionary)
signal chunk_data_registered(coord: Vector2i, dirty: bool)
signal chunk_data_evicted(coord: Vector2i)
signal chunk_loaded(coord: Vector2i, chunk)
signal chunk_unloaded(coord: Vector2i)
signal chunk_changed(coord: Vector2i)
signal chunk_saved(coord: Vector2i)
signal world_saved()

@export var entity_system_path: NodePath
@export var save_slot_name: String = "default"
@export_file("*.png") var terrain_atlas_texture_path := "res://assets/textures/terrain.png"
@export_file("*.gdshader") var solid_block_shader_path := "res://shaders/voxel/voxel_blocks.gdshader"
@export_range(1, 16, 1) var load_radius_chunks := 4
@export_range(2, 20, 1) var unload_radius_chunks := 6
@export_range(1, 12, 1) var collision_radius_chunks := 2
@export_range(1, 16, 1) var mesh_priority_radius_chunks := 3
@export_range(1, 32, 1) var max_chunk_generations_per_frame := 4
@export_range(1, 32, 1) var max_chunk_mesh_updates_per_frame := 2
@export_range(1, 8, 1) var generator_thread_count := 2
@export_range(1, 64, 1) var max_active_generation_jobs := 8
@export_range(1, 32, 1) var max_completed_chunk_integrations_per_frame := 4
@export_range(0, 4096, 1) var max_cached_clean_chunks := 256
@export_range(0.0, 300.0, 1.0) var autosave_interval_seconds := 30.0
@export var collect_chunk_render_stats := false
@export_range(1, 8, 1) var max_chunk_collision_updates_per_frame := 1
@export_range(0, 8, 1) var startup_mesh_warmup_frames := 1
@export_range(0, 8, 1) var startup_mesh_updates_per_frame := 0
@export_range(0, 8, 1) var startup_collision_updates_per_frame := 0

var seed: int = 114514

var _player: Node3D
var _entity_system: Node
var _center_chunk: Vector2i = Vector2i(1 << 29, 1 << 29)
var _loaded_player_state: Dictionary = {}
var _loaded_entity_states: Array = []
var _player_state_applied: bool = false
var _entity_states_applied: bool = false
var _startup_streaming_initialized: bool = false
var _autosave_elapsed: float = 0.0

var _events: WorldEvents
var _storage: WorldStorage
var _generator: WorldGenerator
var _streaming: ChunkStreaming
var _material_registry
var _startup_profile_enabled := false
var _startup_profile_output_path := ""
var _startup_profile_frame_target := 120
var _startup_profile_frames_captured := 0
var _startup_profile_written := false
var _startup_profile_report: Dictionary = {}
var _runtime_profile_enabled := false
var _runtime_profile_output_path := ""
var _runtime_profile_frame_target := 300
var _runtime_profile_frames_captured := 0
var _runtime_profile_written := false
var _runtime_profile_report: Dictionary = {}

func _ready() -> void:
	_configure_startup_profile()
	_configure_runtime_profile()
	_apply_runtime_debug_overrides()
	unload_radius_chunks = maxi(unload_radius_chunks, load_radius_chunks + 1)
	_setup_modules()
	_setup_material()
	_storage.ensure_save_directories()
	_load_world_meta()
	_generator.seed = seed
	_generator.thread_count = maxi(1, generator_thread_count)
	_generator.start_workers()
	_resolve_entity_system()
	var player := _resolve_player()
	_set_player_simulation_enabled(player, false)

func _exit_tree() -> void:
	save_now()
	if _generator != null:
		_generator.stop_workers()

func _process(delta: float) -> void:
	var player := _resolve_player()
	if player == null:
		return

	var frame_started_usec := Time.get_ticks_usec() if _startup_profile_enabled else 0
	var runtime_frame_started_usec := Time.get_ticks_usec() if _runtime_profile_enabled else 0
	var startup_stages: Dictionary = {}
	_sync_streaming_settings()

	if not _startup_streaming_initialized:
		var prepare_started_usec := Time.get_ticks_usec() if _startup_profile_enabled else 0
		_prepare_player_spawn(player)
		_record_profile_usec(startup_stages, "prepare_player_spawn_usec", prepare_started_usec)
		_record_profile_immediate(startup_stages, "prepare_player_spawn", _consume_streaming_immediate_profile())
		var prime_started_usec := Time.get_ticks_usec() if _startup_profile_enabled else 0
		_prime_startup_streaming(player)
		_record_profile_usec(startup_stages, "prime_startup_streaming_usec", prime_started_usec)
		var finalize_started_usec := Time.get_ticks_usec() if _startup_profile_enabled else 0
		_finalize_player_spawn(player)
		_record_profile_usec(startup_stages, "finalize_player_spawn_usec", finalize_started_usec)
		_record_profile_immediate(startup_stages, "finalize_player_spawn", _consume_streaming_immediate_profile())
		var entity_restore_started_usec := Time.get_ticks_usec() if _startup_profile_enabled else 0
		_apply_loaded_entity_states_if_needed()
		_record_profile_usec(startup_stages, "apply_loaded_entities_usec", entity_restore_started_usec)
		_startup_streaming_initialized = true
	else:
		var entity_apply_started_usec := Time.get_ticks_usec() if _startup_profile_enabled else 0
		_apply_loaded_entity_states_if_needed()
		_record_profile_usec(startup_stages, "apply_loaded_entities_usec", entity_apply_started_usec)

	var center_update_started_usec := Time.get_ticks_usec() if _startup_profile_enabled else 0
	_update_center_chunk(player)
	_record_profile_usec(startup_stages, "update_center_chunk_usec", center_update_started_usec)
	_streaming.process_frame(_center_chunk)
	_tick_autosave(delta)
	_record_startup_profile_frame(frame_started_usec, startup_stages)
	_record_runtime_profile_frame(runtime_frame_started_usec)

func get_block_global(pos: Vector3i) -> int:
	if _streaming == null:
		return ContentDBScript.AIR
	return _streaming.get_block_global(pos)

func set_block_global(pos: Vector3i, block_id: int) -> void:
	if _streaming == null:
		return
	_streaming.set_block_global(pos, block_id)

func get_block_material() -> Material:
	if _material_registry == null:
		return null
	return _material_registry.get_block_material()

func get_material_registry():
	return _material_registry

func get_chunk_render_config() -> Dictionary:
	var config: Dictionary = {}
	if _material_registry != null:
		config = _material_registry.get_render_config()

	config["collision_strategy"] = "nearby_concave"
	config["collect_chunk_render_stats"] = collect_chunk_render_stats or _startup_profile_enabled or _runtime_profile_enabled
	config["light_sampler"] = Callable()
	config["fluid_surface_builder"] = Callable()
	config["render_budget"] = {
		"max_chunk_mesh_updates_per_frame": max_chunk_mesh_updates_per_frame,
		"max_chunk_collision_updates_per_frame": max_chunk_collision_updates_per_frame,
		"collision_radius_chunks": collision_radius_chunks,
		"mesh_priority_radius_chunks": mesh_priority_radius_chunks,
		"startup_mesh_warmup_frames": startup_mesh_warmup_frames,
	}
	return config

func get_seed() -> int:
	return seed

func get_save_slot() -> String:
	if _storage == null:
		var normalized: String = save_slot_name.strip_edges()
		if normalized.is_empty():
			return "default"
		return normalized
	return _storage.normalized_save_slot_name()

func get_player() -> Node3D:
	return _resolve_player()

func get_player_state() -> Dictionary:
	return _collect_player_state()

func apply_player_state(state: Dictionary) -> void:
	_loaded_player_state = state.duplicate(true)
	_player_state_applied = false
	_apply_loaded_player_state_if_needed()

func get_center_chunk() -> Vector2i:
	return _center_chunk

func get_events() -> WorldEvents:
	return _events

func has_chunk_data(coord: Vector2i) -> bool:
	if _streaming == null:
		return false
	return _streaming.has_chunk_data(coord)

func is_chunk_loaded(coord: Vector2i) -> bool:
	if _streaming == null:
		return false
	return _streaming.is_chunk_loaded(coord)

func get_loaded_chunk(coord: Vector2i):
	if _streaming == null:
		return null
	return _streaming.get_loaded_chunk(coord)

func get_chunk_meshing_neighbors(coord: Vector2i) -> Dictionary:
	if _streaming == null:
		return {}
	return _streaming.get_chunk_meshing_neighbors(coord)

func force_streaming_update() -> void:
	var player := _resolve_player()
	if player == null or _streaming == null:
		return
	_sync_streaming_settings()
	_center_chunk = WorldConstants.world_to_chunk(
		Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z))
	)
	_streaming.force_streaming_update(_center_chunk)

func save_now() -> void:
	if _storage == null or _streaming == null:
		return
	_save_world_meta()
	_streaming.flush_dirty_chunks()
	_events.world_saved.emit()

static func to_index(x: int, y: int, z: int) -> int:
	return WorldConstants.to_index(x, y, z)

static func world_to_chunk(pos: Vector3i) -> Vector2i:
	return WorldConstants.world_to_chunk(pos)

static func world_to_local(pos: Vector3i) -> Vector3i:
	return WorldConstants.world_to_local(pos)

func _configure_startup_profile() -> void:
	_startup_profile_enabled = OS.get_environment("OURERA_STARTUP_PROFILE") == "1"
	if not _startup_profile_enabled:
		return

	collect_chunk_render_stats = true
	_startup_profile_output_path = OS.get_environment("OURERA_STARTUP_PROFILE_OUTPUT")
	if _startup_profile_output_path.is_empty():
		_startup_profile_output_path = ProjectSettings.globalize_path("res://startup_profile.json")
	_startup_profile_frame_target = _env_int("OURERA_STARTUP_PROFILE_FRAMES", 120)
	_startup_profile_frames_captured = 0
	_startup_profile_written = false
	_startup_profile_report = {
		"meta": {
			"seed": seed,
			"load_radius_chunks": load_radius_chunks,
			"collision_radius_chunks": collision_radius_chunks,
			"mesh_priority_radius_chunks": mesh_priority_radius_chunks,
			"max_chunk_generations_per_frame": max_chunk_generations_per_frame,
			"max_chunk_mesh_updates_per_frame": max_chunk_mesh_updates_per_frame,
			"max_chunk_collision_updates_per_frame": max_chunk_collision_updates_per_frame,
			"startup_mesh_warmup_frames": startup_mesh_warmup_frames,
			"startup_mesh_updates_per_frame": startup_mesh_updates_per_frame,
			"startup_collision_updates_per_frame": startup_collision_updates_per_frame,
			"target_frames": _startup_profile_frame_target,
		},
		"frames": [],
	}

func _record_startup_profile_frame(frame_started_usec: int, startup_stages: Dictionary) -> void:
	if not _startup_profile_enabled or _startup_profile_written:
		return
	if frame_started_usec <= 0:
		return

	var frame_entry := {
		"frame_index": _startup_profile_frames_captured,
		"world_process_usec": Time.get_ticks_usec() - frame_started_usec,
		"startup_stages": _sanitize_profile_value(startup_stages),
		"streaming": _sanitize_profile_value(_streaming.get_last_profile_frame() if _streaming != null else {}),
		"queues": _sanitize_profile_value(_streaming.get_debug_snapshot() if _streaming != null else {}),
	}
	var frames: Array = _startup_profile_report.get("frames", [])
	frames.append(frame_entry)
	_startup_profile_report["frames"] = frames
	_startup_profile_frames_captured += 1

	if _startup_profile_frames_captured >= _startup_profile_frame_target:
		_write_startup_profile()
		get_tree().quit()

func _record_profile_usec(stats: Dictionary, key: String, started_usec: int) -> void:
	if not _startup_profile_enabled or started_usec <= 0:
		return
	stats[key] = Time.get_ticks_usec() - started_usec

func _record_profile_immediate(stats: Dictionary, key: String, profile: Dictionary) -> void:
	if not _startup_profile_enabled or profile.is_empty():
		return
	stats[key] = _sanitize_profile_value(profile)

func _consume_streaming_immediate_profile() -> Dictionary:
	if _streaming == null:
		return {}
	return _streaming.consume_last_immediate_profile()

func _write_startup_profile() -> void:
	if _startup_profile_written:
		return
	_startup_profile_written = true
	_startup_profile_report["meta"] = _sanitize_profile_value(_startup_profile_report.get("meta", {}))
	var file := FileAccess.open(_startup_profile_output_path, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to write startup profile: %s" % _startup_profile_output_path)
		return
	file.store_string(JSON.stringify(_startup_profile_report, "\t"))
	file.close()

func _sanitize_profile_value(value: Variant) -> Variant:
	if value is Dictionary:
		var sanitized: Dictionary = {}
		for key in value.keys():
			sanitized[str(key)] = _sanitize_profile_value(value[key])
		return sanitized
	if value is Array:
		var sanitized_array: Array = []
		for item in value:
			sanitized_array.append(_sanitize_profile_value(item))
		return sanitized_array
	if value is Vector2i:
		return {"x": value.x, "y": value.y}
	if value is Vector3i:
		return {"x": value.x, "y": value.y, "z": value.z}
	if value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z}
	return value

func _env_int(name: String, default_value: int) -> int:
	var raw := OS.get_environment(name)
	if raw.is_empty():
		return default_value
	return maxi(1, int(raw))

func _env_int_optional(name: String, current_value: int) -> int:
	var raw := OS.get_environment(name)
	if raw.is_empty():
		return current_value
	return maxi(0, int(raw))

func _configure_runtime_profile() -> void:
	_runtime_profile_enabled = OS.get_environment("OURERA_RUNTIME_PROFILE") == "1"
	if not _runtime_profile_enabled:
		return

	_runtime_profile_output_path = OS.get_environment("OURERA_RUNTIME_PROFILE_OUTPUT")
	if _runtime_profile_output_path.is_empty():
		_runtime_profile_output_path = ProjectSettings.globalize_path("res://runtime_profile.json")
	_runtime_profile_frame_target = _env_int("OURERA_RUNTIME_PROFILE_FRAMES", 300)
	_runtime_profile_frames_captured = 0
	_runtime_profile_written = false
	_runtime_profile_report = {
		"meta": {
			"seed": seed,
			"load_radius_chunks": load_radius_chunks,
			"collision_radius_chunks": collision_radius_chunks,
			"mesh_priority_radius_chunks": mesh_priority_radius_chunks,
			"max_chunk_mesh_updates_per_frame": max_chunk_mesh_updates_per_frame,
			"max_chunk_collision_updates_per_frame": max_chunk_collision_updates_per_frame,
			"target_frames": _runtime_profile_frame_target,
		},
		"frames": [],
	}

func _record_runtime_profile_frame(frame_started_usec: int) -> void:
	if not _runtime_profile_enabled or _runtime_profile_written:
		return
	if frame_started_usec <= 0:
		return

	var frame_entry := {
		"frame_index": _runtime_profile_frames_captured,
		"world_process_usec": Time.get_ticks_usec() - frame_started_usec,
		"streaming": _sanitize_profile_value(_streaming.get_last_profile_frame() if _streaming != null else {}),
		"performance": _sanitize_profile_value(_collect_performance_snapshot()),
	}
	var frames: Array = _runtime_profile_report.get("frames", [])
	frames.append(frame_entry)
	_runtime_profile_report["frames"] = frames
	_runtime_profile_frames_captured += 1

	if _runtime_profile_frames_captured >= _runtime_profile_frame_target:
		_write_runtime_profile()
		get_tree().quit()

func _write_runtime_profile() -> void:
	if _runtime_profile_written:
		return
	_runtime_profile_written = true
	_runtime_profile_report["meta"] = _sanitize_profile_value(_runtime_profile_report.get("meta", {}))
	var file := FileAccess.open(_runtime_profile_output_path, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to write runtime profile: %s" % _runtime_profile_output_path)
		return
	file.store_string(JSON.stringify(_runtime_profile_report, "\t"))
	file.close()

func _collect_performance_snapshot() -> Dictionary:
	return {
		"fps": _read_monitor(Performance.Monitor.TIME_FPS),
		"process_time_ms": _read_monitor(Performance.Monitor.TIME_PROCESS) * 1000.0,
		"physics_time_ms": _read_monitor(Performance.Monitor.TIME_PHYSICS_PROCESS) * 1000.0,
		"navigation_time_ms": _read_monitor(Performance.Monitor.TIME_NAVIGATION_PROCESS) * 1000.0,
		"draw_calls": _read_monitor(Performance.Monitor.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": _read_monitor(Performance.Monitor.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": _read_monitor(Performance.Monitor.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"texture_mem_mb": _read_monitor(Performance.Monitor.RENDER_TEXTURE_MEM_USED) / 1024.0 / 1024.0,
		"buffer_mem_mb": _read_monitor(Performance.Monitor.RENDER_BUFFER_MEM_USED) / 1024.0 / 1024.0,
		"video_mem_mb": _read_monitor(Performance.Monitor.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0,
	}

func _read_monitor(monitor: int) -> float:
	return float(Performance.get_monitor(monitor))

func _apply_runtime_debug_overrides() -> void:
	load_radius_chunks = maxi(1, _env_int_optional("OURERA_LOAD_RADIUS_CHUNKS", load_radius_chunks))
	collision_radius_chunks = maxi(1, _env_int_optional("OURERA_COLLISION_RADIUS_CHUNKS", collision_radius_chunks))
	mesh_priority_radius_chunks = mini(
		load_radius_chunks,
		maxi(1, _env_int_optional("OURERA_MESH_PRIORITY_RADIUS_CHUNKS", mesh_priority_radius_chunks))
	)
	max_chunk_mesh_updates_per_frame = maxi(1, _env_int_optional("OURERA_MAX_CHUNK_MESH_UPDATES_PER_FRAME", max_chunk_mesh_updates_per_frame))

	if OS.get_environment("OURERA_DISABLE_SHADOWS") == "1":
		var parent := get_parent()
		if parent != null:
			var sun := parent.get_node_or_null("Sun")
			if sun is DirectionalLight3D:
				(sun as DirectionalLight3D).shadow_enabled = false

func _setup_modules() -> void:
	_events = WorldEventsScript.new()
	_storage = WorldStorageScript.new()
	_storage.save_slot_name = save_slot_name
	_generator = WorldGeneratorScript.new()
	_streaming = ChunkStreamingScript.new()
	_streaming.setup(self, _storage, _generator, _events)
	_sync_streaming_settings()
	_connect_world_events()

func _connect_world_events() -> void:
	_events.world_meta_loaded.connect(_on_world_meta_loaded)
	_events.player_state_applied.connect(_on_player_state_applied)
	_events.chunk_data_registered.connect(_on_chunk_data_registered)
	_events.chunk_data_evicted.connect(_on_chunk_data_evicted)
	_events.chunk_loaded.connect(_on_chunk_loaded)
	_events.chunk_unloaded.connect(_on_chunk_unloaded)
	_events.chunk_changed.connect(_on_chunk_changed)
	_events.chunk_saved.connect(_on_chunk_saved)
	_events.world_saved.connect(_on_world_saved)

func _sync_streaming_settings() -> void:
	if _streaming == null:
		return
	_streaming.apply_settings({
		"load_radius_chunks": load_radius_chunks,
		"unload_radius_chunks": unload_radius_chunks,
		"collision_radius_chunks": collision_radius_chunks,
		"mesh_priority_radius_chunks": mesh_priority_radius_chunks,
		"max_chunk_generations_per_frame": max_chunk_generations_per_frame,
		"max_chunk_mesh_updates_per_frame": max_chunk_mesh_updates_per_frame,
		"max_chunk_collision_updates_per_frame": max_chunk_collision_updates_per_frame,
		"startup_mesh_warmup_frames": startup_mesh_warmup_frames,
		"startup_mesh_updates_per_frame": startup_mesh_updates_per_frame,
		"startup_collision_updates_per_frame": startup_collision_updates_per_frame,
		"max_active_generation_jobs": max_active_generation_jobs,
		"max_completed_chunk_integrations_per_frame": max_completed_chunk_integrations_per_frame,
		"max_cached_clean_chunks": max_cached_clean_chunks,
		"collect_runtime_profile": _startup_profile_enabled or _runtime_profile_enabled,
	})

func _setup_material() -> void:
	_material_registry = MaterialRegistryScript.new()
	_material_registry.configure({
		"atlas_texture_path": terrain_atlas_texture_path,
		"solid_block_shader_path": solid_block_shader_path,
		"atlas_size": ContentDBScript.ATLAS_SIZE,
	})

func _tick_autosave(delta: float) -> void:
	if autosave_interval_seconds <= 0.0:
		return
	if not _startup_streaming_initialized:
		return

	_autosave_elapsed += delta
	if _autosave_elapsed < autosave_interval_seconds:
		return

	_autosave_elapsed = 0.0
	save_now()

func _load_world_meta() -> void:
	var payload: Dictionary = _storage.load_world_meta(seed)
	if payload.is_empty():
		return

	seed = int(payload.get("seed", seed))
	var player_variant: Variant = payload.get("player", {})
	if player_variant is Dictionary:
		_loaded_player_state = player_variant.duplicate(true)

	var entity_variant: Variant = payload.get("entities", [])
	if entity_variant is Array:
		_loaded_entity_states = entity_variant.duplicate(true)

	_events.world_meta_loaded.emit(seed, _loaded_player_state)

func _save_world_meta() -> void:
	_storage.save_world_meta(seed, _collect_player_state(), _collect_entity_states())

func _prepare_player_spawn(player: Node3D) -> void:
	_set_player_simulation_enabled(player, false)
	_apply_loaded_player_state_if_needed()
	_prime_player_support_chunk(player.global_position)
	_stabilize_player_spawn(player)

func _prime_startup_streaming(player: Node3D) -> void:
	if _streaming == null:
		return
	_sync_streaming_settings()
	_streaming.begin_startup_warmup()
	_center_chunk = WorldConstants.world_to_chunk(
		Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z))
	)
	_streaming.on_center_chunk_changed(_center_chunk)

func _finalize_player_spawn(player: Node3D) -> void:
	_ensure_player_support_collision(player)

	if player is CharacterBody3D:
		var body: CharacterBody3D = player
		body.velocity = Vector3.ZERO
		body.apply_floor_snap()

	_set_player_simulation_enabled(player, true)

func _prime_player_support_chunk(player_position: Vector3) -> void:
	if _streaming == null:
		return

	var coord := WorldConstants.world_to_chunk(
		Vector3i(floori(player_position.x), 0, floori(player_position.z))
	)
	_streaming.ensure_chunk_immediate(coord, true)

func _ensure_player_support_collision(player: Node3D) -> void:
	if player == null or _streaming == null:
		return
	var coord := WorldConstants.world_to_chunk(
		Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z))
	)
	_streaming.ensure_chunk_collision_immediate(coord)

func _stabilize_player_spawn(player: Node3D) -> void:
	var base_position: Vector3 = player.global_position
	var column_x: int = floori(base_position.x)
	var column_z: int = floori(base_position.z)
	var safe_y: float = _find_highest_standable_y(column_x, column_z) + _get_player_spawn_height_offset(player) + PLAYER_EXTRA_SPAWN_HEIGHT
	player.global_position = Vector3(
		float(column_x) + PLAYER_SPAWN_CELL_OFFSET,
		safe_y,
		float(column_z) + PLAYER_SPAWN_CELL_OFFSET
	)

	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO

func _get_player_spawn_height_offset(player: Node3D) -> float:
	if player != null:
		var collision_shape_node := player.find_child("CollisionShape3D", true, false)
		if collision_shape_node is CollisionShape3D:
			var shape: Shape3D = (collision_shape_node as CollisionShape3D).shape
			if shape is CapsuleShape3D:
				return (shape.height * 0.5) + shape.radius + PLAYER_SPAWN_FLOOR_OFFSET
			if shape is BoxShape3D:
				return (shape.size.y * 0.5) + PLAYER_SPAWN_FLOOR_OFFSET
			if shape is CylinderShape3D:
				return (shape.height * 0.5) + PLAYER_SPAWN_FLOOR_OFFSET
			if shape is SphereShape3D:
				return shape.radius + PLAYER_SPAWN_FLOOR_OFFSET

	return 1.0 + PLAYER_SPAWN_FLOOR_OFFSET

func _find_highest_standable_y(column_x: int, column_z: int) -> float:
	for y in range(WorldConstants.WORLD_HEIGHT - 2, 1, -1):
		var support_block: int = get_block_global(Vector3i(column_x, y - 1, column_z))
		if not ContentDBScript.is_solid(support_block):
			continue

		var feet_block: int = get_block_global(Vector3i(column_x, y, column_z))
		var head_block: int = get_block_global(Vector3i(column_x, y + 1, column_z))
		if not ContentDBScript.can_replace_block(feet_block):
			continue
		if not ContentDBScript.can_replace_block(head_block):
			continue
		return float(y)

	return 1.0

func _set_player_simulation_enabled(player: Node3D, enabled: bool) -> void:
	if player == null:
		return
	if player is EntityBase:
		if enabled:
			(player as EntityBase).set_deferred("simulation_enabled", true)
		else:
			(player as EntityBase).simulation_enabled = false

func _collect_player_state() -> Dictionary:
	var player := _resolve_player()
	if player == null:
		return _loaded_player_state

	if player.has_method("get_persisted_state"):
		var persisted_variant: Variant = player.call("get_persisted_state")
		if persisted_variant is Dictionary:
			return persisted_variant

	return {
		"position": player.global_position,
		"yaw": player.rotation.y,
	}

func _collect_entity_states() -> Array:
	var entity_system := _resolve_entity_system()
	if entity_system == null or not entity_system.has_method("collect_persisted_entities"):
		return _loaded_entity_states

	var excluded_ids := PackedStringArray()
	var player := _resolve_player()
	if player != null and player.has_method("get_entity_id"):
		excluded_ids.append(String(player.call("get_entity_id")))

	var states_variant: Variant = entity_system.call("collect_persisted_entities", excluded_ids)
	if states_variant is Array:
		return states_variant
	return []

func _apply_loaded_player_state_if_needed() -> void:
	if _player_state_applied:
		return
	if _loaded_player_state.is_empty():
		_player_state_applied = true
		return

	var player := _resolve_player()
	if player == null:
		return

	_player_state_applied = true

	if player.has_method("apply_persisted_state"):
		player.call("apply_persisted_state", _loaded_player_state)
	else:
		var saved_position: Variant = _loaded_player_state.get("position", null)
		if saved_position is Vector3:
			player.global_position = saved_position
		player.rotation.y = float(_loaded_player_state.get("yaw", player.rotation.y))

	_events.player_state_applied.emit(_loaded_player_state)

func _apply_loaded_entity_states_if_needed() -> void:
	if _entity_states_applied:
		return
	if _loaded_entity_states.is_empty():
		_entity_states_applied = true
		return

	var entity_system := _resolve_entity_system()
	if entity_system == null:
		return
	if not entity_system.has_method("restore_entities"):
		_entity_states_applied = true
		return

	_entity_states_applied = true
	entity_system.call("restore_entities", _loaded_entity_states)

func _resolve_entity_system() -> Node:
	if _entity_system != null and is_instance_valid(_entity_system):
		return _entity_system
	_entity_system = get_node_or_null(entity_system_path)
	return _entity_system

func _resolve_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player

	var entity_system := _resolve_entity_system()
	if entity_system == null:
		return null

	var player_variant: Variant = null
	if entity_system.has_method("get_primary_entity"):
		player_variant = entity_system.call("get_primary_entity", "player", PRIMARY_PLAYER_ENTITY_ID)
	elif entity_system.has_method("get_entity"):
		player_variant = entity_system.call("get_entity", PRIMARY_PLAYER_ENTITY_ID)

	if player_variant is Node3D:
		_player = player_variant
		return _player

	return null

func _update_center_chunk(player: Node3D) -> void:
	var new_center: Vector2i = WorldConstants.world_to_chunk(
		Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z))
	)
	if new_center != _center_chunk:
		_center_chunk = new_center
		_streaming.on_center_chunk_changed(_center_chunk)

func _on_world_meta_loaded(loaded_seed: int, player_state: Dictionary) -> void:
	world_meta_loaded.emit(loaded_seed, player_state)

func _on_player_state_applied(state: Dictionary) -> void:
	player_state_applied.emit(state)

func _on_chunk_data_registered(coord: Vector2i, dirty: bool) -> void:
	chunk_data_registered.emit(coord, dirty)

func _on_chunk_data_evicted(coord: Vector2i) -> void:
	chunk_data_evicted.emit(coord)

func _on_chunk_loaded(coord: Vector2i, chunk) -> void:
	chunk_loaded.emit(coord, chunk)

func _on_chunk_unloaded(coord: Vector2i) -> void:
	chunk_unloaded.emit(coord)

func _on_chunk_changed(coord: Vector2i) -> void:
	chunk_changed.emit(coord)

func _on_chunk_saved(coord: Vector2i) -> void:
	chunk_saved.emit(coord)

func _on_world_saved() -> void:
	world_saved.emit()

