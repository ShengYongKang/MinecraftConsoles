class_name CollisionBuilder
extends RefCounted

const STRATEGY_NEARBY_CONCAVE: StringName = &"nearby_concave"
const STRATEGY_DISABLED: StringName = &"disabled"

func apply(
	collision_shape: CollisionShape3D,
	mesh: Mesh,
	enabled: bool,
	strategy: StringName = STRATEGY_NEARBY_CONCAVE
) -> void:
	if collision_shape == null:
		return

	if not enabled or strategy == STRATEGY_DISABLED:
		collision_shape.shape = null
		return

	collision_shape.shape = build_shape(mesh)

func build_shape(mesh: Mesh) -> Shape3D:
	if mesh == null:
		return null

	var faces := mesh.get_faces()
	if faces.is_empty():
		return null

	var shape := ConcavePolygonShape3D.new()
	shape.data = faces
	return shape
