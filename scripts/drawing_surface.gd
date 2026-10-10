extends Control
## Raster strokes and editable objects share a session-owned undo history.
signal changed
signal selection_changed
const WIDTH = 1040
const HEIGHT = 330
const CREATIVE_FONT = preload("res://assets/fonts/CreativeSansSC.otf")
const DEFAULT_POSITION = Vector2(152.5, 162.5)
var state: Dictionary = new_state()
var ink := Color("243d35")
var pen_width := 12
var erasing := false
var selecting := false
@export var preview_only := false
@export_enum("none", "star", "cloud", "seal") var preview_kind: String = "none"
var active := false
var pointer := -2
var previous := Vector2.ZERO
var before: Dictionary
var texture: ImageTexture
var avatar := preload("res://assets/characters/dufu-avatar.png")

static func new_state() -> Dictionary:
	var pixels := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	return {"pixels": pixels, "objects": [{"id": 0, "kind": "avatar", "position": DEFAULT_POSITION, "scale": 1.0, "rotation": 0.0}], "selected": -1, "next_id": 1, "undo": [], "redo": [], "revision": 0, "submitted": -1, "result": null}

func _ready() -> void:
	if preview_kind != "none":
		state = new_state()
		state.objects = [{"id": 1, "kind": preview_kind, "position": Vector2(120, 90), "scale": 1.3, "rotation": 0.0}]
		preview_only = true
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE if preview_only else Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE if selecting else Control.CURSOR_CROSS
	texture = ImageTexture.create_from_image(state.pixels)
	if preview_only: return
	mouse_exited.connect(finish)
	resized.connect(finish)
	get_window().focus_exited.connect(finish)
	get_viewport().size_changed.connect(finish)

func _exit_tree() -> void:
	finish()

func dimensions(object: Dictionary) -> Vector2:
	if object.kind == "avatar": return Vector2(235, 235)
	if object.kind == "text":
		return Vector2(maxf(20, CREATIVE_FONT.get_string_size(object.text, HORIZONTAL_ALIGNMENT_LEFT, -1, object.font_size).x), CREATIVE_FONT.get_height(object.font_size))
	return Vector2(120, 100)

func transform_for(object: Dictionary) -> Transform2D:
	return Transform2D(object.rotation, Vector2.ONE * object.scale, 0, object.position)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("fffdf7"))
	for object in state.objects:
		if object.kind == "avatar": draw_object(object)
	draw_set_transform(Vector2.ZERO)
	if texture: draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
	for object in state.objects:
		if object.kind != "avatar": draw_object(object)
	draw_set_transform(Vector2.ZERO)

func draw_object(object: Dictionary) -> void:
	var extent := dimensions(object)
	draw_set_transform(object.position, object.rotation, Vector2.ONE * object.scale)
	if object.kind == "avatar": draw_texture_rect(avatar, Rect2(-extent / 2, extent), false)
	elif object.kind == "text":
		draw_string(CREATIVE_FONT, Vector2(-extent.x / 2, -extent.y / 2 + CREATIVE_FONT.get_ascent(object.font_size)), object.text, HORIZONTAL_ALIGNMENT_LEFT, -1, object.font_size, object.color)
	elif object.kind == "star":
		var points := PackedVector2Array()
		for i in range(10):
			var angle := -PI / 2 + i * PI / 5
			points.append(Vector2(cos(angle), sin(angle)) * (48 if i % 2 == 0 else 22))
		draw_colored_polygon(points, Color("e0a939"))
	elif object.kind == "cloud":
		draw_circle(Vector2(-30, 8), 24, Color("91bdc2"))
		draw_circle(Vector2(0, -9), 34, Color("91bdc2"))
		draw_circle(Vector2(34, 8), 24, Color("91bdc2"))
		draw_rect(Rect2(-30, 8, 64, 24), Color("91bdc2"))
	elif object.kind == "seal":
		draw_rect(Rect2(-42, -42, 84, 84), Color("aa4937"))
		draw_rect(Rect2(-35, -35, 70, 70), Color("f8f4e9"), false, 2)
		draw_string(CREATIVE_FONT, Vector2(-27, 19), "忙", HORIZONTAL_ALIGNMENT_LEFT, -1, 54, Color("f8f4e9"))
	if not preview_only and selecting and state.selected == object.id:
		draw_rect(Rect2(-extent / 2 - Vector2(4, 4), extent + Vector2(8, 8)), Color("416f9a"), false, 2.0 / object.scale)

func selected_object() -> Dictionary:
	for object in state.objects:
		if object.id == state.selected: return object
	return {}

func select_at(p: Vector2) -> void:
	state.selected = -1
	# Strokes are a separate paint layer; objects remain selectable in move mode.
	for i in range(state.objects.size() - 1, -1, -1):
		var object: Dictionary = state.objects[i]
		var local := transform_for(object).affine_inverse() * p
		if Rect2(-dimensions(object) / 2, dimensions(object)).has_point(local):
			state.selected = object.id
			break
	queue_redraw()
	selection_changed.emit()

func position_inside(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(p)

func _gui_input(event: InputEvent) -> void:
	if preview_only: return
	if event is InputEventMouse and event.device == -1: return
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

func snapshot() -> Dictionary:
	return {"pixels": state.pixels.duplicate(), "objects": state.objects.duplicate(true)}

func begin(p: Vector2, id: int) -> void:
	if not position_inside(p): return
	if selecting:
		select_at(p)
		if selected_object().is_empty(): return
	before = snapshot()
	active = true
	pointer = id
	previous = p
	if not selecting: stamp(p)
	refresh()

func move_pen(p: Vector2) -> void:
	if not active: return
	if not position_inside(p):
		finish()
		return
	if selecting:
		var object := selected_object()
		object.position += p - previous
		constrain(object)
	else:
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
	if texture: texture.update(state.pixels)
	queue_redraw()

func record(prior: Dictionary) -> void:
	if prior.objects == state.objects and prior.pixels.get_data() == state.pixels.get_data(): return
	state.undo.append(prior)
	if state.undo.size() > 20: state.undo.pop_front()
	state.redo.clear()
	state.revision += 1
	refresh()
	changed.emit()

func finish() -> void:
	if not active: return
	active = false
	pointer = -2
	record(before)
	before = {}

func travel(redo: bool) -> void:
	finish()
	var source: Array = state.redo if redo else state.undo
	var destination: Array = state.undo if redo else state.redo
	if source.is_empty(): return
	destination.append(snapshot())
	var saved: Dictionary = source.pop_back()
	state.pixels = saved.pixels
	state.objects = saved.objects
	state.selected = -1
	state.revision += 1
	refresh()
	changed.emit()
	selection_changed.emit()

func constrain(object: Dictionary) -> void:
	var d := dimensions(object)
	var cosine := absf(cos(object.rotation))
	var sine := absf(sin(object.rotation))
	var bounds := Vector2(d.x * cosine + d.y * sine, d.x * sine + d.y * cosine)
	object.scale = minf(clampf(object.scale, 0.25, 2.0), minf(WIDTH / bounds.x, HEIGHT / bounds.y))
	var half: Vector2 = bounds * object.scale / 2
	object.position = Vector2(clampf(object.position.x, half.x, WIDTH - half.x), clampf(object.position.y, half.y, HEIGHT - half.y))

func add_object(kind: String, text: String = "", font_size: int = 32, color: Color = Color("243d35")) -> void:
	finish()
	if state.objects.size() >= 25: return
	var prior := snapshot()
	var object := {"id": state.next_id, "kind": kind, "position": Vector2(580, 165), "scale": 1.0, "rotation": 0.0, "text": text, "font_size": font_size, "color": color}
	state.next_id += 1
	state.objects.append(object)
	state.selected = object.id
	constrain(object)
	record(prior)
	selection_changed.emit()

func edit_text(text: String, font_size: int, color: Color) -> void:
	var object := selected_object()
	if object.is_empty() or object.kind != "text": return
	var prior := snapshot()
	object.text = text
	object.font_size = font_size
	object.color = color
	constrain(object)
	record(prior)

func transform_selected(factor: float, angle: float) -> void:
	finish()
	var object := selected_object()
	if object.is_empty(): return
	var prior := snapshot()
	object.scale *= factor
	object.rotation = wrapf(object.rotation + angle, -PI, PI)
	constrain(object)
	record(prior)

func remove_selected() -> void:
	finish()
	var object := selected_object()
	if object.is_empty() or object.kind == "avatar": return
	var prior := snapshot()
	state.objects.erase(object)
	state.selected = -1
	record(prior)
	selection_changed.emit()

func has_ink() -> bool:
	return not state.pixels.is_invisible()

func has_creation() -> bool:
	if has_ink() or state.objects.size() > 1: return true
	var person: Dictionary = state.objects[0]
	return person.position.distance_to(DEFAULT_POSITION) > 0.5 or absf(person.scale - 1) > 0.001 or absf(person.rotation) > 0.001

func artwork() -> Image:
	finish()
	# Use the identical renderer offscreen; omit selection outlines and UI.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(WIDTH, HEIGHT)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var replica = get_script().new()
	replica.state = state
	replica.preview_only = true
	replica.size = Vector2(WIDTH, HEIGHT)
	viewport.add_child(replica)
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	viewport.queue_free()
	return result
