extends SceneTree
## Exercises the player's autosaved-draft gallery flow without touching user data.
## Run: Godot --headless --path . --script res://tests/draft_gallery_test.gd

const MainScene = preload("res://scenes/main.tscn")
const Fixtures = preload("res://tests/ui_scene_test.gd")
const Store = preload("res://scripts/local_store.gd")
const Surface = preload("res://scripts/drawing_surface.gd")

class IsolatedApp:
	extends "res://scripts/main.gd"
	var saved_document: Dictionary = {}

	func _ready() -> void:
		local_store = Fixtures.MemoryStore.new()
		if not saved_document.is_empty():
			assert(Store.validate_document(saved_document))
			local_store.document = saved_document.duplicate(true)
		settings_store = Fixtures.MemorySettingsStore.new()
		super._ready()

func _initialize() -> void:
	call_deferred("run")

func create_app(document: Dictionary = {}) -> Variant:
	var app = MainScene.instantiate()
	app.set_script(IsolatedApp)
	# Gallery coverage visits every topic; unlocking is tested in level_flow_test.
	app.saved_document = Store.empty_document() if document.is_empty() else document.duplicate(true)
	app.saved_document.completed_topics = [0, 1, 2, 3]
	root.add_child(app)
	return app

func click(view: Node, path: NodePath) -> void:
	var button: BaseButton = view.get_node(path)
	assert(button.is_visible_in_tree(), "Button is hidden: %s" % path)
	assert(not button.disabled, "Button is disabled: %s" % path)
	button.pressed.emit()

func card_count(app: Control) -> int:
	var count := 0
	for card in app.page.get_node("MyWorks/Cards").get_children():
		if card.is_visible_in_tree(): count += 1
	return count

func card_surface(app: Control, slot: int = 1) -> Control:
	return app.page.get_node("MyWorks/Cards/Work%d/DraftPreview/DrawingSurface" % slot)

func assert_picture_content(surface: Control, expected: Dictionary) -> void:
	assert(surface.preview_only and surface.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var normalized: Dictionary = Store.decode(Store.encode(expected))
	assert(surface.state.objects == normalized.objects, "Preview lost or changed editable objects")
	assert(surface.state.pixels.get_data() == expected.pixels.get_data(), "Preview lost drawn strokes")
	assert(surface.texture.get_image().get_data() == expected.pixels.get_data())
	assert(surface.size == Vector2(Surface.WIDTH, Surface.HEIGHT), "Preview must preserve drawing coordinates")
	assert(is_equal_approx(surface.scale.x, surface.scale.y), "Preview distorted the artwork")

func run() -> void:
	var app = create_app()
	await process_frame
	app._start_topic(0)
	app._show_gallery(0)
	assert(card_count(app) == 0, "Visiting a blank canvas created an empty gallery entry")
	assert(app.page.get_node("MyWorks/EmptyState").visible)
	app._start_topic(0)
	app.local_store.fail_writes = true
	app.drawing.begin(Vector2(480, 100), -1)
	app.drawing.move_pen(Vector2(640, 145))
	app.drawing.finish()
	app.drawing.add_object("text", "自动保存草稿", 36, Color("3a9d8f"))
	app.drawing.add_object("weapon_blue")
	var state: Dictionary = app.drawings[0]
	assert(state.submitted == -1 and state.result == null)
	app.set_tool("橡皮")
	app._show_gallery(0)
	assert(card_count(app) == 0, "A failed first save was shown as a persisted draft")
	assert(app.storage_retry.visible)
	var gallery_id: int = app.page.get_instance_id()
	app.local_store.fail_writes = false
	click(app.page, "Frame/StorageRetry")
	assert(app.page.get_instance_id() == gallery_id)
	assert(card_count(app) == 1, "Retry did not add the newly saved draft to the open gallery")
	assert(not app.storage_retry.visible)
	assert(app.local_store.document.works.is_empty(), "Autosaving created a completed work")
	assert(app.page.get_node("MyWorks/Cards/Work1/DraftPreview").visible)
	assert(not app.page.get_node("MyWorks/Cards/Work1/Picture").visible)
	assert_picture_content(card_surface(app), state)
	assert(state.undo.size() == 3)
	click(app.page, "MyWorks/Cards/Work1/ViewButton")
	assert(app.overlay.scene_file_path == "res://scenes/dialogs/work_view.tscn")
	assert(app.overlay.get_node("DraftPreview").visible)
	assert(not app.overlay.get_node("Artwork").visible)
	assert_picture_content(app.overlay.get_node("DraftPreview/DrawingSurface"), state)
	assert(not app.overlay.get_node("DownloadButton").visible)
	click(app.overlay, "EditButton")
	assert(app.current == "canvas" and app.topic == 0 and app.overlay == null)
	assert(app.drawings[0].undo.size() == 3, "Continuing a draft discarded undo history")
	assert(app.selected_tool == "橡皮" and app.drawing.erasing, "Continuing changed the selected tool")
	click(app.page, "UndoButton")
	assert(app.drawing.state.objects.size() == 2)
	click(app.page, "RedoButton")
	assert(app.drawing.state.objects.size() == 3)
	app.drawing.state.selected = app.drawing.state.objects[1].id
	app.drawing.edit_text("继续编辑草稿", 40, Color("aa4937"))
	app._show_gallery(0)
	assert(card_count(app) == 1, "Editing a draft created duplicate gallery entries")
	assert_picture_content(card_surface(app), app.drawings[0])
	assert(card_surface(app).state.objects[1].text == "继续编辑草稿")

	# The gallery shows the last persisted snapshot during an error, while opening
	# that entry must retain newer unsaved changes and their undo history.
	click(app.page, "MyWorks/Cards/Work1/EditButton")
	var saved_objects: int = app.drawing.state.objects.size()
	app.local_store.fail_writes = true
	app.drawing.add_object("weapon_violet")
	var unsaved_undo: int = app.drawing.state.undo.size()
	app._show_gallery(0)
	assert(card_surface(app).state.objects.size() == saved_objects)
	click(app.page, "MyWorks/Cards/Work1/EditButton")
	assert(app.drawing.state.objects.size() == saved_objects + 1, "Opening the saved snapshot lost unsaved edits")
	assert(app.drawing.state.undo.size() == unsaved_undo)
	assert(app._draft_save_pending and app.storage_retry.visible)
	app._show_gallery(0)
	gallery_id = app.page.get_instance_id()
	app.local_store.fail_writes = false
	click(app.page, "Frame/StorageRetry")
	assert(app.page.get_instance_id() == gallery_id and card_count(app) == 1)
	assert_picture_content(card_surface(app), app.drawings[0])
	assert(card_surface(app).state.objects.size() == saved_objects + 1)
	assert(not app._draft_save_pending)

	# Current-format drafts are discoverable after relaunch without an explicit
	# submission or finished-work save.
	var saved_document: Dictionary = app.local_store.document.duplicate(true)
	assert(saved_document.version == Store.VERSION and saved_document.works.is_empty())
	app.free()
	app = create_app(saved_document)
	assert(app.current == "gallery" and card_count(app) == 1)
	assert_picture_content(card_surface(app), Store.decode(saved_document.drafts["0"]))
	click(app.page, "MyWorks/Cards/Work1/EditButton")
	assert(app.current == "canvas" and app.topic == 0)
	assert(app.drawing.state.undo.is_empty(), "Undo history is intentionally session-local")
	app.drawing.add_object("text", "重新打开", 28, Color("243d35"))
	assert(app.local_store.document.drafts["0"].objects.back().text == "重新打开")
	for topic_id in [-1, 1, 2, 3]:
		app._start_topic(topic_id)
		app.drawing.add_object("text", "关卡 %d" % topic_id)
	app._show_gallery(0)
	assert(card_count(app) == 4)
	assert(not app.page.get_node("MyWorks/NextButton").disabled)
	click(app.page, "MyWorks/NextButton")
	assert(app.gallery_page == 1 and card_count(app) == 1)
	assert(app.page.get_node("MyWorks/NextButton").disabled)
	click(app.page, "MyWorks/Cards/Work1/EditButton")
	assert(app.topic == -1, "Paged card continued another topic's draft")
	assert(app.drawing.state.objects.back().text == "关卡 -1")
	app.free()

	# A manually saved finished version remains immutable. Its identical draft is
	# represented once; subsequent edits become a distinct draft beside the work.
	app = create_app()
	app._start_topic(0)
	app.drawing.add_object("weapon_du")
	state = app.drawings[0]
	state.submitted = state.revision
	state.result = ImageTexture.create_from_image(state.pixels)
	app.save_work(false)
	assert(app.local_store.document.works.size() == 1)
	var original_work: Dictionary = app.local_store.document.works[0].duplicate(true)
	click(app.overlay, "GalleryButton")
	assert(card_count(app) == 1, "An unchanged saved work was duplicated as a draft")
	assert(app.page.get_node("MyWorks/Cards/Work1/Picture").visible)
	assert(not app.page.get_node("MyWorks/Cards/Work1/DraftPreview").visible)
	click(app.page, "MyWorks/Cards/Work1/EditButton")
	assert(app.overlay.scene_file_path == "res://scenes/dialogs/open_work_confirmation.tscn")
	click(app.overlay, "ConfirmButton")
	app.drawing.add_object("text", "新草稿")
	app._show_gallery(0)
	assert(card_count(app) == 2)
	assert(app.local_store.document.works[0] == original_work, "Draft edits changed a completed work")
	assert(app.page.get_node("MyWorks/Cards/Work1/DraftPreview").visible)
	click(app.page, "MyWorks/Cards/Work1/EditButton")
	click(app.page, "RestartButton")
	click(app.overlay, "ConfirmButton")
	assert(not app.drawing.has_creation())
	app._show_gallery(0)
	assert(card_count(app) == 1, "Resetting the canvas kept an empty draft entry")
	assert(app.local_store.document.works[0] == original_work, "Resetting a draft removed the saved work")
	assert(app.page.get_node("MyWorks/Cards/Work1/Picture").visible)
	app.free()
	await process_frame
	print("DRAFT_GALLERY_TESTS_PASSED")
	quit()
