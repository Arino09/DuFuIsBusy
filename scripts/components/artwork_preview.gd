extends Control
## Renders a saved drawing at its original coordinate size inside a fitted frame.
const Drawing = preload("res://scripts/drawing_surface.gd")

var _state: Dictionary = {}
@onready var _drawing: Drawing = $DrawingSurface

func _ready() -> void:
	resized.connect(_fit_drawing)
	_fit_drawing()
	_apply_state()

func set_state(value: Dictionary) -> void:
	_state = value
	if is_node_ready():
		_apply_state()

func _apply_state() -> void:
	_drawing.visible = not _state.is_empty()
	if _state.is_empty():
		_drawing.state = Drawing.new_state()
		_drawing.texture = null
		return
	_drawing.state = _state
	_drawing.texture = ImageTexture.create_from_image(_state.pixels)
	_drawing.queue_redraw()

func _fit_drawing() -> void:
	var artwork_size := Vector2(Drawing.WIDTH, Drawing.HEIGHT)
	var fit := minf(size.x / artwork_size.x, size.y / artwork_size.y)
	_drawing.scale = Vector2.ONE * fit
	_drawing.position = (size - artwork_size * fit) * 0.5
