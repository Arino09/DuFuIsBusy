extends SceneTree
## Exercise save-before-unlock against real controllers using memory-only storage.
const Fixtures = preload("res://tests/ui_scene_test.gd")
const MainScene = preload("res://scenes/main.tscn")
const Surface = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")

func _initialize() -> void:
	call_deferred("run")

func new_app(document: Dictionary = {}) -> Control:
	var app = MainScene.instantiate()
	app.set_script(Fixtures.IsolatedApp)
	if not document.is_empty(): app.saved_document = document.duplicate(true)
	root.add_child(app)
	return app

func click(view: Node, path: NodePath) -> void:
	var button: BaseButton = view.get_node(path)
	assert(button.is_visible_in_tree(), "Hidden control: %s" % path)
	assert(not button.disabled, "Disabled control: %s" % path)
	button.pressed.emit()

func assert_dialog(app: Control, id: String) -> void:
	assert(is_instance_valid(app.overlay))
	assert(app.overlay.scene_file_path == "res://scenes/dialogs/%s.tscn" % id)

func cache_submission(app: Control) -> void:
	# Headless mode has no GPU capture. Reuse the controller's cached-result path.
	var state: Dictionary = app.drawings[app.topic]
	assert(app.drawing.has_creation())
	state.result = ImageTexture.create_from_image(state.pixels)
	state.submitted = state.revision

func assert_progress(app: Control, expected: Array[int]) -> void:
	assert(app.completed_topics == expected)
	assert(app.local_store.document.completed_topics == expected)
	assert(app._topic_unlocked(-1), "Free creation must always remain available")

func run() -> void:
	var app = new_app()
	await process_frame
	assert_progress(app, [])
	click(app.page, "LevelsButton")
	assert(not app.page.get_node("Topic1/EnterButton").disabled)
	for card in ["Topic2", "Topic3", "Topic4"]:
		assert(app.page.get_node(card + "/EnterButton").disabled)
	# Even an emitted signal cannot bypass the navigation guard.
	app.page.get_node("Topic3/EnterButton").pressed.emit()
	assert(app.current == "levels" and app.topic == 0)
	assert_dialog(app, "info")
	app.close_overlay()

	# Saving free creation is allowed but cannot advance the themed levels.
	app.show_page("home")
	click(app.page, "FreeDrawButton")
	assert(app.current == "canvas" and app.topic == -1)
	app.drawing.add_object("weapon_du")
	cache_submission(app)
	click(app.page, "SubmitButton")
	click(app.overlay, "SaveButton")
	assert_dialog(app, "save_confirmation")
	assert(app.local_store.document.works.size() == 1)
	assert_progress(app, [])
	click(app.overlay, "NextButton")
	assert(app.current == "levels")
	assert(app.page.get_node("Topic2/EnterButton").disabled)

	click(app.page, "Topic1/EnterButton")
	click(app.page, "SubmitButton")
	assert_dialog(app, "info")
	assert_progress(app, [])
	app.close_overlay()
	app.drawing.add_object("weapon_blue")
	cache_submission(app)
	click(app.page, "SubmitButton")
	assert_dialog(app, "submission_result")
	assert_progress(app, [])
	click(app.overlay, "ContinueButton")
	assert(app.current == "canvas" and app.topic == 0)
	click(app.page, "ChangeTopicButton")
	assert(app.current == "levels")
	assert(app.page.get_node("Topic2/EnterButton").disabled, "Submission must not unlock the next level")
	click(app.page, "Topic1/EnterButton")
	click(app.page, "SubmitButton")

	# An explicit failed save stays failed, even after a later draft-only retry.
	var before_failure: Dictionary = app.local_store.document.duplicate(true)
	app.local_store.fail_writes = true
	click(app.overlay, "SaveButton")
	assert_dialog(app, "info")
	assert(app.local_store.document == before_failure)
	assert_progress(app, [])
	app.local_store.fail_writes = false
	app._web_focus_lost([])
	assert(app.local_store.document.works == before_failure.works)
	assert(app.local_store.document.next_id == before_failure.next_id)
	assert(app.local_store.document.drafts["0"].submitted >= 0)
	assert_progress(app, [])
	assert(not app._topic_unlocked(1))
	app.close_overlay()
	click(app.page, "SubmitButton")
	click(app.overlay, "SaveButton")
	assert_dialog(app, "save_confirmation")
	assert_progress(app, [0])
	assert(app.local_store.document.works.size() == 2)
	var completed_work: Dictionary = app.local_store.document.works.back().duplicate(true)
	assert(app._topic_unlocked(1) and not app._topic_unlocked(2))
	click(app.overlay, "NextButton")
	assert(app.current == "canvas" and app.topic == 1)

	# Normal editing, clearing a completed canvas and resetting preferences cannot
	# erase an already persisted completion record or its immutable saved artwork.
	app.drawing.add_object("weapon_pink")
	click(app.page, "UndoButton")
	assert_progress(app, [0])
	click(app.page, "RedoButton")
	assert_progress(app, [0])
	app._start_topic(0)
	app.restart_confirm()
	click(app.overlay, "ConfirmButton")
	assert(not app.drawing.has_creation())
	assert_progress(app, [0])
	assert(app.local_store.document.works.back() == completed_work)
	app.show_page("settings")
	click(app.page, "ResetButton")
	click(app.overlay, "ConfirmButton")
	assert_progress(app, [0])
	app.show_page("levels")
	assert(not app.page.get_node("Topic2/EnterButton").disabled)
	assert(app.page.get_node("Topic3/EnterButton").disabled)
	var persisted: Dictionary = app.local_store.document.duplicate(true)
	app.free()
	await process_frame

	# Reload uses durable progress, including when completed versions are absent.
	persisted.works.clear()
	app = new_app(persisted)
	await process_frame
	assert_progress(app, [0])
	assert(app.current == "levels")
	assert(not app.page.get_node("Topic2/EnterButton").disabled)
	assert(app.page.get_node("Topic3/EnterButton").disabled)
	app.free()
	await process_frame

	# A complete current-format journey advances only after each successful save.
	app = new_app(persisted)
	await process_frame
	for id in [1, 2, 3]:
		app._start_topic(id)
		assert(app.current == "canvas" and app.topic == id)
		app.drawing.add_object("weapon_silver")
		cache_submission(app)
		click(app.page, "SubmitButton")
		var before_save: Array[int] = []
		before_save.assign(range(id))
		assert_progress(app, before_save)
		click(app.overlay, "SaveButton")
		var after_save: Array[int] = []
		after_save.assign(range(id + 1))
		assert_progress(app, after_save)
		assert_dialog(app, "save_confirmation")
		click(app.overlay, "NextButton")
		if id < 3:
			assert(app.current == "canvas" and app.topic == id + 1)
		else:
			assert(app.current == "levels")
	assert(app.local_store.document.works.size() == 3)
	app.free()
	await process_frame

	# Current-format data in a locked level stays viewable without granting access.
	var locked := Store.empty_document()
	var draft := Surface.new_state()
	draft.pixels.set_pixel(500, 100, Color.BLACK)
	draft.revision = 1
	draft.submitted = 1
	var encoded := Store.encode(draft)
	locked.drafts["2"] = encoded
	locked.topic = 2
	locked.page = "canvas"
	app = new_app(locked)
	await process_frame
	assert(app.current == "levels", "Startup must not reopen a locked level")
	assert_progress(app, [])
	assert(app.local_store.document.drafts["2"] == encoded)
	app._show_gallery(0)
	assert(app.page.get_node("MyWorks/Cards/Work1").visible)
	click(app.page, "MyWorks/Cards/Work1/ViewButton")
	assert_dialog(app, "work_view")
	assert(app.overlay.get_node("DraftPreview").visible)
	click(app.overlay, "EditButton")
	assert_dialog(app, "info")
	assert(app.current == "gallery")
	assert(app.local_store.document.drafts["2"] == encoded)
	app.close_overlay()
	click(app.page, "MyWorks/Cards/Work1/EditButton")
	assert_dialog(app, "info")
	assert(app.current == "gallery")
	assert_progress(app, [])
	app.close_overlay()
	app._start_topic(-1)
	assert(app.current == "canvas" and app.topic == -1)
	assert(app.local_store.document.drafts["2"] == encoded)
	app.free()
	await process_frame
	print("LEVEL_FLOW_TESTS_PASSED")
	quit()
