class_name BlockDefs
extends RefCounted

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const COBBLE := 4

const ATLAS_SIZE := 16

# Terrain.png (classic layout) atlas indices.
const TILE_GRASS_TOP := Vector2i(0, 0)
const TILE_STONE := Vector2i(1, 0)
const TILE_DIRT := Vector2i(2, 0)
const TILE_GRASS_SIDE := Vector2i(3, 0)
const TILE_COBBLE := Vector2i(0, 1)

static func is_solid(block_id: int) -> bool:
	return block_id != AIR

static func tile_for_face(block_id: int, face_index: int) -> Vector2i:
	match block_id:
		GRASS:
			if face_index == 2:
				return TILE_GRASS_TOP
			if face_index == 3:
				return TILE_DIRT
			return TILE_GRASS_SIDE
		DIRT:
			return TILE_DIRT
		STONE:
			return TILE_STONE
		COBBLE:
			return TILE_COBBLE
		_:
			return TILE_STONE
