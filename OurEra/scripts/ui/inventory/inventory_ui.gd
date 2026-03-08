class_name InventoryUI
extends Control

const UIIconFactoryScript = preload("res://scripts/ui/ui_icon_factory.gd")

signal close_requested
signal hotbar_slot_requested(slot_index: int)

const SLOT_SIZE := Vector2(58, 62)

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/Layout/HeaderRow/TitleLabel
@onready var subtitle_label: Label = $Panel/Margin/Layout/SubtitleLabel
@onready var selection_label: Label = $Panel/Margin/Layout/SelectionLabel
@onready var quick_slots: HBoxContainer = $Panel/Margin/Layout/QuickSlots
@onready var inventory_grid: GridContainer = $Panel/Margin/Layout/InventoryGrid
@onready var hint_label: Label = $Panel/Margin/Layout/HintLabel
@onready var close_button: Button = $Panel/Margin/Layout/HeaderRow/CloseButton

var _quick_slot_widgets: Array[Dictionary] = []
var _inventory_slot_widgets: Array[Dictionary] = []

func _ready() -> void:
	close_button.pressed.connect(_on_close_button_pressed)
	_apply_palette()

func apply_ui_state(state: Dictionary) -> void:
	visible = bool(state.get("inventory_open", false))
	var controls := Dictionary(state.get("controls", {}))
	var selected_slot := Dictionary(state.get("selected_slot", {}))
	var game_mode := Dictionary(state.get("game_mode", {}))
	var summary := Dictionary(state.get("inventory_summary", {}))

	title_label.text = "%s Backpack" % String(game_mode.get("short_name", "Survival"))
	subtitle_label.text = String(game_mode.get("inventory_detail", ""))
	selection_label.text = _format_selection_label(selected_slot, summary)
	hint_label.text = String(controls.get("inventory_hint", ""))

	_set_quick_slots(Array(state.get("hotbar_slots", [])), int(state.get("selected_hotbar_index", 0)))
	_set_inventory_slots(Array(state.get("inventory_slots", [])))

func _set_quick_slots(slots: Array, selected_index: int) -> void:
	if _quick_slot_widgets.size() != slots.size():
		_rebuild_quick_slots(slots.size())

	for slot_index in range(slots.size()):
		_update_slot_widget(_quick_slot_widgets[slot_index], Dictionary(slots[slot_index]), slot_index == selected_index, true)

func _set_inventory_slots(slots: Array) -> void:
	if _inventory_slot_widgets.size() != slots.size():
		_rebuild_inventory_slots(slots.size())

	for slot_index in range(slots.size()):
		_update_slot_widget(_inventory_slot_widgets[slot_index], Dictionary(slots[slot_index]), false, false)

func _rebuild_quick_slots(slot_count: int) -> void:
	for child in quick_slots.get_children():
		child.queue_free()
	_quick_slot_widgets.clear()

	for slot_index in range(slot_count):
		var frame := _create_slot_frame(SLOT_SIZE)
		frame.gui_input.connect(_on_quick_slot_gui_input.bind(slot_index))
		quick_slots.add_child(frame)
		_quick_slot_widgets.append(_build_slot_widget(frame))

func _rebuild_inventory_slots(slot_count: int) -> void:
	for child in inventory_grid.get_children():
		child.queue_free()
	_inventory_slot_widgets.clear()

	for _slot_index in range(slot_count):
		var frame := _create_slot_frame(SLOT_SIZE)
		inventory_grid.add_child(frame)
		_inventory_slot_widgets.append(_build_slot_widget(frame))

func _create_slot_frame(slot_size: Vector2) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = slot_size
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	return frame

func _build_slot_widget(frame: PanelContainer) -> Dictionary:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 6)
	frame.add_child(margin)

	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 2)
	margin.add_child(layout)

	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	layout.add_child(name_label)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(28, 28)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layout.add_child(icon_rect)

	var count_label := Label.new()
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 12)
	layout.add_child(count_label)

	return {
		"frame": frame,
		"name_label": name_label,
		"icon_rect": icon_rect,
		"count_label": count_label,
	}

func _update_slot_widget(widget: Dictionary, slot: Dictionary, is_selected: bool, emphasize_hotbar: bool) -> void:
	var frame: PanelContainer = widget["frame"]
	var name_label: Label = widget["name_label"]
	var icon_rect: TextureRect = widget["icon_rect"]
	var count_label: Label = widget["count_label"]
	var is_empty := bool(slot.get("is_empty", true))
	var short_name := String(slot.get("short_name", "Empty"))
	var count := int(slot.get("count", 0))

	name_label.text = "-" if is_empty else short_name
	name_label.add_theme_color_override("font_color", Color(0.83, 0.87, 0.92))
	count_label.add_theme_color_override("font_color", Color(0.98, 0.93, 0.83))

	if is_empty:
		icon_rect.texture = null
		count_label.text = ""
		frame.tooltip_text = "Empty slot"
	else:
		icon_rect.texture = UIIconFactoryScript.create_icon_from_tile(slot.get("icon_tile", Vector2i.ZERO))
		count_label.text = str(count)
		frame.tooltip_text = "%s x%d" % [String(slot.get("display_name", "Item")), count]

	frame.add_theme_stylebox_override("panel", _make_slot_style(is_selected, is_empty, emphasize_hotbar))

func _make_slot_style(is_selected: bool, is_empty: bool, emphasize_hotbar: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.13, 0.16, 0.95)
	style.border_color = Color(0.28, 0.33, 0.39, 0.95)
	if emphasize_hotbar:
		style.border_color = Color(0.48, 0.42, 0.24, 0.95)
	if is_empty:
		style.bg_color = Color(0.08, 0.10, 0.13, 0.86)
		style.border_color = Color(0.20, 0.23, 0.28, 0.95)
	if is_selected:
		style.bg_color = Color(0.22, 0.18, 0.09, 0.96)
		style.border_color = Color(0.95, 0.73, 0.34, 1.0)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style

func _format_selection_label(selected_slot: Dictionary, summary: Dictionary) -> String:
	var used_slots := int(summary.get("used_slots", 0))
	var total_slots := int(summary.get("total_slots", 0))
	var total_items := int(summary.get("total_items", 0))
	if bool(selected_slot.get("is_empty", true)):
		return "Selection empty | Slots used: %d/%d | Items stored: %d" % [used_slots, total_slots, total_items]
	return "Selected: %s x%d | Slots used: %d/%d | Items stored: %d" % [
		String(selected_slot.get("display_name", "Item")),
		int(selected_slot.get("count", 0)),
		used_slots,
		total_slots,
		total_items,
	]

func _apply_palette() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.09, 0.12, 0.96)
	panel_style.border_color = Color(0.63, 0.47, 0.22, 0.98)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_left = 18
	panel_style.corner_radius_bottom_right = 18
	panel_style.shadow_size = 12
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	panel.add_theme_stylebox_override("panel", panel_style)

	for label in [title_label, subtitle_label, selection_label, hint_label]:
		label.add_theme_color_override("font_color", Color(0.84, 0.88, 0.93))

	close_button.add_theme_font_size_override("font_size", 14)

func _on_close_button_pressed() -> void:
	close_requested.emit()

func _on_quick_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hotbar_slot_requested.emit(slot_index)
