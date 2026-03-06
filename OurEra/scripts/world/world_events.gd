class_name WorldEvents
extends RefCounted

signal world_meta_loaded(seed: int, player_state: Dictionary)
signal player_state_applied(state: Dictionary)
signal chunk_data_registered(coord: Vector2i, dirty: bool)
signal chunk_data_evicted(coord: Vector2i)
signal chunk_loaded(coord: Vector2i, chunk)
signal chunk_unloaded(coord: Vector2i)
signal chunk_changed(coord: Vector2i)
signal chunk_saved(coord: Vector2i)
signal world_saved()