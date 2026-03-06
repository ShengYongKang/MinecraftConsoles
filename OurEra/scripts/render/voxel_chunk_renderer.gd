class_name VoxelChunkRenderer
extends RefCounted

const WorldConstants = preload("res://scripts/world/world_constants.gd")
const MeshBuilderGreedyScript = preload("res://scripts/render/mesh_builder_greedy.gd")
const CollisionBuilderScript = preload("res://scripts/render/collision_builder.gd")

var world
var chunk_coord: Vector2i = Vector2i.ZERO
var blocks: PackedInt32Array

var _owner: Node3D
var _mesh_instance: MeshInstance3D
var _overlay_root: Node3D
var _static_body: StaticBody3D
var _collision_shape: CollisionShape3D

var _mesh_builder = MeshBuilderGreedyScript.new()
var _collision_builder = CollisionBuilderScript.new()
var _last_build_stats: Dictionary = {}
var _cached_collision_shape: Shape3D
var _collision_enabled := false

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
	var mesh_started_usec := Time.get_ticks_usec() if collect_stats else 0
	var build_result: Dictionary = _mesh_builder.build({
		"chunk_origin": WorldConstants.chunk_origin(chunk_coord),
		"dimensions": Vector3i(
			WorldConstants.CHUNK_WIDTH,
			WorldConstants.WORLD_HEIGHT,
			WorldConstants.CHUNK_WIDTH
		),
		"material": render_config.get("material", null),
		"block_sampler": Callable(self, "_sample_block_for_meshing"),
		"light_sampler": render_config.get("light_sampler", Callable()),
		"collect_collision_faces": with_collision,
	})
	var mesh_build_usec := Time.get_ticks_usec() - mesh_started_usec if collect_stats else 0

	_mesh_instance.mesh = build_result.get("mesh", null)
	_cached_collision_shape = null
	var collision_build_usec := 0

	if with_collision:
		var collision_started_usec := Time.get_ticks_usec() if collect_stats else 0
		var collision_faces: PackedVector3Array = build_result.get("collision_faces", PackedVector3Array())
		_cached_collision_shape = _collision_builder.build_shape_from_faces(collision_faces)
		_apply_collision_shape(_cached_collision_shape, true)
		collision_build_usec = Time.get_ticks_usec() - collision_started_usec if collect_stats else 0
	else:
		_apply_collision_shape(null, false)

	_refresh_overlay_layers(render_config)
	_store_build_stats(build_result, render_config, mesh_build_usec, collision_build_usec)

func sync_collision(enabled: bool) -> void:
	_ensure_render_nodes()
	if not enabled or _mesh_instance == null or _mesh_instance.mesh == null:
		_apply_collision_shape(_cached_collision_shape, false)
		return

	if _cached_collision_shape == null:
		_cached_collision_shape = _collision_builder.build_shape(_mesh_instance.mesh)
	_apply_collision_shape(_cached_collision_shape, true)

func has_collision_enabled() -> bool:
	return _collision_enabled

func get_last_build_stats() -> Dictionary:
	return _last_build_stats.duplicate(true)

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
	collision_build_usec: int
) -> void:
	if not bool(render_config.get("collect_chunk_render_stats", false)):
		_last_build_stats = {}
		return

	var stats: Dictionary = build_result.get("stats", {})
	_last_build_stats = {
		"chunk_coord": chunk_coord,
		"quad_count": int(stats.get("quad_count", 0)),
		"triangle_count": int(stats.get("triangle_count", 0)),
		"vertex_count": int(stats.get("vertex_count", 0)),
		"surface_count": _mesh_instance.mesh.get_surface_count() if _mesh_instance.mesh != null else 0,
		"collision_enabled": _collision_enabled,
		"mesh_build_usec": mesh_build_usec,
		"collision_build_usec": collision_build_usec,
		"render_budget": render_config.get("render_budget", {}),
	}

func _apply_collision_shape(shape: Shape3D, enabled: bool) -> void:
	if _collision_shape == null:
		return

	if shape != null:
		_collision_shape.shape = shape
	elif not enabled:
		_collision_shape.shape = null

	_collision_enabled = enabled and shape != null
	_collision_shape.disabled = not _collision_enabled

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
