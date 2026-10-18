extends SceneTree
## Handle gestures use the same history and serialization for every editable layer.
const CanvasScene = preload("res://scenes/pages/canvas.tscn")
const Surface = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")

func _initialize() -> void:
	call_deferred("run")

func assert_contained(surface, object: Dictionary) -> void:
	for point in surface.resize_handles(object):
		assert(point.x >= -0.01 and point.x <= Surface.WIDTH + 0.01)
		assert(point.y >= -0.01 and point.y <= Surface.HEIGHT + 0.01)
	assert(surface.position_inside(surface.rotation_arm(object)[1]))

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 900)
	var page = CanvasScene.instantiate()
	page.prepare(Surface.new_state(), 0, "")
	root.add_child(page)
	page.refresh_tools("移动", Color.BLACK, 8)
	var surface = page.surface
	for button in ["ShrinkButton", "GrowButton", "RotateLeftButton", "RotateRightButton"]:
		assert(not page.has_node(button), "Transform toolbar buttons must be removed")
	for kind in ["avatar", "text", "dufu_greatsword", "dufu_cyber_mantis_blade", "dufu_longsword", "dufu_cyber_long_blade", "dufu_cyber_greatsword"]:
		if kind == "avatar": surface.select_at(Surface.DEFAULT_POSITION)
		else: surface.add_object(kind, "杜甫很忙")
		var object: Dictionary = surface.selected_object()
		object.position = Vector2(520, 165)
		surface.set_object_scale(object, Vector2(0.65, 0.85))
		var revision: int = surface.state.revision
		var pixels = surface.state.pixels.get_data()
		# A click alone does not dirty artwork; body drag creates one undo entry.
		surface.begin(object.position, -1)
		surface.finish()
		assert(surface.state.revision == revision)
		surface.begin(object.position, -1)
		surface.move_pen(Vector2(535, 165))
		surface.move_pen(Vector2(550, 165))
		surface.finish()
		assert(object.position.is_equal_approx(Vector2(550, 165)))
		assert(surface.state.revision == revision + 1)
		# Edges stretch one local axis; corners preserve an already stretched ratio.
		for rotation in [0.0, 0.35]:
			object.rotation = rotation
			for handle in range(8):
				var original: Dictionary = object.duplicate(true)
				var expected: Vector2 = surface.object_scale(original)
				var direction: Vector2 = Surface.HANDLE_DIRECTIONS[handle]
				if direction.x != 0: expected.x *= 1.1
				if direction.y != 0: expected.y *= 1.1
				var points = surface.resize_handles(object)
				var start: Vector2 = points[handle]
				var opposite: Vector2 = points[(handle + 4) % 8]
				surface.begin(start, -1)
				assert(surface.drag_mode == "scale")
				surface.move_pen(start + (start - opposite) * 0.1)
				surface.finish()
				assert(surface.object_scale(object).is_equal_approx(expected))
				assert(surface.resize_handles(object)[(handle + 4) % 8].is_equal_approx(opposite))
				surface.travel(false)
				surface.state.selected = original.id
				object = surface.selected_object()
				assert(object == original)
				surface.travel(true)
				surface.state.selected = original.id
				assert(surface.object_scale(surface.selected_object()).is_equal_approx(expected))
				surface.travel(false)
				surface.state.selected = original.id
				object = surface.selected_object()
		# Touch rotation applies equally to Dufu, text, and stickers.
		var start: Vector2 = surface.rotation_arm(object)[1]
		var center: Vector2 = object.position
		var old_rotation: float = object.rotation
		var undo_count: int = surface.state.undo.size()
		revision = surface.state.revision
		surface.begin(start, 3)
		assert(surface.drag_mode == "rotate")
		surface.move_pen(center + (start - center).rotated(PI / 6))
		surface.move_pen(center + (start - center).rotated(PI / 3))
		surface.finish()
		assert(is_equal_approx(object.rotation, old_rotation + PI / 3))
		assert(surface.state.revision == revision + 1)
		assert(surface.state.undo.size() == mini(20, undo_count + 1))
		assert(surface.state.pixels.get_data() == pixels)
		assert_contained(surface, object)
		var loaded: Dictionary = Store.decode(Store.encode(surface.state))
		assert(not loaded.is_empty())
		assert(is_equal_approx(loaded.objects[-1].rotation, object.rotation))
		assert(surface.object_scale(loaded.objects[-1]).is_equal_approx(surface.object_scale(object)))
		# Dragging through the opposite grip clamps size instead of flipping the layer.
		var grips = surface.resize_handles(object)
		surface.begin(grips[4], -1)
		surface.move_pen(grips[4] - (grips[4] - grips[0]) * 2)
		surface.finish()
		assert(is_equal_approx(object.scale, 0.25))
		assert_contained(surface, object)
	# Every grip can grow beyond the old 2x cap, preserving axis/ratio semantics.
	for kind in ["avatar", "text", "dufu_greatsword", "dufu_longsword"]:
		for handle in range(8):
			surface.state = Surface.new_state()
			if kind == "avatar": surface.state.selected = 0
			else: surface.add_object(kind, "杜甫")
			var enlarged: Dictionary = surface.selected_object()
			enlarged.position = Vector2(540, 540)
			surface.set_object_scale(enlarged, Vector2.ONE * 0.8)
			var original: Dictionary = enlarged.duplicate(true)
			var points = surface.resize_handles(enlarged)
			var direction: Vector2 = Surface.HANDLE_DIRECTIONS[handle]
			var expected := Vector2(2.4 if direction.x != 0 else 0.8, 2.4 if direction.y != 0 else 0.8)
			var opposite: Vector2 = points[(handle + 4) % 8]
			surface.begin(points[handle], -1)
			surface.move_pen(points[handle] + (points[handle] - opposite) * 2)
			surface.finish()
			assert(surface.object_scale(enlarged).is_equal_approx(expected))
			assert(surface.resize_handles(enlarged)[(handle + 4) % 8].is_equal_approx(opposite))
			var loaded: Dictionary = Store.decode(Store.encode(surface.state))
			assert(not loaded.is_empty() and surface.object_scale(loaded.objects[-1]).is_equal_approx(expected))
			surface.travel(false)
			surface.state.selected = original.id
			assert(surface.selected_object() == original)
			surface.travel(true)
			surface.state.selected = original.id
			enlarged = surface.selected_object()
			# Moving an enlarged layer must not silently shrink it again.
			surface.begin(enlarged.position, -1)
			surface.move_pen(enlarged.position + Vector2(10, 10))
			surface.finish()
			assert(surface.object_scale(enlarged).is_equal_approx(expected))
			assert_contained(surface, enlarged)
	# A side grip stops at the paper edge with its opposite edge and height fixed.
	surface.state = Surface.new_state()
	surface.state.selected = 0
	var stretched: Dictionary = surface.selected_object()
	stretched.position = Vector2(900, 500)
	surface.set_object_scale(stretched, Vector2(0.65, 0.85))
	var edge_points = surface.resize_handles(stretched)
	surface.begin(edge_points[3], -1)
	surface.move_pen(edge_points[3] + Vector2(2000, 100))
	surface.finish()
	assert(is_equal_approx(surface.object_scale(stretched).y, 0.85))
	assert(surface.resize_handles(stretched)[7].is_equal_approx(edge_points[7]))
	assert(is_equal_approx(surface.resize_handles(stretched)[3].x, surface.canvas_size().x))
	assert_contained(surface, stretched)
	# Selected handles win even when another layer covers that position.
	surface.state = Surface.new_state()
	surface.select_at(Surface.DEFAULT_POSITION)
	var corner: Vector2 = surface.resize_handles(surface.selected_object())[2]
	surface.add_object("text", "覆盖手柄")
	surface.selected_object().position = corner
	surface.state.selected = 0
	surface.begin(corner, -1)
	assert(surface.state.selected == 0 and surface.drag_mode == "scale")
	surface.finish()
	await process_frame
	# Route real viewport mouse events, including capture beyond the canvas.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = surface.get_global_transform_with_canvas() * Surface.DEFAULT_POSITION
	root.push_input(press, true)
	assert(surface.active and surface.pointer == -1)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = surface.get_global_transform_with_canvas() * Vector2(1300, 500)
	root.push_input(motion, true)
	assert(surface.active)
	assert_contained(surface, surface.selected_object())
	motion.position = surface.get_global_transform_with_canvas() * Vector2(600, 165)
	root.push_input(motion, true)
	assert(surface.selected_object().position.is_equal_approx(Vector2(600, 165)))
	press.pressed = false
	press.position = surface.get_global_transform_with_canvas() * Vector2(1300, 500)
	root.push_input(press, true)
	assert(not surface.active and surface.pointer == -2)
	# Other fingers cannot steal a touch drag or terminate it.
	var touch := InputEventScreenTouch.new()
	touch.index = 2
	touch.pressed = true
	touch.position = surface.get_global_transform_with_canvas() * Vector2(600, 165)
	root.push_input(touch, true)
	assert(surface.active and surface.pointer == 2)
	var drag := InputEventScreenDrag.new()
	drag.index = 4
	drag.position = surface.get_global_transform_with_canvas() * Vector2(900, 165)
	root.push_input(drag, true)
	assert(surface.selected_object().position.is_equal_approx(Vector2(600, 165)))
	drag.index = 2
	root.push_input(drag, true)
	assert(surface.selected_object().position.is_equal_approx(Vector2(900, 165)))
	touch.pressed = false
	touch.index = 4
	root.push_input(touch, true)
	assert(surface.active)
	touch.index = 2
	root.push_input(touch, true)
	assert(not surface.active)
	# Tool changes finish ongoing transforms and leave brush behavior intact.
	surface.begin(Vector2(900, 165), -1)
	surface.move_pen(Vector2(800, 165))
	page.refresh_tools("笔刷", Color.BLACK, 8)
	assert(not surface.active)
	surface.begin(Vector2(500, 165), -1)
	surface.move_pen(Vector2(530, 165))
	surface.finish()
	assert(surface.has_ink())
	page.queue_free()
	await process_frame
	print("AVATAR_ROTATION_TESTS_PASSED")
	quit()
