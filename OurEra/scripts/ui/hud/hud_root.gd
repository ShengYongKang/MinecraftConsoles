class_name HUDRoot
extends Control

signal hotbar_slot_requested(slot_index: int)

@onready var crosshair: Control = $Crosshair
@onready var selected_label: Label = $BottomBar/SelectedLabel
@onready var hotbar: Control = $BottomBar/Hotbar
@onready var world_hint_label: Label = $WorldHintLabel
@onready var hint_label: Label = $HintLabel
@onready var feedback_label: Label = $FeedbackLabel

func _ready() -> void:
	hotbar.slot_selected.connect(_on_hotbar_slot_selected)
	_apply_palette()

func apply_ui_state(state: Dictionary) -> void:
	var controls := Dictionary(state.get("controls", {}))
	var selected_slot := Dictionary(state.get("selected_slot", {}))
	var inventory_open := bool(state.get("inventory_open", false))
	var menu_open := bool(state.get("menu_open", false))

	hotbar.set_hotbar_state(Array(state.get("hotbar_slots", [])), int(state.get("selected_hotbar_index", 0)))
	selected_label.text = _format_selected_label(selected_slot)
	world_hint_label.text = String(controls.get("world_hint", ""))
	hint_label.text = String(controls.get("hud_hint", ""))
	feedback_label.text = String(state.get("feedback_message", ""))
	feedback_label.visible = not feedback_label.text.is_empty()

	hotbar.modulate = Color(1.0, 1.0, 1.0, 0.35 if menu_open else 1.0)
	selected_label.modulate = Color(1.0, 1.0, 1.0, 0.4 if menu_open else 1.0)
	crosshair.set_dimmed(inventory_open or menu_open)

func _format_selected_label(selected_slot: Dictionary) -> String:
	if bool(selected_slot.get("is_empty", true)):
		return "Quick Access: Empty Placeholder"
	return "Selected: %s x%d" % [
		String(selected_slot.get("display_name", "Item")),
		int(selected_slot.get("count", 0)),
	]

func _apply_palette() -> void:
	selected_label.add_theme_font_size_override("font_size", 18)
	selected_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.84))
	selected_label.add_theme_constant_override("outline_size", 8)
	selected_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 0.88))

	for label in [world_hint_label, hint_label]:
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.81, 0.85, 0.90))
		label.add_theme_constant_override("outline_size", 6)
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 0.82))

	feedback_label.add_theme_font_size_override("font_size", 16)
	feedback_label.add_theme_color_override("font_color", Color(1.0, 0.90, 0.74))
	feedback_label.add_theme_constant_override("outline_size", 8)
	feedback_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 0.86))

func _on_hotbar_slot_selected(slot_index: int) -> void:
	hotbar_slot_requested.emit(slot_index)

