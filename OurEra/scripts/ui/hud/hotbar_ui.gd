class_name HotbarUI
extends PanelContainer

const UIIconFactoryScript = preload("res://scripts/ui/ui_icon_factory.gd")

signal slot_selected(slot_index: int)

const SLOT_SIZE := Vector2(46, 46)
const DEFAULT_SLOT_COUNT := 9
const SLOT_SPACING := 4
const HORIZONTAL_PADDING := 12
const VERTICAL_PADDING := 12

@onready var slots_container: HBoxContainer = $Padding/Slots

var _slot_widgets: Array[Dictionary] = []

func _ready() -> void:
	_apply_chrome_style()
	_rebuild_slots(DEFAULT_SLOT_COUNT)

func set_hotbar_state(slots: Array, selected_index: int) -> void:
	var desired_count := maxi(slots.size(), DEFAULT_SLOT_COUNT)
	if _slot_widgets.size() != desired_count:
		_rebuild_slots(desired_count)

	for slot_index in range(desired_count):
		var slot := _build_fallback_slot(slot_index)
		if slot_index < slots.size() and slots[slot_index] is Dictionary:
			slot = Dictionary(slots[slot_index])
		_update_slot_widget(_slot_widgets[slot_index], slot, slot_index == selected_index)

func _rebuild_slots(slot_count: int) -> void:
	for child in slots_container.get_children():
		child.queue_free()
	_slot_widgets.clear()
	_custom_size_for_slot_count(slot_count)

	for slot_index in range(slot_count):
		var frame := PanelContainer.new()
		frame.custom_minimum_size = SLOT_SIZE
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.gui_input.connect(_on_slot_gui_input.bind(slot_index))
		slots_container.add_child(frame)

		var icon_rect := TextureRect.new()
		icon_rect.anchor_right = 1.0
		icon_rect.anchor_bottom = 1.0
		icon_rect.offset_left = 7.0
		icon_rect.offset_top = 7.0
		icon_rect.offset_right = -7.0
		icon_rect.offset_bottom = -7.0
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		frame.add_child(icon_rect)

		var count_label := Label.new()
		count_label.anchor_left = 1.0
		count_label.anchor_top = 1.0
		count_label.anchor_right = 1.0
		count_label.anchor_bottom = 1.0
		count_label.offset_left = -24.0
		count_label.offset_top = -18.0
		count_label.offset_right = -4.0
		count_label.offset_bottom = -2.0
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.add_theme_font_size_override("font_size", 13)
		frame.add_child(count_label)

		_slot_widgets.append({
			"frame": frame,
			"icon_rect": icon_rect,
			"count_label": count_label,
		})

func _custom_size_for_slot_count(slot_count: int) -> void:
	var width := slot_count * SLOT_SIZE.x
	if slot_count > 1:
		width += (slot_count - 1) * SLOT_SPACING
	width += HORIZONTAL_PADDING
	custom_minimum_size = Vector2(width, SLOT_SIZE.y + VERTICAL_PADDING)

func _build_fallback_slot(slot_index: int) -> Dictionary:
	return {
		"slot_index": slot_index,
		"display_name": "Empty",
		"count": 0,
		"icon_tile": Vector2i.ZERO,
		"is_empty": true,
	}

func _update_slot_widget(widget: Dictionary, slot: Dictionary, is_selected: bool) -> void:
	var frame: PanelContainer = widget["frame"]
	var icon_rect: TextureRect = widget["icon_rect"]
	var count_label: Label = widget["count_label"]
	var is_empty := bool(slot.get("is_empty", true))
	var count := int(slot.get("count", 0))

	count_label.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	count_label.add_theme_constant_override("outline_size", 6)
	count_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05, 0.92))

	if is_empty:
		icon_rect.texture = null
		count_label.text = ""
		frame.tooltip_text = "Empty quick slot"
	else:
		icon_rect.texture = UIIconFactoryScript.create_icon_from_tile(slot.get("icon_tile", Vector2i.ZERO))
		count_label.text = str(count)
		frame.tooltip_text = "%s x%d" % [String(slot.get("display_name", "Item")), count]

	frame.add_theme_stylebox_override("panel", _make_slot_style(is_selected, is_empty))

func _apply_chrome_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(0)
	add_theme_stylebox_override("panel", style)

func _make_slot_style(is_selected: bool, is_empty: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.52)
	style.border_color = Color(0.12, 0.12, 0.12, 0.95)
	if is_empty:
		style.bg_color = Color(0.0, 0.0, 0.0, 0.40)
		style.border_color = Color(0.16, 0.16, 0.16, 0.92)
	if is_selected:
		style.bg_color = Color(0.86, 0.86, 0.86, 0.16)
		style.border_color = Color(0.94, 0.94, 0.94, 0.98)
	style.set_border_width_all(2)
	return style

func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_selected.emit(slot_index)

