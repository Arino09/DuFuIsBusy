extends Control
## Session-owned raster state survives replacement of this Control.
signal changed
const WIDTH = 1040
const HEIGHT = 330
var state: Dictionary
var ink := Color("243d35")
var pen_width := 12
var erasing := false
var active := false
var pointer := -2
var previous := Vector2.ZERO
var before: Image
var texture: ImageTexture
var avatar := preload("res://assets/characters/dufu-avatar.png")

static func new_state() -> Dictionary:
	var pixels := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	return {"pixels": pixels, "undo": [], "redo": [], "revision": 0, "submitted": -1, "result": null}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	texture = ImageTexture.create_from_image(state.pixels)
	mouse_exited.connect(finish)
	resized.connect(finish)
	get_window().focus_exited.connect(finish)
	get_viewport().size_changed.connect(finish)

func _exit_tree() -> void:
	finish()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("fffdf7"))
	draw_texture_rect(avatar, Rect2(35, 45, 235, 235), false)
	if texture: draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)

func position_inside(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(p)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and pointer == -2: begin(event.position, -1)
		elif not event.pressed and pointer == -1: finish()
		accept_event()
	elif event is InputEventMouseMotion and pointer == -1 and active:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT: move_pen(event.position)
		else: finish()
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed and pointer == -2: begin(event.position, event.index)
		elif not event.pressed and pointer == event.index: finish()
		accept_event()
	elif event is InputEventScreenDrag and pointer == event.index:
		move_pen(event.position)
		accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and pointer == -1: finish()
	if event is InputEventScreenTouch and not event.pressed and pointer == event.index: finish()

func begin(p: Vector2, id: int) -> void:
	if not position_inside(p): return
	before = state.pixels.duplicate()
	active = true
	pointer = id
	previous = p
	stamp(p)
	refresh()

func move_pen(p: Vector2) -> void:
	if not position_inside(p):
		finish()
		return
	var distance := previous.distance_to(p)
	var steps := maxi(1, ceili(distance / maxf(1.0, pen_width / 4.0)))
	for i in range(1, steps + 1): stamp(previous.lerp(p, float(i) / steps))
	previous = p
	refresh()

func stamp(p: Vector2) -> void:
	var radius := pen_width * 0.5
	for y in range(maxi(0, floori(p.y - radius)), mini(HEIGHT, ceili(p.y + radius + 1))):
		for x in range(maxi(0, floori(p.x - radius)), mini(WIDTH, ceili(p.x + radius + 1))):
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(p) <= radius * radius:
				state.pixels.set_pixel(x, y, Color.TRANSPARENT if erasing else ink)

func refresh() -> void:
	texture.update(state.pixels)
	queue_redraw()

func finish() -> void:
	if not active: return
	active = false
	pointer = -2
	if before.get_data() != state.pixels.get_data():
		state.undo.append(before)
		if state.undo.size() > 20: state.undo.pop_front()
		state.redo.clear()
		state.revision += 1
		changed.emit()
	before = null

func travel(redo: bool) -> void:
	finish()
	var source: Array = state.redo if redo else state.undo
	var destination: Array = state.undo if redo else state.redo
	if source.is_empty(): return
	destination.append(state.pixels.duplicate())
	state.pixels = source.pop_back()
	state.revision += 1
	refresh()
	changed.emit()

func has_ink() -> bool:
	return not state.pixels.is_invisible()

func artwork() -> Image:
	finish()
	var result := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	result.fill(Color("fffdf7"))
	var portrait := avatar.get_image()
	portrait.convert(Image.FORMAT_RGBA8)
	portrait.resize(235, 235, Image.INTERPOLATE_LANCZOS)
	result.blend_rect(portrait, Rect2i(0, 0, 235, 235), Vector2i(35, 45))
	result.blend_rect(state.pixels, Rect2i(0, 0, WIDTH, HEIGHT), Vector2i.ZERO)
	return result
