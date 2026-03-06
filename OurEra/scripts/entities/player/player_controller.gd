class_name PlayerController
extends EntityBase

const PlayerStateScript = preload("res://scripts/entities/player/player_state.gd")

@export var move_speed := 6.0
@export var jump_velocity := 5.2
@export var gravity := 18.0
@export var mouse_sensitivity := 0.0022
@export var reach_distance := 7.0
@export var capture_mouse_on_ready := true
@export var local_input_authority := true

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var selected_block: int = BlockDefs.COBBLE
var pitch := 0.0

func _init() -> void:
	entity_category = "player"
	entity_archetype = "player"
	entity_id = "player"

func _ready() -> void:
	_ensure_input_bindings()
	if capture_mouse_on_ready and local_input_authority:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_apply_head_pitch()
	super._ready()

func _unhandled_input(event: InputEvent) -> void:
	if not local_input_authority:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= event.relative.x * mouse_sensitivity
		pitch = clamp(
			pitch - event.relative.y * mouse_sensitivity,
			-PlayerStateScript.MAX_LOOK_PITCH,
			PlayerStateScript.MAX_LOOK_PITCH
		)
		_apply_head_pitch()
		return

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return

	if event.is_action_pressed("break_block"):
		_try_break_block()
	elif event.is_action_pressed("place_block"):
		_try_place_block()

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
		"selected_block": selected_block,
	}

func _entity_physics(delta: float) -> void:
	var move_input := Vector2.ZERO
	var wants_jump := false
	if local_input_authority:
		move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wants_jump = Input.is_action_just_pressed("jump")

	var wish_dir := compute_planar_move_direction(move_input)
	step_character_movement(delta, wish_dir, move_speed, jump_velocity, wants_jump, gravity)

func _try_break_block() -> void:
	if get_world_root() == null:
		return

	var hit := _raycast_block()
	if hit.is_empty():
		return

	var p: Vector3 = hit["position"] - hit["normal"] * 0.01
	var target := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	set_world_block(target, BlockDefs.AIR)

func _try_place_block() -> void:
	if get_world_root() == null:
		return

	var hit := _raycast_block()
	if hit.is_empty():
		return

	var p: Vector3 = hit["position"] + hit["normal"] * 0.01
	var target := Vector3i(floori(p.x), floori(p.y), floori(p.z))

	if get_world_block(target) != BlockDefs.AIR:
		return
	if _player_overlaps_block(target):
		return

	set_world_block(target, selected_block)

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

func _ensure_input_bindings() -> void:
	_add_key_if_missing("move_forward", KEY_W)
	_add_key_if_missing("move_back", KEY_S)
	_add_key_if_missing("move_left", KEY_A)
	_add_key_if_missing("move_right", KEY_D)
	_add_key_if_missing("jump", KEY_SPACE)
	_add_mouse_if_missing("break_block", MOUSE_BUTTON_LEFT)
	_add_mouse_if_missing("place_block", MOUSE_BUTTON_RIGHT)

func _add_key_if_missing(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if _has_key_event(action, keycode):
		return
	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action, event)

func _add_mouse_if_missing(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if _has_mouse_event(action, button):
		return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)

func _has_key_event(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.keycode == keycode:
			return true
	return false

func _has_mouse_event(action: StringName, button: MouseButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and event.button_index == button:
			return true
	return false

func _get_custom_persisted_state() -> Dictionary:
	var state := PlayerStateScript.new()
	state.pitch = pitch
	state.selected_block = selected_block
	return state.to_dictionary()

func _apply_custom_persisted_state(state: Dictionary) -> void:
	var restored := PlayerStateScript.create_from_dictionary(state)
	pitch = restored.pitch
	selected_block = restored.selected_block
	_apply_head_pitch()