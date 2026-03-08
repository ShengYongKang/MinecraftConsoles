class_name GameUIRoot
extends CanvasLayer

@onready var bridge = $Bridge
@onready var hud = $Root/HUD
@onready var inventory_ui = $Root/InventoryUI
@onready var pause_menu_ui = $Root/PauseMenuUI

func _ready() -> void:
	hud.hotbar_slot_requested.connect(bridge.request_select_hotbar_index)
	inventory_ui.hotbar_slot_requested.connect(bridge.request_select_hotbar_index)
	inventory_ui.close_requested.connect(bridge.request_close_inventory)
	pause_menu_ui.resume_requested.connect(bridge.request_close_all_overlays)
	pause_menu_ui.inventory_requested.connect(bridge.request_open_inventory)
	bridge.ui_state_changed.connect(_apply_ui_state)
	_apply_ui_state(bridge.get_ui_state())

func _unhandled_input(event: InputEvent) -> void:
	if bridge.handle_unhandled_input(event):
		get_viewport().set_input_as_handled()

func _apply_ui_state(state: Dictionary) -> void:
	hud.apply_ui_state(state)
	inventory_ui.apply_ui_state(state)
	pause_menu_ui.apply_ui_state(state)
