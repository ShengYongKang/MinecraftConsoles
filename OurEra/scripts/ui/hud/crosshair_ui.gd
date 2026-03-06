class_name CrosshairUI
extends Control

@onready var horizontal: ColorRect = $Center/Cross/Horizontal
@onready var vertical: ColorRect = $Center/Cross/Vertical

func _ready() -> void:
	set_dimmed(false)

func set_dimmed(dimmed: bool) -> void:
	var color := Color(0.98, 0.95, 0.87, 0.95)
	if dimmed:
		color = Color(0.72, 0.76, 0.82, 0.38)
	horizontal.color = color
	vertical.color = color
