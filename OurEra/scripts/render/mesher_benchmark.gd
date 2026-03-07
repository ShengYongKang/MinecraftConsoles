class_name MesherBenchmark
extends RefCounted

const BackendScript = preload("res://scripts/render/mesh_builder_backend.gd")
const GDScriptBuilderScript = preload("res://scripts/render/mesh_builder_greedy.gd")

var _backend = BackendScript.new()
var _gd_builder = GDScriptBuilderScript.new()

func compare(context: Dictionary, iterations: int = 1) -> Dictionary:
	var safe_iterations := maxi(1, iterations)
	var gd_usec := _benchmark_builder(_gd_builder, context, safe_iterations)
	var native_available := _backend.has_native_backend()
	var native_usec := -1
	if native_available:
		native_usec = _benchmark_builder(_backend, context, safe_iterations)
	return {
		"iterations": safe_iterations,
		"gdscript_usec": gd_usec,
		"native_available": native_available,
		"native_usec": native_usec,
		"speedup": float(gd_usec) / float(native_usec) if native_usec > 0 else 0.0,
	}

func _benchmark_builder(builder: RefCounted, context: Dictionary, iterations: int) -> int:
	var started_usec := Time.get_ticks_usec()
	for _i in range(iterations):
		builder.call("build", context)
	return Time.get_ticks_usec() - started_usec
