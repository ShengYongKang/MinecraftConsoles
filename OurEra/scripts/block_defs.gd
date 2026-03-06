class_name BlockDefs
extends RefCounted

const ContentDBScript = preload("res://scripts/content/content_db.gd")

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4

const ATLAS_SIZE := 16

const TILE_GRASS_TOP := Vector2i(0, 0)
const TILE_STONE := Vector2i(1, 0)
const TILE_DIRT := Vector2i(2, 0)
const TILE_GRASS_SIDE := Vector2i(3, 0)
const TILE_COBBLE := Vector2i(0, 1)

static func has_block(block_id: int) -> bool:
	return ContentDBScript.has_block(block_id)

static func get_block_ids() -> PackedInt32Array:
	return ContentDBScript.get_block_ids()

static func get_block_def(block_id: int) -> Dictionary:
	return ContentDBScript.get_block_def(block_id)

static func get_display_data(block_id: int) -> Dictionary:
	return ContentDBScript.get_block_display_data(block_id)

static func get_block_meta(block_id: int) -> Dictionary:
	return ContentDBScript.get_block_meta(block_id)

static func get_property(block_id: int, property_name: StringName, default_value: Variant = null) -> Variant:
	return ContentDBScript.get_block_property(block_id, property_name, default_value)

static func get_item_id(block_id: int) -> int:
	return ContentDBScript.get_item_id_for_block(block_id)

static func get_loot_table_id(block_id: int) -> StringName:
	return ContentDBScript.get_loot_table_id_for_block(block_id)

static func is_solid(block_id: int) -> bool:
	return ContentDBScript.is_solid(block_id)

static func is_transparent(block_id: int) -> bool:
	return ContentDBScript.is_transparent(block_id)

static func is_replaceable(block_id: int) -> bool:
	return ContentDBScript.is_replaceable(block_id)

static func blocks_light(block_id: int) -> bool:
	return ContentDBScript.blocks_light(block_id)

static func tile_for_face(block_id: int, face_index: int) -> Vector2i:
	return ContentDBScript.tile_for_face(block_id, face_index)

static func get_block_drops(block_id: int, context: Dictionary = {}) -> Array[Dictionary]:
	return ContentDBScript.get_block_drops(block_id, context)

static func get_item_def(item_id: int) -> Dictionary:
	return ContentDBScript.get_item_def(item_id)

static func get_item_display_data(item_id: int) -> Dictionary:
	return ContentDBScript.get_item_display_data(item_id)

static func get_item_meta(item_id: int) -> Dictionary:
	return ContentDBScript.get_item_meta(item_id)

static func get_recipe(recipe_id: StringName) -> Dictionary:
	return ContentDBScript.get_recipe(recipe_id)

static func get_recipes_for_output(item_id: int) -> Array[Dictionary]:
	return ContentDBScript.get_recipes_for_output(item_id)

static func get_loot_table(table_id: StringName) -> Dictionary:
	return ContentDBScript.get_loot_table(table_id)
