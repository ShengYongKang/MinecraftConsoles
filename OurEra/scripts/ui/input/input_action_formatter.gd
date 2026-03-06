class_name InputActionFormatter
extends RefCounted

static func format_action_short(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""

	var labels: Array[String] = []
	for event in InputMap.action_get_events(action):
		var label := _format_event(event)
		if label.is_empty():
			continue
		if labels.has(label):
			continue
		labels.append(label)

	return " / ".join(labels)

static func _format_event(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		return _format_mouse_button(event.button_index)

	var raw_text := event.as_text().replace("(Physical)", "").replace("Physical ", "").strip_edges()
	if raw_text.is_empty():
		return ""
	return raw_text

static func _format_mouse_button(button_index: MouseButton) -> String:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return "LMB"
		MOUSE_BUTTON_RIGHT:
			return "RMB"
		MOUSE_BUTTON_MIDDLE:
			return "MMB"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
		_:
			return "Mouse %d" % int(button_index)
