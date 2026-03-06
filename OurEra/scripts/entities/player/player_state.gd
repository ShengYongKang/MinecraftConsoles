class_name PlayerState
extends RefCounted

const ContentDBScript = preload("res://scripts/content/content_db.gd")

const MAX_LOOK_PITCH := 1.55

var pitch := 0.0
var selected_block: int = ContentDBScript.get_default_selected_block_id()

func from_dictionary(data: Dictionary) -> PlayerState:
	pitch = clamp(float(data.get("pitch", pitch)), -MAX_LOOK_PITCH, MAX_LOOK_PITCH)
	selected_block = ContentDBScript.sanitize_placeable_block_id(int(data.get("selected_block", selected_block)))
	return self

func to_dictionary() -> Dictionary:
	return {
		"pitch": pitch,
		"selected_block": selected_block,
	}

static func create_from_dictionary(data: Dictionary) -> PlayerState:
	return PlayerState.new().from_dictionary(data)
