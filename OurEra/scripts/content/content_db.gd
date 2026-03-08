class_name ContentDB
extends RefCounted

const ContentBlockDefsScript = preload("res://scripts/content/block_defs.gd")
const GameModeDefsScript = preload("res://scripts/content/game_mode_defs.gd")
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

const GAME_MODE_CREATIVE := GameModeDefsScript.CREATIVE
const GAME_MODE_SURVIVAL := GameModeDefsScript.SURVIVAL

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

static func has_game_mode(mode_id: StringName) -> bool:
	return GameModeDefsScript.has_mode(mode_id)

static func get_game_mode_ids() -> Array[StringName]:
	return GameModeDefsScript.get_mode_ids()

static func get_default_game_mode_id() -> StringName:
	return GameModeDefsScript.get_default_mode_id()

static func normalize_game_mode_id(mode_id: StringName) -> StringName:
	return GameModeDefsScript.normalize_mode_id(mode_id)

static func get_game_mode_def(mode_id: StringName) -> Dictionary:
	return GameModeDefsScript.get_mode_def(mode_id)

static func get_game_mode_display_data(mode_id: StringName) -> Dictionary:
	return GameModeDefsScript.get_display_data(mode_id)

static func get_game_mode_meta(mode_id: StringName) -> Dictionary:
	return GameModeDefsScript.get_mode_meta(mode_id)

static func get_game_mode_setting(mode_id: StringName, setting_key: StringName, default_value: Variant = null) -> Variant:
	return GameModeDefsScript.get_setting(mode_id, setting_key, default_value)

static func allows_block_drops(mode_id: StringName) -> bool:
	return GameModeDefsScript.are_block_drops_enabled(mode_id)

static func does_placement_consume_inventory(mode_id: StringName) -> bool:
	return GameModeDefsScript.does_placement_consume_inventory(mode_id)

static func requires_inventory_for_placement(mode_id: StringName) -> bool:
	return GameModeDefsScript.does_placement_require_inventory(mode_id)

static func allows_drop_pickup(mode_id: StringName) -> bool:
	return GameModeDefsScript.is_drop_pickup_enabled(mode_id)

static func is_instant_break_enabled(mode_id: StringName) -> bool:
	return GameModeDefsScript.is_instant_break_enabled(mode_id)

static func is_health_enabled(mode_id: StringName) -> bool:
	return GameModeDefsScript.is_health_enabled(mode_id)

static func is_hunger_enabled(mode_id: StringName) -> bool:
	return GameModeDefsScript.is_hunger_enabled(mode_id)

static func is_damage_enabled(mode_id: StringName) -> bool:
	return GameModeDefsScript.is_damage_enabled(mode_id)

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
