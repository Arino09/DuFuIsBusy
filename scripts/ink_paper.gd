extends Control

const PAPER_TEXTURE = preload("res://assets/ui/paper-background.jpeg")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var original := PAPER_TEXTURE.get_size()
	var ratio: float = maxf(size.x / original.x, size.y / original.y)
	var drawn := original * ratio
	draw_texture_rect(PAPER_TEXTURE, Rect2((size - drawn) * 0.5, drawn), false)
