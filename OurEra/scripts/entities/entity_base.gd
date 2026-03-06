class_name EntityBase
extends CharacterBody3D

const ContentDBScript = preload("res://scripts/content/content_db.gd")

signal entity_registered(entity: EntityBase)
signal entity_unregistered(entity: EntityBase)
signal despawn_requested(entity: EntityBase, reason: String)

@export var entity_system_path: NodePath = NodePath("..")
@export var entity_category: String = "entity"
@export var entity_archetype: String = "entity"
@export var entity_id: String = ""
@export var simulation_enabled := true
@export var auto_register_with_system := true
@export var gravity_acceleration := 18.0
@export var terminal_fall_speed := 54.0

var entity_system: Node
var world: Node

var _is_registered := false
var _despawn_queued := false

func _ready() -> void:
	if auto_register_with_system:
		_register_with_entity_system()
		if not _is_registered:
			call_deferred("_register_with_entity_system")

func _exit_tree() -> void:
	_unregister_from_entity_system()

func bind_entity_system(system: Node) -> void:
	entity_system = system

func bind_world(world_root: Node) -> void:
	world = world_root

func on_registered() -> void:
	_is_registered = true
	_despawn_queued = false
	_on_registered()
	entity_registered.emit(self)

func on_unregistered() -> void:
	if not _is_registered:
		return
	_is_registered = false
	_on_unregistered()
	entity_unregistered.emit(self)

func entity_physics_tick(delta: float) -> void:
	if not simulation_enabled:
		return
	if world == null and entity_system != null and entity_system.has_method("get_world"):
		world = entity_system.get_world()
	_entity_pre_physics(delta)
	_entity_physics(delta)
	_entity_post_physics(delta)

func get_entity_id() -> String:
	return entity_id

func set_entity_id(value: String) -> void:
	entity_id = value.strip_edges()

func can_persist() -> bool:
	return true

func get_simulation_priority() -> int:
	return 100

func get_world_root() -> Node:
	return world

func get_target_origin() -> Vector3:
	return global_position

func get_combat_anchor() -> Node3D:
	return self

func build_ai_context() -> Dictionary:
	return {}

func handle_damage(_amount: float, _source: EntityBase = null, _context: Dictionary = {}) -> void:
	pass

func request_despawn(reason: String = "") -> void:
	if _despawn_queued:
		return
	_despawn_queued = true
	despawn_requested.emit(self, reason)
	if entity_system != null and entity_system.has_method("request_despawn"):
		entity_system.request_despawn(self, reason)
	else:
		queue_free()

func compute_planar_move_direction(move_input: Vector2) -> Vector3:
	return compute_planar_move_direction_from_basis(move_input, global_transform.basis)

func compute_planar_move_direction_from_basis(move_input: Vector2, basis: Basis) -> Vector3:
	var forward: Vector3 = -basis.z
	var right: Vector3 = basis.x
	var wish_dir: Vector3 = right * move_input.x + forward * move_input.y
	wish_dir.y = 0.0
	return wish_dir.normalized()

func step_character_movement(
	delta: float,
	wish_dir: Vector3,
	move_speed: float,
	jump_speed: float,
	wants_jump: bool,
	gravity_value: float = gravity_acceleration
) -> void:
	var planar_dir: Vector3 = wish_dir
	planar_dir.y = 0.0
	planar_dir = planar_dir.normalized()

	velocity.x = planar_dir.x * move_speed
	velocity.z = planar_dir.z * move_speed

	if not is_on_floor():
		velocity.y = maxf(velocity.y - gravity_value * delta, -terminal_fall_speed)
	elif wants_jump:
		velocity.y = jump_speed

	move_and_slide()

func get_world_block(pos: Vector3i) -> int:
	if world == null or not world.has_method("get_block_global"):
		return ContentDBScript.AIR
	return world.get_block_global(pos)

func set_world_block(pos: Vector3i, block_id: int) -> void:
	if world == null or not world.has_method("set_block_global"):
		return
	world.set_block_global(pos, block_id)

func get_persisted_state() -> Dictionary:
	var state: Dictionary = {
		"position": global_position if is_inside_tree() else position,
		"yaw": rotation.y,
		"velocity": velocity,
		"entity_id": entity_id,
		"entity_category": entity_category,
		"entity_archetype": entity_archetype,
	}
	state.merge(_get_custom_persisted_state(), true)
	return state

func get_entity_snapshot() -> Dictionary:
	return get_persisted_state().duplicate(true)

func apply_persisted_state(state: Dictionary) -> void:
	var saved_position: Variant = state.get("position", null)
	if saved_position is Vector3:
		global_position = saved_position

	rotation.y = float(state.get("yaw", rotation.y))

	var saved_velocity: Variant = state.get("velocity", null)
	if saved_velocity is Vector3:
		velocity = saved_velocity
	else:
		velocity = Vector3.ZERO

	var saved_entity_id := String(state.get("entity_id", entity_id)).strip_edges()
	if not saved_entity_id.is_empty():
		entity_id = saved_entity_id

	var saved_category := String(state.get("entity_category", entity_category)).strip_edges()
	if not saved_category.is_empty():
		entity_category = saved_category

	var saved_archetype := String(state.get("entity_archetype", entity_archetype)).strip_edges()
	if not saved_archetype.is_empty():
		entity_archetype = saved_archetype

	_apply_custom_persisted_state(state)

func _register_with_entity_system() -> void:
	if _is_registered:
		return
	var system := _resolve_entity_system()
	if system == null:
		return
	system.register_entity(self)

func _unregister_from_entity_system() -> void:
	if entity_system == null:
		return
	if not is_instance_valid(entity_system):
		return
	if not entity_system.has_method("unregister_entity"):
		return
	entity_system.unregister_entity(self)

func _resolve_entity_system() -> Node:
	if entity_system != null and is_instance_valid(entity_system):
		return entity_system

	if not entity_system_path.is_empty():
		var direct_system: Node = get_node_or_null(entity_system_path)
		if direct_system != null and direct_system.has_method("register_entity"):
			return direct_system

	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method("register_entity"):
			return cursor
		cursor = cursor.get_parent()

	return null

func _entity_pre_physics(_delta: float) -> void:
	pass

func _entity_physics(_delta: float) -> void:
	pass

func _entity_post_physics(_delta: float) -> void:
	pass

func _on_registered() -> void:
	pass

func _on_unregistered() -> void:
	pass

func _get_custom_persisted_state() -> Dictionary:
	return {}

func _apply_custom_persisted_state(_state: Dictionary) -> void:
	pass
