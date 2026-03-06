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
@export_range(1, 32, 1) var max_chunk_generations_per_frame := 4
@export_range(1, 32, 1) var max_chunk_mesh_updates_per_frame := 2
@export_range(1, 8, 1) var generator_thread_count := 2
@export_range(1, 64, 1) var max_active_generation_jobs := 8
@export_range(1, 32, 1) var max_completed_chunk_integrations_per_frame := 4
@export_range(0, 4096, 1) var max_cached_clean_chunks := 256
@export_range(0.0, 300.0, 1.0) var autosave_interval_seconds := 30.0
@export var collect_chunk_render_stats := false

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

func _ready() -> void:
	unload_radius_chunks = maxi(unload_radius_chunks, load_radius_chunks + 1)
	_setup_modules()
	_setup_material()
	_storage.ensure_save_directories()
	_load_world_meta()
	_generator.seed = seed
	_generator.thread_count = maxi(1, generator_thread_count)
	_generator.start_workers()
	_resolve_entity_system()
	_resolve_player()

func _exit_tree() -> void:
	save_now()
	if _generator != null:
		_generator.stop_workers()

func _process(delta: float) -> void:
	if _resolve_player() == null:
		return

	_sync_streaming_settings()

	if not _startup_streaming_initialized:
		_apply_loaded_player_state_if_needed()
		_apply_loaded_entity_states_if_needed()
		force_streaming_update()
		_startup_streaming_initialized = true
	else:
		_apply_loaded_entity_states_if_needed()

	var player := _player
	var new_center: Vector2i = WorldConstants.world_to_chunk(
		Vector3i(floori(player.global_position.x), 0, floori(player.global_position.z))
	)
	if new_center != _center_chunk:
		_center_chunk = new_center
		_streaming.on_center_chunk_changed(_center_chunk)

	_streaming.process_frame(_center_chunk)
	_tick_autosave(delta)

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
	config["collect_chunk_render_stats"] = collect_chunk_render_stats
	config["light_sampler"] = Callable()
	config["fluid_surface_builder"] = Callable()
	config["render_budget"] = {
		"max_chunk_mesh_updates_per_frame": max_chunk_mesh_updates_per_frame,
		"collision_radius_chunks": collision_radius_chunks,
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
		"max_chunk_generations_per_frame": max_chunk_generations_per_frame,
		"max_chunk_mesh_updates_per_frame": max_chunk_mesh_updates_per_frame,
		"max_active_generation_jobs": max_active_generation_jobs,
		"max_completed_chunk_integrations_per_frame": max_completed_chunk_integrations_per_frame,
		"max_cached_clean_chunks": max_cached_clean_chunks,
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
