class_name VoxelWorld
extends WorldRoot

const WorldConstants = preload("res://scripts/world/world_constants.gd")

const CHUNK_WIDTH := WorldConstants.CHUNK_WIDTH
const WORLD_HEIGHT := WorldConstants.WORLD_HEIGHT
const SEA_LEVEL := WorldConstants.SEA_LEVEL
const CHUNK_VOLUME := WorldConstants.CHUNK_VOLUME
const SAVE_FORMAT_VERSION := WorldConstants.SAVE_FORMAT_VERSION
const WORLD_META_FORMAT_VERSION := WorldConstants.WORLD_META_FORMAT_VERSION