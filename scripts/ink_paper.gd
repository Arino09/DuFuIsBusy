extends Control
## Original procedural paper decoration: no presentation artwork.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("f3eedf"))
	for i in range(90):
		var y := float(i * 13)
		draw_line(Vector2(0, y), Vector2(size.x, y + 23), Color(0.45, 0.37, 0.22, 0.025), 1)
	for i in range(7):
		draw_arc(Vector2(1415, 890), 110.0 + i * 31, PI, TAU, 50, Color(0.17, 0.27, 0.21, 0.035), 9)
