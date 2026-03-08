class_name PlayerState
extends RefCounted

const ContentDBScript = preload("res://scripts/content/content_db.gd")

const MAX_LOOK_PITCH := 1.55

var pitch := 0.0
var selected_block: int = ContentDBScript.get_default_selected_block_id()
var selected_hotbar_index := 0
var hotbar_slots: Array[Dictionary] = []
var inventory_slots: Array[Dictionary] = []

func from_dictionary(data: Dictionary) -> PlayerState:
	pitch = clamp(float(data.get("pitch", pitch)), -MAX_LOOK_PITCH, MAX_LOOK_PITCH)
	selected_block = ContentDBScript.sanitize_placeable_block_id(int(data.get("selected_block", selected_block)))
	selected_hotbar_index = maxi(0, int(data.get("selected_hotbar_index", selected_hotbar_index)))
	hotbar_slots = _read_slot_array(data.get("hotbar_slots", []))
	inventory_slots = _read_slot_array(data.get("inventory_slots", []))
	return self

func to_dictionary() -> Dictionary:
	return {
		"pitch": pitch,
		"selected_block": selected_block,
		"selected_hotbar_index": selected_hotbar_index,
		"hotbar_slots": _clone_slots(hotbar_slots),
		"inventory_slots": _clone_slots(inventory_slots),
	}

static func create_from_dictionary(data: Dictionary) -> PlayerState:
	return PlayerState.new().from_dictionary(data)

func _read_slot_array(value: Variant) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if value is Array:
		for entry in value:
			if entry is Dictionary:
				slots.append(Dictionary(entry).duplicate(true))
	return slots

func _clone_slots(slots: Array[Dictionary]) -> Array[Dictionary]:
	var clone: Array[Dictionary] = []
	for slot in slots:
		clone.append(slot.duplicate(true))
	return clone
