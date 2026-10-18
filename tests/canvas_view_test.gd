extends SceneTree
## Canvas size, view transforms, persistence and rendering without player storage.
const CanvasScene = preload("res://scenes/pages/canvas.tscn")
const Surface = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")
const PreviewScene = preload("res://scenes/components/artwork_preview.tscn")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 900)
	var page = CanvasScene.instantiate()
	page.prepare(Surface.new_state(), -1, "自由创作")
	root.add_child(page)
	await process_frame
	var surface = page.surface
	assert(surface.canvas_size() == Vector2i(1080, 1080))
	assert(surface.size == Vector2(1080, 1080))
	assert(page.canvas_width.value == 1080 and page.canvas_height.value == 1080)
	assert(is_equal_approx(surface.scale.x, 330.0 / 1080))
	var initial_position: Vector2 = surface.position
	var anchor: Vector2 = page.canvas_view.size / 2
	var canvas_point: Vector2 = (anchor - surface.position) / page.view_zoom
	var revision: int = surface.state.revision
	page.get_node("ZoomInButton").pressed.emit()
	assert(((anchor - surface.position) / page.view_zoom).is_equal_approx(canvas_point))
	assert(surface.state.revision == revision and surface.state.undo.is_empty())
	page.get_node("ZoomOutButton").pressed.emit()
	assert(surface.position.is_equal_approx(initial_position))
	page.zoom_at(100, anchor)
	assert(page.view_zoom == 4 and page.get_node("ZoomInButton").disabled)
	page.zoom_at(0.001, anchor)
	assert(page.view_zoom == 0.1 and page.get_node("ZoomOutButton").disabled)
	page.get_node("FitViewButton").pressed.emit()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = page.canvas_view.get_global_transform_with_canvas() * anchor
	var zoom_before: float = page.view_zoom
	root.push_input(wheel, true)
	assert(is_equal_approx(page.view_zoom, zoom_before * 1.25), "Wheel input must zoom exactly once")
	assert(surface.state.revision == revision)
	# Draw through transformed input coordinates at two zoom levels.
	for zoom in [0.5, 2.0]:
		page.zoom_at(zoom, anchor)
		var point := Vector2(600, 560)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = surface.get_global_transform_with_canvas() * point
		root.push_input(press, true)
		await process_frame
		press = press.duplicate()
		press.pressed = false
		root.push_input(press, true)
		await process_frame
		assert(surface.state.pixels.get_pixel(600, 560).a > 0, "Zoomed input missed its artwork coordinates")
	# Pan does not create a drawing edit and fit restores the whole page.
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	page._view_input(middle)
	var pan := InputEventMouseMotion.new()
	pan.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	pan.relative = Vector2(40, 20)
	var before_pan: Vector2 = surface.position
	revision = surface.state.revision
	page._input(pan)
	assert(surface.position.is_equal_approx(before_pan + pan.relative))
	assert(surface.state.revision == revision)
	middle.pressed = false
	page._input(middle)
	assert(not page.view_panning)
	page.fit_view()
	assert(surface.position.is_equal_approx(initial_position))
	surface.begin(Vector2(1079, 1079), -1)
	surface.finish()
	assert(surface.state.pixels.get_pixel(1079, 1079).a > 0)
	var original_pixels: PackedByteArray = surface.state.pixels.get_data()
	page.canvas_width.get_line_edit().text = "1600"
	page.canvas_height.get_line_edit().text = "900"
	page.get_node("CanvasSize/ApplySizeButton").pressed.emit()
	assert(surface.canvas_size() == Vector2i(1600, 900))
	assert(surface.texture.get_size() == Vector2(1600, 900))
	assert(surface.state.pixels.get_pixel(600, 560).a > 0)
	assert(surface.state.pixels.get_pixel(1500, 800).a == 0)
	surface.travel(false)
	assert(surface.canvas_size() == Vector2i(1080, 1080))
	assert(surface.state.pixels.get_data() == original_pixels)
	assert(page.canvas_width.value == 1080 and page.canvas_height.value == 1080)
	surface.travel(true)
	assert(surface.canvas_size() == Vector2i(1600, 900))
	surface.add_object("dufu_greatsword")
	assert(surface.selected_object().position == Vector2(800, 450))
	surface.resize_canvas(Vector2i(512, 512))
	assert(surface.selected_object().position.x < 512)
	surface.travel(false)
	assert(surface.selected_object().is_empty())
	var encoded: Dictionary = Store.encode(surface.state)
	var decoded: Dictionary = Store.decode(encoded)
	assert(decoded.pixels.get_size() == Vector2i(1600, 900))
	assert(Store.encode(decoded) == encoded)
	var legacy := Surface.new_state("paper", Vector2i(1040, 330))
	assert(Store.decode(Store.encode(legacy)).pixels.get_size() == Vector2i(1040, 330))
	var smallest := Surface.new_state("paper", Vector2i(256, 256))
	assert(not Surface.has_creation_in(smallest))
	assert(smallest.objects[0].position.x + 117.5 <= 256 and smallest.objects[0].position.y + 117.5 <= 256)
	var preview = PreviewScene.instantiate()
	preview.size = Vector2(400, 300)
	preview.set_state(decoded)
	root.add_child(preview)
	assert(preview.get_node("DrawingSurface").size == Vector2(1600, 900))
	assert(is_equal_approx(preview.get_node("DrawingSurface").scale.x, 0.25))
	preview.free()
	# Invalid sizes must never mutate a draft.
	revision = surface.state.revision
	for extent in [Vector2i(0, 900), Vector2i(900, 255), Vector2i(2049, 900)]:
		surface.resize_canvas(extent)
	assert(surface.state.revision == revision)
	if DisplayServer.get_name() != "headless":
		page.fit_view()
		var artwork: Image = await surface.artwork()
		assert(artwork.get_size() == Vector2i(1600, 900))
		assert(artwork.get_pixel(600, 560).is_equal_approx(surface.ink))
		var doc := Store.empty_document()
		doc.next_id = 2
		doc.works.append({"id": "work-1", "topic": -1, "title": "测试", "data": encoded, "preview": Marshalls.raw_to_base64(artwork.save_png_to_buffer())})
		assert(Store.validate_document(doc))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/canvas-view-check.png")
	page.free()
	print("CANVAS_VIEW_TESTS_PASSED")
	quit()
