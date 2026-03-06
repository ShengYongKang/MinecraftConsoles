class_name HotbarUI
extends PanelContainer

const UIIconFactoryScript = preload("res://scripts/ui/ui_icon_factory.gd")

signal slot_selected(slot_index: int)

const SLOT_SIZE := Vector2(70, 74)

@onready var slots_container: HBoxContainer = $Padding/Slots

var _slot_widgets: Array[Dictionary] = []

func _ready() -> void:
	_apply_chrome_style()

func set_hotbar_state(slots: Array, selected_index: int) -> void:
	if _slot_widgets.size() != slots.size():
		_rebuild_slots(slots.size())

	for slot_index in range(slots.size()):
		_update_slot_widget(_slot_widgets[slot_index], Dictionary(slots[slot_index]), slot_index == selected_index)

func _rebuild_slots(slot_count: int) -> void:
	for child in slots_container.get_children():
		child.queue_free()
	_slot_widgets.clear()

	for slot_index in range(slot_count):
		var frame := PanelContainer.new()
		frame.custom_minimum_size = SLOT_SIZE
		frame.mouse_filter = Control.MOUSE_FILTER_STOP
		frame.gui_input.connect(_on_slot_gui_input.bind(slot_index))
		slots_container.add_child(frame)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_bottom", 6)
		frame.add_child(margin)

		var layout := VBoxContainer.new()
		layout.alignment = BoxContainer.ALIGNMENT_CENTER
		layout.add_theme_constant_override("separation", 4)
		margin.add_child(layout)

		var key_label := Label.new()
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_label.add_theme_font_size_override("font_size", 13)
		layout.add_child(key_label)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(34, 34)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layout.add_child(icon_rect)

		var count_label := Label.new()
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", 13)
		layout.add_child(count_label)

		_slot_widgets.append({
			"frame": frame,
			"key_label": key_label,
			"icon_rect": icon_rect,
			"count_label": count_label,
		})

func _update_slot_widget(widget: Dictionary, slot: Dictionary, is_selected: bool) -> void:
	var frame: PanelContainer = widget["frame"]
	var key_label: Label = widget["key_label"]
	var icon_rect: TextureRect = widget["icon_rect"]
	var count_label: Label = widget["count_label"]
	var slot_index := int(slot.get("slot_index", 0))
	var is_empty := bool(slot.get("is_empty", true))
	var count := int(slot.get("count", 0))

	key_label.text = str(slot_index + 1)
	key_label.add_theme_color_override("font_color", Color(0.82, 0.85, 0.91))

	if is_empty:
		icon_rect.texture = null
		count_label.text = ""
		frame.tooltip_text = "Empty quick slot"
	else:
		icon_rect.texture = UIIconFactoryScript.create_icon_from_tile(slot.get("icon_tile", Vector2i.ZERO))
		count_label.text = str(count)
		frame.tooltip_text = "%s x%d" % [String(slot.get("display_name", "Item")), count]

	count_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.83))
	frame.add_theme_stylebox_override("panel", _make_slot_style(is_selected, is_empty))

func _apply_chrome_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 0.78)
	style.border_color = Color(0.63, 0.48, 0.24, 0.95)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.shadow_size = 8
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.24)
	add_theme_stylebox_override("panel", style)

func _make_slot_style(is_selected: bool, is_empty: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.15, 0.19, 0.92)
	style.border_color = Color(0.35, 0.39, 0.47, 0.95)
	if is_empty:
		style.bg_color = Color(0.09, 0.11, 0.14, 0.82)
		style.border_color = Color(0.22, 0.25, 0.30, 0.95)
	if is_selected:
		style.bg_color = Color(0.23, 0.18, 0.09, 0.96)
		style.border_color = Color(0.95, 0.74, 0.34, 1.0)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	return style

func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_selected.emit(slot_index)
