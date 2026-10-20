extends SceneTree
## Backgrounds follow editable layers through drafts, gallery previews and reload.
const Fixtures = preload("res://tests/ui_scene_test.gd")
const Store = preload("res://scripts/local_store.gd")
const Backgrounds = preload("res://scripts/artwork_backgrounds.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app = Fixtures.MainScene.instantiate()
	app.set_script(Fixtures.IsolatedApp)
	app.saved_document = Store.empty_document()
	app.saved_document.completed_topics = [0, 1, 2, 3, 4, 5]
	root.add_child(app)
	var backgrounds: Array[String] = []
	for id in app.content_catalog.topic_ids():
		app._start_topic(id)
		var expected: String = app.content_catalog.get_topic(id).background_id
		assert(expected != "paper" and not backgrounds.has(expected))
		backgrounds.append(expected)
		assert(Backgrounds.texture_for(expected).get_size() == Vector2(1040, 330))
		assert(app.drawing.state.background_id == expected)
		assert(not app.drawing.has_creation(), "The supplied scenery cannot count as player creation")
		app.drawing.begin(Vector2(800, 210), -1)
		app.drawing.move_pen(Vector2(920, 220))
		app.drawing.finish()
		assert(app.local_store.document.drafts[str(id)].background_id == expected)
		app.drawing.travel(false)
		assert(app.drawing.state.background_id == expected and not app.drawing.has_creation())
		app.drawing.travel(true)
		app.set_tool("橡皮")
		app.drawing.begin(Vector2(800, 210), -1)
		app.drawing.finish()
		assert(app.drawing.state.background_id == expected)
		app.set_tool("笔刷")
	app._show_gallery(0)
	for card in app.page.get_node("MyWorks/Cards").get_children():
		assert(card.visible and card.get_node("DraftPreview").visible)
		var preview = card.get_node("DraftPreview/DrawingSurface")
		assert(preview.state.background_id in backgrounds)
	var saved: Dictionary = app.local_store.document.duplicate(true)
	app.free()
	app = Fixtures.MainScene.instantiate()
	app.set_script(Fixtures.IsolatedApp)
	app.saved_document = saved
	root.add_child(app)
	for id in app.content_catalog.topic_ids():
		app._start_topic(id)
		assert(app.drawing.state.background_id == backgrounds[id])
		app._restart_drawing()
		assert(app.drawing.state.background_id == backgrounds[id] and not app.drawing.has_creation())
	app._start_topic(-1)
	assert(app.drawing.state.background_id == "paper")
	assert(Backgrounds.texture_for("paper") == null)
	app.free()
	await process_frame
	print("BACKGROUND_TESTS_PASSED")
	quit()
