class_name PlayerLoadoutState
extends Node

const ContentDBScript = preload("res://scripts/content/content_db.gd")

signal selected_block_changed(block_id: int)

@export var selected_block: int = ContentDBScript.get_default_selected_block_id()

func _ready() -> void:
	selected_block = ContentDBScript.sanitize_placeable_block_id(selected_block)

func get_selected_block() -> int:
	return selected_block

func set_selected_block(block_id: int) -> void:
	var next_block := ContentDBScript.sanitize_placeable_block_id(block_id)
	if selected_block == next_block:
		return
	selected_block = next_block
	selected_block_changed.emit(selected_block)
