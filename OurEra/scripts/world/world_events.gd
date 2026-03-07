class_name WorldEvents
extends RefCounted

signal world_meta_loaded(seed: int, player_state: Dictionary)
signal player_state_applied(state: Dictionary)
signal world_ready(player_position: Vector3, center_chunk: Vector2i)
signal center_chunk_changed(previous: Vector2i, current: Vector2i)
signal chunk_data_registered(coord: Vector2i, dirty: bool)
signal chunk_data_evicted(coord: Vector2i)
signal chunk_loaded(coord: Vector2i, chunk)
signal chunk_unloaded(coord: Vector2i)
signal chunk_changed(coord: Vector2i)
signal chunk_state_changed(coord: Vector2i, state: Dictionary)
signal chunk_saved(coord: Vector2i)
signal world_save_started(reason: String)
signal world_save_completed(success: bool, reason: String)
signal world_saved()