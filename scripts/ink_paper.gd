extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("f1ecdf"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 927
	for i in range(2800):
		var p := Vector2(rng.randf_range(0, size.x), rng.randf_range(0, size.y))
		draw_line(p, p + Vector2(rng.randf_range(1, 5), 0), Color(0.42, 0.36, 0.24, 0.045), 1)
	for layer in range(3):
		var pts := PackedVector2Array([Vector2(0, size.y)])
		for i in range(17):
			pts.append(Vector2(i * size.x / 16, size.y - 38 - rng.randf_range(0, 90) - layer * 28))
		pts.append(Vector2(size.x, size.y))
		draw_colored_polygon(pts, Color(0.23, 0.34, 0.28, 0.025 + layer * 0.012))
	draw_circle(Vector2(size.x - 126, 124), 68, Color(0.59, 0.27, 0.18, 0.035))
