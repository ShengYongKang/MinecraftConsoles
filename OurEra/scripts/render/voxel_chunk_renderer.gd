class_name VoxelChunkRenderer
extends RefCounted

const WorldConstants = preload("res://scripts/world/world_constants.gd")
const MeshBuilderBackendScript = preload("res://scripts/render/mesh_builder_backend.gd")
const CollisionBuilderScript = preload("res://scripts/render/collision_builder.gd")

var world
var chunk_coord: Vector2i = Vector2i.ZERO
var blocks: PackedInt32Array

var _owner: Node3D
var _mesh_instance: MeshInstance3D
var _overlay_root: Node3D
var _static_body: StaticBody3D
var _collision_shape: CollisionShape3D

var _mesh_builder = MeshBuilderBackendScript.new()
var _collision_builder = CollisionBuilderScript.new()
var _last_build_stats: Dictionary = {}
var _last_collision_sync_stats: Dictionary = {}
var _cached_collision_shape: Shape3D
var _collision_enabled := false
var _collision_dirty := false

func attach(owner: Node3D) -> void:
	_owner = owner
	_ensure_render_nodes()

func configure(p_world, p_chunk_coord: Vector2i, p_blocks: PackedInt32Array) -> void:
	world = p_world
	chunk_coord = p_chunk_coord
	blocks = p_blocks

func rebuild(with_collision: bool = true) -> void:
	if world == null:
		return

	_ensure_render_nodes()
	var render_config := _get_render_config()
	var collect_stats := bool(render_config.get("collect_chunk_render_stats", false))
	var collision_was_active := _collision_enabled
	var neighbor_columns: Dictionary = {}
	if world != null and world.has_method("get_chunk_meshing_neighbors"):
		var neighbor_variant: Variant = world.call("get_chunk_meshing_neighbors", chunk_coord)
		if neighbor_variant is Dictionary:
			neighbor_columns = neighbor_variant
	var mesh_started_usec := Time.get_ticks_usec() if collect_stats else 0
	var build_result: Dictionary = _mesh_builder.build({
		"chunk_origin": WorldConstants.chunk_origin(chunk_coord),
		"dimensions": Vector3i(
			WorldConstants.CHUNK_WIDTH,
			WorldConstants.WORLD_HEIGHT,
			WorldConstants.CHUNK_WIDTH
		),
		"material": render_config.get("material", null),
		"chunk_blocks": blocks,
		"neighbor_columns": neighbor_columns,
		"block_sampler": Callable(self, "_sample_block_for_meshing"),
		"light_sampler": render_config.get("light_sampler", Callable()),
		"include_vertex_colors": bool(render_config.get("use_vertex_lighting", false)),
		"collect_collision_faces": with_collision,
		"collect_timing_stats": collect_stats,
	})
	var mesh_build_usec := Time.get_ticks_usec() - mesh_started_usec if collect_stats else 0
	var mesh_apply_started_usec := Time.get_ticks_usec() if collect_stats else 0
	_mesh_instance.mesh = build_result.get("mesh", null)
	var mesh_apply_usec := Time.get_ticks_usec() - mesh_apply_started_usec if collect_stats else 0
	var collision_build_usec := 0
	var collision_apply_usec := 0

	if with_collision:
		var collision_started_usec := Time.get_ticks_usec() if collect_stats else 0
		var collision_faces: PackedVector3Array = build_result.get("collision_faces", PackedVector3Array())
		_cached_collision_shape = _collision_builder.build_shape_from_faces(collision_faces)
		collision_build_usec = Time.get_ticks_usec() - collision_started_usec if collect_stats else 0
		_collision_dirty = false
		var collision_apply_started_usec := Time.get_ticks_usec() if collect_stats else 0
		_apply_collision_shape(_cached_collision_shape, true, true)
		collision_apply_usec = Time.get_ticks_usec() - collision_apply_started_usec if collect_stats else 0
	elif collision_was_active:
		_collision_dirty = true
		var cached_apply_started_usec := Time.get_ticks_usec() if collect_stats else 0
		_apply_collision_shape(_cached_collision_shape, true, false)
		collision_apply_usec = Time.get_ticks_usec() - cached_apply_started_usec if collect_stats else 0
	else:
		_cached_collision_shape = null
		_collision_dirty = false
		var clear_apply_started_usec := Time.get_ticks_usec() if collect_stats else 0
		_apply_collision_shape(null, false, true)
		collision_apply_usec = Time.get_ticks_usec() - clear_apply_started_usec if collect_stats else 0

	_last_collision_sync_stats = {}
	_refresh_overlay_layers(render_config)
	_store_build_stats(
		build_result,
		render_config,
		mesh_build_usec,
		mesh_apply_usec,
		collision_build_usec,
		collision_apply_usec
	)

func sync_collision(enabled: bool) -> void:
	_ensure_render_nodes()
	var render_config := _get_render_config()
	var collect_stats := bool(render_config.get("collect_chunk_render_stats", false))
	var sync_started_usec := Time.get_ticks_usec() if collect_stats else 0
	var collision_build_usec := 0
	var collision_apply_usec := 0

	if not enabled or _mesh_instance == null or _mesh_instance.mesh == null:
		var disable_apply_started_usec := Time.get_ticks_usec() if collect_stats else 0
		if _collision_dirty:
			_cached_collision_shape = null
			_collision_dirty = false
			_apply_collision_shape(null, false, true)
		else:
			_apply_collision_shape(_cached_collision_shape, false, false)
		collision_apply_usec = Time.get_ticks_usec() - disable_apply_started_usec if collect_stats else 0
		_store_collision_sync_stats(collect_stats, enabled, sync_started_usec, collision_build_usec, collision_apply_usec)
		return

	if _cached_collision_shape == null or _collision_dirty:
		var collision_started_usec := Time.get_ticks_usec() if collect_stats else 0
		_cached_collision_shape = _collision_builder.build_shape(_mesh_instance.mesh)
		collision_build_usec = Time.get_ticks_usec() - collision_started_usec if collect_stats else 0
		_collision_dirty = false

	var collision_apply_started_usec := Time.get_ticks_usec() if collect_stats else 0
	_apply_collision_shape(_cached_collision_shape, true, true)
	collision_apply_usec = Time.get_ticks_usec() - collision_apply_started_usec if collect_stats else 0
	_store_collision_sync_stats(collect_stats, enabled, sync_started_usec, collision_build_usec, collision_apply_usec)

func has_collision_enabled() -> bool:
	return _collision_enabled

func get_last_build_stats() -> Dictionary:
	var combined := _last_build_stats.duplicate(true)
	for key in _last_collision_sync_stats.keys():
		combined[key] = _last_collision_sync_stats[key]
	return combined

func _sample_block_for_meshing(local_pos: Vector3i) -> int:
	if local_pos.y < 0 or local_pos.y >= WorldConstants.WORLD_HEIGHT:
		return BlockDefs.AIR
	if blocks.size() != WorldConstants.CHUNK_VOLUME:
		return BlockDefs.AIR

	if (
		local_pos.x >= 0 and local_pos.x < WorldConstants.CHUNK_WIDTH and
		local_pos.z >= 0 and local_pos.z < WorldConstants.CHUNK_WIDTH
	):
		return blocks[WorldConstants.to_index(local_pos.x, local_pos.y, local_pos.z)]

	if world == null or not world.has_method("get_block_global"):
		return BlockDefs.AIR
	return world.get_block_global(WorldConstants.chunk_origin(chunk_coord) + local_pos)

func _get_render_config() -> Dictionary:
	if world != null and world.has_method("get_chunk_render_config"):
		var config: Variant = world.call("get_chunk_render_config")
		if config is Dictionary:
			return config

	var fallback_material: Material = null
	if world != null and world.has_method("get_block_material"):
		fallback_material = world.get_block_material()
	return {
		"material": fallback_material,
		"collision_strategy": CollisionBuilderScript.STRATEGY_NEARBY_CONCAVE,
	}

func _refresh_overlay_layers(render_config: Dictionary) -> void:
	var fluid_surface_builder: Callable = render_config.get("fluid_surface_builder", Callable())
	if not fluid_surface_builder.is_valid():
		return
	for child in _overlay_root.get_children():
		child.queue_free()
	fluid_surface_builder.call({
		"chunk_coord": chunk_coord,
		"blocks": blocks,
		"world": world,
		"root": _overlay_root,
	})

func _store_build_stats(
	build_result: Dictionary,
	render_config: Dictionary,
	mesh_build_usec: int,
	mesh_apply_usec: int,
	collision_build_usec: int,
	collision_apply_usec: int
) -> void:
	if not bool(render_config.get("collect_chunk_render_stats", false)):
		_last_build_stats = {}
		return

	var stats: Dictionary = build_result.get("stats", {})
	var mesh_commit_usec := int(stats.get("mesh_commit_usec", 0))
	_last_build_stats = {
		"chunk_coord": chunk_coord,
		"quad_count": int(stats.get("quad_count", 0)),
		"triangle_count": int(stats.get("triangle_count", 0)),
		"vertex_count": int(stats.get("vertex_count", 0)),
		"surface_count": _mesh_instance.mesh.get_surface_count() if _mesh_instance.mesh != null else 0,
		"collision_enabled": _collision_enabled,
		"collision_dirty": _collision_dirty,
		"mesh_build_usec": mesh_build_usec,
		"mesh_geometry_usec": int(stats.get("mesh_geometry_usec", 0)),
		"mesh_commit_usec": mesh_commit_usec,
		"mesh_apply_usec": mesh_apply_usec,
		"mesh_submission_usec": mesh_commit_usec + mesh_apply_usec,
		"collision_build_usec": collision_build_usec,
		"collision_apply_usec": collision_apply_usec,
		"render_budget": render_config.get("render_budget", {}),
	}

func _apply_collision_shape(shape: Shape3D, enabled: bool, replace_shape: bool) -> void:
	if _collision_shape == null:
		return

	if replace_shape:
		_collision_shape.shape = shape
	elif shape != null and _collision_shape.shape == null:
		_collision_shape.shape = shape

	_collision_enabled = enabled and _collision_shape.shape != null
	_collision_shape.disabled = not _collision_enabled

func _store_collision_sync_stats(
	collect_stats: bool,
	requested_enabled: bool,
	sync_started_usec: int,
	collision_build_usec: int,
	collision_apply_usec: int
) -> void:
	if not collect_stats:
		_last_collision_sync_stats = {}
		return

	_last_collision_sync_stats = {
		"collision_sync_requested_enabled": requested_enabled,
		"collision_sync_usec": Time.get_ticks_usec() - sync_started_usec,
		"collision_shape_build_usec": collision_build_usec,
		"collision_sync_apply_usec": collision_apply_usec,
		"collision_sync_enabled": _collision_enabled,
	}

func _ensure_render_nodes() -> void:
	if _owner == null:
		return

	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "ChunkMesh"
		_owner.add_child(_mesh_instance)

	if _overlay_root == null:
		_overlay_root = Node3D.new()
		_overlay_root.name = "ChunkOverlays"
		_owner.add_child(_overlay_root)

	if _static_body == null:
		_static_body = StaticBody3D.new()
		_static_body.name = "ChunkBody"
		_owner.add_child(_static_body)

	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "ChunkCollision"
		_collision_shape.disabled = true
		_static_body.add_child(_collision_shape)

