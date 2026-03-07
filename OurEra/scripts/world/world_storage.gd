class_name WorldStorage
extends RefCounted

const WorldConstants = preload("res://scripts/world/world_constants.gd")
const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"

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
	var payload: Dictionary = _load_payload_candidates(_payload_candidates(get_chunk_save_path(coord)))
	if payload.is_empty():
		return empty

	payload = _normalize_chunk_payload(payload)
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

	var payload: Dictionary = {
		"version": WorldConstants.SAVE_FORMAT_VERSION,
		"blocks": blocks,
	}
	return _write_payload_atomic(get_chunk_save_path(coord), payload, "chunk %s" % coord)

func load_world_meta(default_seed: int) -> Dictionary:
	var payload: Dictionary = _load_payload_candidates(_payload_candidates(get_world_meta_path()))
	if payload.is_empty():
		return {}

	payload = _normalize_world_meta_payload(payload)
	if payload.is_empty():
		return {}

	var player_state: Dictionary = {}
	var player_variant: Variant = payload.get("player", {})
	if player_variant is Dictionary:
		player_state = player_variant.duplicate(true)

	var entity_states: Array = []
	var entity_variant: Variant = payload.get("entities", [])
	if entity_variant is Array:
		entity_states = entity_variant.duplicate(true)

	return {
		"seed": int(payload.get("seed", default_seed)),
		"player": player_state,
		"entities": entity_states,
	}

func save_world_meta(world_seed: int, player_state: Dictionary, entity_states: Array = []) -> bool:
	var payload: Dictionary = {
		"version": WorldConstants.WORLD_META_FORMAT_VERSION,
		"seed": world_seed,
		"player": player_state.duplicate(true),
		"entities": entity_states.duplicate(true),
	}
	return _write_payload_atomic(get_world_meta_path(), payload, "world metadata")

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

func _payload_candidates(path: String) -> Array[String]:
	return [
		path,
		"%s%s" % [path, BACKUP_SUFFIX],
		"%s%s" % [path, TEMP_SUFFIX],
	]

func _load_payload_candidates(paths: Array[String]) -> Dictionary:
	for candidate in paths:
		var payload := _read_payload_file(candidate)
		if not payload.is_empty():
			return payload
	return {}

func _read_payload_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}

	var loaded: Variant = file.get_var()
	file.close()
	if loaded is Dictionary:
		return (loaded as Dictionary).duplicate(true)
	return {}

func _write_payload_atomic(path: String, payload: Dictionary, label: String) -> bool:
	ensure_save_directories()
	var temp_path := "%s%s" % [path, TEMP_SUFFIX]
	var backup_path := "%s%s" % [path, BACKUP_SUFFIX]

	var temp_file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if temp_file == null:
		push_warning("Failed to save %s" % label)
		return false

	temp_file.store_var(payload)
	temp_file.flush()
	temp_file.close()

	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)

	if FileAccess.file_exists(path):
		var backup_result := DirAccess.rename_absolute(path, backup_path)
		if backup_result != OK:
			DirAccess.remove_absolute(temp_path)
			push_warning("Failed to rotate existing %s" % label)
			return false

	var swap_result := DirAccess.rename_absolute(temp_path, path)
	if swap_result != OK:
		if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(backup_path, path)
		DirAccess.remove_absolute(temp_path)
		push_warning("Failed to finalize %s" % label)
		return false

	return true