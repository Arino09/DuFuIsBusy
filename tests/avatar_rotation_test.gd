extends SceneTree
## Handle gestures use the same history and serialization for every editable layer.
const CanvasScene = preload("res://scenes/pages/canvas.tscn")
const Surface = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")

func _initialize() -> void:
	call_deferred("run")

func assert_valid_transform(surface, object: Dictionary) -> void:
	for point in surface.resize_handles(object):
		assert(is_finite(point.x) and is_finite(point.y))
	var value: Vector2 = surface.object_scale(object)
	assert(value.is_finite() and value.x != 0.0 and value.y != 0.0)
	var inverse: Transform2D = surface.transform_for(object).affine_inverse()
	assert(inverse.x.is_finite() and inverse.y.is_finite() and inverse.origin.is_finite())

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
		assert_valid_transform(surface, object)
		var loaded: Dictionary = Store.decode(Store.encode(surface.state))
		assert(not loaded.is_empty())
		assert(is_equal_approx(loaded.objects[-1].rotation, object.rotation))
		assert(surface.object_scale(loaded.objects[-1]).is_equal_approx(surface.object_scale(object)))
		# Dragging a corner through the opposite grip reverses both signed axes.
		var grips = surface.resize_handles(object)
		var previous_scale: Vector2 = surface.object_scale(object)
		surface.begin(grips[4], -1)
		surface.move_pen(grips[4] - (grips[4] - grips[0]) * 2)
		surface.finish()
		assert(surface.object_scale(object).is_equal_approx(-previous_scale))
		assert(surface.resize_handles(object)[0].is_equal_approx(grips[0]))
		assert_valid_transform(surface, object)
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
			assert_valid_transform(surface, enlarged)
	# A side grip crosses the paper edge with its opposite edge and height fixed.
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
	assert(surface.resize_handles(stretched)[3].x > surface.canvas_size().x)
	assert_valid_transform(surface, stretched)
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
	assert_valid_transform(surface, surface.selected_object())
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
	test_mirrored_handles(surface)
	test_small_scale_history(surface)
	page.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless": await test_mirror_rendering()
	print("AVATAR_ROTATION_TESTS_PASSED")
	quit()

func test_mirrored_handles(surface) -> void:
	surface.selecting = true
	for initial in [Vector2(1.2, 0.8), Vector2(-1.2, 0.8), Vector2(1.2, -0.8), Vector2(-1.2, -0.8)]:
		for rotation in [0.0, 0.35]:
			for handle in range(8):
				surface.state = Surface.new_state()
				surface.add_object("dufu_greatsword")
				var object: Dictionary = surface.selected_object()
				object.position = Vector2(540, 540)
				object.rotation = rotation
				# Menu mirrors compose with signed scales and remain in old saves.
				object.flip_h = true
				surface.set_object_scale(object, initial)
				var original: Dictionary = object.duplicate(true)
				var handles = surface.resize_handles(object)
				var start: Vector2 = handles[handle]
				var opposite: Vector2 = handles[(handle + 4) % 8]
				var direction: Vector2 = Surface.HANDLE_DIRECTIONS[handle]
				var expected: Vector2 = initial * Vector2(-1 if direction.x != 0 else 1, -1 if direction.y != 0 else 1)
				var revision: int = surface.state.revision
				surface.begin(start, -1 if handle % 2 else 3)
				assert(surface.drag_mode == "scale" and surface.drag_handle == handle)
				# Passing zero in either direction must retain a usable, anchored transform.
				for ratio in [0.0, -0.001, -0.01, -1.0, 0.001, 0.01, 1.0, -1.0]:
					surface.move_pen(start + (start - opposite) * (ratio - 1.0))
					assert_valid_transform(surface, object)
					assert(surface.resize_handles(object)[(handle + 4) % 8].is_equal_approx(opposite))
					var actual: Vector2 = surface.object_scale(object)
					if ratio == 0.0:
						# The singular point gets only a subpixel numerical guard.
						if direction.x != 0: assert(absf(actual.x) <= 0.0002)
						if direction.y != 0: assert(absf(actual.y) <= 0.0002)
					else:
						var expected_small: Vector2 = initial * Vector2(ratio if direction.x != 0 else 1.0, ratio if direction.y != 0 else 1.0)
						assert(actual.is_equal_approx(expected_small), "Crossing zero must not clamp small positive or negative scales")
				surface.finish()
				assert(surface.object_scale(object).is_equal_approx(expected))
				assert(surface.state.revision == revision + 1)
				assert(surface.rotation_arm(object)[1].distance_to(object.position) > 0)
				# Selection uses the mirrored transform, including points away from the center.
				var inside: Vector2 = surface.transform_for(object) * (surface.dimensions(object) * Vector2(0.2, 0.1))
				surface.select_at(inside)
				assert(surface.state.selected == object.id)
				var loaded := Store.decode(Store.encode(surface.state))
				assert(not loaded.is_empty() and surface.object_scale(loaded.objects[-1]).is_equal_approx(expected))
				surface.travel(false)
				surface.select_object(original.id)
				assert(surface.selected_object() == original)
				surface.travel(true)
				surface.select_object(original.id)
				object = surface.selected_object()
				# Mirroring survives later movement and can be canceled during another resize.
				surface.begin(object.position, -1)
				surface.move_pen(object.position + Vector2(10, 10))
				surface.finish()
				assert(surface.object_scale(object).is_equal_approx(expected))
				var mirrored: Dictionary = object.duplicate(true)
				handles = surface.resize_handles(object)
				surface.begin(handles[handle], -1)
				surface.move_pen(handles[handle] + (handles[handle] - handles[(handle + 4) % 8]))
				surface.cancel()
				assert(surface.selected_object() == mirrored)

func test_small_scale_history(surface) -> void:
	surface.selecting = true
	for pointer_id in [-1, 3]:
		for ratio in [0.01, -0.001]:
			for handle in range(8):
				surface.state = Surface.new_state()
				surface.add_object("dufu_greatsword")
				var object: Dictionary = surface.selected_object()
				object.position = Vector2(540, 540)
				object.rotation = 0.35
				surface.set_object_scale(object, Vector2(1.2, 0.8))
				var original: Dictionary = object.duplicate(true)
				var grips = surface.resize_handles(object)
				var direction: Vector2 = Surface.HANDLE_DIRECTIONS[handle]
				var expected := Vector2(1.2 * ratio if direction.x != 0 else 1.2, 0.8 * ratio if direction.y != 0 else 0.8)
				surface.begin(grips[handle], pointer_id)
				assert(surface.drag_mode == "scale" and surface.drag_handle == handle)
				surface.move_pen(grips[(handle + 4) % 8] + (grips[handle] - grips[(handle + 4) % 8]) * ratio)
				surface.finish()
				assert(surface.object_scale(object).is_equal_approx(expected), "Small stickers must stay small after releasing a grip")
				assert_valid_transform(surface, object)
				var saved: Dictionary = Store.decode(JSON.parse_string(JSON.stringify(Store.encode(surface.state))))
				assert(not saved.is_empty() and surface.object_scale(saved.objects[-1]).is_equal_approx(expected))
				surface.travel(false)
				surface.select_object(original.id)
				assert(surface.selected_object() == original)
				surface.travel(true)
				surface.select_object(original.id)
				object = surface.selected_object()
				assert(surface.object_scale(object).is_equal_approx(expected))
				surface.begin(object.position, pointer_id)
				assert(surface.drag_mode == "move")
				surface.move_pen(object.position + Vector2(10, 10))
				surface.finish()
				assert(surface.object_scale(object).is_equal_approx(expected), "Moving a tiny sticker must not enlarge it")
				# It can still be grabbed and enlarged after shrinking and mirroring.
				grips = surface.resize_handles(object)
				surface.begin(grips[handle], pointer_id)
				assert(surface.drag_mode == "scale" and surface.drag_handle == handle)
				surface.move_pen(grips[handle] + (grips[handle] - grips[(handle + 4) % 8]) * 10)
				surface.finish()
				var enlarged := expected * Vector2(11.0 if direction.x != 0 else 1.0, 11.0 if direction.y != 0 else 1.0)
				assert(surface.object_scale(object).distance_to(enlarged) < 0.0001)

func test_mirror_rendering() -> void:
	var surface := Surface.new()
	surface.state = Surface.new_state("paper", Vector2i(256, 256))
	root.add_child(surface)
	surface.state.objects[0].position = Vector2(-500, -500)
	surface.add_object("dufu_greatsword")
	var object: Dictionary = surface.selected_object()
	var original: Image = await surface.artwork()
	for value in [Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		surface.set_object_scale(object, value)
		var reflected: Image = await surface.artwork()
		var expected: Image = original.duplicate()
		if value.x < 0: expected.flip_x()
		if value.y < 0: expected.flip_y()
		assert(reflected.get_data() == expected.get_data(), "Signed scales must mirror exported sticker pixels")
		var loaded := Store.decode(Store.encode(surface.state))
		surface.state = loaded
		surface.refresh()
		var restored: Image = await surface.artwork()
		assert(restored.get_data() == reflected.get_data(), "Reloading must preserve the mirrored export")
		object = surface.state.objects[-1]
	surface.free()
