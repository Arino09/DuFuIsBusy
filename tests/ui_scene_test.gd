extends SceneTree
## Integration coverage for authored scenes and controller bindings.
## Never reads or writes player saves: the app and storage below stay in memory.
## Run: Godot --headless --path . --script res://tests/ui_scene_test.gd

const MainScene = preload("res://scenes/main.tscn")
const Controller = preload("res://scripts/main.gd")
const Surface = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")
const SettingsStore = preload("res://scripts/settings_store.gd")

class MemorySettingsStore:
	extends "res://scripts/settings_store.gd"
	var writes := 0
	var fail_writes := false
	var stored: Dictionary = {}

	func _is_web() -> bool:
		return false

	func _read_native() -> Variant:
		return stored.duplicate(true)

	func _write_native(values: Dictionary) -> bool:
		if fail_writes: return false
		stored = values.duplicate(true)
		writes += 1
		return true

class CountingCache:
	extends "res://scripts/draft_cache.gd"
	var encodes := 0

	func _encode(state: Dictionary) -> Dictionary:
		encodes += 1
		return Store.encode(state)

class MemoryStore:
	extends "res://scripts/local_store.gd"
	var writes := 0
	var fail_writes := false

	func read_document() -> bool:
		return true

	func write_document(candidate: Dictionary) -> bool:
		if fail_writes:
			error = "测试：本地存储不可用。"
			return false
		assert(validate_document(candidate), "Controller emitted an invalid save document")
		document = candidate.duplicate(true)
		writes += 1
		error = ""
		return true

class IsolatedApp:
	extends "res://scripts/main.gd"
	var saved_settings: Dictionary = {}
	var saved_document: Dictionary = {}
	var settings_writes: int:
		get: return (settings_store as MemorySettingsStore).writes
	var work_view_requests := 0
	var work_edit_requests := 0

	func _ready() -> void:
		local_store = MemoryStore.new()
		if not saved_document.is_empty(): local_store.document = saved_document.duplicate(true)
		draft_cache = CountingCache.new()
		settings_store = MemorySettingsStore.new()
		(settings_store as MemorySettingsStore).stored = saved_settings.duplicate(true)
		super._ready()

	func view_work(work: Dictionary) -> void:
		work_view_requests += 1
		super.view_work(work)

	func open_work_confirm(work: Dictionary) -> void:
		work_edit_requests += 1
		super.open_work_confirm(work)

func _initialize() -> void:
	call_deferred("run")

static func click(view: Node, path: NodePath) -> void:
	var button: BaseButton = view.get_node(path)
	if not button.is_visible_in_tree() and view.has_node("MobileUI/Toolbar"):
		var original_name := button.name
		button = view.get_node("MobileUI/Toolbar").find_child(original_name, true, false)
		if button == null:
			view.workspace_layout.open_panel("layers")
			button = view.get_node("MobileUI/Drawer").find_child(original_name, true, false)
		else:
			view.get_node("MobileUI/Toolbar").ensure_control_visible(button)
		assert(button != null, "Missing drawer action: %s" % path)
	assert(button.is_visible_in_tree(), "Button is hidden: %s" % path)
	assert(not button.disabled, "Button is disabled: %s" % path)
	button.pressed.emit()

static func assert_canvas_drawer(page: Control) -> void:
	var drawer: Control = page.get_node("MobileUI/Drawer")
	var panel: Panel = drawer.get_node("Panel")
	var background := panel.get_global_rect()
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	assert(background.has_area() and background.size.x >= 280, "Drawer needs a full-width background")
	assert(style != null and style.bg_color.a == 1.0, "Drawer background must be opaque")
	var title: Control = drawer.get_node("Title")
	var close: Control = drawer.get_node("CloseButton")
	var scroll: Control = drawer.get_node("Scroll")
	for control in [title, close, scroll]:
		assert(background.encloses(control.get_global_rect()), "Drawer control outside its background: %s" % control.name)
	assert(not title.get_global_rect().intersects(close.get_global_rect()), "Drawer title overlaps its close button")
	assert(close.get_global_rect().position.x > background.get_center().x, "Close button must sit at the top right")
	assert(scroll.get_global_rect().position.y >= maxf(title.get_global_rect().end.y, close.get_global_rect().end.y) + 8, "Drawer content must start below the header")

func visible_card_count(cards: Node) -> int:
	var count := 0
	for card in cards.get_children():
		if card.visible: count += 1
	return count

func assert_same_canvas(app: Control, page_id: int, drawing_id: int) -> void:
	assert(app.page.get_instance_id() == page_id, "A local canvas update recreated its page")
	assert(app.drawing.get_instance_id() == drawing_id, "A local canvas update recreated DrawingSurface")
	assert(app.get_node("PageHost").get_child_count() == 1)

func assert_dialog(app: Control, id: String) -> void:
	assert(is_instance_valid(app.overlay))
	assert(app.overlay.scene_file_path == "res://scenes/dialogs/%s.tscn" % id)
	assert(app.get_node("DialogHost").get_child_count() == 1)

func verify_unique_scene_resource_ids(directory: String, declaration: RegEx) -> bool:
	# Godot may silently reuse duplicate subresource IDs, so successful loading
	# alone cannot prove that each authored style/texture stayed distinct.
	for child in DirAccess.get_directories_at(directory):
		if not verify_unique_scene_resource_ids(directory.path_join(child), declaration):
			return false
	for filename in DirAccess.get_files_at(directory):
		if filename.get_extension() != "tscn": continue
		var path := directory.path_join(filename)
		var ids := {}
		for matched in declaration.search_all(FileAccess.get_file_as_string(path)):
			# External and embedded resource IDs occupy separate namespaces.
			var key := matched.get_string(1) + ":" + matched.get_string(2)
			if ids.has(key):
				push_error("Duplicate resource declaration %s in %s" % [key, path])
				return false
			ids[key] = true
	return true

func verify_authored_scenes() -> bool:
	var declaration := RegEx.new()
	assert(declaration.compile('(?m)^\\[(ext_resource|sub_resource)\\s[^\\r\\n]*\\bid="([^"]+)"') == OK)
	if not verify_unique_scene_resource_ids("res://scenes", declaration): return false
	for collection in [Controller.PAGE_SCENES, Controller.DIALOG_SCENES]:
		for id in collection:
			var scene: Control = collection[id].instantiate()
			var authored_toolbar_offsets := Vector4()
			if id == "canvas" and collection == Controller.PAGE_SCENES:
				assert(scene.has_node("MobileUI/Toolbar/Tools/LayersButton"), "Toolbar must exist before scripts run")
				assert(scene.has_node("MobileUI/Toolbar/Tools/PaletteButton"), "Palette button must be authored in the bottom toolbar")
				var workspace: Control = scene.get_node("MobileUI")
				assert(workspace.scene_file_path == "res://scenes/components/canvas_workspace.tscn")
				for panel in ["PalettePanel", "LayersPanel", "CanvasPanel"]:
					var control: Control = workspace.get_node("Drawer/Scroll/Content/" + panel)
					assert(not control.scene_file_path.is_empty(), "Each settings panel must be an editable scene")
				# A designer's position change must survive the desktop controller's setup.
				var toolbar: Control = workspace.get_node("Toolbar")
				toolbar.offset_left += 2
				authored_toolbar_offsets = Vector4(toolbar.offset_left, toolbar.offset_top, toolbar.offset_right, toolbar.offset_bottom)
			root.add_child(scene)
			if id == "canvas" and collection == Controller.PAGE_SCENES:
				var toolbar: Control = scene.get_node("MobileUI/Toolbar")
				assert(Vector4(toolbar.offset_left, toolbar.offset_top, toolbar.offset_right, toolbar.offset_bottom) == authored_toolbar_offsets, "Runtime setup must preserve authored toolbar offsets")
				assert_canvas_drawer(scene)
			assert(scene.size == Vector2(1440, 900), "Wrong scene viewport: %s" % id)
			assert(scene.theme != null, "Scene needs its own theme for standalone preview: %s" % id)
			assert(scene.get_node("Frame/Title") is Label)
			assert(scene.get_node("Frame").size == Vector2(1440, 900))
			if collection == Controller.PAGE_SCENES:
				assert(scene.get_node("Frame/StorageRetry") is Button)
			else:
				assert(scene.get_node("Frame/Shade").mouse_filter == Control.MOUSE_FILTER_STOP)
				assert(scene.get_node("Frame/Body") is Label)
			scene.free()
	var theme: Theme = load("res://themes/ui_theme.tres")
	assert(theme.get_stylebox("pressed", "SelectableButton").bg_color.is_equal_approx(Color("292824")))
	assert(theme.get_color("font_pressed_color", "SelectableButton").is_equal_approx(Color("fbfaf5")))
	assert(theme.get_stylebox("normal", "CompactRetryButton").content_margin_top == 2.0)
	return true

func run() -> void:
	# Headless windows default to 64x64; authoring checks use the design aspect.
	# Other aspect ratios are exercised by resolution_test.gd.
	root.size = Vector2i(1440, 900)
	if not verify_authored_scenes():
		quit(1)
		return
	var app = MainScene.instantiate()
	app.set_script(IsolatedApp)
	# This suite exercises page controls across topics; progression has its own suite.
	app.saved_document = Store.empty_document()
	app.saved_document.completed_topics = [0, 1]
	root.add_child(app)
	await process_frame
	assert(app.current == "home")
	assert(not app.page.get_node("Frame/Title").visible)
	assert(app.get_node("PageHost").get_child_count() == 1)
	click(app.page, "LevelsButton")
	assert(app.current == "levels")
	click(app.page, "Topic3/EnterButton")
	assert(app.current == "canvas" and app.topic == 2)
	assert(app.drawing.state == app.drawings[2])
	assert(app.page.get_node("UndoButton").disabled and app.page.get_node("RedoButton").disabled)
	assert(app.page.get_node("ToolBrush").button_pressed)
	var canvas_id: int = app.page.get_instance_id()
	var surface_id: int = app.drawing.get_instance_id()
	var encoded_before: int = app.draft_cache.encodes

	# Scene-authored controls still drive tool state, drawing history and draft saves.
	for i in range(3):
		click(app.page, "ToolEraser")
		assert(app.drawing.erasing and app.selected_tool == "橡皮")
		assert(app.page.get_node("ToolEraser").button_pressed)
		assert(not app.page.get_node("ToolBrush").button_pressed)
		click(app.page, "ToolMove")
		assert(app.drawing.selecting and not app.drawing.erasing)
		assert(app.drawing.mouse_default_cursor_shape == Control.CURSOR_MOVE)
		click(app.page, "ToolBrush")
		assert(not app.drawing.selecting and not app.drawing.erasing)
		assert(app.drawing.mouse_default_cursor_shape == Control.CURSOR_CROSS)
		assert_same_canvas(app, canvas_id, surface_id)
	assert(app.draft_cache.encodes == encoded_before, "Tool changes re-encoded an unchanged draft")
	var writes_before: int = app.local_store.writes
	app.page.get_node("WidthSlider").value = 20
	app.page.get_node("WidthSlider").value = 24
	app.page.get_node("WidthSlider").value = 28
	assert(app.pen_width == 28 and app.drawing.pen_width == 28)
	assert(app.local_store.writes == writes_before, "A continuous slider gesture wrote before debounce")
	await create_timer(0.35).timeout
	assert(app.local_store.writes == writes_before + 1, "Width changes must coalesce into one save")
	assert(app.local_store.document.tools.width == 28)
	assert(app.draft_cache.encodes == encoded_before)
	app.drawing.begin(Vector2(500, 150), -1)
	app.drawing.move_pen(Vector2(600, 180))
	app.drawing.finish()
	assert(app.drawing.has_ink() and not app.page.get_node("UndoButton").disabled)
	click(app.page, "UndoButton")
	assert(not app.drawing.has_ink() and not app.page.get_node("RedoButton").disabled)
	click(app.page, "RedoButton")
	assert(app.drawing.has_ink())
	assert(app.local_store.document.tools.width == 28)

	# The settings drawer changes the brush without replacing the canvas.
	var palette = app.page.get_node("ColorPalette")
	assert(not palette.is_visible_in_tree())
	click(app.page, "MobileUI/Toolbar/Tools/PaletteButton")
	var drawer: Control = app.page.get_node("MobileUI/Drawer")
	assert(drawer.visible)
	var hex: LineEdit = drawer.get_node("Scroll").find_child("HexInput", true, false)
	hex.text_submitted.emit("oops")
	assert(hex.has_theme_color_override("font_color"))
	hex.text_submitted.emit("3a9d8f")
	assert(app.overlay == null and app.pen_color == Color("3a9d8f"))
	assert(app.drawing.ink == app.pen_color)
	assert_same_canvas(app, canvas_id, surface_id)
	assert(app.responsive_layout.close_canvas_tools() and not drawer.visible)
	assert(app.color_history == ["243d35"], "Adjusting a color must not fill usage history")
	click(app.page, "MobileUI/Toolbar/Tools/PaletteButton")
	var wheel: ColorPicker = drawer.find_child("ColorPicker", true, false)
	var red: SpinBox = drawer.find_child("RedInput", true, false)
	var green: SpinBox = drawer.find_child("GreenInput", true, false)
	var blue: SpinBox = drawer.find_child("BlueInput", true, false)
	wheel.color_changed.emit(Color.BLUE)
	assert(app.pen_color.is_equal_approx(Color.BLUE))
	red.value = 255
	green.value = 255
	blue.value = 0
	assert(app.pen_color.is_equal_approx(Color.YELLOW))
	wheel.color_changed.emit(Color.RED)
	assert(app.pen_color == Color.RED and green.value == 0)
	click(drawer, "CloseButton")
	for i in range(12):
		app.apply_color(Color.from_hsv(i / 12.0, 1, 1))
		app.drawing.begin(Vector2(400 + i * 20, 220), -1)
		app.drawing.finish()
	assert(app.color_history.size() == 10)
	assert(not "ff0000" in app.color_history, "Oldest used color was not evicted")
	var recalled: String = app.color_history[5]
	click(app.page, "MobileUI/Toolbar/Tools/PaletteButton")
	var history_button: Button = drawer.find_child("History5", true, false)
	click(drawer, drawer.get_path_to(history_button))
	assert(app.pen_color == Color.html(recalled))
	click(drawer, "CloseButton")
	app.drawing.begin(Vector2(750, 260), -1)
	app.drawing.finish()
	assert(app.color_history.size() == 10 and app.color_history[0] == recalled)
	assert(app.local_store.document.tools.color_history == app.color_history)
	var palette_restore = MainScene.instantiate()
	palette_restore.set_script(IsolatedApp)
	palette_restore.saved_document = app.local_store.document.duplicate(true)
	root.add_child(palette_restore)
	assert(palette_restore.color_history == app.color_history)
	assert(palette_restore.page.palette.get_node("History0").get_meta("color") == recalled)
	palette_restore.free()
	click(app.page, "MobileUI/Toolbar/Tools/PaletteButton")
	hex.text_submitted.emit("3a9d8f")
	click(drawer, "CloseButton")
	# Modal focus still blocks the inline controls and returns to its source.
	var source: Button = app.page.get_node("MobileUI/Toolbar").find_child("AddTextButton", true, false)
	source.grab_focus()
	click(app.page, "AddTextButton")
	for control in app.page.find_children("*", "Control", true, false):
		assert(control.focus_mode == Control.FOCUS_NONE)
	assert(root.gui_get_focus_owner() == app.overlay.get_node("TextInput"))
	click(app.overlay, "Frame/CloseButton")
	assert(app.overlay == null and source.focus_mode == Control.FOCUS_ALL)
	assert(root.gui_get_focus_owner() == source)

	click(app.page, "AddTextButton")
	assert_dialog(app, "text_editor")
	click(app.overlay, "ApplyButton")
	assert(not app.overlay.get_node("ErrorLabel").text.is_empty())
	app.overlay.get_node("TextInput").text = "诗圣摸鱼"
	app.overlay.get_node("FontSizeInput").value = 44
	app.overlay.get_node("ColorInput").text = "zz9988"
	var objects_before: int = app.drawing.state.objects.size()
	writes_before = app.local_store.writes
	click(app.overlay, "ApplyButton")
	assert_dialog(app, "text_editor")
	assert(not app.overlay.get_node("ErrorLabel").text.is_empty())
	assert(app.drawing.state.objects.size() == objects_before and app.local_store.writes == writes_before)
	app.overlay.get_node("ColorInput").text = "3A9D8F"
	app.overlay.get_node("ColorInput").text_changed.emit("3A9D8F")
	assert(app.overlay.get_node("ErrorLabel").text.is_empty())
	click(app.overlay, "ApplyButton")
	assert(app.selected_tool == "移动")
	assert(app.drawing.selected_object().text == "诗圣摸鱼")
	assert(app.drawing.selected_object().font_size == 44)
	assert_same_canvas(app, canvas_id, surface_id)
	click(app.page, "EditObjectButton")
	app.overlay.get_node("TextInput").text = "忙里偷闲"
	click(app.overlay, "ApplyButton")
	assert(app.drawing.selected_object().text == "忙里偷闲")
	assert_same_canvas(app, canvas_id, surface_id)
	# Every category exposes the exact imported texture and editable saved ID.
	var last_sticker: String = Surface.Stickers.CATEGORIES.values().back().ids.back()
	for category in Surface.Stickers.CATEGORIES:
		for kind in Surface.Stickers.CATEGORIES[category].ids:
			click(app.page, "StickerButton")
			assert_dialog(app, "sticker_picker")
			click(app.overlay, "Categories/" + category)
			var card_path: String = "Scroll/Grid/" + kind + "/Content/"
			var preview: TextureRect = app.overlay.get_node(card_path + "Preview")
			assert(preview.texture == Surface.STICKER_TEXTURES[kind])
			click(app.overlay, card_path + "UseButton")
			assert(app.drawing.selected_object().kind == kind)
			assert(app.page.get_node("DrawingStatus").text.contains(app.page.OBJECT_NAMES[kind]))
			assert_same_canvas(app, canvas_id, surface_id)
			if kind != last_sticker: click(app.page, "DeleteObjectButton")
	var initial_scale: float = app.drawing.selected_object().scale
	var revision_before: int = app.drawings[app.topic].revision
	writes_before = app.local_store.writes
	var handles = app.drawing.resize_handles(app.drawing.selected_object())
	app.drawing.begin(handles[4], -1)
	app.drawing.move_pen(handles[4] + (handles[4] - handles[0]) * 0.15)
	app.drawing.finish()
	assert(is_equal_approx(app.drawing.selected_object().scale, initial_scale * 1.15), "Handle drag must scale the selected layer")
	assert(app.drawings[app.topic].revision == revision_before + 1)
	assert(app.local_store.writes == writes_before + 1, "One object action saved more than once")
	click(app.page, "DeleteObjectButton")
	assert(app.drawings[app.topic].objects.size() == 2)

	# The catalog opens the weapon picker and preserves the scene reference links.
	click(app.page, "ReferenceButton")
	assert_dialog(app, "sticker_catalog")
	click(app.overlay, "WeaponButton")
	assert_dialog(app, "sticker_picker")
	click(app.overlay, "Frame/CloseButton")
	click(app.page, "ReferenceButton")
	for button in ["CityButton", "MarketButton"]:
		click(app.overlay, button)
		assert_dialog(app, "image_view")
		assert(app.overlay.get_node("Picture").texture != null)
		click(app.overlay, "BackButton")
		assert_dialog(app, "sticker_catalog")
	click(app.overlay, "BackButton")
	assert(app.overlay == null)

	# Headless rendering cannot capture GPU viewports; provide the cached capture
	# that the real controller reuses when re-submitting an unchanged revision.
	var state: Dictionary = app.drawings[app.topic]
	state.result = ImageTexture.create_from_image(state.pixels)
	state.submitted = state.revision
	click(app.page, "SubmitButton")
	assert_dialog(app, "submission_result")
	assert(app.overlay.get_node("Artwork").texture == state.result)
	encoded_before = app.draft_cache.encodes
	click(app.overlay, "SaveButton")
	assert_dialog(app, "save_confirmation")
	assert(app.local_store.document.works.size() == 1)
	assert(app.draft_cache.encodes == encoded_before, "Saving a work encoded the unchanged draft again")
	assert(app.storage_candidate().drafts[str(app.topic)].work_id == state.work_id)
	var original_work: Dictionary = app.local_store.document.works[0].duplicate(true)
	click(app.overlay, "GalleryButton")
	assert(app.current == "gallery" and app.gallery_tab == 0)
	assert(visible_card_count(app.page.get_node("MyWorks/Cards")) == 1)
	assert(not app.page.get_node("MyWorks/EmptyState").visible)
	click(app.page, "MyWorks/Cards/Work1/ViewButton")
	assert_dialog(app, "work_view")
	click(app.overlay, "EditButton")
	assert_dialog(app, "open_work_confirmation")
	click(app.overlay, "ConfirmButton")
	assert(app.current == "canvas" and app.selected_tool == "移动")
	assert(app.drawings[app.topic].work_id == original_work.id)
	app.drawing.add_object("dufu_greatsword")
	state = app.drawings[app.topic]
	state.result = ImageTexture.create_from_image(state.pixels)
	state.submitted = state.revision
	var saved_before: Dictionary = app.local_store.document.duplicate(true)
	var work_id_before: String = state.work_id
	app.local_store.fail_writes = true
	app.save_work(false)
	assert_dialog(app, "info")
	assert(app.local_store.document == saved_before)
	assert(state.work_id == work_id_before, "A failed write changed the draft's saved work identity")
	encoded_before = app.draft_cache.encodes
	app.local_store.fail_writes = false
	writes_before = app.local_store.writes
	app._web_focus_lost([])
	assert(app.local_store.writes == writes_before + 1, "Focus loss did not retry the failed work's draft")
	assert(app.local_store.document.drafts[str(app.topic)] == Store.encode(state))
	assert(app.local_store.document.works == saved_before.works, "A background retry silently saved a gallery work")
	assert(app.local_store.document.next_id == saved_before.next_id)
	assert(state.work_id == work_id_before)
	assert(app.draft_cache.encodes == encoded_before)
	app.save_work(false)
	assert(app.local_store.document.works.size() == 2)
	assert(app.local_store.document.works[0] == original_work)
	assert(app.draft_cache.encodes == encoded_before, "Retry encoded unchanged pixels again")
	for i in range(3): app.save_work(true)
	assert(app.local_store.document.works.size() == 5)
	assert(app.local_store.document.works[0] == original_work, "Saving new versions mutated an older work")
	assert(app.storage_candidate().drafts[str(app.topic)].work_id == state.work_id)
	click(app.overlay, "GalleryButton")
	var gallery_id: int = app.page.get_instance_id()
	assert(visible_card_count(app.page.get_node("MyWorks/Cards")) == 4)
	assert(not app.page.get_node("MyWorks/NextButton").disabled)
	click(app.page, "MyWorks/NextButton")
	assert(app.page.get_instance_id() == gallery_id)
	assert(app.gallery_page == 1)
	assert(visible_card_count(app.page.get_node("MyWorks/Cards")) == 1)
	assert(app.page.get_node("MyWorks/NextButton").disabled)
	var requests_before: int = app.work_view_requests
	click(app.page, "MyWorks/Cards/Work1/ViewButton")
	assert(app.work_view_requests == requests_before + 1, "Paging connected a work button more than once")
	assert(app.overlay.get_node("Frame/Title").text == original_work.title, "Work button captured a previous slot's work")
	click(app.overlay, "Frame/CloseButton")
	requests_before = app.work_edit_requests
	click(app.page, "MyWorks/Cards/Work1/EditButton")
	assert(app.work_edit_requests == requests_before + 1)
	click(app.overlay, "ConfirmButton")
	assert(app.drawings[app.topic].work_id == original_work.id, "Edit button captured a previous slot's work")
	assert(app.drawing.state.objects.size() == original_work.data.objects.size())
	assert(app.local_store.document.works[0] == original_work)
	app.show_page("gallery")
	gallery_id = app.page.get_instance_id()
	click(app.page, "MyWorks/PreviousButton")
	assert(app.page.get_instance_id() == gallery_id)
	assert(app.gallery_page == 0)
	requests_before = app.work_view_requests
	click(app.page, "MyWorks/Cards/Work1/ViewButton")
	assert(app.work_view_requests == requests_before + 1)
	assert(app.overlay.get_node("Frame/Title").text == app.local_store.document.works.back().title)
	click(app.overlay, "Frame/CloseButton")

	click(app.page, "ExamplesTab")
	assert(app.page.get_instance_id() == gallery_id)
	assert(visible_card_count(app.page.get_node("Examples/Cards")) == 4)
	click(app.page, "Examples/FilterSciFi")
	await process_frame
	assert(app.page.get_instance_id() == gallery_id)
	assert(app.gallery_filter == "科幻")
	assert(visible_card_count(app.page.get_node("Examples/Cards")) == 1)
	assert(app.page.get_node("Examples/Cards/Example2").position == Vector2.ZERO)
	click(app.page, "Examples/Cards/Example2/ViewButton")
	assert_dialog(app, "image_view")
	click(app.overlay, "BackButton")
	click(app.page, "MyWorksTab")
	click(app.page, "ExamplesTab")
	assert(app.page.get_instance_id() == gallery_id)
	assert(app.gallery_filter == "科幻")
	assert(visible_card_count(app.page.get_node("Examples/Cards")) == 1)
	click(app.page, "Frame/BackButton")
	click(app.page, "SettingsButton")
	assert(app.current == "settings")
	var settings_id: int = app.page.get_instance_id()
	app.page.get_node("VolumeSlider").value = 45
	app.page.get_node("VolumeSlider").value = 38
	app.page.get_node("VolumeSlider").value = 31
	assert(app.settings.volume == 31 and app.settings_writes == 0)
	app.flush_pending_saves()
	assert(app.settings_writes == 1, "Volume changes must coalesce into one settings write")
	app.page.get_node("SoundToggle").button_pressed = false
	app.page.get_node("QualityOption").item_selected.emit(0)
	assert(app.settings.volume == 31 and not app.settings.sound and app.settings.quality == 0)
	assert(app.settings_writes == 3)
	app.page.get_node("VolumeSlider").value = 32
	app.page.get_node("SoundToggle").button_pressed = true
	assert(app.settings_writes == 4)
	app.flush_pending_saves()
	assert(app.settings_writes == 4, "An immediate setting change left a duplicate volume save pending")
	assert(app.page.get_instance_id() == settings_id)
	app.page.get_node("VolumeSlider").value = 33
	app._web_focus_lost([])
	assert(app.settings_writes == 5, "Focus loss did not flush a pending volume change")
	app.page.get_node("VolumeSlider").value = 34
	click(app.page, "Frame/BackButton")
	assert(app.settings_writes == 6, "Leaving settings did not flush a pending volume change")
	click(app.page, "SettingsButton")
	var reset_page_id: int = app.page.get_instance_id()
	click(app.page, "ResetButton")
	assert_dialog(app, "reset_confirmation")
	click(app.overlay, "ConfirmButton")
	assert(app.settings.volume == 70 and app.settings.sound and app.settings.quality == 1)
	assert(app.settings == SettingsStore.defaults() and app.settings_store.stored == app.settings)
	assert(app.page.get_node("VolumeSlider").value == app.settings.volume)
	assert(app.page.get_instance_id() == reset_page_id, "Reset recreated the settings page")
	# The real main save path keeps a failed preference write pending for focus loss.
	app.settings_store.fail_writes = true
	app.page.get_node("VolumeSlider").value = 51
	app.flush_pending_saves()
	assert(app._settings_pending and app.settings_store.stored.volume == 70)
	assert(app.page.get_node("SettingsNote").text.contains("设置保存失败"))
	app.settings_store.fail_writes = false
	app._web_focus_lost([])
	assert(not app._settings_pending and app.settings_store.stored.volume == 51)
	assert(app.page.get_instance_id() == reset_page_id)

	# Failed writes show the pre-authored retry action; retry succeeds in memory.
	app.local_store.fail_writes = true
	app.autosave()
	assert(app.storage_retry.visible)
	app.local_store.fail_writes = false
	click(app.page, "Frame/StorageRetry")
	assert(not app.storage_retry.visible)
	click(app.page, "Frame/BackButton")
	click(app.page, "FreeDrawButton")
	assert(app.topic == -1)
	app.page.get_node("WidthSlider").value = 36
	app._web_focus_lost([])
	assert(app.local_store.document.tools.width == 36, "Focus loss did not flush the latest width")
	app.page.get_node("WidthSlider").value = 40
	click(app.page, "Frame/BackButton")
	assert(app.local_store.document.tools.width == 40, "Leaving canvas lost a pending width")
	click(app.page, "FreeDrawButton")
	assert(app.drawing.pen_width == 40)
	click(app.page, "SubmitButton")
	assert_dialog(app, "info")
	click(app.overlay, "OkayButton")
	# A failed ordinary draft write stays retryable after storage recovers.
	saved_before = app.local_store.document.duplicate(true)
	writes_before = app.local_store.writes
	app.local_store.fail_writes = true
	app.drawing.add_object("dufu_greatsword")
	assert(app.storage_retry.visible)
	assert(app.local_store.document == saved_before)
	assert(app.local_store.writes == writes_before)
	app.local_store.fail_writes = false
	app._web_focus_lost([])
	assert(not app.storage_retry.visible)
	assert(app.local_store.writes == writes_before + 1, "Focus loss did not retry a failed draft write")
	assert(app.local_store.document.drafts["-1"] == Store.encode(app.drawings[-1]))
	assert(app.local_store.document.drafts["-1"].objects.back().kind == "dufu_greatsword")
	assert(app.local_store.document.works == saved_before.works)
	click(app.page, "RestartButton")
	assert_dialog(app, "restart_confirmation")
	click(app.overlay, "ConfirmButton")
	assert(not app.drawing.has_creation())
	assert(app.local_store.document.works.size() == 5)
	assert(Store.validate_document(app.local_store.document))
	assert(app.get_node("PageHost").get_child_count() == 1)
	app.page.get_node("WidthSlider").value = 44
	app.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert(app.local_store.document.tools.width == 44, "Native focus loss did not flush a pending width")
	var final_store: MemoryStore = app.local_store
	writes_before = final_store.writes
	app.page.get_node("WidthSlider").value = 48
	assert(final_store.writes == writes_before and final_store.document.tools.width == 44)
	app.free()
	assert(final_store.document.tools.width == 48, "Exiting discarded a pending width change")
	assert(final_store.writes == writes_before + 1, "Exiting must flush the pending save once")
	# Exercise main._ready with invalid persisted preferences, using memory I/O.
	var restored = MainScene.instantiate()
	restored.set_script(IsolatedApp)
	restored.saved_settings = {"volume": 160, "quality": -10, "sound": "false", "music": false}
	root.add_child(restored)
	assert(restored.settings == {"volume": 100.0, "quality": 0, "sound": true, "music": false, "motion": false})
	assert(restored.settings_writes == 0, "Loading preferences unexpectedly wrote settings")
	restored.show_page("settings")
	assert(restored.page.get_node("VolumeSlider").value == 100)
	assert(restored.page.get_node("QualityOption").selected == 0)
	assert(restored.page.get_node("SoundToggle").button_pressed)
	assert(not restored.page.get_node("MusicToggle").button_pressed)
	restored.free()
	await process_frame
	print("UI_SCENE_TESTS_PASSED")
	quit()
