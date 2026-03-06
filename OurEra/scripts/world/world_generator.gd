class_name WorldGenerator
extends RefCounted

const WorldConstants = preload("res://scripts/world/world_constants.gd")

var seed: int = 114514
var thread_count: int = 2

var _queue_mutex: Mutex = Mutex.new()
var _result_mutex: Mutex = Mutex.new()
var _semaphore: Semaphore = Semaphore.new()
var _job_queue: Array[Vector2i] = []
var _results: Array[Dictionary] = []
var _threads: Array[Thread] = []
var _shutdown: bool = false

func start_workers() -> void:
	stop_workers()
	_shutdown = false

	for _i in range(maxi(1, thread_count)):
		var thread: Thread = Thread.new()
		var err: Error = thread.start(Callable(self, "_generation_worker_loop"))
		if err != OK:
			push_warning("Failed to start world generation worker: %s" % [err])
			continue
		_threads.append(thread)

func stop_workers() -> void:
	if _threads.is_empty():
		_clear_pending_work()
		return

	_queue_mutex.lock()
	_shutdown = true
	_queue_mutex.unlock()
	for _i in range(_threads.size()):
		_semaphore.post()

	for thread in _threads:
		thread.wait_to_finish()

	_threads.clear()
	_clear_pending_work()

func queue_chunk(coord: Vector2i) -> void:
	_queue_mutex.lock()
	_job_queue.append(coord)
	_queue_mutex.unlock()
	_semaphore.post()

func consume_completed(max_count: int) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	_result_mutex.lock()
	var count: int = mini(max_count, _results.size())
	for _i in range(count):
		results.append(_results.pop_front())
	_result_mutex.unlock()
	return results

func generate_chunk(coord: Vector2i) -> PackedInt32Array:
	return _generate_chunk_blocks_with_noise(
		coord,
		_create_height_noise(seed),
		_create_detail_noise(seed)
	)

func _clear_pending_work() -> void:
	_queue_mutex.lock()
	_job_queue.clear()
	_queue_mutex.unlock()

	_result_mutex.lock()
	_results.clear()
	_result_mutex.unlock()

func _generation_worker_loop() -> void:
	var worker_height_noise: FastNoiseLite = _create_height_noise(seed)
	var worker_detail_noise: FastNoiseLite = _create_detail_noise(seed)

	while true:
		_semaphore.wait()

		var has_job: bool = false
		var coord: Vector2i = Vector2i.ZERO

		_queue_mutex.lock()
		if _shutdown:
			_queue_mutex.unlock()
			return
		if not _job_queue.is_empty():
			coord = _job_queue.pop_front()
			has_job = true
		_queue_mutex.unlock()

		if not has_job:
			continue

		var data: PackedInt32Array = _generate_chunk_blocks_with_noise(coord, worker_height_noise, worker_detail_noise)

		_result_mutex.lock()
		_results.append({
			"coord": coord,
			"data": data,
		})
		_result_mutex.unlock()

func _create_height_noise(noise_seed: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.0075
	return noise

func _create_detail_noise(noise_seed: int) -> FastNoiseLite:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = noise_seed ^ 0x6E624EB7
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.02
	return noise

func _generate_chunk_blocks_with_noise(
	coord: Vector2i,
	height_noise: FastNoiseLite,
	detail_noise: FastNoiseLite
) -> PackedInt32Array:
	var data: PackedInt32Array = PackedInt32Array()
	data.resize(WorldConstants.CHUNK_VOLUME)

	for z in range(WorldConstants.CHUNK_WIDTH):
		for x in range(WorldConstants.CHUNK_WIDTH):
			var wx: int = coord.x * WorldConstants.CHUNK_WIDTH + x
			var wz: int = coord.y * WorldConstants.CHUNK_WIDTH + z
			var height: int = _sample_height(wx, wz, height_noise, detail_noise)

			for y in range(height + 1):
				var id: int = BlockDefs.STONE
				if y == height:
					id = BlockDefs.GRASS
				elif y >= height - 3:
					id = BlockDefs.DIRT

				if y < WorldConstants.SEA_LEVEL - 6 and y % 9 == 0:
					id = BlockDefs.COBBLE

				data[WorldConstants.to_index(x, y, z)] = id

	return data

func _sample_height(
	wx: int,
	wz: int,
	height_noise: FastNoiseLite,
	detail_noise: FastNoiseLite
) -> int:
	var h0: float = height_noise.get_noise_2d(wx, wz) * 18.0
	var h1: float = detail_noise.get_noise_2d(wx, wz) * 6.0
	var h: int = int(round(WorldConstants.SEA_LEVEL + h0 + h1))
	return clampi(h, 8, WorldConstants.WORLD_HEIGHT - 2)