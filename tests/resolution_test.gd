extends SceneTree
## Exercise the shipped window/stretch settings, using only in-memory player data.
## Run: Godot --headless --path . --script res://tests/resolution_test.gd

const Fixtures = preload("res://tests/ui_scene_test.gd")
const Controller = preload("res://scripts/main.gd")
const MainScene = preload("res://scenes/main.tscn")
const BASE := Vector2(1440, 900)
const WINDOW_SIZES := [
	Vector2i(1152, 720), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(1280, 1024), Vector2i(3440, 1440), Vector2i(1152, 720),
]
const CANVAS_CONTROLS := [
	"Frame/BackButton", "ColorPalette", "CanvasSize", "ChangeTopicButton",
	"ZoomOutButton", "ZoomInButton", "FitViewButton", "UndoButton", "RedoButton",
	"ReferenceButton", "RestartButton", "SubmitButton", "DrawingStatus", "ViewHint",
]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func check_rect(control: Control, expected: Rect2, description: String) -> void:
	var actual := control.get_global_rect()
	check(actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size),
		"%s: expected %s, got %s" % [description, expected, actual])

func check_inside(control: Control, bounds: Rect2) -> void:
	if not control.is_visible_in_tree(): return
	check(bounds.grow(0.1).encloses(control.get_global_rect()),
		"%s outside viewport %s: %s" % [control.get_path(), bounds, control.get_global_rect()])

func resize_window(extent: Vector2i) -> Vector2:
	root.size = extent
	# Window stretch and container minimum sizes settle on separate notifications.
	await process_frame
	await process_frame
	var factor := minf(extent.x / BASE.x, extent.y / BASE.y)
	var expected := Vector2(extent) / factor
	var logical := root.get_visible_rect().size
	check(logical.is_equal_approx(expected), "Wrong expanded viewport for %s: %s" % [extent, logical])
	check(root.get_final_transform().get_scale().is_equal_approx(Vector2.ONE * factor),
		"Window stretch is not uniform for %s" % extent)
	return logical

func centered_children(scene: Control) -> Dictionary:
	var result := {}
	for child in scene.get_children():
		if child is Control and child.name != "Frame":
			result[NodePath(child.name)] = Rect2(child.position - BASE / 2, child.size)
	return result

func check_centered(scene: Control, baseline: Dictionary, logical: Vector2) -> void:
	for path in baseline:
		var before: Rect2 = baseline[path]
		var control: Control = scene.get_node(path)
		check_rect(control, Rect2(before.position + logical / 2, before.size),
			"Content drifted from center: %s" % control.get_path())
		check_inside(control, Rect2(Vector2.ZERO, logical))

func verify_pages(app: Control) -> void:
	for id in Controller.PAGE_SCENES:
		await resize_window(WINDOW_SIZES[0])
		app.show_page(id)
		await process_frame
		var scene: Control = app.page
		var baseline := centered_children(scene) if id != "canvas" else {}
		var initial_view := Vector2.ZERO
		if id == "canvas": initial_view = scene.get_node("CanvasView").size
		for extent in WINDOW_SIZES:
			var logical := await resize_window(extent)
			var viewport := Rect2(Vector2.ZERO, logical)
			for control in [app, app.page_host, app.dialog_host, scene, scene.get_node("Frame"), scene.get_node("Frame/Paper")]:
				check_rect(control, viewport, "Page must fill viewport: %s at %s" % [control.get_path(), extent])
			check_inside(scene.get_node("Frame/BackButton"), viewport)
			check_inside(scene.get_node("Frame/StorageHint"), viewport)
			if id != "canvas":
				check_centered(scene, baseline, logical)
				continue
			var canvas_view: Control = scene.get_node("CanvasView")
			check(canvas_view.size.is_equal_approx(initial_view + logical - BASE),
				"Canvas view did not use the added window space at %s" % extent)
			check_inside(canvas_view, viewport)
			for path in CANVAS_CONTROLS: check_inside(scene.get_node(path), viewport)
			check(scene.get_node("ColorPalette").get_global_rect().end.x < canvas_view.global_position.x,
				"Palette overlaps canvas view at %s" % extent)
			check(scene.get_node("SubmitButton").global_position.y > canvas_view.get_global_rect().end.y,
				"Completion button overlaps canvas view at %s" % extent)
			check(scene.get_node("FitViewButton").get_global_rect().end.x <= scene.get_node("UndoButton").global_position.x,
				"Zoom controls overlap history controls at %s" % extent)

func verify_dialogs(app: Control) -> void:
	for id in Controller.DIALOG_SCENES:
		await resize_window(WINDOW_SIZES[0])
		var dialog: Control = Controller.DIALOG_SCENES[id].instantiate()
		app.dialog_host.add_child(dialog)
		await process_frame
		var baseline := centered_children(dialog)
		for path in ["Frame/Panel", "Frame/Title", "Frame/Body", "Frame/CloseButton"]:
			var control: Control = dialog.get_node(path)
			baseline[NodePath(path)] = Rect2(control.global_position - BASE / 2, control.size)
		for extent in WINDOW_SIZES:
			var logical := await resize_window(extent)
			var viewport := Rect2(Vector2.ZERO, logical)
			for control in [dialog, dialog.get_node("Frame"), dialog.get_node("Frame/Shade")]:
				check_rect(control, viewport, "Modal must cover viewport: %s at %s" % [control.get_path(), extent])
			check(dialog.get_node("Frame/Shade").mouse_filter == Control.MOUSE_FILTER_STOP,
				"Modal shade must block input: %s" % id)
			check_centered(dialog, baseline, logical)
		dialog.free()

func verify_artwork_and_input(app: Control) -> void:
	await resize_window(WINDOW_SIZES[0])
	app.show_page("canvas")
	await process_frame
	var page = app.page
	var surface = app.drawing
	# Use a non-square artwork, like the saved canvas in the reported screenshot.
	surface.resize_canvas(Vector2i(1040, 330))
	surface.begin(Vector2(700, 220), -1)
	surface.finish()
	var original_pixels: PackedByteArray = surface.state.pixels.get_data()
	var original_objects: Array = surface.state.objects.duplicate(true)
	var revision: int = surface.state.revision
	var undo_count: int = surface.state.undo.size()
	var writes: int = app.local_store.writes
	var original_view: Vector2 = page.canvas_view.size
	var original_position: Vector2 = surface.position
	var original_zoom: float = page.view_zoom
	for extent in WINDOW_SIZES:
		await resize_window(extent)
		check(surface.canvas_size() == Vector2i(1040, 330), "Window resize changed artwork dimensions")
		check(surface.state.revision == revision and surface.state.undo.size() == undo_count,
			"Window resize created a drawing edit")
		check(surface.state.objects == original_objects, "Window resize moved editable objects")
		check(surface.state.pixels.get_data() == original_pixels, "Window resize resampled saved pixels")
		check(app.local_store.writes == writes, "Window resize unexpectedly saved a changed draft")
	check(page.canvas_view.size.is_equal_approx(original_view) and surface.position.is_equal_approx(original_position)
		and is_equal_approx(page.view_zoom, original_zoom), "Resize round trip did not restore fitted view")
	# Feed real window coordinates through the root viewport's stretch transform.
	# Passing local coordinates with push_input(..., true) would miss this regression.
	for i in range(WINDOW_SIZES.size() - 1):
		await resize_window(WINDOW_SIZES[i])
		var point := Vector2(460 + 60 * i, 150)
		var window_point: Vector2 = root.get_final_transform() * surface.get_global_transform_with_canvas() * point
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = window_point
		event.global_position = window_point
		event.pressed = true
		root.push_input(event, false)
		await process_frame
		event = event.duplicate()
		event.pressed = false
		root.push_input(event, false)
		await process_frame
		check(surface.state.pixels.get_pixelv(Vector2i(point)).a > 0,
			"Stretched window input missed artwork coordinates at %s" % WINDOW_SIZES[i])
		check(surface.state.revision == revision + i + 1, "One physical click must create exactly one edit")

func run() -> void:
	# Do not replace the project's content_scale settings: these are part of the fix.
	check(root.content_scale_size == Vector2i(BASE), "Project needs a 1440x900 design viewport")
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "Project must scale canvas items")
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Project must expand to fill the window")
	var app = MainScene.instantiate()
	app.set_script(Fixtures.IsolatedApp)
	root.add_child(app)
	app.close_overlay()
	await verify_pages(app)
	await verify_dialogs(app)
	await verify_artwork_and_input(app)
	app.free()
	await process_frame
	if not failures.is_empty():
		printerr("RESOLUTION_TESTS_FAILED: %d checks" % failures.size())
		quit(1)
		return
	print("RESOLUTION_TESTS_PASSED")
	quit()
