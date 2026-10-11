extends SceneTree
## Tests palette gestures and persistence entirely in memory.
const Harness = preload("res://tests/ui_scene_test.gd")
const MainScene = preload("res://scenes/main.tscn")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var app = MainScene.instantiate()
	app.set_script(Harness.IsolatedApp)
	root.add_child(app)
	app._start_topic(-1)
	var canvas_id: int = app.page.get_instance_id()
	var surface_id: int = app.drawing.get_instance_id()
	app.drawing.begin(Vector2(500, 150), -1)
	app.drawing.finish()
	# Inline palette changes the brush without opening or replacing the canvas.
	var palette = app.page.get_node("ColorPalette")
	assert(palette.is_visible_in_tree() and not app.page.has_node("PaletteButton"))
	palette.get_node("HexInput").text_submitted.emit("oops")
	assert(palette.get_node("HexInput").has_theme_color_override("font_color"))
	palette.get_node("HexInput").text_submitted.emit("3a9d8f")
	assert(app.overlay == null and app.pen_color == Color("3a9d8f"))
	assert(app.drawing.ink == app.pen_color)
	assert_same_canvas(app, canvas_id, surface_id)
	assert(app.color_history == ["243d35"], "Adjusting a color must not fill usage history")
	click(palette, "HSV")
	assert(palette.hsv_mode and palette._labels[0].text == "H")
	assert(palette._values[0].max_value == 360 and palette._values[1].max_value == 100)
	palette._values[0].value = 240
	palette._values[1].value = 100
	palette._values[2].value = 100
	assert(app.pen_color.is_equal_approx(Color.BLUE))
	# Preserve hue and saturation while passing through black.
	palette._values[2].value = 0
	palette._values[0].value = 120
	palette._values[2].value = 100
	assert(app.pen_color.is_equal_approx(Color.GREEN))
	click(palette, "RGB")
	assert(palette._values[0].max_value == 255 and palette._labels[0].text == "R")
	palette._values[0].value = 255
	assert(app.pen_color.is_equal_approx(Color.YELLOW))
	palette.get_node("Wheel").color_changed.emit(Color.RED)
	assert(app.pen_color == Color.RED and palette._values[1].value == 0)
	for i in range(12):
		app.apply_color(Color.from_hsv(i / 12.0, 1, 1))
		app.drawing.begin(Vector2(400 + i * 20, 220), -1)
		app.drawing.finish()
	assert(app.color_history.size() == 10)
	assert(not "ff0000" in app.color_history, "Oldest used color was not evicted")
	var recalled: String = app.color_history[5]
	click(palette, "History5")
	assert(app.pen_color == Color.html(recalled))
	app.drawing.begin(Vector2(750, 260), -1)
	app.drawing.finish()
	assert(app.color_history.size() == 10 and app.color_history[0] == recalled)
	assert(app.local_store.document.tools.color_history == app.color_history)
	var palette_restore = MainScene.instantiate()
	palette_restore.set_script(Harness.IsolatedApp)
	palette_restore.saved_document = app.local_store.document.duplicate(true)
	root.add_child(palette_restore)
	assert(palette_restore.color_history == app.color_history)
	assert(palette_restore.page.palette.get_node("History0").get_meta("color") == recalled)
	palette_restore.free()
	palette.get_node("HexInput").text_submitted.emit("3a9d8f")
	# Modal focus still blocks the inline controls and returns to its source.
	var source: Button = app.page.get_node("AddTextButton")
	source.grab_focus()
	click(app.page, "AddTextButton")
	for control in app.page.find_children("*", "Control", true, false):
		assert(control.focus_mode == Control.FOCUS_NONE)
	assert(root.gui_get_focus_owner() == app.overlay.get_node("TextInput"))
	click(app.overlay, "Frame/CloseButton")
	assert(app.overlay == null and source.focus_mode == Control.FOCUS_ALL)
	assert(root.gui_get_focus_owner() == source)

	# Erasing does not introduce the currently selected color into history.
	var history_before: Array = app.color_history.duplicate()
	app.apply_color(Color("123456"))
	app.set_tool("橡皮")
	app.drawing.begin(Vector2(500, 150), -1)
	app.drawing.finish()
	assert(app.color_history == history_before)
	app._apply_text("杜甫", 32, Color("654321"), false)
	assert(app.color_history[0] == "654321")
	assert(app.local_store.document.tools.color_history == app.color_history)
	# Route real pointer events through the embedded wheel and channel slider.
	await process_frame
	var prior_color: Color = app.pen_color
	var wheel: ColorPicker = palette.get_node("Wheel")
	pointer_click(wheel.get_global_transform_with_canvas() * Vector2(106, 108))
	assert(app.pen_color != prior_color, "Wheel did not receive pointer input")
	prior_color = app.pen_color
	var slider: HSlider = palette._sliders[0]
	pointer_click(slider.get_global_transform_with_canvas() * Vector2(90, 10))
	assert(app.pen_color != prior_color, "RGB slider did not receive pointer input")
	app.free()
	print("PALETTE_TESTS_PASSED")
	quit()

func click(view: Node, path: NodePath) -> void:
	var button: BaseButton = view.get_node(path)
	assert(button.is_visible_in_tree(), "Button is hidden: %s" % path)
	assert(not button.disabled, "Button is disabled: %s" % path)
	button.pressed.emit()


func assert_same_canvas(app: Control, page_id: int, drawing_id: int) -> void:
	assert(app.page.get_instance_id() == page_id, "A local canvas update recreated its page")
	assert(app.drawing.get_instance_id() == drawing_id, "A local canvas update recreated DrawingSurface")
	assert(app.get_node("PageHost").get_child_count() == 1)


func pointer_click(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
