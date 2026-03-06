class_name WorldStorage
extends RefCounted

const WorldConstants = preload("res://scripts/world/world_constants.gd")

var save_slot_name: String = "default"

func normalized_save_slot_name() -> String:
	var normalized: String = save_slot_name.strip_edges()
	if normalized.is_empty():
		return "default"
	return normalized

func ensure_save_directories() -> void:
	DirAccess.make_dir_recursive_absolute(get_save_root_dir())

func get_save_root_dir() -> String:
	return ProjectSettings.globalize_path("res://save_data/worlds/%s" % normalized_save_slot_name())

func get_world_meta_path() -> String:
	return "%s/world.meta" % get_save_root_dir()

func get_chunk_save_path(coord: Vector2i) -> String:
	return "%s/%d_%d.chunk" % [get_save_root_dir(), coord.x, coord.y]

func load_chunk_data(coord: Vector2i) -> PackedInt32Array:
	var empty: PackedInt32Array = PackedInt32Array()
	var path: String = get_chunk_save_path(coord)
	if not FileAccess.file_exists(path):
		return empty

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return empty

	var loaded: Variant = file.get_var()
	if not (loaded is Dictionary):
		return empty

	var payload: Dictionary = _normalize_chunk_payload(loaded)
	if payload.is_empty():
		return empty

	var blocks_variant: Variant = payload.get("blocks", null)
	if blocks_variant is PackedInt32Array:
		var blocks_data: PackedInt32Array = blocks_variant
		if blocks_data.size() == WorldConstants.CHUNK_VOLUME:
			return blocks_data

	return empty

func save_chunk_data(coord: Vector2i, blocks: PackedInt32Array) -> bool:
	if blocks.size() != WorldConstants.CHUNK_VOLUME:
		return false

	ensure_save_directories()
	var file: FileAccess = FileAccess.open(get_chunk_save_path(coord), FileAccess.WRITE)
	if file == null:
		push_warning("Failed to save chunk %s" % [coord])
		return false

	var payload: Dictionary = {
		"version": WorldConstants.SAVE_FORMAT_VERSION,
		"blocks": blocks,
	}
	file.store_var(payload)
	file.flush()
	return true

func load_world_meta(default_seed: int) -> Dictionary:
	var path: String = get_world_meta_path()
	if not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var loaded: Variant = file.get_var()
	if not (loaded is Dictionary):
		return {}

	var payload: Dictionary = _normalize_world_meta_payload(loaded)
	if payload.is_empty():
		return {}

	var player_state: Dictionary = {}
	var player_variant: Variant = payload.get("player", {})
	if player_variant is Dictionary:
		player_state = player_variant

	return {
		"seed": int(payload.get("seed", default_seed)),
		"player": player_state,
	}

func save_world_meta(world_seed: int, player_state: Dictionary) -> bool:
	ensure_save_directories()
	var file: FileAccess = FileAccess.open(get_world_meta_path(), FileAccess.WRITE)
	if file == null:
		push_warning("Failed to save world metadata")
		return false

	var payload: Dictionary = {
		"version": WorldConstants.WORLD_META_FORMAT_VERSION,
		"seed": world_seed,
		"player": player_state,
	}
	file.store_var(payload)
	file.flush()
	return true

func _normalize_chunk_payload(payload: Dictionary) -> Dictionary:
	var version: int = int(payload.get("version", -1))
	if version == WorldConstants.SAVE_FORMAT_VERSION:
		return payload
	if version < 0 or version > WorldConstants.SAVE_FORMAT_VERSION:
		return {}
	return migrate_chunk_payload(version, payload)

func _normalize_world_meta_payload(payload: Dictionary) -> Dictionary:
	var version: int = int(payload.get("version", -1))
	if version == WorldConstants.WORLD_META_FORMAT_VERSION:
		return payload
	if version < 0 or version > WorldConstants.WORLD_META_FORMAT_VERSION:
		return {}
	return migrate_world_meta_payload(version, payload)

func migrate_chunk_payload(from_version: int, payload: Dictionary) -> Dictionary:
	# Route future chunk save upgrades through this single entry point.
	match from_version:
		_:
			return {}

func migrate_world_meta_payload(from_version: int, payload: Dictionary) -> Dictionary:
	# Route future world metadata upgrades through this single entry point.
	match from_version:
		_:
			return {}