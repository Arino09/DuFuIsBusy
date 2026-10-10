@tool
extends Control
## A plain paper ground keeps the drawing and controls in focus.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("f5f3ed"))
