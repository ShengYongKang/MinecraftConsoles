class_name UIIconFactory
extends RefCounted

const TILE_SIZE := 16
const PROTOTYPE_ATLAS_PATH := "res://assets/prototype_temp/mc_placeholder/terrain.png"
const FALLBACK_ATLAS_PATH := "res://assets/textures/terrain.png"

static var _atlas_texture: Texture2D

static func create_icon_from_tile(tile: Vector2i) -> Texture2D:
	var atlas := _get_atlas_texture()
	if atlas == null:
		return null

	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = Rect2(tile * TILE_SIZE, Vector2(TILE_SIZE, TILE_SIZE))
	return texture

static func _get_atlas_texture() -> Texture2D:
	if _atlas_texture != null:
		return _atlas_texture

	_atlas_texture = _load_texture_from_png(PROTOTYPE_ATLAS_PATH)
	if _atlas_texture == null:
		_atlas_texture = _load_texture_from_png(FALLBACK_ATLAS_PATH)
	return _atlas_texture

static func _load_texture_from_png(resource_path: String) -> Texture2D:
	var global_path := ProjectSettings.globalize_path(resource_path)
	if not FileAccess.file_exists(global_path):
		return null

	var png_bytes := FileAccess.get_file_as_bytes(global_path)
	if png_bytes.is_empty():
		return null

	var image := Image.new()
	var error := image.load_png_from_buffer(png_bytes)
	if error != OK:
		return null

	return ImageTexture.create_from_image(image)
