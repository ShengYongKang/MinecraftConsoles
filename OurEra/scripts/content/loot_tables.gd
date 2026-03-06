class_name LootTables
extends RefCounted

const ITEM_NONE := 0
const ITEM_GRASS_BLOCK := 1
const ITEM_DIRT_BLOCK := 2
const ITEM_STONE_BLOCK := 3
const ITEM_COBBLE_BLOCK := 4

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4

const TABLE_AIR := &"blocks/air"
const TABLE_GRASS := &"blocks/grass"
const TABLE_DIRT := &"blocks/dirt"
const TABLE_STONE := &"blocks/stone"
const TABLE_COBBLE := &"blocks/cobble"

const _BLOCK_TABLE_IDS := {
	AIR: TABLE_AIR,
	GRASS: TABLE_GRASS,
	DIRT: TABLE_DIRT,
	STONE: TABLE_STONE,
	COBBLE: TABLE_COBBLE,
}

static var _TABLES: Dictionary = _build_tables()

static func has_table(table_id: StringName) -> bool:
	return _TABLES.has(table_id)

static func get_table(table_id: StringName) -> Dictionary:
	return _resolve_table(table_id).duplicate(true)

static func get_block_table_id(block_id: int) -> StringName:
	return _BLOCK_TABLE_IDS.get(block_id, TABLE_AIR)

static func get_block_loot_table(block_id: int) -> Dictionary:
	return get_table(get_block_table_id(block_id))

static func get_drops_for_block(block_id: int, context: Dictionary = {}) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	var table := _resolve_table(get_block_table_id(block_id))
	var entries: Array = table.get("entries", [])

	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue

		var entry: Dictionary = entry_variant
		if not _passes_context(entry, context):
			continue

		var count := _resolve_drop_count(entry)
		if count <= 0:
			continue

		drops.append({
			"item_id": int(entry.get("item_id", ITEM_NONE)),
			"count": count,
			"source_table": table.get("id", TABLE_AIR),
		})

	return drops

static func _resolve_table(table_id: StringName) -> Dictionary:
	if _TABLES.has(table_id):
		return _TABLES[table_id]
	return _TABLES[TABLE_AIR]

static func _resolve_drop_count(entry: Dictionary) -> int:
	var min_count := maxi(0, int(entry.get("min_count", 1)))
	var max_count := maxi(min_count, int(entry.get("max_count", min_count)))

	if min_count == max_count:
		return min_count

	return min_count

static func _passes_context(entry: Dictionary, context: Dictionary) -> bool:
	var required_flag: Variant = entry.get("requires_flag", null)
	if required_flag == null:
		return true
	return bool(context.get(required_flag, false))

static func _build_tables() -> Dictionary:
	return {
		TABLE_AIR: {
			"id": TABLE_AIR,
			"entries": [],
			"meta": {
				"source": &"block_break",
			},
		},
		TABLE_GRASS: {
			"id": TABLE_GRASS,
			"entries": [
				{
					"item_id": ITEM_GRASS_BLOCK,
					"min_count": 1,
					"max_count": 1,
				},
			],
			"meta": {
				"source": &"block_break",
			},
		},
		TABLE_DIRT: {
			"id": TABLE_DIRT,
			"entries": [
				{
					"item_id": ITEM_DIRT_BLOCK,
					"min_count": 1,
					"max_count": 1,
				},
			],
			"meta": {
				"source": &"block_break",
			},
		},
		TABLE_STONE: {
			"id": TABLE_STONE,
			"entries": [
				{
					"item_id": ITEM_STONE_BLOCK,
					"min_count": 1,
					"max_count": 1,
				},
			],
			"meta": {
				"source": &"block_break",
			},
		},
		TABLE_COBBLE: {
			"id": TABLE_COBBLE,
			"entries": [
				{
					"item_id": ITEM_COBBLE_BLOCK,
					"min_count": 1,
					"max_count": 1,
				},
			],
			"meta": {
				"source": &"block_break",
			},
		},
	}
