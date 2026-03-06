class_name PlayerController
extends EntityBase

const PlayerContentDBScript = preload("res://scripts/content/content_db.gd")
const PlayerStateScript = preload("res://scripts/entities/player/player_state.gd")

@export var move_speed := 6.0
@export var jump_velocity := 5.2
@export var gravity := 18.0
@export var reach_distance := 7.0
@export var local_input_authority := true
@export var loadout_state_path: NodePath = NodePath("LoadoutState")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var pitch := 0.0
var _move_input := Vector2.ZERO
var _wants_jump := false
var _loadout_state: Node

func _init() -> void:
	entity_category = "player"
	entity_archetype = "player"
	entity_id = "player"

func _ready() -> void:
	_resolve_loadout_state()
	_apply_head_pitch()
	super._ready()

func get_target_origin() -> Vector3:
	if camera == null:
		return global_position
	return camera.global_position

func get_combat_anchor() -> Node3D:
	if head == null:
		return self
	return head

func build_ai_context() -> Dictionary:
	var look_direction := Vector3.ZERO
	if camera != null:
		look_direction = -camera.global_transform.basis.z
	return {
		"view_origin": get_target_origin(),
		"look_direction": look_direction,
		"selected_block": get_selected_block(),
	}

func set_local_move_input(move_input: Vector2) -> void:
	_move_input = move_input

func queue_local_jump() -> void:
	_wants_jump = true

func apply_look_delta(relative: Vector2, sensitivity: float) -> void:
	rotation.y -= relative.x * sensitivity
	pitch = clamp(
		pitch - relative.y * sensitivity,
		-PlayerStateScript.MAX_LOOK_PITCH,
		PlayerStateScript.MAX_LOOK_PITCH
	)
	_apply_head_pitch()

func request_break_targeted_block() -> void:
	if get_world_root() == null:
		return

	var hit := _raycast_block()
	if hit.is_empty():
		return

	var p: Vector3 = hit["position"] - hit["normal"] * 0.01
	var target := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	set_world_block(target, PlayerContentDBScript.AIR)

func request_place_targeted_block(block_id: int) -> void:
	if get_world_root() == null:
		return

	var selected_block := PlayerContentDBScript.sanitize_placeable_block_id(block_id)
	if not PlayerContentDBScript.can_place_block(selected_block):
		return

	var hit := _raycast_block()
	if hit.is_empty():
		return

	var p: Vector3 = hit["position"] + hit["normal"] * 0.01
	var target := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	var current_block := get_world_block(target)

	if not PlayerContentDBScript.can_replace_block(current_block):
		return
	if _player_overlaps_block(target):
		return

	set_world_block(target, selected_block)

func get_selected_block() -> int:
	var loadout_state := get_loadout_state()
	if loadout_state != null and loadout_state.has_method("get_selected_block"):
		return int(loadout_state.get_selected_block())
	return PlayerContentDBScript.get_default_selected_block_id()

func get_loadout_state() -> Node:
	if _loadout_state == null:
		_resolve_loadout_state()
	return _loadout_state

func _entity_physics(delta: float) -> void:
	var wish_dir := compute_planar_move_direction(_move_input)
	var wants_jump := _wants_jump
	_wants_jump = false
	step_character_movement(delta, wish_dir, move_speed, jump_velocity, wants_jump, gravity)

func _player_overlaps_block(cell: Vector3i) -> bool:
	var cell_min := Vector3(cell.x, cell.y, cell.z)
	var cell_max := cell_min + Vector3.ONE
	var player_half_extents := Vector3(0.3, 0.9, 0.3)
	var player_center := global_position + Vector3(0, 0.9, 0)
	var player_min := player_center - player_half_extents
	var player_max := player_center + player_half_extents

	return (
		player_min.x < cell_max.x and player_max.x > cell_min.x and
		player_min.y < cell_max.y and player_max.y > cell_min.y and
		player_min.z < cell_max.z and player_max.z > cell_min.z
	)

func _raycast_block() -> Dictionary:
	if camera == null:
		return {}

	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_transform.basis.z * reach_distance)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(params)

func _apply_head_pitch() -> void:
	if head != null:
		head.rotation.x = pitch

func _resolve_loadout_state() -> void:
	_loadout_state = get_node_or_null(loadout_state_path)

func _get_custom_persisted_state() -> Dictionary:
	var state := PlayerStateScript.new()
	state.pitch = pitch
	state.selected_block = get_selected_block()
	return state.to_dictionary()

func _apply_custom_persisted_state(state: Dictionary) -> void:
	var restored := PlayerStateScript.create_from_dictionary(state)
	pitch = restored.pitch
	var loadout_state := get_loadout_state()
	if loadout_state != null and loadout_state.has_method("set_selected_block"):
		loadout_state.set_selected_block(restored.selected_block)
	_apply_head_pitch()
