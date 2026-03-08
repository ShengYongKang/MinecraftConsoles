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
var _world_root: Node
var _inventory_open := false
var _menu_open := false
var _selected_hotbar_index := 0
var _hotbar_slots: Array[Dictionary] = []
var _inventory_slots: Array[Dictionary] = []
var _feedback_message := ""
var _feedback_time_left := 0.0
var _game_mode_id: StringName = ContentDBScript.get_default_game_mode_id()
var _game_mode_display: Dictionary = ContentDBScript.get_game_mode_display_data(_game_mode_id)

func _ready() -> void:
	_ensure_input_actions()
	_build_empty_slot_state()
	_resolve_player_ref()
	set_process(true)
	_sync_overlay_state()

func _process(delta: float) -> void:
	if _player == null:
		_resolve_player_ref()
	elif _world_root == null:
		_resolve_world_ref()
	else:
		_poll_player_state()

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
		"game_mode": _build_game_mode_state(),
		"inventory_summary": _build_inventory_summary(),
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
	_set_feedback("Backpack open", 0.8)
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
	_disconnect_world_root()
	_player = node as PlayerController
	_world_root = null
	if _player == null:
		_build_empty_slot_state()
		_refresh_game_mode_state()
		_emit_ui_state()
		return

	var selected_callable := Callable(self, "_on_player_selected_block_changed")
	if not _player.selected_block_changed.is_connected(selected_callable):
		_player.selected_block_changed.connect(selected_callable)

	var hotbar_callable := Callable(self, "_on_player_selected_hotbar_changed")
	if not _player.selected_hotbar_changed.is_connected(hotbar_callable):
		_player.selected_hotbar_changed.connect(hotbar_callable)

	var inventory_callable := Callable(self, "_on_player_inventory_changed")
	if not _player.inventory_changed.is_connected(inventory_callable):
		_player.inventory_changed.connect(inventory_callable)

	var capture_callable := Callable(self, "_on_player_mouse_capture_changed")
	if not _player.mouse_capture_changed.is_connected(capture_callable):
		_player.mouse_capture_changed.connect(capture_callable)

	var feedback_callable := Callable(self, "_on_player_ui_feedback_emitted")
	if not _player.ui_feedback_emitted.is_connected(feedback_callable):
		_player.ui_feedback_emitted.connect(feedback_callable)

	var pickup_callable := Callable(self, "_on_player_drop_item_collected")
	if _player.has_signal("drop_item_collected") and not _player.drop_item_collected.is_connected(pickup_callable):
		_player.drop_item_collected.connect(pickup_callable)

	_resolve_world_ref()
	_refresh_inventory_from_player()
	_refresh_selection_from_player()
	_refresh_game_mode_state()
	_sync_overlay_state()

func _resolve_world_ref() -> void:
	_disconnect_world_root()
	if _player == null:
		_world_root = null
		_refresh_game_mode_state()
		return

	_world_root = _player.get_world_root()
	if _world_root == null:
		_refresh_game_mode_state()
		return
	if _world_root.has_signal("game_mode_changed"):
		var callable := Callable(self, "_on_world_game_mode_changed")
		if not _world_root.game_mode_changed.is_connected(callable):
			_world_root.game_mode_changed.connect(callable)
	_refresh_game_mode_state()

func _disconnect_player() -> void:
	if _player == null:
		return

	var selected_callable := Callable(self, "_on_player_selected_block_changed")
	if _player.selected_block_changed.is_connected(selected_callable):
		_player.selected_block_changed.disconnect(selected_callable)

	var hotbar_callable := Callable(self, "_on_player_selected_hotbar_changed")
	if _player.selected_hotbar_changed.is_connected(hotbar_callable):
		_player.selected_hotbar_changed.disconnect(hotbar_callable)

	var inventory_callable := Callable(self, "_on_player_inventory_changed")
	if _player.inventory_changed.is_connected(inventory_callable):
		_player.inventory_changed.disconnect(inventory_callable)

	var capture_callable := Callable(self, "_on_player_mouse_capture_changed")
	if _player.mouse_capture_changed.is_connected(capture_callable):
		_player.mouse_capture_changed.disconnect(capture_callable)

	var feedback_callable := Callable(self, "_on_player_ui_feedback_emitted")
	if _player.ui_feedback_emitted.is_connected(feedback_callable):
		_player.ui_feedback_emitted.disconnect(feedback_callable)

	var pickup_callable := Callable(self, "_on_player_drop_item_collected")
	if _player.has_signal("drop_item_collected") and _player.drop_item_collected.is_connected(pickup_callable):
		_player.drop_item_collected.disconnect(pickup_callable)

func _disconnect_world_root() -> void:
	if _world_root == null:
		return
	if _world_root.has_signal("game_mode_changed"):
		var callable := Callable(self, "_on_world_game_mode_changed")
		if _world_root.game_mode_changed.is_connected(callable):
			_world_root.game_mode_changed.disconnect(callable)

func _poll_player_state() -> void:
	if _player == null:
		return
	var next_hotbar := _player.get_hotbar_slots()
	var next_inventory := _player.get_inventory_slots()
	var next_selected := _player.get_selected_hotbar_index()
	var inventory_changed := not _slots_equal(_hotbar_slots, next_hotbar) or not _slots_equal(_inventory_slots, next_inventory)
	var selection_changed := next_selected != _selected_hotbar_index
	if inventory_changed:
		_hotbar_slots = next_hotbar
		_inventory_slots = next_inventory
	if selection_changed:
		_selected_hotbar_index = clampi(next_selected, 0, maxi(_hotbar_slots.size() - 1, 0))
	if inventory_changed or selection_changed:
		_emit_ui_state()

func _slots_equal(current_slots: Array[Dictionary], next_slots: Array[Dictionary]) -> bool:
	if current_slots.size() != next_slots.size():
		return false
	for slot_index in range(current_slots.size()):
		if current_slots[slot_index] != next_slots[slot_index]:
			return false
	return true

func _refresh_selection_from_player() -> void:
	if _player == null:
		return
	_selected_hotbar_index = clampi(_player.get_selected_hotbar_index(), 0, maxi(_hotbar_slots.size() - 1, 0))
	_emit_ui_state()

func _refresh_inventory_from_player() -> void:
	if _player == null:
		return
	_hotbar_slots = _player.get_hotbar_slots()
	_inventory_slots = _player.get_inventory_slots()
	_emit_ui_state()

func _refresh_game_mode_state() -> void:
	if _world_root != null and _world_root.has_method("get_game_mode_id"):
		_game_mode_id = _world_root.get_game_mode_id()
	else:
		_game_mode_id = ContentDBScript.get_default_game_mode_id()
	_game_mode_display = ContentDBScript.get_game_mode_display_data(_game_mode_id)
	_emit_ui_state()

func _apply_selection_to_player() -> void:
	if _player == null:
		return
	_player.select_hotbar_index(_selected_hotbar_index)
	_refresh_inventory_from_player()

func _build_empty_slot_state() -> void:
	_hotbar_slots.clear()
	_inventory_slots.clear()
	for slot_index in range(hotbar_size):
		_hotbar_slots.append(_build_empty_slot(slot_index, &"hotbar"))
	for slot_index in range(inventory_rows * inventory_columns):
		_inventory_slots.append(_build_empty_slot(slot_index, &"inventory"))
	_selected_hotbar_index = 0

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

func _build_game_mode_state() -> Dictionary:
	var short_name := String(_game_mode_display.get("short_name", _game_mode_id))
	var mode_name := String(_game_mode_display.get("name", short_name))
	var consumes_inventory := ContentDBScript.does_placement_consume_inventory(_game_mode_id)
	var pickup_enabled := ContentDBScript.allows_drop_pickup(_game_mode_id)
	var requires_inventory := ContentDBScript.requires_inventory_for_placement(_game_mode_id)
	return {
		"id": _game_mode_id,
		"name": mode_name,
		"short_name": short_name,
		"hud_badge": short_name.to_upper(),
		"hud_detail": _format_mode_detail(consumes_inventory, pickup_enabled, requires_inventory),
		"inventory_detail": _format_inventory_mode_detail(mode_name, consumes_inventory, pickup_enabled, requires_inventory),
		"placement_consumes_inventory": consumes_inventory,
		"placement_requires_inventory": requires_inventory,
		"drop_pickup_enabled": pickup_enabled,
	}

func _format_mode_detail(consumes_inventory: bool, pickup_enabled: bool, requires_inventory: bool) -> String:
	if consumes_inventory:
		return "Drops and placement use real inventory."
	if not pickup_enabled and not requires_inventory:
		return "Instant build. Drops are ignored."
	return "Sandbox rules active."

func _format_inventory_mode_detail(mode_name: String, consumes_inventory: bool, pickup_enabled: bool, requires_inventory: bool) -> String:
	var placement_text := "Infinite placement"
	if requires_inventory:
		placement_text = "Placement requires stored items"
	var pickup_text := "Pickup disabled"
	if pickup_enabled:
		pickup_text = "Drop pickup enabled"
	var consume_text := "No placement cost"
	if consumes_inventory:
		consume_text = "Placement consumes stacks"
	return "%s mode. %s. %s. %s." % [mode_name, placement_text, pickup_text, consume_text]

func _build_inventory_summary() -> Dictionary:
	var used_slots := 0
	var total_items := 0
	for slot in _hotbar_slots:
		if not bool(slot.get("is_empty", true)):
			used_slots += 1
			total_items += int(slot.get("count", 0))
	for slot in _inventory_slots:
		if not bool(slot.get("is_empty", true)):
			used_slots += 1
			total_items += int(slot.get("count", 0))
	return {
		"used_slots": used_slots,
		"total_slots": _hotbar_slots.size() + _inventory_slots.size(),
		"total_items": total_items,
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

func _on_player_selected_block_changed(_block_id: int) -> void:
	_refresh_selection_from_player()

func _on_player_selected_hotbar_changed(slot_index: int) -> void:
	_selected_hotbar_index = clampi(slot_index, 0, maxi(_hotbar_slots.size() - 1, 0))
	_emit_ui_state()

func _on_player_inventory_changed() -> void:
	_refresh_inventory_from_player()
	_refresh_selection_from_player()

func _on_player_drop_item_collected(_result: Dictionary) -> void:
	_refresh_inventory_from_player()
	_refresh_selection_from_player()

func _on_player_mouse_capture_changed(captured: bool) -> void:
	if captured:
		if _inventory_open or _menu_open:
			request_close_all_overlays()
		return

	if _inventory_open:
		return
	if not _menu_open:
		request_toggle_menu()

func _on_player_ui_feedback_emitted(feedback: Dictionary) -> void:
	var message := String(feedback.get("message", "")).strip_edges()
	if message.is_empty():
		return
	var kind := StringName(feedback.get("kind", &"info"))
	var duration := 1.1
	if kind == &"pickup":
		duration = 1.35
	elif kind == &"place_failed":
		duration = 1.8
	_set_feedback(message, duration)

func _on_world_game_mode_changed(_previous: StringName, _current: StringName) -> void:
	_refresh_game_mode_state()
