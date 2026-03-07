class_name PlayerController
extends EntityBase

const PlayerStateScript = preload("res://scripts/entities/player/player_state.gd")
const ContentDBScript = preload("res://scripts/content/content_db.gd")

signal mouse_capture_changed(captured: bool)
signal selected_block_changed(block_id: int)

@export var move_speed := 6.0
@export var jump_velocity := 6.45
@export var gravity := 20.0
@export var fall_gravity_multiplier := 1.85
@export var jump_release_gravity_multiplier := 1.35
@export var mouse_sensitivity := 0.0022
@export var reach_distance := 7.0
@export var capture_mouse_on_ready := true
@export var local_input_authority := true
@export var eye_height := 1.62
@export var block_place_vertical_clearance := 0.03
@export var block_place_horizontal_inset := 0.02
@export var block_place_embed_depth := 0.08
@export var block_target_surface_bias := 0.001
@export var landing_bob_max_offset := 0.12
@export var landing_bob_recover_speed := 6.5
@export var landing_pitch_max := 0.08
@export var landing_pitch_recover_speed := 7.5

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var selected_block: int = ContentDBScript.get_default_selected_block_id()
var pitch := 0.0

var _pending_mouse_capture := false
var _recapture_on_focus := false
var _ui_overlay_active := false
var _landing_bob_offset := 0.0
var _landing_pitch_offset := 0.0

func _init() -> void:
	entity_category = "player"
	entity_archetype = "player"
	entity_id = "player"

func _ready() -> void:
	_ensure_input_bindings()
	selected_block = ContentDBScript.sanitize_placeable_block_id(selected_block)
	_pending_mouse_capture = capture_mouse_on_ready and local_input_authority
	_sync_view_height()
	_apply_head_pitch()
	super._ready()
	if _pending_mouse_capture:
		call_deferred("_capture_mouse_if_needed")

func _process(delta: float) -> void:
	_update_landing_feedback(delta)
	if not _pending_mouse_capture:
		return
	if not _window_has_focus():
		return
	_capture_mouse_if_needed()

func _input(event: InputEvent) -> void:
	if not local_input_authority:
		return
	if _ui_overlay_active:
		return

	if event is InputEventMouseButton and event.pressed and not _is_mouse_captured():
		_capture_mouse_if_needed()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _is_mouse_captured():
		rotation.y -= event.relative.x * mouse_sensitivity
		pitch = clamp(
			pitch - event.relative.y * mouse_sensitivity,
			-PlayerStateScript.MAX_LOOK_PITCH,
			PlayerStateScript.MAX_LOOK_PITCH
		)
		_apply_head_pitch()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		if _is_mouse_captured():
			_release_mouse()
		else:
			_capture_mouse_if_needed()
		get_viewport().set_input_as_handled()
		return

	if not _is_mouse_captured():
		return

	if event.is_action_pressed("break_block"):
		_try_break_block()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("place_block"):
		_try_place_block()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if not local_input_authority:
		return

	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_recapture_on_focus = _is_mouse_captured()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and _recapture_on_focus:
		_pending_mouse_capture = true
		call_deferred("_capture_mouse_if_needed")

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

func _entity_physics(delta: float) -> void:
	var move_input := Vector2.ZERO
	var wants_jump := false
	var jump_held := false
	if local_input_authority and not _ui_overlay_active:
		move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wants_jump = Input.is_action_just_pressed("jump")
		jump_held = Input.is_action_pressed("jump")

	var wish_dir := compute_planar_move_direction(move_input)
	var landing_speed := step_character_movement(
		delta,
		wish_dir,
		move_speed,
		jump_velocity,
		wants_jump,
		gravity,
		jump_held,
		fall_gravity_multiplier,
		jump_release_gravity_multiplier
	)
	if landing_speed > 0.0:
		_apply_landing_feedback(landing_speed)

func get_selected_block() -> int:
	return selected_block

func set_selected_block(block_id: int) -> void:
	var next_block: int = ContentDBScript.sanitize_placeable_block_id(block_id)
	if selected_block == next_block:
		return
	selected_block = next_block
	selected_block_changed.emit(selected_block)

func set_ui_overlay_active(active: bool) -> void:
	if _ui_overlay_active == active:
		return

	_ui_overlay_active = active
	if _ui_overlay_active:
		_release_mouse()
		return

	if local_input_authority:
		_pending_mouse_capture = true
		call_deferred("_capture_mouse_if_needed")

func is_ui_overlay_active() -> bool:
	return _ui_overlay_active

func _try_break_block() -> void:
	if get_world_root() == null:
		return

	var hit := _raycast_block()
	if hit.is_empty():
		return

	var target := _get_target_cell(hit, false)
	set_world_block(target, BlockDefs.AIR)

func _try_place_block() -> void:
	if get_world_root() == null:
		return

	var hit := _raycast_block()
	if hit.is_empty():
		return

	var target := _get_target_cell(hit, true)

	if get_world_block(target) != BlockDefs.AIR:
		return
	if _player_overlaps_block(target):
		return

	set_world_block(target, selected_block)

func _player_overlaps_block(cell: Vector3i) -> bool:
	var player_bounds := get_collision_bounds(block_place_horizontal_inset, 0.0)
	if player_bounds.size == Vector3.ZERO:
		return false

	var overlap := _aabb_intersection(player_bounds, AABB(Vector3(cell.x, cell.y, cell.z), Vector3.ONE))
	if overlap.size == Vector3.ZERO:
		return false
	if overlap.size.y <= block_place_vertical_clearance:
		return false
	return overlap.size.x > block_place_embed_depth and overlap.size.z > block_place_embed_depth

func _raycast_block() -> Dictionary:
	if camera == null:
		return {}

	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_transform.basis.z * reach_distance)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collide_with_areas = false
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(params)

func _capture_mouse_if_needed() -> void:
	if not local_input_authority:
		return
	if _ui_overlay_active:
		return
	if not _window_has_focus():
		_pending_mouse_capture = true
		return

	var was_captured := _is_mouse_captured()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_pending_mouse_capture = not _is_mouse_captured()
	if _is_mouse_captured():
		_recapture_on_focus = false
	if not was_captured and _is_mouse_captured():
		mouse_capture_changed.emit(true)

func _release_mouse() -> void:
	var was_captured := _is_mouse_captured()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_pending_mouse_capture = false
	_recapture_on_focus = false
	if was_captured:
		mouse_capture_changed.emit(false)

func _is_mouse_captured() -> bool:
	return Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED

func _window_has_focus() -> bool:
	var window := get_window()
	return window != null and window.has_focus()

func _apply_head_pitch() -> void:
	if head != null:
		head.rotation.x = pitch + _landing_pitch_offset

func _sync_view_height() -> void:
	if head == null:
		return
	head.position.y = eye_height + _landing_bob_offset

func _ensure_input_bindings() -> void:
	_add_key_if_missing("move_forward", KEY_W)
	_add_key_if_missing("move_back", KEY_S)
	_add_key_if_missing("move_left", KEY_A)
	_add_key_if_missing("move_right", KEY_D)
	_add_key_if_missing("jump", KEY_SPACE)
	_add_key_if_missing("ui_cancel", KEY_ESCAPE)
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

func _get_target_cell(hit: Dictionary, place_block: bool) -> Vector3i:
	var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
	var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var bias := block_target_surface_bias if place_block else -block_target_surface_bias
	var sample := hit_position + hit_normal * bias
	return Vector3i(floori(sample.x), floori(sample.y), floori(sample.z))

func _aabb_intersection(first: AABB, second: AABB) -> AABB:
	var position := Vector3(
		maxf(first.position.x, second.position.x),
		maxf(first.position.y, second.position.y),
		maxf(first.position.z, second.position.z)
	)
	var end := Vector3(
		minf(first.end.x, second.end.x),
		minf(first.end.y, second.end.y),
		minf(first.end.z, second.end.z)
	)
	if end.x <= position.x or end.y <= position.y or end.z <= position.z:
		return AABB(position, Vector3.ZERO)
	return AABB(position, end - position)

func _apply_landing_feedback(landing_speed: float) -> void:
	var landing_ratio := clampf((landing_speed - 4.0) / 8.0, 0.0, 1.0)
	if landing_ratio <= 0.0:
		return
	_landing_bob_offset = minf(_landing_bob_offset, -landing_bob_max_offset * landing_ratio)
	_landing_pitch_offset = minf(_landing_pitch_offset, -landing_pitch_max * landing_ratio)
	_sync_view_height()
	_apply_head_pitch()

func _update_landing_feedback(delta: float) -> void:
	var bob_changed := not is_zero_approx(_landing_bob_offset)
	var pitch_changed := not is_zero_approx(_landing_pitch_offset)
	if not bob_changed and not pitch_changed:
		return
	_landing_bob_offset = move_toward(_landing_bob_offset, 0.0, landing_bob_recover_speed * delta)
	_landing_pitch_offset = move_toward(_landing_pitch_offset, 0.0, landing_pitch_recover_speed * delta)
	if bob_changed:
		_sync_view_height()
	if pitch_changed:
		_apply_head_pitch()

func _get_custom_persisted_state() -> Dictionary:
	var state := PlayerStateScript.new()
	state.pitch = pitch
	state.selected_block = selected_block
	return state.to_dictionary()

func _apply_custom_persisted_state(state: Dictionary) -> void:
	var restored := PlayerStateScript.create_from_dictionary(state)
	pitch = restored.pitch
	set_selected_block(restored.selected_block)
	_apply_head_pitch()

