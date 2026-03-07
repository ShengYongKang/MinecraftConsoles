class_name GameUIBridge
extends Node

const ContentDBScript = preload("res://scripts/content/content_db.gd")
const InputActionFormatterScript = preload("res://scripts/ui/input/input_action_formatter.gd")

signal ui_state_changed(state: Dictionary)

const TOGGLE_INVENTORY_ACTION := &"toggle_inventory"
const HOTBAR_ACTION_PREFIX := "hotbar_slot_"

@export var player_path: NodePath
@export_range(1, 9, 1) var hotbar_size := 9
@export_range(1, 6, 1) var inventory_rows := 3
@export_range(3, 9, 1) var inventory_columns := 9

var _player: PlayerController
var _inventory_open := false
var _menu_open := false
var _selected_hotbar_index := 0
var _hotbar_slots: Array[Dictionary] = []
var _inventory_slots: Array[Dictionary] = []
var _feedback_message := ""
var _feedback_time_left := 0.0

func _ready() -> void:
	_ensure_input_actions()
	_build_placeholder_data()
	_resolve_player_ref()
	set_process(true)
	_set_feedback("UI prototype online", 1.5)
	_refresh_selection_from_player()
	_sync_overlay_state()

func _process(delta: float) -> void:
	if _player == null:
		_resolve_player_ref()

	if _feedback_time_left <= 0.0:
		return

	_feedback_time_left = maxf(_feedback_time_left - delta, 0.0)
	if is_zero_approx(_feedback_time_left) and not _feedback_message.is_empty():
		_feedback_message = ""
		_emit_ui_state()

func get_ui_state() -> Dictionary:
	return {
		"inventory_open": _inventory_open,
		"menu_open": _menu_open,
		"selected_hotbar_index": _selected_hotbar_index,
		"hotbar_slots": _clone_slots(_hotbar_slots),
		"inventory_slots": _clone_slots(_inventory_slots),
		"selected_slot": _get_selected_slot(),
		"feedback_message": _feedback_message,
		"controls": _build_controls_data(),
	}

func handle_unhandled_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.echo:
		return false

	if event.is_action_pressed(TOGGLE_INVENTORY_ACTION):
		if _menu_open:
			request_open_inventory()
		else:
			request_toggle_inventory()
		return true

	if (_inventory_open or _menu_open) and event.is_action_pressed("ui_cancel"):
		request_close_all_overlays()
		return true

	if _inventory_open or _menu_open:
		return false

	var hotbar_index := _hotbar_action_index_from_event(event)
	if hotbar_index != -1:
		request_select_hotbar_index(hotbar_index)
		return true

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_hotbar(-1)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_hotbar(1)
			return true

	return false

func request_open_inventory() -> void:
	_inventory_open = true
	_menu_open = false
	_set_feedback("Prototype backpack open", 1.1)
	_sync_overlay_state()

func request_toggle_inventory() -> void:
	if _inventory_open:
		request_close_inventory()
		return
	request_open_inventory()

func request_close_inventory() -> void:
	if not _inventory_open:
		return
	_inventory_open = false
	_set_feedback("Backpack closed", 0.8)
	_sync_overlay_state()

func request_toggle_menu() -> void:
	_menu_open = not _menu_open
	if _menu_open:
		_inventory_open = false
		_set_feedback("Menu open", 0.8)
	else:
		_set_feedback("Menu closed", 0.8)
	_sync_overlay_state()

func request_close_all_overlays() -> void:
	var had_overlay := _inventory_open or _menu_open
	_inventory_open = false
	_menu_open = false
	if had_overlay:
		_set_feedback("Gameplay resumed", 0.8)
	_sync_overlay_state()

func request_select_hotbar_index(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _hotbar_slots.size():
		return

	_selected_hotbar_index = slot_index
	var slot := _hotbar_slots[slot_index]
	if bool(slot.get("is_empty", true)):
		_set_feedback("Quick slot %d is empty" % (slot_index + 1), 0.9)
		_emit_ui_state()
		return

	_apply_selection_to_player()
	_set_feedback("Selected %s" % String(slot.get("display_name", "Item")), 0.9)
	_emit_ui_state()

func _resolve_player_ref() -> void:
	var node := get_node_or_null(player_path)
	if node == _player:
		return

	_disconnect_player()
	_player = node as PlayerController
	if _player == null:
		_emit_ui_state()
		return

	var selected_callable := Callable(self, "_on_player_selected_block_changed")
	if not _player.selected_block_changed.is_connected(selected_callable):
		_player.selected_block_changed.connect(selected_callable)

	var capture_callable := Callable(self, "_on_player_mouse_capture_changed")
	if not _player.mouse_capture_changed.is_connected(capture_callable):
		_player.mouse_capture_changed.connect(capture_callable)

	_refresh_selection_from_player()
	_sync_overlay_state()

func _disconnect_player() -> void:
	if _player == null:
		return

	var selected_callable := Callable(self, "_on_player_selected_block_changed")
	if _player.selected_block_changed.is_connected(selected_callable):
		_player.selected_block_changed.disconnect(selected_callable)

	var capture_callable := Callable(self, "_on_player_mouse_capture_changed")
	if _player.mouse_capture_changed.is_connected(capture_callable):
		_player.mouse_capture_changed.disconnect(capture_callable)

func _refresh_selection_from_player() -> void:
	if _player == null:
		return

	var hotbar_index := _find_hotbar_index_for_block(_player.get_selected_block())
	if hotbar_index == -1:
		return

	_selected_hotbar_index = hotbar_index
	_emit_ui_state()

func _apply_selection_to_player() -> void:
	if _player == null:
		return

	var slot := _hotbar_slots[_selected_hotbar_index]
	if bool(slot.get("is_empty", true)):
		return

	_player.set_selected_block(int(slot.get("block_id", ContentDBScript.get_default_selected_block_id())))

func _build_placeholder_data() -> void:
	_hotbar_slots.clear()
	_inventory_slots.clear()

	var hotbar_blocks := [
		ContentDBScript.GRASS,
		ContentDBScript.DIRT,
		ContentDBScript.STONE,
		ContentDBScript.COBBLE,
		ContentDBScript.STONE,
		ContentDBScript.DIRT,
		ContentDBScript.GRASS,
		ContentDBScript.COBBLE,
	]

	for slot_index in range(hotbar_size):
		if slot_index < hotbar_blocks.size():
			var count := maxi(16, 64 - slot_index * 5)
			_hotbar_slots.append(_build_slot_from_block(hotbar_blocks[slot_index], count, slot_index, &"hotbar"))
			continue
		_hotbar_slots.append(_build_empty_slot(slot_index, &"hotbar"))

	var inventory_size := inventory_rows * inventory_columns
	var inventory_blocks := [
		ContentDBScript.GRASS,
		ContentDBScript.DIRT,
		ContentDBScript.STONE,
		ContentDBScript.COBBLE,
	]

	for slot_index in range(inventory_size):
		if slot_index % 5 == 4:
			_inventory_slots.append(_build_empty_slot(slot_index, &"inventory"))
			continue

		var block_id: int = inventory_blocks[slot_index % inventory_blocks.size()]
		var count := 12 + int((slot_index * 9) % 49)
		_inventory_slots.append(_build_slot_from_block(block_id, count, slot_index, &"inventory"))

	_selected_hotbar_index = _find_hotbar_index_for_block(ContentDBScript.get_default_selected_block_id())
	if _selected_hotbar_index == -1:
		_selected_hotbar_index = 0

func _build_slot_from_block(block_id: int, count: int, slot_index: int, section: StringName) -> Dictionary:
	var item_id := ContentDBScript.get_item_id_for_block(block_id)
	var display := ContentDBScript.get_item_display_data(item_id)
	return {
		"slot_index": slot_index,
		"section": section,
		"item_id": item_id,
		"block_id": block_id,
		"display_name": String(display.get("name", "Prototype Block")),
		"short_name": String(display.get("short_name", display.get("name", "Block"))),
		"count": count,
		"icon_tile": ContentDBScript.get_item_icon_tile(item_id),
		"is_empty": false,
		"is_placeholder": true,
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
		"is_placeholder": true,
	}

func _build_controls_data() -> Dictionary:
	var inventory_key := InputActionFormatterScript.format_action_short(TOGGLE_INVENTORY_ACTION)
	var menu_key := InputActionFormatterScript.format_action_short("ui_cancel")
	var break_key := InputActionFormatterScript.format_action_short("break_block")
	var place_key := InputActionFormatterScript.format_action_short("place_block")
	return {
		"hud_hint": "%s Backpack | %s Menu | 1-9 / Wheel Select" % [inventory_key, menu_key],
		"world_hint": "%s Break | %s Place" % [break_key, place_key],
		"inventory_hint": "%s Close | Click quick slots to sync selection" % [inventory_key],
		"menu_hint": "%s Resume | %s Backpack" % [menu_key, inventory_key],
	}

func _clone_slots(slots: Array[Dictionary]) -> Array[Dictionary]:
	var clone: Array[Dictionary] = []
	for slot in slots:
		clone.append(slot.duplicate(true))
	return clone

func _get_selected_slot() -> Dictionary:
	if _selected_hotbar_index < 0 or _selected_hotbar_index >= _hotbar_slots.size():
		return {}
	return _hotbar_slots[_selected_hotbar_index].duplicate(true)

func _find_hotbar_index_for_block(block_id: int) -> int:
	for slot_index in range(_hotbar_slots.size()):
		var slot := _hotbar_slots[slot_index]
		if bool(slot.get("is_empty", true)):
			continue
		if int(slot.get("block_id", 0)) == block_id:
			return slot_index
	return -1

func _cycle_hotbar(direction: int) -> void:
	if _hotbar_slots.is_empty():
		return

	var next_index := wrapi(_selected_hotbar_index + direction, 0, _hotbar_slots.size())
	request_select_hotbar_index(next_index)

func _hotbar_action_index_from_event(event: InputEvent) -> int:
	for slot_index in range(hotbar_size):
		var action_name := StringName("%s%d" % [HOTBAR_ACTION_PREFIX, slot_index + 1])
		if event.is_action_pressed(action_name):
			return slot_index
	return -1

func _sync_overlay_state() -> void:
	if _player != null:
		_player.set_ui_overlay_active(_inventory_open or _menu_open)
	_emit_ui_state()

func _set_feedback(message: String, duration: float) -> void:
	_feedback_message = message
	_feedback_time_left = maxf(duration, 0.0)
	_emit_ui_state()

func _emit_ui_state() -> void:
	ui_state_changed.emit(get_ui_state())

func _ensure_input_actions() -> void:
	_add_key_if_missing(TOGGLE_INVENTORY_ACTION, KEY_E)

	for slot_index in range(hotbar_size):
		var action_name := StringName("%s%d" % [HOTBAR_ACTION_PREFIX, slot_index + 1])
		_add_key_if_missing(action_name, KEY_1 + slot_index)

func _add_key_if_missing(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if _has_key_event(action, keycode):
		return
	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action, event)

func _has_key_event(action: StringName, keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and event.keycode == keycode:
			return true
	return false

func _on_player_selected_block_changed(block_id: int) -> void:
	var hotbar_index := _find_hotbar_index_for_block(block_id)
	if hotbar_index == -1:
		return
	_selected_hotbar_index = hotbar_index
	_emit_ui_state()

func _on_player_mouse_capture_changed(captured: bool) -> void:
	if captured:
		if _inventory_open or _menu_open:
			request_close_all_overlays()
		return

	if _inventory_open:
		return
	if not _menu_open:
		request_toggle_menu()
