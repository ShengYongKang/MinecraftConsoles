class_name GameRules
extends RefCounted

const FACE_POS_X := 0
const FACE_NEG_X := 1
const FACE_TOP := 2
const FACE_BOTTOM := 3
const FACE_POS_Z := 4
const FACE_NEG_Z := 5
const FACE_SIDE := 6
const FACE_ANY := -1
const FACE_COUNT := 6

const TERRAIN_ATLAS_SIZE := 16
const DEFAULT_ITEM_STACK_SIZE := 64
const CRAFTING_GRID_SIZE := Vector2i(3, 3)

static func normalize_face_index(face_index: int) -> int:
	if face_index >= 0 and face_index < FACE_COUNT:
		return face_index
	return FACE_ANY

static func is_lateral_face(face_index: int) -> bool:
	return (
		face_index == FACE_POS_X or
		face_index == FACE_NEG_X or
		face_index == FACE_POS_Z or
		face_index == FACE_NEG_Z
	)
