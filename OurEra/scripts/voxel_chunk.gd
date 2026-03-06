class_name VoxelChunk
extends Node3D

const WorldConstants = preload("res://scripts/world/world_constants.gd")
const VoxelChunkRendererScript = preload("res://scripts/render/voxel_chunk_renderer.gd")

var world
var chunk_coord: Vector2i = Vector2i.ZERO
var blocks: PackedInt32Array
var renderer = VoxelChunkRendererScript.new()

func _ready() -> void:
	renderer.attach(self)

func initialize(p_world, p_coord: Vector2i, p_blocks: PackedInt32Array) -> void:
	world = p_world
	chunk_coord = p_coord
	blocks = p_blocks
	position = Vector3(chunk_coord.x * WorldConstants.CHUNK_WIDTH, 0, chunk_coord.y * WorldConstants.CHUNK_WIDTH)
	renderer.attach(self)
	renderer.configure(world, chunk_coord, blocks)

func refresh_render(with_collision: bool = true) -> void:
	if world == null:
		return

	renderer.attach(self)
	renderer.configure(world, chunk_coord, blocks)
	renderer.rebuild(with_collision)

func sync_collision(enabled: bool) -> void:
	renderer.attach(self)
	renderer.sync_collision(enabled)

func has_collision_enabled() -> bool:
	return renderer.has_collision_enabled()

func rebuild_mesh(with_collision: bool = true) -> void:
	refresh_render(with_collision)

func get_render_stats() -> Dictionary:
	return renderer.get_last_build_stats()
