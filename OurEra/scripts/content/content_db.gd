class_name ContentDB
extends RefCounted

const ContentBlockDefsScript = preload("res://scripts/content/block_defs.gd")
const ItemDefsScript = preload("res://scripts/content/item_defs.gd")
const RecipeDefsScript = preload("res://scripts/content/recipe_defs.gd")
const LootTablesScript = preload("res://scripts/content/loot_tables.gd")
const BlockBehaviorsScript = preload("res://scripts/content/block_behaviors.gd")

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4

const ATLAS_SIZE := 16
const DEFAULT_SELECTED_BLOCK_ID := COBBLE

static func has_block(block_id: int) -> bool:
	return ContentBlockDefsScript.has_block(block_id)

static func get_block_ids() -> PackedInt32Array:
	return ContentBlockDefsScript.get_block_ids()

static func get_block_def(block_id: int) -> Dictionary:
	return ContentBlockDefsScript.get_block_def(block_id)

static func get_block_display_data(block_id: int) -> Dictionary:
	return ContentBlockDefsScript.get_display_data(block_id)

static func get_block_meta(block_id: int) -> Dictionary:
	return ContentBlockDefsScript.get_block_meta(block_id)

static func get_block_property(block_id: int, property_name: StringName, default_value: Variant = null) -> Variant:
	return ContentBlockDefsScript.get_property(block_id, property_name, default_value)

static func get_item_id_for_block(block_id: int) -> int:
	return ContentBlockDefsScript.get_item_id(block_id)

static func get_loot_table_id_for_block(block_id: int) -> StringName:
	return ContentBlockDefsScript.get_loot_table_id(block_id)

static func is_air(block_id: int) -> bool:
	return block_id == AIR

static func is_solid(block_id: int) -> bool:
	return BlockBehaviorsScript.is_solid(block_id)

static func is_transparent(block_id: int) -> bool:
	return BlockBehaviorsScript.is_transparent(block_id)

static func is_replaceable(block_id: int) -> bool:
	return BlockBehaviorsScript.is_replaceable(block_id)

static func blocks_light(block_id: int) -> bool:
	return BlockBehaviorsScript.blocks_light(block_id)

static func can_place_block(block_id: int) -> bool:
	return has_block(block_id) and not is_air(block_id)

static func sanitize_placeable_block_id(block_id: int) -> int:
	if can_place_block(block_id):
		return block_id
	return DEFAULT_SELECTED_BLOCK_ID

static func get_default_selected_block_id() -> int:
	return DEFAULT_SELECTED_BLOCK_ID

static func can_replace_block(block_id: int) -> bool:
	return is_replaceable(block_id)

static func tile_for_face(block_id: int, face_index: int) -> Vector2i:
	return ContentBlockDefsScript.tile_for_face(block_id, face_index)

static func get_block_drops(block_id: int, context: Dictionary = {}) -> Array[Dictionary]:
	return ContentBlockDefsScript.get_block_drops(block_id, context)

static func get_item_def(item_id: int) -> Dictionary:
	return ItemDefsScript.get_item_def(item_id)

static func get_item_display_data(item_id: int) -> Dictionary:
	return ItemDefsScript.get_display_data(item_id)

static func get_item_meta(item_id: int) -> Dictionary:
	return ItemDefsScript.get_item_meta(item_id)

static func get_item_icon_tile(item_id: int) -> Vector2i:
	return ItemDefsScript.get_icon_tile(item_id)

static func get_recipe(recipe_id: StringName) -> Dictionary:
	return RecipeDefsScript.get_recipe(recipe_id)

static func get_recipes_for_output(item_id: int) -> Array[Dictionary]:
	return RecipeDefsScript.get_recipes_for_output(item_id)

static func get_loot_table(table_id: StringName) -> Dictionary:
	return LootTablesScript.get_table(table_id)

static func get_generated_block_id(surface_height: int, y: int, sea_level: int) -> int:
	var block_id := STONE
	if y == surface_height:
		block_id = GRASS
	elif y >= surface_height - 3:
		block_id = DIRT

	if y < sea_level - 6 and y % 9 == 0:
		block_id = COBBLE

	return block_id
