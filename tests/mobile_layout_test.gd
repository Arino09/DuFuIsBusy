extends SceneTree
## Mobile reflow uses the real app and memory stores, including orientation changes.
const Fixtures = preload("res://tests/ui_scene_test.gd")
const SIZES := [Vector2i(390, 844), Vector2i(844, 390), Vector2i(320, 568), Vector2i(768, 1024)]
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
	check(control.size.x >= 44 and control.size.y >= 44, "Touch target too small: %s %s" % [control.get_path(), control.size])
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
			for path in ["ToolBrush", "ToolEraser", "ToolMove", "AddTextButton", "StickerButton", "UndoButton", "RedoButton", "ZoomOutButton", "ZoomInButton", "FitViewButton", "SubmitButton", "MobileUI/ToolsButton", "Frame/BackButton"]:
				touch_target(page.get_node(path), bounds)
			check(not page.get_node("SubmitButton").get_global_rect().intersects(page.get_node("RedoButton").get_global_rect()), "Submit overlaps redo at %s" % extent)
			page.get_node("MobileUI/ToolsButton").pressed.emit()
			await settle()
			touch_target(page.get_node("MobileUI/Drawer/CloseButton"), bounds)
			check(page.get_node("MobileUI/Drawer").visible, "Tools drawer did not open")
			page.get_node("MobileUI/Drawer/CloseButton").pressed.emit()
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
			check(app.page.get_node("ColorPalette").visible, "Desktop palette did not return")
			check(app.page.canvas_view.size.is_equal_approx(Vector2(1040, 330)), "Desktop canvas anchors changed")
	app.free()
	await process_frame
	if not failures.is_empty():
		printerr("MOBILE_LAYOUT_TESTS_FAILED:", failures.size())
		quit(1)
		return
	print("MOBILE_LAYOUT_TESTS_PASSED")
	quit()
