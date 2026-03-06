class_name WorldConstants
extends RefCounted

const CHUNK_WIDTH := 16
const WORLD_HEIGHT := 128
const SEA_LEVEL := 63
const CHUNK_VOLUME := CHUNK_WIDTH * CHUNK_WIDTH * WORLD_HEIGHT
const SAVE_FORMAT_VERSION := 1
const WORLD_META_FORMAT_VERSION := 1

static func to_index(x: int, y: int, z: int) -> int:
	return x + z * CHUNK_WIDTH + y * CHUNK_WIDTH * CHUNK_WIDTH

static func floor_div(a: int, b: int) -> int:
	return floori(float(a) / float(b))

static func world_to_chunk(pos: Vector3i) -> Vector2i:
	return Vector2i(
		floor_div(pos.x, CHUNK_WIDTH),
		floor_div(pos.z, CHUNK_WIDTH)
	)

static func world_to_local(pos: Vector3i) -> Vector3i:
	var lx: int = pos.x - floor_div(pos.x, CHUNK_WIDTH) * CHUNK_WIDTH
	var lz: int = pos.z - floor_div(pos.z, CHUNK_WIDTH) * CHUNK_WIDTH
	return Vector3i(lx, pos.y, lz)

static func chunk_origin(coord: Vector2i) -> Vector3i:
	return Vector3i(coord.x * CHUNK_WIDTH, 0, coord.y * CHUNK_WIDTH)

static func chunk_distance_sq(center: Vector2i, coord: Vector2i) -> int:
	var dx: int = coord.x - center.x
	var dz: int = coord.y - center.y
	return dx * dx + dz * dz

static func chunk_chebyshev_distance(center: Vector2i, coord: Vector2i) -> int:
	return maxi(absi(coord.x - center.x), absi(coord.y - center.y))