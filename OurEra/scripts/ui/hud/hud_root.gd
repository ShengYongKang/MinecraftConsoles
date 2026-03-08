class_name HUDRoot
extends Control

const UIIconFactoryScript = preload("res://scripts/ui/ui_icon_factory.gd")

signal hotbar_slot_requested(slot_index: int)

@onready var crosshair: Control = $Crosshair
@onready var mode_label: Label = $ModeLabel
@onready var mode_detail_label: Label = $ModeDetailLabel
@onready var selected_label: Label = $BottomBar/SelectedLabel
@onready var hotbar: Control = $BottomBar/Hotbar
@onready var world_hint_label: Label = $WorldHintLabel
@onready var hint_label: Label = $HintLabel
@onready var feedback_label: Label = $FeedbackLabel
@onready var debug_panel: PanelContainer = $SelectionDebugPanel
@onready var debug_icon: TextureRect = $SelectionDebugPanel/Margin/DebugLayout/DebugIcon
@onready var debug_name_label: Label = $SelectionDebugPanel/Margin/DebugLayout/DebugNameLabel
@onready var debug_item_id_label: Label = $SelectionDebugPanel/Margin/DebugLayout/DebugItemIdLabel
@onready var debug_block_id_label: Label = $SelectionDebugPanel/Margin/DebugLayout/DebugBlockIdLabel
@onready var debug_count_label: Label = $SelectionDebugPanel/Margin/DebugLayout/DebugCountLabel

func _ready() -> void:
	hotbar.slot_selected.connect(_on_hotbar_slot_selected)
	_apply_palette()

func apply_ui_state(state: Dictionary) -> void:
	var controls := Dictionary(state.get("controls", {}))
	var selected_slot := Dictionary(state.get("selected_slot", {}))
	var game_mode := Dictionary(state.get("game_mode", {}))
	var inventory_open := bool(state.get("inventory_open", false))
	var menu_open := bool(state.get("menu_open", false))

	hotbar.set_hotbar_state(Array(state.get("hotbar_slots", [])), int(state.get("selected_hotbar_index", 0)))
	mode_label.text = String(game_mode.get("hud_badge", "SURVIVAL"))
	mode_detail_label.text = String(game_mode.get("hud_detail", ""))
	selected_label.text = _format_selected_label(selected_slot, game_mode)
	_apply_debug_panel(selected_slot)
	world_hint_label.text = String(controls.get("world_hint", ""))
	hint_label.text = String(controls.get("hud_hint", ""))
	feedback_label.text = String(state.get("feedback_message", ""))
	feedback_label.visible = not feedback_label.text.is_empty()

	hotbar.modulate = Color(1.0, 1.0, 1.0, 0.35 if menu_open else 1.0)
	selected_label.modulate = Color(1.0, 1.0, 1.0, 0.4 if menu_open else 1.0)
	mode_label.modulate = Color(1.0, 1.0, 1.0, 0.4 if menu_open else 1.0)
	mode_detail_label.modulate = Color(1.0, 1.0, 1.0, 0.4 if menu_open else 1.0)
	debug_panel.modulate = Color(1.0, 1.0, 1.0, 0.45 if menu_open else 1.0)
	crosshair.set_dimmed(inventory_open or menu_open)

func _apply_debug_panel(selected_slot: Dictionary) -> void:
	var is_empty := bool(selected_slot.get("is_empty", true))
	if is_empty:
		debug_icon.texture = null
		debug_name_label.text = "Selected Slot: Empty"
		debug_item_id_label.text = "item_id: 0"
		debug_block_id_label.text = "block_id: 0"
		debug_count_label.text = "count: 0"
		return

	debug_icon.texture = UIIconFactoryScript.create_icon_from_tile(selected_slot.get("icon_tile", Vector2i.ZERO))
	debug_name_label.text = "Selected Slot: %s" % String(selected_slot.get("display_name", "Item"))
	debug_item_id_label.text = "item_id: %d" % int(selected_slot.get("item_id", 0))
	debug_block_id_label.text = "block_id: %d" % int(selected_slot.get("block_id", 0))
	debug_count_label.text = "count: %d" % int(selected_slot.get("count", 0))

func _format_selected_label(selected_slot: Dictionary, game_mode: Dictionary) -> String:
	var mode_name := String(game_mode.get("short_name", "Survival"))
	if bool(selected_slot.get("is_empty", true)):
		return "%s | Selected slot empty" % mode_name
	var display_name := String(selected_slot.get("display_name", "Item"))
	var count := int(selected_slot.get("count", 0))
	if bool(game_mode.get("placement_consumes_inventory", false)):
		return "%s | Selected: %s x%d" % [mode_name, display_name, count]
	return "%s | Selected: %s | Infinite placement" % [mode_name, display_name]

func _apply_palette() -> void:
	mode_label.add_theme_font_size_override("font_size", 18)
	mode_label.add_theme_color_override("font_color", Color(0.96, 0.80, 0.37))
	mode_label.add_theme_constant_override("outline_size", 7)
	mode_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 0.88))

	mode_detail_label.add_theme_font_size_override("font_size", 13)
	mode_detail_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	mode_detail_label.add_theme_constant_override("outline_size", 6)
	mode_detail_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 0.82))

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

	var debug_style := StyleBoxFlat.new()
	debug_style.bg_color = Color(0.06, 0.08, 0.10, 0.88)
	debug_style.border_color = Color(0.63, 0.48, 0.24, 0.95)
	debug_style.set_border_width_all(2)
	debug_style.corner_radius_top_left = 12
	debug_style.corner_radius_top_right = 12
	debug_style.corner_radius_bottom_left = 12
	debug_style.corner_radius_bottom_right = 12
	debug_panel.add_theme_stylebox_override("panel", debug_style)

	debug_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for label in [debug_name_label, debug_item_id_label, debug_block_id_label, debug_count_label]:
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color(0.90, 0.93, 0.96))

func _on_hotbar_slot_selected(slot_index: int) -> void:
	hotbar_slot_requested.emit(slot_index)
