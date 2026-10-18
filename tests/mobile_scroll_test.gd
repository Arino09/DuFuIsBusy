extends SceneTree
## Feed phone touch drags through the real GUI tree; never writes player storage.
## Run: Godot --headless --path . --script res://tests/mobile_scroll_test.gd

const Fixtures = preload("res://tests/ui_scene_test.gd")
var app: Control
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func settle() -> void:
	for index in range(5): await process_frame

func touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = root.get_final_transform() * point
	event.pressed = pressed
	root.push_input(event, false)
	# Viewport.push_input bypasses Input's platform mouse emulation. Godot 4.7's
	# native ScrollContainer consumes that companion mouse stream on touchscreens.
	var mouse := InputEventMouseButton.new()
	mouse.device = -1
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	mouse.position = root.get_final_transform() * point
	mouse.global_position = mouse.position
	mouse.pressed = pressed
	root.push_input(mouse, false)

func drag(point: Vector2, previous: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = root.get_final_transform() * point
	event.relative = root.get_final_transform().basis_xform(point - previous)
	event.screen_relative = event.relative
	event.velocity = event.relative * 60.0
	event.screen_velocity = event.velocity
	root.push_input(event, false)
	var mouse := InputEventMouseMotion.new()
	mouse.device = -1
	mouse.button_mask = MOUSE_BUTTON_MASK_LEFT
	mouse.position = event.position
	mouse.global_position = mouse.position
	mouse.relative = event.relative
	mouse.screen_relative = event.relative
	mouse.velocity = event.velocity
	mouse.screen_velocity = event.velocity
	root.push_input(mouse, false)

func swipe(start: Vector2, end: Vector2) -> void:
	touch(start, true)
	await process_frame
	var previous := start
	for index in range(1, 13):
		var point := start.lerp(end, index / 12.0)
		drag(point, previous)
		previous = point
		await process_frame
	touch(end, false)
	await settle()

func tap(point: Vector2) -> void:
	touch(point, true)
	await process_frame
	touch(point, false)
	await settle()

func swipe_start(scroll: ScrollContainer, start_x: float) -> Vector2:
	var viewport := scroll.get_global_rect()
	var x := viewport.position.x + 8.0 if start_x < 0.0 else start_x
	var start := Vector2(x, viewport.end.y - 50.0)
	# Start in a gap or label rather than changing a slider or color wheel.
	for candidate_y in range(int(start.y), int(viewport.position.y + 140.0), -3):
		var candidate := Vector2(x, candidate_y)
		var blocked := false
		for control in scroll.find_children("*", "Control", true, false):
			if control.is_visible_in_tree() and control.mouse_filter == Control.MOUSE_FILTER_STOP and control.get_global_rect().has_point(candidate):
				blocked = true
				break
		if not blocked:
			start = candidate
			break
	return start

func swipe_to_end(scroll: ScrollContainer, description: String, start_x: float = -1.0) -> void:
	if scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page <= 1.0: return
	var routed := {}
	var observe := func(event: InputEvent): routed[event.get_class()] = int(routed.get(event.get_class(), 0)) + 1
	scroll.gui_input.connect(observe)
	var start := swipe_start(scroll, start_x)
	var end := Vector2(start.x, scroll.global_position.y + 78.0)
	var initial := scroll.scroll_vertical
	await swipe(start, end)
	print("SCROLL_ROUTE: ", description, " touch_available=", DisplayServer.is_touchscreen_available(), " events=", routed)
	scroll.gui_input.disconnect(observe)
	check(scroll.scroll_vertical > initial, "%s: finger swipe did not scroll (offset %d)" % [description, scroll.scroll_vertical])
	for index in range(8):
		var bar := scroll.get_v_scroll_bar()
		if scroll.scroll_vertical >= bar.max_value - bar.page - 1.0: break
		await swipe(swipe_start(scroll, start_x), end)
	var bar := scroll.get_v_scroll_bar()
	check(scroll.scroll_vertical >= bar.max_value - bar.page - 1.0, "%s: bottom cannot be reached by finger (offset %d, max %.0f)" % [description, scroll.scroll_vertical, bar.max_value - bar.page])

func run() -> void:
	Input.emulate_touch_from_mouse = true
	root.size = Vector2i(320, 568)
	app = Fixtures.MainScene.instantiate()
	app.set_script(Fixtures.IsolatedApp)
	root.add_child(app)
	app.close_overlay()
	await settle()
	for extent in [Vector2i(320, 568), Vector2i(390, 844)]:
		root.size = extent
		await settle()
		app.show_page("levels")
		await settle()
		var scroll := app.page.get_parent() as ScrollContainer
		check(scroll != null, "Levels needs its mobile scroll container")
		if scroll != null:
			await swipe_to_end(scroll, "Levels %s" % extent)
			check(scroll.get_global_rect().encloses(app.page.get_node("Topic4/EnterButton").get_global_rect()), "Last level is unreachable at %s" % extent)
		app.show_page("gallery")
		await settle()
		app.page.get_node("ExamplesTab").pressed.emit()
		await settle()
		scroll = app.page.get_parent() as ScrollContainer
		if scroll != null:
			await swipe_to_end(scroll, "Gallery %s" % extent)
			var view: Button = app.page.get_node("Examples/Cards/Example4/ViewButton")
			check(scroll.get_global_rect().encloses(view.get_global_rect()), "Last gallery card is unreachable at %s" % extent)
			var taps := [0]
			view.pressed.connect(func(): taps[0] += 1)
			await tap(view.get_global_rect().get_center())
			check(taps[0] == 1 and is_instance_valid(app.overlay), "Tap on the scrolled gallery button must open exactly one preview at %s" % extent)
			app.close_overlay()
			await settle()
		app.show_page("canvas")
		await settle()
		var tools: Button = app.page.get_node("MobileUI/ToolsButton")
		await tap(tools.get_global_rect().get_center())
		var drawer: Control = app.page.get_node("MobileUI/Drawer")
		check(drawer.visible, "A touch tap did not activate the native Tools button at %s" % extent)
		if not drawer.visible:
			tools.pressed.emit()
			await settle()
		scroll = drawer.get_node("Scroll")
		await swipe_to_end(scroll, "Tools drawer %s" % extent)
		var close: Button = drawer.get_node("CloseButton")
		await tap(close.get_global_rect().get_center())
		check(not drawer.visible, "A touch tap did not activate the native drawer Close button at %s" % extent)
		if drawer.visible: close.pressed.emit()
	# Simulate the smaller visual area left by a software keyboard.
	root.size = Vector2i(390, 360)
	await settle()
	app.text_editor(false)
	await settle()
	var dialog: Control = app.overlay
	var dialog_scroll := dialog.get_parent() as ScrollContainer
	var input: LineEdit = dialog.get_node("TextInput")
	var apply: Button = dialog.get_node("ApplyButton")
	input.grab_focus()
	dialog_scroll.ensure_control_visible(input)
	await settle()
	check(dialog_scroll.get_global_rect().encloses(input.get_global_rect()), "Keyboard viewport does not expose the focused text input")
	apply.grab_focus()
	dialog_scroll.ensure_control_visible(apply)
	await settle()
	check(dialog_scroll.get_global_rect().encloses(apply.get_global_rect()), "Keyboard viewport does not expose the text confirmation button")
	app.free()
	await process_frame
	if failures.is_empty(): print("MOBILE_SCROLL_TESTS_PASSED")
	else: printerr("MOBILE_SCROLL_TESTS_FAILED: %d checks" % failures.size())
	quit(0 if failures.is_empty() else 1)
