extends Control
## Owns the canvas controls; navigation, dialogs and persistence belong to main.

signal tool_requested(tool: String)
signal width_changed(width: int)
signal color_changed(color: Color)
signal action_requested(action: String)
signal artwork_changed

const Drawing = preload("res://scripts/drawing_surface.gd")
const AudioHooks = preload("res://scripts/audio/audio_hooks.gd")
const TOOL_NAMES = {"ToolBrush": "笔刷", "ToolEraser": "橡皮", "ToolMove": "移动"}
const TOOL_AUDIO_IDS = {"笔刷": "brush", "橡皮": "eraser", "移动": "move"}
const OBJECT_ACTIONS = {
	"EditObjectButton": "编辑",
	"DeleteObjectButton": "删除", "DeselectButton": "取消",
}
const PAGE_ACTIONS = {
	"ChangeTopicButton": "levels", "AddTextButton": "text", "StickerButton": "stickers",
	"ReferenceButton": "reference",
	"RestartButton": "restart", "SubmitButton": "submit",
}
const OBJECT_NAMES = Drawing.Stickers.NAMES

var surface: Drawing
var topic_id := 0
var tool_buttons: Dictionary = {}
var object_buttons: Dictionary = {}
var view_zoom := 1.0
var view_panning := false
var fitted_size := Vector2i.ZERO
var _touch_points: Dictionary = {}
var _touch_navigating := false
var _touch_selection := -1
const MIN_ZOOM = 0.1
const MAX_ZOOM = 4.0

@onready var palette = $ColorPalette
@onready var width_label: Label = $WidthLabel
@onready var width_slider: HSlider = $WidthSlider
@onready var undo_button: Button = $UndoButton
@onready var redo_button: Button = $RedoButton
@onready var drawing_status: Label = $DrawingStatus
@onready var canvas_view: Control = $CanvasView
@onready var canvas_width: SpinBox = $CanvasSize/CanvasWidth
@onready var canvas_height: SpinBox = $CanvasSize/CanvasHeight
@onready var zoom_label: Label = $ZoomLabel

func prepare(state: Dictionary, id: int, prompt: String) -> void:
	# Set the session before DrawingSurface._ready creates its image texture.
	surface = get_node("CanvasView/DrawingSurface")
	surface.state = state
	topic_id = id
	get_node("TopicPrompt").text = prompt

func _ready() -> void:
	if surface == null: surface = $CanvasView/DrawingSurface
	palette.color_changed.connect(func(color: Color): color_changed.emit(color))
	for node_name in TOOL_NAMES:
		var tool: String = TOOL_NAMES[node_name]
		var button := get_node(node_name) as Button
		tool_buttons[tool] = button
		button.pressed.connect(_request_tool.bind(tool))
	for node_name in OBJECT_ACTIONS:
		var action: String = OBJECT_ACTIONS[node_name]
		var button := get_node(node_name) as Button
		object_buttons[action] = button
		button.pressed.connect(object_action.bind(action))
	for node_name in PAGE_ACTIONS:
		var button := get_node(node_name) as Button
		button.pressed.connect(_request_action.bind(PAGE_ACTIONS[node_name]))
	width_slider.value_changed.connect(_on_width_changed)
	undo_button.pressed.connect(surface.travel.bind(false))
	redo_button.pressed.connect(surface.travel.bind(true))
	surface.changed.connect(_on_artwork_changed)
	surface.selection_changed.connect(update_controls)
	$CanvasSize/ApplySizeButton.pressed.connect(apply_canvas_size)
	$ZoomOutButton.pressed.connect(func(): zoom_at(view_zoom / 1.25, canvas_view.size / 2))
	$ZoomInButton.pressed.connect(func(): zoom_at(view_zoom * 1.25, canvas_view.size / 2))
	$FitViewButton.pressed.connect(fit_view)
	canvas_view.gui_input.connect(_view_input)
	surface.gui_input.connect(_view_input.bind(true))
	surface.touch_input_router = _route_surface_touch
	canvas_view.resized.connect(fit_view)
	get_window().focus_exited.connect(cancel_touch_navigation)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): cancel_touch_navigation())
	fit_view()
	var tool := "移动" if surface.selecting else "橡皮" if surface.erasing else "笔刷"
	refresh_tools(tool, surface.ink, surface.pen_width)

func refresh_tools(tool: String, color: Color, width: int) -> void:
	surface.finish()
	surface.erasing = tool == "橡皮"
	surface.selecting = tool == "移动"
	AudioHooks.fact("tool", TOOL_AUDIO_IDS.get(tool, ""))
	surface.ink = color
	surface.pen_width = width
	surface.mouse_default_cursor_shape = Control.CURSOR_MOVE if surface.selecting else Control.CURSOR_CROSS
	for name in tool_buttons:
		tool_buttons[name].set_pressed_no_signal(name == tool)
	width_slider.set_value_no_signal(width)
	width_label.text = "粗细  %d" % width
	palette.set_color(color)
	surface.queue_redraw()
	update_controls()

func update_controls() -> void:
	var state := surface.state
	if fitted_size != surface.canvas_size(): fit_view()
	undo_button.disabled = state.undo.is_empty()
	redo_button.disabled = state.redo.is_empty()
	var object: Dictionary = surface.selected_object() if surface.selecting else {}
	for action in object_buttons:
		object_buttons[action].disabled = object.is_empty()
	object_buttons["编辑"].disabled = object.is_empty() or object.kind != "text"
	object_buttons["删除"].disabled = object.is_empty() or object.kind == "avatar"
	drawing_status.text = "点击图层进行移动、缩放或旋转" if surface.selecting else "橡皮" if surface.erasing else "画笔"
	if not object.is_empty(): drawing_status.text = "已选中：" + OBJECT_NAMES[object.kind] + " · 拖动移动，边柄拉伸，角柄等比缩放，圆柄旋转"
	print("DRAW_STATE:", topic_id, ":", state.revision, ":", surface.has_creation(), ":", state.undo.size(), ":", state.redo.size())
	print("OBJECT_STATE:", state.objects.size(), ":", state.selected)

func object_action(action: String) -> void:
	match action:
		"编辑": action_requested.emit("edit_text")
		"删除": surface.remove_selected()
		"取消":
			surface.finish()
			surface.state.selected = -1
			surface.queue_redraw()
			update_controls()

func _request_tool(tool: String) -> void:
	tool_requested.emit(tool)

func _request_action(action: String) -> void:
	action_requested.emit(action)

func _on_width_changed(value: float) -> void:
	var width := int(value)
	surface.pen_width = width
	width_label.text = "粗细  %d" % width
	print("DRAW_WIDTH:", width)
	width_changed.emit(width)

func _on_artwork_changed() -> void:
	update_controls()
	artwork_changed.emit()

func apply_canvas_size() -> void:
	canvas_width.apply()
	canvas_height.apply()
	surface.resize_canvas(Vector2i(int(canvas_width.value), int(canvas_height.value)))

func fit_view() -> void:
	if not is_node_ready(): return
	cancel_touch_navigation()
	surface.finish()
	fitted_size = surface.canvas_size()
	canvas_width.set_value_no_signal(fitted_size.x)
	canvas_height.set_value_no_signal(fitted_size.y)
	view_zoom = clampf(minf(canvas_view.size.x / fitted_size.x, canvas_view.size.y / fitted_size.y), MIN_ZOOM, MAX_ZOOM)
	surface.scale = Vector2.ONE * view_zoom
	surface.position = (canvas_view.size - Vector2(fitted_size) * view_zoom) / 2
	_update_view_controls()

func zoom_at(value: float, anchor: Vector2) -> void:
	surface.finish()
	var artwork_point := (anchor - surface.position) / view_zoom
	view_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	surface.scale = Vector2.ONE * view_zoom
	surface.position = anchor - artwork_point * view_zoom
	_clamp_view()
	_update_view_controls()

func _clamp_view() -> void:
	# Keep a small part of the paper reachable even after a long pan.
	var extent := Vector2(surface.canvas_size()) * view_zoom
	surface.position = surface.position.clamp(Vector2.ONE * 48 - extent, canvas_view.size - Vector2.ONE * 48)

func _update_view_controls() -> void:
	zoom_label.text = "%d%%" % roundi(view_zoom * 100)
	AudioHooks.param("canvas.zoom", view_zoom)
	$ZoomOutButton.disabled = view_zoom <= MIN_ZOOM
	$ZoomInButton.disabled = view_zoom >= MAX_ZOOM
	surface.queue_redraw()

func _view_input(event: InputEvent, from_surface: bool = false) -> void:
	if event is InputEventMouse and event.device == -1: return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		# Surface's own GUI callback supplies its transform. Empty view margins
		# also accept gestures, with the view's local coordinates instead.
		if not from_surface and _route_touch_event(event.xformed_by(canvas_view.get_global_transform_with_canvas()), true):
			accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			surface.finish()
			view_panning = event.pressed
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var factor := 1.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8
			zoom_at(view_zoom * factor, canvas_view.get_local_mouse_position())
			accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_at(view_zoom * event.factor, canvas_view.get_local_mouse_position())
		accept_event()

func _input(event: InputEvent) -> void:
	if not view_panning: return
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			surface.position += canvas_view.get_global_transform_with_canvas().basis_xform_inv(event.relative)
			_clamp_view()
		else: view_panning = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		view_panning = false
		get_viewport().set_input_as_handled()

func _route_surface_touch(event: InputEvent, from_gui: bool) -> bool:
	var global_event := event.xformed_by(surface.get_global_transform_with_canvas()) if from_gui else event
	return _route_touch_event(global_event, from_gui)

func _route_touch_event(event: InputEvent, from_gui: bool) -> bool:
	if not is_visible_in_tree(): return false
	var point: Vector2 = canvas_view.get_global_transform_with_canvas().affine_inverse() * event.position
	if event is InputEventScreenTouch:
		if event.canceled:
			if not _touch_points.has(event.index): return false
			cancel_touch_navigation()
			return true
		if event.pressed:
			# A new finger must pass the normal GUI hit test, so dialogs and
			# controls over the canvas keep their input and do not mark the paper.
			if not from_gui or not Rect2(Vector2.ZERO, canvas_view.size).has_point(point): return false
			if _touch_points.has(event.index): return true
			_touch_points[event.index] = point
			if _touch_points.size() == 1:
				_touch_selection = surface.state.selected
				surface.begin((point - surface.position) / view_zoom, event.index)
			elif not _touch_navigating:
				surface.cancel()
				surface.state.selected = _touch_selection
				surface.selection_changed.emit()
				_touch_navigating = true
			return true
		if not _touch_points.has(event.index): return false
		_touch_points.erase(event.index)
		if not _touch_navigating and surface.pointer == event.index: surface.finish()
		if _touch_points.is_empty(): _touch_navigating = false
		return true
	if event is InputEventScreenDrag and _touch_points.has(event.index):
		if _touch_navigating and _touch_points.size() >= 2:
			var indices := _touch_points.keys()
			var first: Vector2 = _touch_points[indices[0]]
			var second: Vector2 = _touch_points[indices[1]]
			var old_center := (first + second) / 2
			var old_distance := first.distance_to(second)
			_touch_points[event.index] = point
			first = _touch_points[indices[0]]
			second = _touch_points[indices[1]]
			var artwork_anchor := (old_center - surface.position) / view_zoom
			if old_distance > 1.0:
				view_zoom = clampf(view_zoom * first.distance_to(second) / old_distance, MIN_ZOOM, MAX_ZOOM)
			surface.scale = Vector2.ONE * view_zoom
			surface.position = (first + second) / 2 - artwork_anchor * view_zoom
			_clamp_view()
			_update_view_controls()
		else:
			_touch_points[event.index] = point
			# After a pinch, the remaining finger cannot start drawing until all
			# fingers lift. That prevents a stray stroke at the end of a gesture.
			if not _touch_navigating and surface.pointer == event.index:
				surface.move_pen((point - surface.position) / view_zoom)
		return true
	return false

func cancel_touch_navigation() -> void:
	view_panning = false
	if is_instance_valid(surface) and surface.pointer >= 0:
		surface.cancel()
	_touch_points.clear()
	_touch_navigating = false

func _exit_tree() -> void:
	cancel_touch_navigation()
