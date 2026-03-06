class_name MaterialRegistry
extends RefCounted

const SOLID_BLOCKS_MATERIAL_ID: StringName = &"solid_blocks"
const DEFAULT_ATLAS_TEXTURE_PATH := "res://assets/textures/terrain.png"
const DEFAULT_SOLID_BLOCK_SHADER_PATH := "res://shaders/voxel/voxel_blocks.gdshader"
const LEGACY_SOLID_BLOCK_SHADER_PATH := "res://shaders/voxel_blocks.gdshader"

var atlas_texture_path := DEFAULT_ATLAS_TEXTURE_PATH
var solid_block_shader_path := DEFAULT_SOLID_BLOCK_SHADER_PATH
var atlas_size := BlockDefs.ATLAS_SIZE
var use_vertex_lighting := false

var _materials: Dictionary = {}
var _atlas_texture: Texture2D
var _solid_block_shader: Shader

func configure(options: Dictionary = {}) -> void:
	atlas_texture_path = str(options.get("atlas_texture_path", atlas_texture_path))
	solid_block_shader_path = str(options.get("solid_block_shader_path", solid_block_shader_path))
	atlas_size = maxi(1, int(options.get("atlas_size", atlas_size)))
	use_vertex_lighting = bool(options.get("use_vertex_lighting", use_vertex_lighting))
	_materials.clear()
	_atlas_texture = null
	_solid_block_shader = null

func get_material(material_id: StringName = SOLID_BLOCKS_MATERIAL_ID) -> Material:
	match material_id:
		SOLID_BLOCKS_MATERIAL_ID:
			return _get_or_create_solid_block_material()
		_:
			return null

func get_block_material() -> Material:
	return get_material(SOLID_BLOCKS_MATERIAL_ID)

func get_render_config() -> Dictionary:
	return {
		"material": get_block_material(),
		"material_id": SOLID_BLOCKS_MATERIAL_ID,
		"atlas_texture_path": atlas_texture_path,
		"solid_block_shader_path": solid_block_shader_path,
		"atlas_size": atlas_size,
		"use_vertex_lighting": use_vertex_lighting,
	}

func _get_or_create_solid_block_material() -> Material:
	if _materials.has(SOLID_BLOCKS_MATERIAL_ID):
		return _materials[SOLID_BLOCKS_MATERIAL_ID]

	var shader := _load_solid_block_shader()
	if shader == null:
		return null

	var material := ShaderMaterial.new()
	material.shader = shader
	_apply_solid_block_material_parameters(material)
	_materials[SOLID_BLOCKS_MATERIAL_ID] = material
	return material

func _apply_solid_block_material_parameters(material: ShaderMaterial) -> void:
	var atlas_texture := _load_atlas_texture()
	material.set_shader_parameter("atlas_texture", atlas_texture)
	material.set_shader_parameter("atlas_size", float(atlas_size))
	material.set_shader_parameter("tile_resolution", _compute_tile_resolution(atlas_texture))
	material.set_shader_parameter("use_vertex_lighting", use_vertex_lighting)

func _load_atlas_texture() -> Texture2D:
	if _atlas_texture != null:
		return _atlas_texture

	_atlas_texture = load(atlas_texture_path)
	if _atlas_texture == null and atlas_texture_path != DEFAULT_ATLAS_TEXTURE_PATH:
		_atlas_texture = load(DEFAULT_ATLAS_TEXTURE_PATH)
	return _atlas_texture

func _load_solid_block_shader() -> Shader:
	if _solid_block_shader != null:
		return _solid_block_shader

	_solid_block_shader = load(solid_block_shader_path)
	if _solid_block_shader == null and solid_block_shader_path != LEGACY_SOLID_BLOCK_SHADER_PATH:
		_solid_block_shader = load(LEGACY_SOLID_BLOCK_SHADER_PATH)
	return _solid_block_shader

func _compute_tile_resolution(atlas_texture: Texture2D) -> float:
	if atlas_texture == null:
		return 16.0
	return float(atlas_texture.get_width()) / float(atlas_size)
