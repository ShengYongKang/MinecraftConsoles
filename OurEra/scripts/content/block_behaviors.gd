class_name BlockBehaviors
extends RefCounted

const ContentBlockDefsScript = preload("res://scripts/content/block_defs.gd")
const LootTablesScript = preload("res://scripts/content/loot_tables.gd")

static func is_solid(block_id: int) -> bool:
	return ContentBlockDefsScript.is_solid(block_id)

static func is_transparent(block_id: int) -> bool:
	return ContentBlockDefsScript.is_transparent(block_id)

static func is_replaceable(block_id: int) -> bool:
	return ContentBlockDefsScript.is_replaceable(block_id)

static func blocks_light(block_id: int) -> bool:
	return ContentBlockDefsScript.blocks_light(block_id)

static func can_support_neighbor(block_id: int) -> bool:
	return is_solid(block_id)

static func get_hardness(block_id: int) -> float:
	return float(ContentBlockDefsScript.get_property(block_id, &"hardness", 0.0))

static func get_break_drops(block_id: int, context: Dictionary = {}) -> Array[Dictionary]:
	return LootTablesScript.get_drops_for_block(block_id, context)

static func tile_for_face(block_id: int, face_index: int) -> Vector2i:
	return ContentBlockDefsScript.tile_for_face(block_id, face_index)
