class_name ContentBlockDefs
extends RefCounted

const GameRulesScript = preload("res://scripts/content/game_rules.gd")
const ItemDefsScript = preload("res://scripts/content/item_defs.gd")
const RecipeDefsScript = preload("res://scripts/content/recipe_defs.gd")
const LootTablesScript = preload("res://scripts/content/loot_tables.gd")

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4

const ITEM_NONE := 0
const ITEM_GRASS_BLOCK := 1
const ITEM_DIRT_BLOCK := 2
const ITEM_STONE_BLOCK := 3
const ITEM_COBBLE_BLOCK := 4

const LOOT_TABLE_AIR := &"blocks/air"
const LOOT_TABLE_GRASS := &"blocks/grass"
const LOOT_TABLE_DIRT := &"blocks/dirt"
const LOOT_TABLE_STONE := &"blocks/stone"
const LOOT_TABLE_COBBLE := &"blocks/cobble"

const FACE_TOP := 2
const FACE_BOTTOM := 3
const FACE_SIDE := 6
const FACE_ANY := -1

const ATLAS_SIZE := 16

const TILE_GRASS_TOP := Vector2i(0, 0)
const TILE_STONE := Vector2i(1, 0)
const TILE_DIRT := Vector2i(2, 0)
const TILE_GRASS_SIDE := Vector2i(3, 0)
const TILE_COBBLE := Vector2i(0, 1)

const _ORDERED_BLOCK_IDS := [
	AIR,
	GRASS,
	DIRT,
	STONE,
	COBBLE,
]

static var _BLOCKS: Dictionary = _build_blocks()

static func has_block(block_id: int) -> bool:
	return _BLOCKS.has(block_id)

static func get_block_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for block_id in _ORDERED_BLOCK_IDS:
		ids.append(block_id)
	return ids

static func get_block_def(block_id: int) -> Dictionary:
	return _resolve_block(block_id).duplicate(true)

static func get_display_data(block_id: int) -> Dictionary:
	return Dictionary(_resolve_block(block_id).get("display", {})).duplicate(true)

static func get_block_meta(block_id: int) -> Dictionary:
	return Dictionary(_resolve_block(block_id).get("meta", {})).duplicate(true)

static func get_property(block_id: int, property_name: StringName, default_value: Variant = null) -> Variant:
	return _resolve_block(block_id).get(str(property_name), default_value)

static func get_item_id(block_id: int) -> int:
	return int(_resolve_block(block_id).get("item_id", ITEM_NONE))

static func get_loot_table_id(block_id: int) -> StringName:
	return StringName(_resolve_block(block_id).get("loot_table", LOOT_TABLE_AIR))

static func get_item_def(item_id: int) -> Dictionary:
	return ItemDefsScript.get_item_def(item_id)

static func get_item_display_data(item_id: int) -> Dictionary:
	return ItemDefsScript.get_display_data(item_id)

static func get_item_meta(item_id: int) -> Dictionary:
	return ItemDefsScript.get_item_meta(item_id)

static func is_air(block_id: int) -> bool:
	return block_id == AIR

static func is_solid(block_id: int) -> bool:
	return bool(_resolve_block(block_id).get("solid", false))

static func is_transparent(block_id: int) -> bool:
	return bool(_resolve_block(block_id).get("transparent", false))

static func is_replaceable(block_id: int) -> bool:
	return bool(_resolve_block(block_id).get("replaceable", false))

static func blocks_light(block_id: int) -> bool:
	return bool(_resolve_block(block_id).get("blocks_light", is_solid(block_id)))

static func tile_for_face(block_id: int, face_index: int) -> Vector2i:
	var block_def := _resolve_block(block_id)
	var tiles: Dictionary = block_def.get("tiles", {})
	var normalized_face: int = GameRulesScript.normalize_face_index(face_index)

	var exact_tile: Variant = tiles.get(normalized_face, null)
	if exact_tile is Vector2i:
		return exact_tile

	if GameRulesScript.is_lateral_face(normalized_face):
		var side_tile: Variant = tiles.get(FACE_SIDE, null)
		if side_tile is Vector2i:
			return side_tile

	var any_tile: Variant = tiles.get(FACE_ANY, null)
	if any_tile is Vector2i:
		return any_tile

	return TILE_STONE

static func get_block_drops(block_id: int, context: Dictionary = {}) -> Array[Dictionary]:
	return LootTablesScript.get_drops_for_block(block_id, context)

static func get_recipe(recipe_id: StringName) -> Dictionary:
	return RecipeDefsScript.get_recipe(recipe_id)

static func get_recipes_for_output(item_id: int) -> Array[Dictionary]:
	return RecipeDefsScript.get_recipes_for_output(item_id)

static func get_loot_table(table_id: StringName) -> Dictionary:
	return LootTablesScript.get_table(table_id)

static func _resolve_block(block_id: int) -> Dictionary:
	if _BLOCKS.has(block_id):
		return _BLOCKS[block_id]
	return _BLOCKS[STONE]

static func _build_blocks() -> Dictionary:
	return {
		AIR: {
			"id": AIR,
			"key": &"air",
			"display": {
				"name": "Air",
				"short_name": "Air",
			},
			"meta": {
				"debug_name": "AIR",
				"category": &"utility",
				"tags": PackedStringArray(["non_solid", "replaceable"]),
			},
			"solid": false,
			"transparent": true,
			"replaceable": true,
			"blocks_light": false,
			"hardness": 0.0,
			"item_id": ITEM_NONE,
			"loot_table": LOOT_TABLE_AIR,
			"tiles": {},
		},
		GRASS: {
			"id": GRASS,
			"key": &"grass",
			"display": {
				"name": "Grass Block",
				"short_name": "Grass",
			},
			"meta": {
				"debug_name": "GRASS",
				"category": &"terrain",
				"tags": PackedStringArray(["natural", "surface", "ground"]),
			},
			"solid": true,
			"transparent": false,
			"replaceable": false,
			"blocks_light": true,
			"hardness": 0.6,
			"item_id": ITEM_GRASS_BLOCK,
			"loot_table": LOOT_TABLE_GRASS,
			"tiles": {
				FACE_TOP: TILE_GRASS_TOP,
				FACE_BOTTOM: TILE_DIRT,
				FACE_SIDE: TILE_GRASS_SIDE,
			},
		},
		DIRT: {
			"id": DIRT,
			"key": &"dirt",
			"display": {
				"name": "Dirt",
				"short_name": "Dirt",
			},
			"meta": {
				"debug_name": "DIRT",
				"category": &"terrain",
				"tags": PackedStringArray(["natural", "ground"]),
			},
			"solid": true,
			"transparent": false,
			"replaceable": false,
			"blocks_light": true,
			"hardness": 0.5,
			"item_id": ITEM_DIRT_BLOCK,
			"loot_table": LOOT_TABLE_DIRT,
			"tiles": {
				FACE_ANY: TILE_DIRT,
			},
		},
		STONE: {
			"id": STONE,
			"key": &"stone",
			"display": {
				"name": "Stone",
				"short_name": "Stone",
			},
			"meta": {
				"debug_name": "STONE",
				"category": &"terrain",
				"tags": PackedStringArray(["natural", "underground"]),
			},
			"solid": true,
			"transparent": false,
			"replaceable": false,
			"blocks_light": true,
			"hardness": 1.5,
			"item_id": ITEM_STONE_BLOCK,
			"loot_table": LOOT_TABLE_STONE,
			"tiles": {
				FACE_ANY: TILE_STONE,
			},
		},
		COBBLE: {
			"id": COBBLE,
			"key": &"cobble",
			"display": {
				"name": "Cobblestone",
				"short_name": "Cobble",
			},
			"meta": {
				"debug_name": "COBBLE",
				"category": &"terrain",
				"tags": PackedStringArray(["crafted", "stone"]),
			},
			"solid": true,
			"transparent": false,
			"replaceable": false,
			"blocks_light": true,
			"hardness": 2.0,
			"item_id": ITEM_COBBLE_BLOCK,
			"loot_table": LOOT_TABLE_COBBLE,
			"tiles": {
				FACE_ANY: TILE_COBBLE,
			},
		},
	}
