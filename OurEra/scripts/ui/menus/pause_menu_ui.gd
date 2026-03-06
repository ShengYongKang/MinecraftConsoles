class_name PauseMenuUI
extends Control

signal resume_requested
signal inventory_requested

@onready var panel: PanelContainer = $Panel
@onready var hint_label: Label = $Panel/Margin/Layout/HintLabel
@onready var resume_button: Button = $Panel/Margin/Layout/ResumeButton
@onready var inventory_button: Button = $Panel/Margin/Layout/InventoryButton

func _ready() -> void:
	resume_button.pressed.connect(_on_resume_button_pressed)
	inventory_button.pressed.connect(_on_inventory_button_pressed)
	_apply_palette()

func apply_ui_state(state: Dictionary) -> void:
	visible = bool(state.get("menu_open", false))
	var controls := Dictionary(state.get("controls", {}))
	hint_label.text = String(controls.get("menu_hint", ""))

func _apply_palette() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.09, 0.12, 0.96)
	panel_style.border_color = Color(0.62, 0.48, 0.22, 0.98)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_left = 18
	panel_style.corner_radius_bottom_right = 18
	panel_style.shadow_size = 12
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	panel.add_theme_stylebox_override("panel", panel_style)

	for button in [resume_button, inventory_button]:
		button.flat = true
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", Color(0.98, 0.93, 0.84))
		button.add_theme_stylebox_override("normal", _make_button_style(Color(0.16, 0.18, 0.22, 0.96)))
		button.add_theme_stylebox_override("hover", _make_button_style(Color(0.22, 0.18, 0.10, 0.98)))
		button.add_theme_stylebox_override("pressed", _make_button_style(Color(0.28, 0.22, 0.12, 1.0)))

	hint_label.add_theme_color_override("font_color", Color(0.84, 0.88, 0.93))

func _make_button_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(0.70, 0.57, 0.28, 0.98)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	return style

func _on_resume_button_pressed() -> void:
	resume_requested.emit()

func _on_inventory_button_pressed() -> void:
	inventory_requested.emit()
