class_name ItemDefs
extends RefCounted

const NONE := 0
const GRASS_BLOCK := 1
const DIRT_BLOCK := 2
const STONE_BLOCK := 3
const COBBLE_BLOCK := 4

const DEFAULT_STACK_SIZE := 64

const _ORDERED_ITEM_IDS := [
	GRASS_BLOCK,
	DIRT_BLOCK,
	STONE_BLOCK,
	COBBLE_BLOCK,
]

static var _ITEMS: Dictionary = _build_items()

static func has_item(item_id: int) -> bool:
	return _ITEMS.has(item_id)

static func get_item_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for item_id in _ORDERED_ITEM_IDS:
		ids.append(item_id)
	return ids

static func get_item_def(item_id: int) -> Dictionary:
	return _resolve_item(item_id).duplicate(true)

static func get_display_data(item_id: int) -> Dictionary:
	return Dictionary(_resolve_item(item_id).get("display", {})).duplicate(true)

static func get_item_meta(item_id: int) -> Dictionary:
	return Dictionary(_resolve_item(item_id).get("meta", {})).duplicate(true)

static func get_placeable_block_id(item_id: int) -> int:
	return int(_resolve_item(item_id).get("placeable_block_id", 0))

static func get_icon_tile(item_id: int) -> Vector2i:
	var icon_tile: Variant = _resolve_item(item_id).get("icon_tile", Vector2i.ZERO)
	if icon_tile is Vector2i:
		return icon_tile
	return Vector2i.ZERO

static func get_property(item_id: int, property_name: StringName, default_value: Variant = null) -> Variant:
	return _resolve_item(item_id).get(str(property_name), default_value)

static func _resolve_item(item_id: int) -> Dictionary:
	if _ITEMS.has(item_id):
		return _ITEMS[item_id]
	return _ITEMS[NONE]

static func _build_items() -> Dictionary:
	return {
		NONE: {
			"id": NONE,
			"key": &"none",
			"display": {
				"name": "None",
				"short_name": "None",
			},
			"category": &"system",
			"max_stack": 0,
			"placeable_block_id": 0,
			"icon_tile": Vector2i.ZERO,
			"meta": {
				"debug_name": "NONE",
				"tags": PackedStringArray(["system"]),
			},
		},
		GRASS_BLOCK: {
			"id": GRASS_BLOCK,
			"key": &"grass_block",
			"display": {
				"name": "Grass Block",
				"short_name": "Grass",
			},
			"category": &"block",
			"max_stack": DEFAULT_STACK_SIZE,
			"placeable_block_id": 1,
			"icon_tile": Vector2i(0, 0),
			"meta": {
				"debug_name": "GRASS_BLOCK",
				"tags": PackedStringArray(["block", "terrain", "placeable"]),
			},
		},
		DIRT_BLOCK: {
			"id": DIRT_BLOCK,
			"key": &"dirt_block",
			"display": {
				"name": "Dirt",
				"short_name": "Dirt",
			},
			"category": &"block",
			"max_stack": DEFAULT_STACK_SIZE,
			"placeable_block_id": 2,
			"icon_tile": Vector2i(2, 0),
			"meta": {
				"debug_name": "DIRT_BLOCK",
				"tags": PackedStringArray(["block", "terrain", "placeable"]),
			},
		},
		STONE_BLOCK: {
			"id": STONE_BLOCK,
			"key": &"stone_block",
			"display": {
				"name": "Stone",
				"short_name": "Stone",
			},
			"category": &"block",
			"max_stack": DEFAULT_STACK_SIZE,
			"placeable_block_id": 3,
			"icon_tile": Vector2i(1, 0),
			"meta": {
				"debug_name": "STONE_BLOCK",
				"tags": PackedStringArray(["block", "terrain", "placeable"]),
			},
		},
		COBBLE_BLOCK: {
			"id": COBBLE_BLOCK,
			"key": &"cobble_block",
			"display": {
				"name": "Cobblestone",
				"short_name": "Cobble",
			},
			"category": &"block",
			"max_stack": DEFAULT_STACK_SIZE,
			"placeable_block_id": 4,
			"icon_tile": Vector2i(0, 1),
			"meta": {
				"debug_name": "COBBLE_BLOCK",
				"tags": PackedStringArray(["block", "terrain", "placeable"]),
			},
		},
	}
