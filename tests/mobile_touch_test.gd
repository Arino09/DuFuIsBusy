extends SceneTree
## Feed real touch events through GUI hit testing and capture, without player storage.
const CanvasScene = preload("res://scenes/pages/canvas.tscn")
const Surface = preload("res://scripts/drawing_surface.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func touch(index: int, point: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = root.get_final_transform() * point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, false)

func drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = root.get_final_transform() * point
	root.push_input(event, false)

func at_view(page: Control, point: Vector2) -> Vector2:
	return page.canvas_view.get_global_transform_with_canvas() * point

func at_artwork(page: Control, point: Vector2) -> Vector2:
	return page.surface.get_global_transform_with_canvas() * point

func verify_touch(page: Control) -> void:
	var surface = page.surface
	var center: Vector2 = page.canvas_view.size / 2
	var artwork_point := Vector2(600, 600)
	var down := at_artwork(page, artwork_point)
	touch(0, down, true)
	check(surface.active and surface.pointer == 0, "First touch did not begin a stroke")
	drag(0, at_artwork(page, artwork_point + Vector2(40, 0)))
	touch(0, at_artwork(page, artwork_point + Vector2(40, 0)), false)
	check(not surface.active and surface.pointer == -2, "Touch release left an active pointer")
	check(surface.state.pixels.get_pixel(620, 600).a > 0, "Touch coordinates missed the artwork")
	check(surface.state.revision == 1 and surface.state.undo.size() == 1, "Single touch must create one edit")

	var saved_pixels: PackedByteArray = surface.state.pixels.get_data()
	var revision: int = surface.state.revision
	var first: Vector2 = center - Vector2(45, 0)
	var second: Vector2 = center + Vector2(45, 0)
	touch(1, at_view(page, first), true)
	drag(1, at_view(page, first + Vector2(0, 8)))
	first += Vector2(0, 8)
	touch(2, at_view(page, second), true)
	check(not surface.active and surface.pointer == -2, "Second finger must end the drawing transaction")
	check(surface.state.pixels.get_data() == saved_pixels, "Pinch retained marks from the first finger")
	check(surface.state.revision == revision and surface.state.undo.size() == 1, "Pinch changed drawing history")
	var initial_zoom: float = page.view_zoom
	var initial_distance := first.distance_to(second)
	var anchor: Vector2 = ((first + second) / 2 - surface.position) / initial_zoom
	second += Vector2(40, 12)
	drag(2, at_view(page, second))
	check(is_equal_approx(page.view_zoom, initial_zoom * first.distance_to(second) / initial_distance), "Pinch distance did not control zoom")
	check((((first + second) / 2 - surface.position) / page.view_zoom).is_equal_approx(anchor), "Pinch moved the artwork away from its midpoint anchor")
	var position_before: Vector2 = surface.position
	var zoom_before: float = page.view_zoom
	var pan := Vector2(12, 18)
	first += pan
	second += pan
	drag(1, at_view(page, first))
	drag(2, at_view(page, second))
	check(is_equal_approx(page.view_zoom, zoom_before), "Two-finger pan changed the zoom")
	check(surface.position.is_equal_approx(position_before + pan), "Two-finger pan missed its displacement")
	touch(2, at_view(page, second), false)
	drag(1, at_view(page, first + Vector2(40, 20)))
	touch(1, at_view(page, first + Vector2(40, 20)), false)
	check(surface.state.pixels.get_data() == saved_pixels and surface.state.revision == revision, "Remaining finger drew at the end of a pinch")
	check(not surface.active and page._touch_points.is_empty(), "Gesture release left captured touches")
	# Additional fingers are tracked without changing the active pair's view.
	touch(10, at_view(page, center - Vector2(45, 0)), true)
	touch(11, at_view(page, center + Vector2(45, 0)), true)
	position_before = surface.position
	zoom_before = page.view_zoom
	touch(12, at_view(page, center), true)
	drag(12, at_view(page, center + Vector2(20, 20)))
	check(surface.position.is_equal_approx(position_before) and is_equal_approx(page.view_zoom, zoom_before), "Third finger jumped the viewport")
	touch(10, at_view(page, center - Vector2(45, 0)), false)
	drag(12, at_view(page, center + Vector2(30, 20)))
	touch(11, at_view(page, center + Vector2(45, 0)), false)
	touch(12, at_view(page, center + Vector2(30, 20)), false)
	check(surface.state.pixels.get_data() == saved_pixels and surface.state.revision == revision, "Three-finger transition marked the artwork")

	# Cancel discards only the in-progress stroke and preserves earlier artwork.
	page.fit_view()
	touch(3, at_artwork(page, Vector2(800, 800)), true)
	drag(3, at_artwork(page, Vector2(850, 800)))
	surface.mouse_exited.emit()
	check(surface.active and surface.state.revision == revision, "Emulated mouse exit prematurely committed a touch")
	touch(3, at_artwork(page, Vector2(850, 800)), false, true)
	check(surface.state.pixels.get_data() == saved_pixels and surface.state.revision == revision, "Canceled touch changed existing artwork/history")
	check(not surface.active and surface.pointer == -2 and page._touch_points.is_empty(), "Canceled touch retained capture")

	# Starting a pinch while moving an object must restore that pending move.
	surface.selecting = true
	surface.state.selected = -1
	var objects: Array = surface.state.objects.duplicate(true)
	var object_point: Vector2 = objects[0].position
	touch(4, at_artwork(page, object_point), true)
	drag(4, at_artwork(page, object_point + Vector2(80, 50)))
	check(surface.state.objects != objects, "Single touch did not move an editable object")
	touch(5, at_view(page, center), true)
	check(surface.state.objects == objects and surface.state.selected == -1, "Pinch retained a pending object move or selection")
	touch(5, at_view(page, center), false)
	touch(4, at_artwork(page, object_point), false)
	check(surface.state.revision == revision, "Canceled object drag changed undo history")
	surface.selecting = false

	# Synthetic mouse events generated from touch must not duplicate marks.
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.device = -1
	mouse.position = at_artwork(page, Vector2(750, 750))
	mouse.pressed = true
	root.push_input(mouse, true)
	mouse = mouse.duplicate()
	mouse.pressed = false
	root.push_input(mouse, true)
	check(surface.state.revision == revision and not surface.active, "Emulated mouse generated a duplicate edit")

	# Focus changes, hiding the page, and orientation changes release captures.
	touch(6, at_artwork(page, Vector2(700, 700)), true)
	root.focus_exited.emit()
	check(not surface.active and surface.pointer == -2 and page._touch_points.is_empty(), "Focus loss retained touch capture")
	touch(7, at_artwork(page, Vector2(700, 700)), true)
	page.hide()
	check(not surface.active and page._touch_points.is_empty(), "Hidden page retained touch capture")
	page.show()
	touch(8, at_artwork(page, Vector2(700, 700)), true)
	page.fit_view()
	check(not surface.active and page._touch_points.is_empty(), "View refit retained touch capture")
	check(surface.state.pixels.get_data() == saved_pixels, "Interrupted navigation damaged earlier artwork")

	# A covering Control must intercept a new touch before canvas capture begins.
	var shade := Control.new()
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.position = page.canvas_view.position
	shade.size = page.canvas_view.size
	page.add_child(shade)
	touch(9, at_view(page, center), true)
	touch(9, at_view(page, center), false)
	check(not surface.active and page._touch_points.is_empty(), "Touch passed through a modal shade")
	shade.free()
	check(surface.state.revision == revision, "View-only operations changed the artwork revision")
	# A completed one-finger object move is still a normal undoable artwork edit.
	surface.selecting = true
	touch(13, at_artwork(page, object_point), true)
	drag(13, at_artwork(page, object_point + Vector2(60, 40)))
	touch(13, at_artwork(page, object_point + Vector2(60, 40)), false)
	check(surface.state.objects[0].position.is_equal_approx(object_point + Vector2(60, 40)), "Completed touch object move was lost")
	check(surface.state.revision == revision + 1 and not surface.active, "Completed object move must create one edit")
	surface.selecting = false
	touch(14, at_artwork(page, Vector2(700, 700)), true)
	root.remove_child(page)
	check(surface.pointer == -2 and not surface.active and page._touch_points.is_empty(), "Page removal retained a touch pointer")

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for extent in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(768, 1024)]:
		root.size = extent
		var page = CanvasScene.instantiate()
		page.prepare(Surface.new_state(), -1, "触控测试")
		root.add_child(page)
		# Isolate the canvas input surface; page layout has its own integration test.
		for child in page.get_children():
			if child is Control and child.name != "CanvasView": child.hide()
		page.canvas_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
		page.canvas_view.position = Vector2(16, 16)
		page.canvas_view.size = Vector2(extent) - Vector2(32, 32)
		await process_frame
		page.fit_view()
		verify_touch(page)
		page.free()
		await process_frame
	if not failures.is_empty():
		printerr("MOBILE_TOUCH_TESTS_FAILED: %d checks" % failures.size())
		quit(1)
		return
	print("MOBILE_TOUCH_TESTS_PASSED")
	quit()
