class_name CollisionBuilder
extends RefCounted

const STRATEGY_NEARBY_CONCAVE: StringName = &"nearby_concave"
const STRATEGY_DISABLED: StringName = &"disabled"

func apply(
	collision_shape: CollisionShape3D,
	mesh: Mesh,
	enabled: bool,
	strategy: StringName = STRATEGY_NEARBY_CONCAVE,
	faces: PackedVector3Array = PackedVector3Array()
) -> void:
	if collision_shape == null:
		return

	if not enabled or strategy == STRATEGY_DISABLED:
		collision_shape.disabled = true
		if faces.is_empty():
			collision_shape.shape = null
		return

	var shape := build_shape_from_faces(faces)
	if shape == null:
		shape = build_shape(mesh)

	collision_shape.shape = shape
	collision_shape.disabled = shape == null

func build_shape(mesh: Mesh) -> Shape3D:
	if mesh == null:
		return null
	return build_shape_from_faces(mesh.get_faces())

func build_shape_from_faces(faces: PackedVector3Array) -> Shape3D:
	if faces.is_empty():
		return null

	var shape := ConcavePolygonShape3D.new()
	shape.data = faces
	return shape
