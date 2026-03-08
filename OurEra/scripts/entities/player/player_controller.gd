class_name PlayerController
extends EntityBase

const PlayerStateScript = preload("res://scripts/entities/player/player_state.gd")
const ContentDBScript = preload("res://scripts/content/content_db.gd")
const DropEntityScene = preload("res://scenes/entities/drops/drop_entity.tscn")

signal mouse_capture_changed(captured: bool)
signal selected_block_changed(block_id: int)
signal selected_hotbar_changed(slot_index: int)
signal inventory_changed
signal drop_item_collected(result: Dictionary)
signal ui_feedback_emitted(feedback: Dictionary)

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
@export var block_target_cell_sample_depth := 0.03
@export var block_place_airborne_feet_overlap_tolerance := 0.2
@export var landing_bob_max_offset := 0.12
@export var landing_bob_recover_speed := 6.5
@export var landing_pitch_max := 0.08
@export var landing_pitch_recover_speed := 7.5
@export_range(1, 9, 1) var hotbar_size := 9
@export_range(1, 6, 1) var inventory_rows := 3
@export_range(3, 9, 1) var inventory_columns := 9

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var selected_block: int = ContentDBScript.get_default_selected_block_id()
var pitch := 0.0

var _pending_mouse_capture := false
var _recapture_on_focus := false
var _ui_overlay_active := false
var _landing_bob_offset := 0.0
var _landing_pitch_offset := 0.0
var _selected_hotbar_index := 0
var _hotbar_slots: Array[Dictionary] = []
var _inventory_slots: Array[Dictionary] = []

func _init() -> void:
	entity_category = "player"
	entity_archetype = "player"
	entity_id = "player"

func _ready() -> void:
	_ensure_input_bindings()
	_ensure_inventory_initialized()
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
		"selected_hotbar_index": get_selected_hotbar_index(),
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

func _entity_post_physics(_delta: float) -> void:
	_attempt_pickup_nearby_drops()

func get_selected_block() -> int:
	var active_block_id := _get_selected_placeable_block_id()
	if active_block_id > 0:
		return active_block_id
	return selected_block

func set_selected_block(block_id: int) -> void:
	var next_block: int = ContentDBScript.sanitize_placeable_block_id(block_id)
	var hotbar_index := _find_hotbar_index_for_block(next_block)
	if hotbar_index != -1 and hotbar_index != _selected_hotbar_index:
		_selected_hotbar_index = hotbar_index
		selected_hotbar_changed.emit(_selected_hotbar_index)
	_sync_selected_block_from_hotbar()
	if hotbar_index == -1:
		_set_selected_block_cache(next_block)

func get_selected_hotbar_index() -> int:
	return _selected_hotbar_index

func select_hotbar_index(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _hotbar_slots.size():
		return
	if _selected_hotbar_index == slot_index:
		_sync_selected_block_from_hotbar()
		return
	_selected_hotbar_index = slot_index
	selected_hotbar_changed.emit(_selected_hotbar_index)
	_sync_selected_block_from_hotbar()

func get_hotbar_slots() -> Array[Dictionary]:
	return _clone_slots(_hotbar_slots)

func get_inventory_slots() -> Array[Dictionary]:
	return _clone_slots(_inventory_slots)

func can_collect_drop_item(item_id: int, count: int = 1) -> bool:
	if not world_allows_drop_pickup():
		return false
	if item_id <= 0 or count <= 0:
		return false
	return _get_inventory_capacity_for_item(item_id) >= count

func collect_drop_item(item_id: int, count: int) -> int:
	if not can_collect_drop_item(item_id, 1):
		return 0

	var remaining := count
	remaining = _fill_selected_hotbar_slot(item_id, remaining)
	remaining = _fill_existing_item_stacks(_hotbar_slots, item_id, remaining, _selected_hotbar_index)
	remaining = _fill_empty_item_stacks(_hotbar_slots, &"hotbar", item_id, remaining, _selected_hotbar_index)
	remaining = _fill_existing_item_stacks(_inventory_slots, item_id, remaining)
	remaining = _fill_empty_item_stacks(_inventory_slots, &"inventory", item_id, remaining)

	var accepted := count - remaining
	if accepted > 0:
		var payload := {
			"item_id": item_id,
			"count": accepted,
			"total_count": _get_total_item_count(item_id),
		}
		_emit_inventory_changed()
		drop_item_collected.emit(payload.duplicate(true))
		var display := ContentDBScript.get_item_display_data(item_id)
		_emit_ui_feedback(
			&"pickup",
			"Picked up %s x%d" % [String(display.get("name", "Item")), accepted],
			payload
		)
	return accepted

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
	var broken_block := get_world_block(target)
	if broken_block == BlockDefs.AIR:
		return

	set_world_block(target, BlockDefs.AIR)
	if world_allows_block_drops():
		_spawn_block_drops(target, broken_block)

func _try_place_block() -> void:
	if get_world_root() == null:
		return

	var hit := _raycast_block()
	if hit.is_empty():
		return

	var target := _get_target_cell(hit, true)
	var existing_block := get_world_block(target)
	if not ContentDBScript.can_replace_block(existing_block):
		_emit_ui_feedback(&"place_failed", "Can't place into an occupied block.")
		return
	if _player_overlaps_block(target):
		_emit_ui_feedback(&"place_failed", "Can't place inside the player.")
		return
	var place_block_id := _get_selected_placeable_block_id()
	var place_item_id := _get_selected_hotbar_item_id()
	if place_block_id <= 0:
		_emit_ui_feedback(&"place_failed", "No placeable block selected.")
		return
	if world_requires_inventory_for_placement() and not _has_selected_block_inventory():
		var display := ContentDBScript.get_item_display_data(place_item_id)
		_emit_ui_feedback(
			&"place_failed",
			"No %s left in inventory." % String(display.get("name", "selected block")),
			{
				"item_id": place_item_id,
				"block_id": place_block_id,
			}
		)
		return

	set_world_block(target, place_block_id)
	if world_does_placement_consume_inventory():
		_consume_selected_block_inventory(1)

func _player_overlaps_block(cell: Vector3i) -> bool:
	var player_bounds := get_collision_bounds(block_place_horizontal_inset, 0.0)
	if player_bounds.size == Vector3.ZERO:
		return false

	var overlap := _aabb_intersection(player_bounds, AABB(Vector3(cell.x, cell.y, cell.z), Vector3.ONE))
	if overlap.size == Vector3.ZERO:
		return false
	if overlap.size.x <= block_place_embed_depth or overlap.size.z <= block_place_embed_depth:
		return false
	if overlap.size.y <= block_place_vertical_clearance:
		return false
	var block_top := float(cell.y + 1)
	var player_bottom := player_bounds.position.y
	if not is_on_floor() and block_top <= player_bottom + block_place_airborne_feet_overlap_tolerance:
		return false
	return true

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
	var sample_depth := maxf(block_target_surface_bias, block_target_cell_sample_depth)
	var hit_sample := hit_position - hit_normal * sample_depth
	var hit_cell := Vector3i(floori(hit_sample.x), floori(hit_sample.y), floori(hit_sample.z))
	if not place_block:
		return hit_cell
	return hit_cell + _normal_to_cell_offset(hit_normal)

func _normal_to_cell_offset(normal: Vector3) -> Vector3i:
	var axis := normal.abs().max_axis_index()
	match axis:
		Vector3.AXIS_X:
			return Vector3i(signi(normal.x), 0, 0)
		Vector3.AXIS_Y:
			return Vector3i(0, signi(normal.y), 0)
		_:
			return Vector3i(0, 0, signi(normal.z))

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

func _ensure_inventory_initialized() -> void:
	if _hotbar_slots.size() != hotbar_size:
		_hotbar_slots = _build_default_hotbar_slots()
	if _inventory_slots.size() != inventory_rows * inventory_columns:
		_inventory_slots = _build_default_inventory_slots()
	_selected_hotbar_index = clampi(_selected_hotbar_index, 0, maxi(_hotbar_slots.size() - 1, 0))
	_sync_selected_block_from_hotbar(true)
	_emit_inventory_changed()

func _build_default_hotbar_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for slot_index in range(hotbar_size):
		slots.append(_build_empty_slot(slot_index, &"hotbar"))
	return slots

func _build_default_inventory_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var inventory_size := inventory_rows * inventory_columns
	for slot_index in range(inventory_size):
		slots.append(_build_empty_slot(slot_index, &"inventory"))
	return slots
func _build_slot_from_block(block_id: int, count: int, slot_index: int, section: StringName) -> Dictionary:
	var item_id := ContentDBScript.get_item_id_for_block(block_id)
	return _build_slot_from_item(item_id, count, slot_index, section)

func _build_slot_from_item(item_id: int, count: int, slot_index: int, section: StringName) -> Dictionary:
	var item_def := ContentDBScript.get_item_def(item_id)
	var display := ContentDBScript.get_item_display_data(item_id)
	var block_id := int(item_def.get("placeable_block_id", 0))
	return {
		"slot_index": slot_index,
		"section": section,
		"item_id": item_id,
		"block_id": block_id,
		"display_name": String(display.get("name", "Item")),
		"short_name": String(display.get("short_name", display.get("name", "Item"))),
		"count": maxi(1, count),
		"icon_tile": ContentDBScript.get_item_icon_tile(item_id),
		"is_empty": false,
		"is_placeholder": false,
	}

func _build_empty_slot(slot_index: int, section: StringName) -> Dictionary:
	return {
		"slot_index": slot_index,
		"section": section,
		"item_id": 0,
		"block_id": 0,
		"display_name": "Empty",
		"short_name": "Empty",
		"count": 0,
		"icon_tile": Vector2i.ZERO,
		"is_empty": true,
		"is_placeholder": false,
	}

func _clone_slots(slots: Array[Dictionary]) -> Array[Dictionary]:
	var clone: Array[Dictionary] = []
	for slot in slots:
		clone.append(slot.duplicate(true))
	return clone

func _get_selected_hotbar_slot() -> Dictionary:
	if _selected_hotbar_index < 0 or _selected_hotbar_index >= _hotbar_slots.size():
		return {}
	return _hotbar_slots[_selected_hotbar_index]

func _get_selected_hotbar_item_id() -> int:
	var slot := _get_selected_hotbar_slot()
	if slot.is_empty() or bool(slot.get("is_empty", true)):
		return 0
	return int(slot.get("item_id", 0))

func _get_selected_placeable_block_id() -> int:
	var slot := _get_selected_hotbar_slot()
	if slot.is_empty() or bool(slot.get("is_empty", true)):
		return 0
	return int(slot.get("block_id", 0))

func _set_selected_block_cache(block_id: int) -> void:
	if selected_block == block_id:
		return
	selected_block = block_id
	selected_block_changed.emit(selected_block)

func _sync_selected_block_from_hotbar(force_emit: bool = false) -> void:
	if _selected_hotbar_index < 0 or _selected_hotbar_index >= _hotbar_slots.size():
		return
	if force_emit:
		selected_hotbar_changed.emit(_selected_hotbar_index)
	_set_selected_block_cache(_get_selected_placeable_block_id())

func _find_hotbar_index_for_block(block_id: int) -> int:
	for slot_index in range(_hotbar_slots.size()):
		var slot := _hotbar_slots[slot_index]
		if bool(slot.get("is_empty", true)):
			continue
		if int(slot.get("block_id", 0)) == block_id:
			return slot_index
	return -1

func _get_inventory_capacity_for_item(item_id: int) -> int:
	var max_stack := _get_item_max_stack(item_id)
	if max_stack <= 0:
		return 0
	var capacity := 0
	for slot in _hotbar_slots:
		capacity += _get_slot_capacity(slot, item_id, max_stack)
	for slot in _inventory_slots:
		capacity += _get_slot_capacity(slot, item_id, max_stack)
	return capacity

func _get_slot_capacity(slot: Dictionary, item_id: int, max_stack: int) -> int:
	if bool(slot.get("is_empty", true)):
		return max_stack
	if int(slot.get("item_id", 0)) != item_id:
		return 0
	return maxi(0, max_stack - int(slot.get("count", 0)))

func _get_item_max_stack(item_id: int) -> int:
	var item_def := ContentDBScript.get_item_def(item_id)
	return maxi(0, int(item_def.get("max_stack", 0)))

func _fill_selected_hotbar_slot(item_id: int, remaining: int) -> int:
	if remaining <= 0:
		return 0
	if _selected_hotbar_index < 0 or _selected_hotbar_index >= _hotbar_slots.size():
		return remaining
	var slot := _hotbar_slots[_selected_hotbar_index]
	var max_stack := _get_item_max_stack(item_id)
	if bool(slot.get("is_empty", true)):
		var stack_count := mini(max_stack, remaining)
		_hotbar_slots[_selected_hotbar_index] = _build_slot_from_item(item_id, stack_count, _selected_hotbar_index, &"hotbar")
		return remaining - stack_count
	if int(slot.get("item_id", 0)) != item_id:
		return remaining
	var current_count := int(slot.get("count", 0))
	var add_amount := mini(max_stack - current_count, remaining)
	if add_amount <= 0:
		return remaining
	slot["count"] = current_count + add_amount
	_hotbar_slots[_selected_hotbar_index] = slot
	return remaining - add_amount

func _fill_existing_item_stacks(slots: Array[Dictionary], item_id: int, remaining: int, skip_slot_index: int = -1) -> int:
	if remaining <= 0:
		return 0
	var max_stack := _get_item_max_stack(item_id)
	for slot_index in range(slots.size()):
		if remaining <= 0:
			break
		if slot_index == skip_slot_index:
			continue
		var slot := slots[slot_index]
		if bool(slot.get("is_empty", true)):
			continue
		if int(slot.get("item_id", 0)) != item_id:
			continue
		var current_count := int(slot.get("count", 0))
		var add_amount := mini(max_stack - current_count, remaining)
		if add_amount <= 0:
			continue
		slot["count"] = current_count + add_amount
		slots[slot_index] = slot
		remaining -= add_amount
	return remaining

func _fill_empty_item_stacks(slots: Array[Dictionary], section: StringName, item_id: int, remaining: int, skip_slot_index: int = -1) -> int:
	if remaining <= 0:
		return 0
	var max_stack := _get_item_max_stack(item_id)
	for slot_index in range(slots.size()):
		if remaining <= 0:
			break
		if slot_index == skip_slot_index:
			continue
		var slot := slots[slot_index]
		if not bool(slot.get("is_empty", true)):
			continue
		var stack_count := mini(max_stack, remaining)
		slots[slot_index] = _build_slot_from_item(item_id, stack_count, slot_index, section)
		remaining -= stack_count
	return remaining

func _has_selected_block_inventory() -> bool:
	var item_id := _get_selected_hotbar_item_id()
	if item_id <= 0:
		return false
	return _get_total_item_count(item_id) > 0

func _consume_selected_block_inventory(amount: int) -> bool:
	var item_id := _get_selected_hotbar_item_id()
	if item_id <= 0:
		return false
	if _get_total_item_count(item_id) < amount:
		return false

	var remaining := amount
	remaining = _remove_selected_hotbar_item(item_id, remaining)
	remaining = _remove_item_from_slots(_hotbar_slots, &"hotbar", item_id, remaining, _selected_hotbar_index)
	remaining = _remove_item_from_slots(_inventory_slots, &"inventory", item_id, remaining)
	_emit_inventory_changed()
	return remaining == 0

func _get_total_item_count(item_id: int) -> int:
	var total := 0
	for slot in _hotbar_slots:
		if int(slot.get("item_id", 0)) == item_id:
			total += int(slot.get("count", 0))
	for slot in _inventory_slots:
		if int(slot.get("item_id", 0)) == item_id:
			total += int(slot.get("count", 0))
	return total

func _remove_selected_hotbar_item(item_id: int, remaining: int) -> int:
	if remaining <= 0:
		return 0
	if _selected_hotbar_index < 0 or _selected_hotbar_index >= _hotbar_slots.size():
		return remaining
	var slot := _hotbar_slots[_selected_hotbar_index]
	if bool(slot.get("is_empty", true)):
		return remaining
	if int(slot.get("item_id", 0)) != item_id:
		return remaining
	var current_count := int(slot.get("count", 0))
	var consume_amount := mini(current_count, remaining)
	current_count -= consume_amount
	remaining -= consume_amount
	if current_count <= 0:
		_hotbar_slots[_selected_hotbar_index] = _build_empty_slot(_selected_hotbar_index, &"hotbar")
	else:
		slot["count"] = current_count
		_hotbar_slots[_selected_hotbar_index] = slot
	return remaining

func _remove_item_from_slots(slots: Array[Dictionary], section: StringName, item_id: int, remaining: int, skip_slot_index: int = -1) -> int:
	for slot_index in range(slots.size()):
		if remaining <= 0:
			break
		if slot_index == skip_slot_index:
			continue
		var slot := slots[slot_index]
		if bool(slot.get("is_empty", true)):
			continue
		if int(slot.get("item_id", 0)) != item_id:
			continue
		var current_count := int(slot.get("count", 0))
		var consume_amount := mini(current_count, remaining)
		current_count -= consume_amount
		remaining -= consume_amount
		if current_count <= 0:
			slots[slot_index] = _build_empty_slot(slot_index, section)
		else:
			slot["count"] = current_count
			slots[slot_index] = slot
	return remaining

func _emit_inventory_changed() -> void:
	_sync_selected_block_from_hotbar()
	inventory_changed.emit()

func _emit_ui_feedback(kind: StringName, message: String, data: Dictionary = {}) -> void:
	var payload := data.duplicate(true)
	payload["kind"] = kind
	payload["message"] = message
	ui_feedback_emitted.emit(payload)

func _spawn_block_drops(cell: Vector3i, block_id: int) -> void:
	var drops := ContentDBScript.get_block_drops(block_id, {
		"game_mode": get_world_game_mode_id(),
	})
	if drops.is_empty():
		return

	var drop_origin := Vector3(cell.x + 0.5, cell.y + 0.5, cell.z + 0.5)
	for drop_any in drops:
		if not (drop_any is Dictionary):
			continue
		var drop: Dictionary = drop_any
		var item_id := int(drop.get("item_id", 0))
		var count := maxi(0, int(drop.get("count", 0)))
		if item_id <= 0 or count <= 0:
			continue
		_spawn_item_drop(item_id, count, drop_origin)

func _spawn_item_drop(item_id: int, count: int, origin: Vector3) -> void:
	if entity_system == null or not entity_system.has_method("spawn_entity"):
		return
	var launch_velocity := Vector3(
		randf_range(-0.8, 0.8),
		randf_range(2.2, 3.2),
		randf_range(-0.8, 0.8)
	)
	entity_system.spawn_entity(DropEntityScene, {
		"position": origin + Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1)),
		"velocity": launch_velocity,
		"item_id": item_id,
		"stack_size": count,
	}, entity_system)

func _attempt_pickup_nearby_drops() -> void:
	if not world_allows_drop_pickup():
		return
	if entity_system == null or not entity_system.has_method("get_entities_in_category"):
		return
	for entity_any in entity_system.get_entities_in_category("drop"):
		if not is_instance_valid(entity_any):
			continue
		if not entity_any.has_method("can_be_picked_up_by") or not entity_any.has_method("collect_into"):
			continue
		var pickup_radius := float(entity_any.get("pickup_radius"))
		if global_position.distance_squared_to(entity_any.global_position) > pickup_radius * pickup_radius:
			continue
		if entity_any.can_be_picked_up_by(self):
			entity_any.collect_into(self)

func _get_custom_persisted_state() -> Dictionary:
	var state := PlayerStateScript.new()
	state.pitch = pitch
	state.selected_block = selected_block
	state.selected_hotbar_index = _selected_hotbar_index
	state.hotbar_slots = _clone_slots(_hotbar_slots)
	state.inventory_slots = _clone_slots(_inventory_slots)
	return state.to_dictionary()

func _apply_custom_persisted_state(state: Dictionary) -> void:
	var restored := PlayerStateScript.create_from_dictionary(state)
	pitch = restored.pitch
	_selected_hotbar_index = restored.selected_hotbar_index
	_hotbar_slots = _restore_slot_array(restored.hotbar_slots, hotbar_size, &"hotbar")
	_inventory_slots = _restore_slot_array(restored.inventory_slots, inventory_rows * inventory_columns, &"inventory")
	if _hotbar_slots.is_empty():
		_hotbar_slots = _build_default_hotbar_slots()
	if _inventory_slots.is_empty():
		_inventory_slots = _build_default_inventory_slots()
	selected_block = ContentDBScript.sanitize_placeable_block_id(restored.selected_block)
	_emit_inventory_changed()
	_apply_head_pitch()

func _restore_slot_array(serialized_slots: Array[Dictionary], slot_count: int, section: StringName) -> Array[Dictionary]:
	var restored: Array[Dictionary] = []
	for slot_index in range(slot_count):
		if slot_index >= serialized_slots.size():
			restored.append(_build_empty_slot(slot_index, section))
			continue
		var slot: Dictionary = serialized_slots[slot_index]
		var item_id := int(slot.get("item_id", 0))
		var count := maxi(0, int(slot.get("count", 0)))
		if item_id <= 0 or count <= 0:
			restored.append(_build_empty_slot(slot_index, section))
			continue
		restored.append(_build_slot_from_item(item_id, count, slot_index, section))
	return restored









