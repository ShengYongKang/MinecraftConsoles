class_name MeshBuilderBackend
extends RefCounted

const GDScriptMeshBuilder = preload("res://scripts/render/mesh_builder_greedy.gd")
const NATIVE_EXTENSION_PATH := "res://native/voxel_mesher/ourera_mesher.gdextension"
const NATIVE_DEBUG_DLL_PATH := "res://native/voxel_mesher/bin/windows/ourera_mesher.windows.template_debug.x86_64.dll"
const NATIVE_RELEASE_DLL_PATH := "res://native/voxel_mesher/bin/windows/ourera_mesher.windows.template_release.x86_64.dll"
const NATIVE_CLASS_NAME := &"OurEraGreedyMesherNative"

var _gd_builder = GDScriptMeshBuilder.new()
var _native_builder: RefCounted
var _native_attempted := false
var _native_available := false
var _solid_lookup := PackedByteArray()
var _tile_lookup := PackedInt32Array()

func build(context: Dictionary) -> Dictionary:
	var native_builder := _get_native_builder()
	if native_builder != null:
		var native_context := _make_native_context(context)
		var native_result: Variant = native_builder.call("build", native_context)
		if native_result is Dictionary:
			var adapted := _adapt_native_result(native_result, context)
			if not adapted.is_empty():
				return adapted
	return _gd_builder.build(context)

func has_native_backend() -> bool:
	return _get_native_builder() != null

func build_native_raw(context: Dictionary) -> Dictionary:
	var native_builder := _get_native_builder()
	if native_builder == null:
		return {}
	var native_result: Variant = native_builder.call("build", _make_native_context(context))
	return native_result if native_result is Dictionary else {}

func get_backend_name() -> String:
	return "native" if has_native_backend() else "gdscript"

func _get_native_builder() -> RefCounted:
	if _native_attempted:
		return _native_builder if _native_available else null

	_native_attempted = true
	if OS.get_environment("OURERA_DISABLE_NATIVE_MESHER") == "1":
		return null

	if not _native_binary_exists():
		return null

	var extension_resource := load(NATIVE_EXTENSION_PATH)
	if extension_resource == null:
		return null
	if not ClassDB.class_exists(NATIVE_CLASS_NAME):
		return null

	var instance: Variant = ClassDB.instantiate(StringName(NATIVE_CLASS_NAME))
	if instance is RefCounted:
		_native_builder = instance
		_native_available = true
		return _native_builder
	return null

func _native_binary_exists() -> bool:
	return FileAccess.file_exists(NATIVE_DEBUG_DLL_PATH) or FileAccess.file_exists(NATIVE_RELEASE_DLL_PATH)

func _make_native_context(context: Dictionary) -> Dictionary:
	_ensure_lookup_tables()
	return {
		"dimensions": context.get("dimensions", Vector3i.ONE),
		"chunk_blocks": context.get("chunk_blocks", PackedInt32Array()),
		"neighbor_columns": context.get("neighbor_columns", {}),
		"collect_collision_faces": bool(context.get("collect_collision_faces", false)),
		"include_vertex_colors": bool(context.get("include_vertex_colors", false)),
		"solid_lookup": _solid_lookup,
		"tile_lookup": _tile_lookup,
	}
func _ensure_lookup_tables() -> void:
	if not _solid_lookup.is_empty() and not _tile_lookup.is_empty():
		return

	var block_ids := BlockDefs.get_block_ids()
	var max_block_id := 0
	for block_id in block_ids:
		max_block_id = maxi(max_block_id, int(block_id))

	_solid_lookup.resize(max_block_id + 1)
	_tile_lookup.resize((max_block_id + 1) * 12)
	for block_id in block_ids:
		var id := int(block_id)
		_solid_lookup[id] = 1 if BlockDefs.is_solid(id) else 0
		for face_index in range(6):
			var tile := BlockDefs.tile_for_face(id, face_index)
			var base := (id * 12) + face_index * 2
			_tile_lookup[base] = tile.x
			_tile_lookup[base + 1] = tile.y

func _adapt_native_result(native_result: Dictionary, context: Dictionary) -> Dictionary:
	var mesh_variant: Variant = native_result.get("mesh", null)
	var mesh: Mesh = mesh_variant if mesh_variant is Mesh else null
	if mesh == null:
		var arrays: Variant = native_result.get("arrays", [])
		if arrays is Array and arrays.size() > Mesh.ARRAY_VERTEX:
			var vertex_array: Variant = arrays[Mesh.ARRAY_VERTEX]
			if vertex_array is PackedVector3Array and not vertex_array.is_empty():
				var mesh_arrays: Array = arrays.duplicate(false)
				if mesh_arrays.size() <= Mesh.ARRAY_INDEX:
					mesh_arrays.resize(Mesh.ARRAY_MAX)
				var index_array: Variant = mesh_arrays[Mesh.ARRAY_INDEX]
				if index_array is PackedInt32Array and index_array.is_empty():
					mesh_arrays[Mesh.ARRAY_INDEX] = null
				var array_mesh := ArrayMesh.new()
				array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_arrays)
				mesh = array_mesh
	if mesh == null:
		return {}

	var material: Material = context.get("material", null)
	if material != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, material)

	return {
		"mesh": mesh,
		"stats": native_result.get("stats", {}),
		"collision_faces": native_result.get("collision_faces", PackedVector3Array()),
	}

