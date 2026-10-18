extends Control
## Raster strokes and editable objects share a session-owned undo history.
signal color_used(color: Color)
signal changed
signal selection_changed
const WIDTH = 1080
const HEIGHT = 1080
const MIN_SIZE = 256
const MAX_SIZE = 2048
const CREATIVE_FONT = preload("res://assets/fonts/chill_long_cang.tres")
const DEFAULT_POSITION = Vector2(152.5, 162.5)
const Backgrounds = preload("res://scripts/artwork_backgrounds.gd")
const AudioHooks = preload("res://scripts/audio/audio_hooks.gd")
const Stickers = preload("res://scripts/sticker_catalog.gd")
const STICKER_TEXTURES = Stickers.TEXTURES
const STICKER_MAX_SIZE = Vector2(150, 180)
const SELECTION_COLOR = Color("527fff")
const HANDLE_SIZE = 10.0
const HANDLE_DIRECTIONS = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0)]
const ROTATE_HANDLE = 8
# Wwise's brush curves use 0–100; measure canvas pixels so zoom does not change the sound.
const BRUSH_FULL_SPEED := 3000.0
const BRUSH_RESPONSE := 20.0
var state: Dictionary = new_state()
var ink := Color("243d35")
var pen_width := 12:
	set(value):
		pen_width = value
		queue_redraw()
var erasing := false
var selecting := false
@export var preview_only := false
@export var preview_kind: String = "none"
var active := false
var pointer := -2
var previous := Vector2.ZERO
var before: Dictionary
var drag_mode := ""
var drag_handle := -1
var drag_start := Vector2.ZERO
var drag_object: Dictionary = {}
# CanvasPage owns touch navigation; standalone surfaces keep their drawing input.
var touch_input_router := Callable()
var _brush_distance := 0.0
var _brush_speed := 0.0
var _drag_audio_key := ""
var texture: ImageTexture
var _brush_cursor_visible := false
var _brush_cursor_position := Vector2.ZERO
var avatar := preload("res://assets/characters/dufu-avatar.png")

static func new_state(background_id: String = "paper", canvas_size: Vector2i = Vector2i(WIDTH, HEIGHT)) -> Dictionary:
	var pixels := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	return {"background_id": background_id, "pixels": pixels, "objects": [{"id": 0, "kind": "avatar", "position": initial_avatar_position(canvas_size), "scale": 1.0, "rotation": 0.0}], "selected": -1, "next_id": 1, "undo": [], "redo": [], "revision": 0, "submitted": -1, "result": null}

static func initial_avatar_position(extent: Vector2i) -> Vector2:
	return DEFAULT_POSITION.clamp(Vector2.ONE * 117.5, Vector2(extent) - Vector2.ONE * 117.5)

func _ready() -> void:
	if not preview_only and preview_kind == "none": size = canvas_size()
	if preview_kind != "none":
		state = new_state()
		var object := {"id": 1, "kind": preview_kind, "position": size / 2, "scale": 1.0, "rotation": 0.0}
		var extent := dimensions(object)
		object.scale = minf(1.3, minf(maxf(1, size.x - 24) / extent.x, maxf(1, size.y - 24) / extent.y))
		state.objects = [object]
		preview_only = true
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE if preview_only else Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE if selecting else Control.CURSOR_CROSS
	texture = ImageTexture.create_from_image(state.pixels)
	if preview_only:
		set_process(false)
		return
	mouse_exited.connect(func():
		_hide_brush_cursor()
		if drag_mode == "paint" and pointer < 0: finish())
	resized.connect(finish)
	get_window().focus_exited.connect(func():
		_hide_brush_cursor()
		if pointer >= 0: cancel()
		else: finish())
	get_viewport().size_changed.connect(func():
		if pointer >= 0: cancel()
		else: finish())

func _process(delta: float) -> void:
	if preview_only: return
	_update_brush_audio(delta)
	# Query the hovered control so dialogs and clipped paper cannot retain a ring.
	var show_cursor := (
		not selecting and pointer < 0 and is_visible_in_tree()
		and get_window().has_focus() and get_viewport().gui_get_hovered_control() == self
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)
	var local_pointer := get_local_mouse_position()
	show_cursor = show_cursor and position_inside(local_pointer)
	if show_cursor != _brush_cursor_visible or (show_cursor and local_pointer != _brush_cursor_position):
		_brush_cursor_visible = show_cursor
		_brush_cursor_position = local_pointer
		queue_redraw()

func _hide_brush_cursor() -> void:
	if not _brush_cursor_visible: return
	_brush_cursor_visible = false
	queue_redraw()

func _exit_tree() -> void:
	finish()

func _update_brush_audio(delta: float) -> void:
	if not active or _drag_audio_key != "paint" or delta <= 0.0: return
	var target := clampf(_brush_distance / delta / BRUSH_FULL_SPEED * 100.0, 0.0, 100.0)
	_brush_distance = 0.0
	_brush_speed = lerpf(_brush_speed, target, 1.0 - exp(-BRUSH_RESPONSE * delta))
	if _brush_speed < 0.1: _brush_speed = 0.0
	AudioHooks.param("canvas.drag_speed", _brush_speed)

func dimensions(object: Dictionary) -> Vector2:
	if object.kind == "avatar": return Vector2(235, 235)
	if object.kind == "text":
		return Vector2(maxf(20, CREATIVE_FONT.get_string_size(object.text, HORIZONTAL_ALIGNMENT_LEFT, -1, object.font_size).x), CREATIVE_FONT.get_height(object.font_size))
	if STICKER_TEXTURES.has(object.kind):
		var source_size: Vector2 = STICKER_TEXTURES[object.kind].get_size()
		return source_size * minf(STICKER_MAX_SIZE.x / source_size.x, STICKER_MAX_SIZE.y / source_size.y)
	return Vector2(120, 100)

static func object_scale(object: Dictionary) -> Vector2:
	# Old artwork stores a single uniform scale; scale_y is optional.
	return Vector2(object.scale, object.get("scale_y", object.scale))

func set_object_scale(object: Dictionary, value: Vector2) -> void:
	object.scale = value.x
	if object.has("scale_y") or not is_equal_approx(value.x, value.y):
		object.scale_y = value.y

func transform_for(object: Dictionary) -> Transform2D:
	return Transform2D(object.rotation, object_scale(object), 0, object.position)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("fffdf7"))
	var background := Backgrounds.texture_for(state.background_id)
	if background: draw_texture_rect(background, Rect2(Vector2.ZERO, size), false)
	for object in state.objects:
		if object.kind == "avatar": draw_object(object)
	draw_set_transform(Vector2.ZERO)
	if texture: draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false)
	for object in state.objects:
		if object.kind != "avatar": draw_object(object)
	draw_set_transform(Vector2.ZERO)
	# Draw the selection above every artwork layer, including ink and stickers.
	if not preview_only and selecting and not selected_object().is_empty():
		draw_selection(selected_object())
	if not preview_only and not selecting and _brush_cursor_visible:
		# Match stamp() in artwork coordinates; keep the outline legible at any zoom.
		var unit := 1.0 / get_global_transform_with_canvas().get_scale().x
		var radius := pen_width * 0.5
		draw_arc(_brush_cursor_position, radius, 0, TAU, 96, Color.BLACK, 3.0 * unit, true)
		draw_arc(_brush_cursor_position, radius, 0, TAU, 96, Color.WHITE, 1.0 * unit, true)

func draw_object(object: Dictionary) -> void:
	var extent := dimensions(object)
	draw_set_transform(object.position, object.rotation, object_scale(object))
	if object.kind == "avatar": draw_texture_rect(avatar, Rect2(-extent / 2, extent), false)
	elif object.kind == "text":
		draw_string(CREATIVE_FONT, Vector2(-extent.x / 2, -extent.y / 2 + CREATIVE_FONT.get_ascent(object.font_size)), object.text, HORIZONTAL_ALIGNMENT_LEFT, -1, object.font_size, object.color)
	elif STICKER_TEXTURES.has(object.kind):
		draw_texture_rect(STICKER_TEXTURES[object.kind], Rect2(-extent / 2, extent), false)

func resize_handles(object: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	var half := dimensions(object) / 2
	for direction in HANDLE_DIRECTIONS:
		points.append(transform_for(object) * (half * direction))
	return points

func rotation_arm(object: Dictionary) -> PackedVector2Array:
	var half: Vector2 = dimensions(object) * object_scale(object) / 2
	var unit := 1.0 / scale.x
	var safe_area := Rect2(Vector2.ONE * 12 * unit, size - Vector2.ONE * 24 * unit)
	# Use another side when the top of a layer touches the canvas edge.
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var base: Vector2 = object.position + (half * direction).rotated(object.rotation)
		var tip: Vector2 = base + (direction * 30 * unit).rotated(object.rotation)
		if safe_area.has_point(tip): return PackedVector2Array([base, tip])
	var base: Vector2 = object.position + Vector2(0, -half.y).rotated(object.rotation)
	var tip: Vector2 = base + Vector2(0, minf(30 * unit, half.y)).rotated(object.rotation)
	return PackedVector2Array([base, tip])

func draw_selection(object: Dictionary) -> void:
	var unit := 1.0 / scale.x
	var handles := resize_handles(object)
	var outline := PackedVector2Array([handles[0], handles[2], handles[4], handles[6], handles[0]])
	draw_polyline(outline, SELECTION_COLOR, 1.5 * unit, true)
	var arm := rotation_arm(object)
	draw_line(arm[0], arm[1], SELECTION_COLOR, 1.5 * unit, true)
	for point in handles:
		var rect := Rect2(point - Vector2.ONE * HANDLE_SIZE * unit / 2, Vector2.ONE * HANDLE_SIZE * unit)
		draw_rect(rect, Color.WHITE)
		draw_rect(rect, SELECTION_COLOR, false, 1.5 * unit)
	draw_circle(arm[1], 7 * unit, Color.WHITE)
	draw_arc(arm[1], 7 * unit, 0, TAU, 32, SELECTION_COLOR, 1.5 * unit, true)
	draw_arc(arm[1], 3.5 * unit, -PI * 0.8, PI * 0.65, 16, SELECTION_COLOR, 1.2 * unit, true)

func handle_at(p: Vector2, touch: bool = false) -> int:
	var object := selected_object()
	if object.is_empty(): return -1
	var points := resize_handles(object)
	points.append(rotation_arm(object)[1])
	var nearest := -1
	var distance := (22.0 if touch else 12.0) / scale.x
	for i in range(points.size()):
		var candidate := points[i].distance_to(p)
		if candidate < distance:
			nearest = i
			distance = candidate
	# Preserve a body grab area even for narrow stickers or tiny text.
	if p.distance_to(object.position) < distance: return -1
	return nearest

func update_cursor(p: Vector2) -> void:
	if not selecting:
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		return
	var handle := handle_at(p)
	if handle == ROTATE_HANDLE:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	elif handle >= 0:
		var direction: Vector2 = HANDLE_DIRECTIONS[handle].rotated(selected_object().rotation)
		var sector := posmod(roundi(direction.angle() / (PI / 4)), 4)
		mouse_default_cursor_shape = [Control.CURSOR_HSIZE, Control.CURSOR_FDIAGSIZE, Control.CURSOR_VSIZE, Control.CURSOR_BDIAGSIZE][sector]
	else:
		mouse_default_cursor_shape = Control.CURSOR_MOVE

func selected_object() -> Dictionary:
	for object in state.objects:
		if object.id == state.selected: return object
	return {}

func select_at(p: Vector2) -> void:
	var previous_selection: int = state.selected
	state.selected = -1
	# Strokes are a separate paint layer; objects remain selectable in move mode.
	for i in range(state.objects.size() - 1, -1, -1):
		var object: Dictionary = state.objects[i]
		var local := transform_for(object).affine_inverse() * p
		if Rect2(-dimensions(object) / 2, dimensions(object)).has_point(local):
			state.selected = object.id
			break
	if state.selected != previous_selection:
		AudioHooks.cue("canvas.object.deselect" if state.selected < 0 else "canvas.object.select." + selected_object().kind)
	queue_redraw()
	selection_changed.emit()

func position_inside(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, canvas_size()).has_point(p)

func canvas_size() -> Vector2i:
	return state.pixels.get_size()

func resize_canvas(value: Vector2i) -> void:
	if value.x < MIN_SIZE or value.y < MIN_SIZE or value.x > MAX_SIZE or value.y > MAX_SIZE or value == canvas_size(): return
	finish()
	var prior := snapshot()
	var pixels := Image.create(value.x, value.y, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	pixels.blit_rect(state.pixels, Rect2i(Vector2i.ZERO, canvas_size().min(value)), Vector2i.ZERO)
	state.pixels = pixels
	for object in state.objects: constrain(object)
	record(prior)
	AudioHooks.cue("canvas.resize")

func _gui_input(event: InputEvent) -> void:
	if preview_only: return
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and touch_input_router.is_valid():
		if touch_input_router.call(event, true): accept_event()
		return
	if event is InputEventMouse and event.device == -1: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and pointer == -2: begin(event.position, -1)
		elif not event.pressed and pointer == -1: finish()
		accept_event()
	elif event is InputEventMouseMotion:
		update_cursor(event.position)
	elif event is InputEventScreenTouch:
		if event.canceled:
			if pointer == event.index: cancel()
		elif event.pressed and pointer == -2: begin(event.position, event.index)
		elif not event.pressed and pointer == event.index: finish()
		accept_event()

func _input(event: InputEvent) -> void:
	if preview_only: return
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and touch_input_router.is_valid():
		if touch_input_router.call(event, false): get_viewport().set_input_as_handled()
		return
	if not active: return
	if event is InputEventMouse and event.device == -1: return
	# Continue a captured drag outside the canvas and consume its release.
	if event is InputEventMouseMotion and pointer == -1:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			move_pen(get_global_transform_with_canvas().affine_inverse() * event.position)
		else: finish()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and pointer == -1:
		finish()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and pointer == event.index:
		move_pen(get_global_transform_with_canvas().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and not event.pressed and pointer == event.index:
		if event.canceled: cancel()
		else: finish()
		get_viewport().set_input_as_handled()

func snapshot() -> Dictionary:
	return {"pixels": state.pixels.duplicate(), "objects": state.objects.duplicate(true)}

func begin(p: Vector2, id: int) -> void:
	if active or not position_inside(p): return
	drag_mode = "paint"
	if selecting:
		drag_handle = handle_at(p, id >= 0)
		if drag_handle < 0: select_at(p)
		if selected_object().is_empty(): return
		drag_object = selected_object().duplicate(true)
		drag_mode = "rotate" if drag_handle == ROTATE_HANDLE else "scale" if drag_handle >= 0 else "move"
	drag_start = p
	before = snapshot()
	active = true
	pointer = id
	previous = p
	_drag_audio_key = _drag_audio_id()
	_brush_distance = 0.0
	_brush_speed = 0.0
	if _drag_audio_key == "paint": AudioHooks.param("canvas.drag_speed", 0.0, true)
	AudioHooks.cue("canvas.drag.begin." + _drag_audio_key)
	if not selecting: stamp(p)
	refresh()

func move_pen(p: Vector2) -> void:
	if not active: return
	if drag_mode == "paint" and not position_inside(p):
		# A routed touch may come back, or become a two-finger view gesture.
		# Standalone drawing surfaces still finish as soon as a stroke leaves paper.
		if pointer < 0 or not touch_input_router.is_valid(): finish()
		return
	if drag_mode != "paint":
		var object := selected_object()
		if object.is_empty():
			finish()
			return
		if drag_mode == "move":
			object.position = drag_object.position + p - drag_start
		elif drag_mode == "scale":
			resize_from_handle(object, p)
		elif drag_mode == "rotate":
			var initial: Vector2 = drag_start - drag_object.position
			var current: Vector2 = p - drag_object.position
			if current.length() < 8: return
			object.rotation = wrapf(drag_object.rotation + initial.angle_to(current), -PI, PI)
			object.position = drag_object.position
			set_object_scale(object, object_scale(drag_object))
		constrain(object)
	else:
		var distance := previous.distance_to(p)
		var steps := maxi(1, ceili(distance / maxf(1.0, pen_width / 4.0)))
		for i in range(1, steps + 1): stamp(previous.lerp(p, float(i) / steps))
	if _drag_audio_key == "paint": _brush_distance += previous.distance_to(p)
	previous = p
	refresh()

func resize_from_handle(object: Dictionary, p: Vector2) -> void:
	var direction: Vector2 = HANDLE_DIRECTIONS[drag_handle]
	var initial := object_scale(drag_object)
	var extent := dimensions(drag_object)
	var axis: Vector2 = (extent * direction * initial).rotated(drag_object.rotation)
	var ratio := 1.0 + (p - drag_start).dot(axis) / axis.length_squared()
	var target := initial
	if direction.x == 0:
		target.y = maxf(initial.y * ratio, minf(0.25, initial.y))
	elif direction.y == 0:
		target.x = maxf(initial.x * ratio, minf(0.25, initial.x))
	else:
		# Corners preserve the layer's current aspect ratio, including any stretch.
		var minimum := minf(1.0, maxf(0.25 / initial.x, 0.25 / initial.y))
		target = initial * maxf(ratio, minimum)
	var displacement := (extent * direction * (target - initial) / 2).rotated(drag_object.rotation)
	# Stop at the paper boundary without moving the opposite grip or resizing
	# the other axis. Each corner travels linearly throughout this gesture.
	var fraction := 1.0
	var points := resize_handles(drag_object)
	for i in [0, 2, 4, 6]:
		var delta: Vector2 = displacement + (extent * HANDLE_DIRECTIONS[i] * (target - initial) / 2).rotated(drag_object.rotation)
		for component in [0, 1]:
			if delta[component] > 0.00001:
				fraction = minf(fraction, (canvas_size()[component] - points[i][component]) / delta[component])
			elif delta[component] < -0.00001:
				fraction = minf(fraction, -points[i][component] / delta[component])
	fraction = clampf(fraction, 0, 1)
	set_object_scale(object, initial.lerp(target, fraction))
	object.position = drag_object.position + displacement * fraction

func stamp(p: Vector2) -> void:
	var radius := pen_width * 0.5
	for y in range(maxi(0, floori(p.y - radius)), mini(canvas_size().y, ceili(p.y + radius + 1))):
		for x in range(maxi(0, floori(p.x - radius)), mini(canvas_size().x, ceili(p.x + radius + 1))):
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(p) <= radius * radius:
				state.pixels.set_pixel(x, y, Color.TRANSPARENT if erasing else ink)

func refresh() -> void:
	if not preview_only: size = canvas_size()
	if texture:
		if Vector2i(texture.get_size()) == canvas_size(): texture.update(state.pixels)
		else: texture.set_image(state.pixels)
	queue_redraw()

## "paint" / "erase" for strokes, "<move|scale|rotate>.<kind>" for object drags.
func _drag_audio_id() -> String:
	if drag_mode == "paint": return "erase" if erasing else "paint"
	return "%s.%s" % [drag_mode, drag_object.get("kind", "")]

func record(prior: Dictionary) -> void:
	if prior.objects == state.objects and prior.pixels.get_size() == canvas_size() and prior.pixels.get_data() == state.pixels.get_data(): return
	state.undo.append(prior)
	if state.undo.size() > 20: state.undo.pop_front()
	state.redo.clear()
	state.revision += 1
	refresh()
	changed.emit()

func finish() -> void:
	if not active: return
	AudioHooks.cue("canvas.drag.end." + _drag_audio_key)
	if _drag_audio_key == "paint": AudioHooks.param("canvas.drag_speed", 0.0, true)
	_brush_distance = 0.0
	_brush_speed = 0.0
	_drag_audio_key = ""
	if drag_mode == "paint" and not erasing and before.pixels.get_data() != state.pixels.get_data():
		color_used.emit(ink)
	active = false
	pointer = -2
	drag_mode = ""
	drag_object = {}
	drag_handle = -1
	record(before)
	before = {}

func cancel() -> void:
	# Only restore the current, uncommitted drag; never traverse undo history.
	if not active: return
	AudioHooks.cue("canvas.drag.end." + _drag_audio_key)
	if _drag_audio_key == "paint": AudioHooks.param("canvas.drag_speed", 0.0, true)
	_brush_distance = 0.0
	_brush_speed = 0.0
	_drag_audio_key = ""
	state.pixels = before.pixels
	state.objects = before.objects
	active = false
	pointer = -2
	drag_mode = ""
	drag_object = {}
	drag_handle = -1
	before = {}
	refresh()

func travel(redo: bool) -> void:
	finish()
	var source: Array = state.redo if redo else state.undo
	var destination: Array = state.undo if redo else state.redo
	if source.is_empty(): return
	AudioHooks.cue("canvas.redo" if redo else "canvas.undo")
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
	var extent := canvas_size()
	var scaling := object_scale(object).max(Vector2.ONE * 0.25)
	var d := dimensions(object) * scaling
	var cosine := absf(cos(object.rotation))
	var sine := absf(sin(object.rotation))
	var bounds := Vector2(d.x * cosine + d.y * sine, d.x * sine + d.y * cosine)
	var fit := minf(1.0, minf(extent.x / bounds.x, extent.y / bounds.y))
	set_object_scale(object, scaling * fit)
	var half: Vector2 = bounds * fit / 2
	object.position = Vector2(clampf(object.position.x, half.x, extent.x - half.x), clampf(object.position.y, half.y, extent.y - half.y))

func add_object(kind: String, text: String = "", font_size: int = 32, color: Color = Color("243d35")) -> void:
	if kind != "text" and not STICKER_TEXTURES.has(kind): return
	finish()
	if state.objects.size() >= 25: return
	var prior := snapshot()
	var object := {"id": state.next_id, "kind": kind, "position": Vector2(canvas_size()) / 2, "scale": 1.0, "rotation": 0.0, "text": text, "font_size": font_size, "color": color}
	state.next_id += 1
	state.objects.append(object)
	state.selected = object.id
	constrain(object)
	record(prior)
	AudioHooks.cue("canvas.object.add." + kind)
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
	AudioHooks.cue("canvas.object.edit.text")

func transform_selected(factor: float, angle: float) -> void:
	var object := selected_object()
	if object.is_empty(): return
	finish()
	var prior := snapshot()
	set_object_scale(object, object_scale(object) * factor)
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
	AudioHooks.cue("canvas.object.remove." + str(object.kind))
	selection_changed.emit()

func has_ink() -> bool:
	return not state.pixels.is_invisible()

func has_creation() -> bool:
	return has_creation_in(state)

static func has_creation_in(candidate: Dictionary) -> bool:
	if not candidate.pixels.is_invisible() or candidate.objects.size() > 1: return true
	var person: Dictionary = candidate.objects[0]
	return person.position.distance_to(initial_avatar_position(candidate.pixels.get_size())) > 0.5 or object_scale(person).distance_to(Vector2.ONE) > 0.001 or absf(person.rotation) > 0.001

func artwork() -> Image:
	finish()
	# Use the identical renderer offscreen; omit selection outlines and UI.
	var viewport := SubViewport.new()
	viewport.size = canvas_size()
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var replica = get_script().new()
	replica.state = state
	replica.preview_only = true
	replica.size = canvas_size()
	viewport.add_child(replica)
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	viewport.queue_free()
	return result
