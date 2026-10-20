extends SceneTree
## Mobile reflow uses the real app and memory stores, including orientation changes.
const Fixtures = preload("res://tests/ui_scene_test.gd")
const SIZES := [Vector2i(390, 844), Vector2i(844, 390), Vector2i(320, 568), Vector2i(568, 320), Vector2i(768, 1024)]
var failures: Array[String] = []
var app: Control

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures.append(message)
	push_error(message)

func settle() -> void:
	for i in range(4): await process_frame

func resize_to(extent: Vector2i) -> void:
	root.size = extent
	await settle()
	check(app.responsive_layout.compact, "Small window did not select compact layout: %s" % extent)
	check(root.get_visible_rect().size.is_equal_approx(Vector2(extent)), "Mobile UI must use legible logical pixels")

func touch_target(control: Control, bounds: Rect2) -> void:
	if not control.is_visible_in_tree(): return
	check(control.size.x >= 55.9 and control.size.y >= 55.9, "Touch target too small: %s %s" % [control.get_path(), control.size])
	check(bounds.grow(0.1).encloses(control.get_global_rect()), "Touch target overflow: %s %s" % [control.get_path(), control.get_global_rect()])

func run() -> void:
	root.size = SIZES[0]
	app = Fixtures.MainScene.instantiate()
	app.set_script(Fixtures.IsolatedApp)
	root.add_child(app)
	app.close_overlay()
	await settle()
	for extent in SIZES:
		await resize_to(extent)
		for id in ["home", "levels", "gallery", "settings", "canvas"]:
			app.show_page(id)
			await settle()
			var page: Control = app.page
			var bounds := Rect2(Vector2.ZERO, Vector2(extent))
			check(is_equal_approx(page.size.x, extent.x), "Page overflow: %s at %s: %s" % [id, extent, page.size])
			if id != "canvas":
				check(page.get_parent() is ScrollContainer, "Long mobile pages need touch scrolling")
				check(page.size.y >= extent.y, "Mobile page leaves uncovered area")
				continue
			check(page.get_parent() == app.page_host, "Drawing gestures must not scroll the page")
			check(bounds.encloses(page.canvas_view.get_global_rect()), "Canvas outside mobile viewport")
			var minimum_share := 0.48 if extent.y < 368 else 0.52
			check(page.canvas_view.size.x * page.canvas_view.size.y / (extent.x * extent.y) >= minimum_share, "Canvas must occupy most of the screen at %s" % extent)
			var visible_tools: Array[Control] = []
			for path in ["ToolBrush", "ToolEraser", "ToolMove", "AddTextButton", "StickerButton", "UndoButton", "RedoButton", "ZoomOutButton", "ZoomInButton", "FitViewButton", "SubmitButton", "MobileUI/Toolbar/Tools/PaletteButton", "Frame/BackButton"]:
				var control: Control = page.get_node(path)
				touch_target(control, bounds)
				if control.is_visible_in_tree():
					check(not control.get_global_rect().intersects(page.canvas_view.get_global_rect()), "Toolbar overlaps drawing area: %s at %s" % [path, extent])
					for other in visible_tools:
						check(not other.get_global_rect().intersects(control.get_global_rect()), "Toolbar buttons overlap: %s / %s at %s" % [control.name, other.name, extent])
					visible_tools.append(control)
			var toolbar: ScrollContainer = page.get_node("MobileUI/Toolbar")
			var palette_button: Button = toolbar.get_node("Tools/PaletteButton")
			check(toolbar.get_global_rect().encloses(palette_button.get_global_rect()), "Palette button must stay inside the bottom toolbar at %s" % extent)
			for button in toolbar.get_child(0).get_children():
				check(button.size.x >= 55.9 and button.size.y >= 55.9, "Toolbar action too small at %s" % extent)
			for action in ["ChangeTopicButton", "ReferenceButton", "RestartButton", "LayersButton", "CanvasButton"]:
				check(toolbar.find_child(action, true, false) != null, "Missing external action: %s" % action)
			check(page.get_node("Frame/StorageHint").visible and page.get_node("ViewHint").visible, "Draft status and operation hints must stay outside the panels")
			check(page.get_node("Frame/StorageHint").get_theme_font_size("font_size") <= 14, "Draft status should use small text")
			check(not page.get_node("SubmitButton").get_global_rect().intersects(page.get_node("RedoButton").get_global_rect()), "Submit overlaps redo at %s" % extent)
			palette_button.pressed.emit()
			await settle()
			touch_target(page.get_node("MobileUI/Drawer/CloseButton"), bounds)
			check(page.get_node("MobileUI/Drawer").visible, "Tools drawer did not open")
			var tools_scroll: ScrollContainer = page.get_node("MobileUI/Drawer/Scroll")
			var tool_content: Control = tools_scroll.get_child(0)
			check(tool_content.size.x <= tools_scroll.size.x + 0.1, "Tools drawer content overflows horizontally at %s" % extent)
			for control in tool_content.find_children("*", "Control", true, false):
				if not control.is_visible_in_tree(): continue
				if control is BaseButton or control is Slider or control is SpinBox or control is LineEdit:
					check(control.size.y >= 55.9, "Drawer field too small: %s at %s" % [control.get_path(), extent])
			page.get_node("MobileUI/Drawer/CloseButton").pressed.emit()
			for panel_id in ["palette", "layers", "canvas"]:
				page.workspace_layout.open_panel(panel_id)
				await settle()
				Fixtures.assert_canvas_drawer(page)
				var panel: Control = page.get_node("MobileUI/Drawer/Scroll").get_child(0)
				var visible_count := 0
				for section in panel.get_children():
					if section.visible: visible_count += 1
				check(visible_count == 1, "Each panel should show its own controls")
				check(panel.find_child("ZoomOutButton", true, false) == null, "Zoom belongs outside the panels")
				check(panel.find_child("ReferenceButton", true, false) == null, "Assets belong outside the panels")
				page.workspace_layout.close_tools()
			app.apply_color(Color("3a9d8f"))
			var swatch: Button = palette_button
			check(swatch.get_theme_stylebox("normal").bg_color.is_equal_approx(app.drawing.ink), "Palette button must show the current drawing color")
			# Save recovery remains reachable without colliding with the main action.
			app.local_store.fail_writes = true
			app.autosave()
			await settle()
			touch_target(page.get_node("Frame/StorageRetry"), bounds)
			check(page.get_node("Frame/StorageRetry").visible and not page.get_node("SubmitButton").visible, "Failed-save recovery must replace the completion button")
			app.local_store.fail_writes = false
			page.get_node("Frame/StorageRetry").pressed.emit()
			await settle()
			check(not page.get_node("Frame/StorageRetry").visible and page.get_node("SubmitButton").visible, "Successful retry must restore completion")
		for id in app.DIALOG_SCENES:
			app.modal(id)
			await settle()
			var dialog: Control = app.overlay
			check(dialog.get_parent() is ScrollContainer, "Dialog must remain reachable above mobile keyboard")
			check(is_equal_approx(dialog.size.x, extent.x), "Dialog overflow: %s at %s" % [id, extent])
			var bounds := Rect2(Vector2.ZERO, Vector2(extent.x, dialog.size.y))
			for control in dialog.find_children("*", "Button", true, false):
				var inside_list := dialog.has_node("Scroll") and dialog.get_node("Scroll").is_ancestor_of(control)
				touch_target(control, Rect2(0, -10000, extent.x, 20000) if inside_list else bounds)
			app.close_overlay()
	# Reflow keeps the actual drawing and its data; desktop anchors return intact.
	app.show_page("canvas")
	await settle()
	var surface = app.drawing
	surface.begin(Vector2(600, 520), -1)
	surface.finish()
	var pixels: PackedByteArray = surface.state.pixels.get_data()
	var revision: int = surface.state.revision
	for extent in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(1152, 720), Vector2i(390, 844)]:
		root.size = extent
		await settle()
		check(app.drawing == surface, "Orientation change recreated artwork")
		check(surface.state.revision == revision and surface.state.pixels.get_data() == pixels, "Reflow modified artwork")
		if extent == Vector2i(1152, 720):
			check(not app.responsive_layout.compact, "Desktop layout was not restored")
			check(app.page.get_node("MobileUI/Toolbar/Tools/PaletteButton").visible, "Desktop settings drawer did not return")
			check(app.page.canvas_view.size.is_equal_approx(Vector2(1424, 732)), "Desktop drawing area did not return")
		app.page.workspace_layout.open_panel("palette")
		await settle()
		Fixtures.assert_canvas_drawer(app.page)
		app.page.workspace_layout.close_tools()
	app.free()
	await process_frame
	if not failures.is_empty():
		printerr("MOBILE_LAYOUT_TESTS_FAILED:", failures.size())
		quit(1)
		return
	print("MOBILE_LAYOUT_TESTS_PASSED")
	quit()
