extends SceneTree
## Regression coverage for the feedback: off-paper layers, order, mirrors, saves and audio output.
const Fixtures = preload("res://tests/ui_scene_test.gd")
const Drawing = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")
const Entries = preload("res://scripts/gallery_entries.gd")
const Director = preload("res://scripts/audio/audio_director.gd")
const Table = preload("res://scripts/audio/audio_table.gd")

class AudioBackend:
	extends RefCounted
	var gains: Dictionary = {}
	var events: Array = []
	func set_game_object_output_bus_volume(emitter: Node, _listener: Node, gain: float) -> bool:
		gains[emitter] = gain
		return true
	func post_event(event: String, emitter: Node) -> int:
		events.append([event, emitter])
		return 1

func _initialize() -> void:
	call_deferred("run")

func test_mix() -> void:
	var director := Director.new()
	var backend := AudioBackend.new()
	var music := Node.new()
	director._music_emitter = music
	director.wwise = backend
	director.load_table(Table.from_file(Director.TABLE_PATH))
	# Preferences received before Wwise starts must apply before the first event.
	director.param("setting.volume", 0.0)
	director.param("setting.music", 0.0)
	director.param("setting.sound", 0.0)
	director.running = true
	director._apply_mix()
	assert(backend.gains[director] == 0.0 and backend.gains[music] == 0.0)
	director.cue("app.boot")
	assert(backend.events == [["Play_Music_Theme", music]])
	director.cue("page.enter.home")
	assert(backend.events.size() == 1, "Muted effects cannot start new voices")
	director.param("setting.volume", 25.0)
	assert(backend.gains[director] == 0.0 and backend.gains[music] == 0.0)
	director.param("setting.music", 1.0)
	assert(backend.gains[music] == 0.25 and backend.gains[director] == 0.0)
	director.param("setting.sound", 1.0)
	director.cue("page.enter.home")
	assert(backend.gains[director] == 0.25 and backend.events[-1] == ["Play_SFX_Enter_Home", director])
	director.param("setting.sound", 0.0)
	director.cue("canvas.drag.end.paint")
	assert(backend.events[-1] == ["Stop_SFX_Brush_Loop", director], "Mute cannot swallow loop cleanup")
	assert(backend.gains[music] == 0.25, "Disabling effects must preserve music")
	director.param("setting.volume", 0.0)
	assert(backend.gains[music] == 0.0 and backend.gains[director] == 0.0)
	director.param("setting.volume", 100.0)
	assert(backend.gains[music] == 1.0 and backend.gains[director] == 0.0)
	director.free()
	music.free()

func run() -> void:
	root.size = Vector2i(1440, 900)
	test_mix()
	var app = Fixtures.MainScene.instantiate()
	app.set_script(Fixtures.IsolatedApp)
	app.saved_settings = {"volume": 0.0}
	root.add_child(app)
	app.close_overlay()
	app._start_topic(-1)
	app.set_tool("移动")
	var surface = app.drawing
	surface.add_object("dufu_greatsword")
	var sticker_id: int = surface.state.selected
	surface.add_object("text", "图层测试")
	surface.select_object(sticker_id)
	app.page.layer_action("bottom")
	assert(surface.state.objects[0].id == sticker_id)
	assert(surface.state.selected == sticker_id)
	app.page.layer_action("up")
	assert(surface.state.objects[1].id == sticker_id)
	app.page.layer_action("top")
	assert(surface.state.objects.back().id == sticker_id)
	app.page.layer_action("down")
	assert(surface.state.objects[1].id == sticker_id)
	# The same order drives hit testing, with Dufu allowed above stickers.
	surface.select_object(0)
	surface.selected_object().position = Vector2(540, 540)
	app.page.layer_action("top")
	surface.select_at(Vector2(540, 540))
	assert(surface.state.selected == 0)
	var revision: int = surface.state.revision
	app.page.layer_action("top")
	assert(surface.state.revision == revision, "An already-top layer cannot dirty the draft")
	surface.select_object(sticker_id)
	surface.selected_object().position = Vector2(800, 400)
	surface.begin(Vector2(800, 400), -1)
	surface.move_pen(Vector2(-420, 200))
	surface.finish()
	assert(surface.selected_object().position == Vector2(-420, 200))
	var saved := Store.decode(app.local_store.document.drafts["-1"])
	assert(not saved.is_empty() and saved.objects.filter(func(layer: Dictionary): return layer.id == sticker_id)[0].position == Vector2(-420, 200))
	# Click an off-paper body through the real workspace GUI, then drag it back.
	await process_frame
	surface.select_object(-1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = surface.get_global_transform_with_canvas() * Vector2(-420, 200)
	root.push_input(press, true)
	assert(surface.active and surface.state.selected == sticker_id)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = surface.get_global_transform_with_canvas() * Vector2(-400, 200)
	root.push_input(motion, true)
	assert(surface.selected_object().position.is_equal_approx(Vector2(-400, 200)))
	motion.position = press.position
	root.push_input(motion, true)
	press.pressed = false
	root.push_input(press, true)
	assert(not surface.active)
	# An off-paper layer remains selectable, mirrored and resizable.
	surface.select_at(Vector2(-420, 200))
	assert(surface.state.selected == sticker_id)
	app.page.layer_action("flip_h")
	app.page.layer_action("flip_v")
	var object: Dictionary = surface.selected_object()
	assert(Drawing.render_scale(object) == -Vector2.ONE)
	assert(surface.transform_for(object) * Vector2(10, 20) == object.position - Vector2(10, 20))
	var handles = surface.resize_handles(object)
	var opposite: Vector2 = handles[0]
	surface.begin(handles[4], -1)
	surface.move_pen(handles[4] + (handles[4] - opposite) * 0.5)
	surface.finish()
	assert(surface.resize_handles(object)[0].is_equal_approx(opposite))
	assert(Drawing.object_scale(object).is_equal_approx(Vector2.ONE * 1.5))
	var order: Array = surface.state.objects.map(func(layer: Dictionary): return layer.id)
	var encoded := Store.encode(surface.state)
	assert(Store.encode(Store.decode(encoded)) == encoded, "Order, outside positions and mirrors must round-trip")
	assert(Store.decode(encoded).objects.map(func(layer: Dictionary): return layer.id) == order)
	# Recover through the actual picker and button even when no part is visible.
	var outside_position: Vector2 = object.position
	surface.select_object(-1)
	app.page.layer_picker.item_selected.emit(app.page.layer_picker.get_item_index(sticker_id))
	assert(surface.state.selected == sticker_id)
	app.page.get_node("LayerTools/CenterLayerButton").pressed.emit()
	assert(surface.selected_object().position == Vector2(surface.canvas_size()) / 2)
	app.page.layer_picker.item_selected.emit(app.page.layer_picker.get_item_index(0))
	assert(surface.state.selected == 0, "Placeholder cannot shadow Dufu's ID in the picker")
	app.page.layer_picker.item_selected.emit(0)
	assert(surface.state.selected == -1)
	surface.travel(false)
	surface.select_object(sticker_id)
	assert(surface.selected_object().position == outside_position)
	surface.travel(true)
	surface.select_object(sticker_id)
	assert(surface.selected_object().position == Vector2(surface.canvas_size()) / 2)
	# All six topics can be serialized and discovered in the gallery.
	var document := Store.empty_document()
	document.completed_topics = [0, 1, 2, 3, 4, 5]
	document.topic = 5
	for id in range(6): document.drafts[str(id)] = encoded
	assert(Store.validate_document(document))
	assert(Entries.build(document, func(id: int): return str(id)).size() == 6)
	var invalid := encoded.duplicate(true)
	invalid.objects.append(invalid.objects.back().duplicate(true))
	assert(Store.decode(invalid).is_empty())
	invalid = encoded.duplicate(true)
	invalid.objects[0].flip_h = 1
	assert(Store.decode(invalid).is_empty())
	if DisplayServer.get_name() != "headless":
		await test_rendering()
	app.free()
	await process_frame
	print("FEEDBACK_TESTS_PASSED")
	quit()

func test_rendering() -> void:
	var surface := Drawing.new()
	surface.state = Drawing.new_state("paper", Vector2i(256, 256))
	root.add_child(surface)
	surface.select_object(0)
	surface.selected_object().position = Vector2(128, 128)
	var original := await surface.artwork()
	surface.flip_selected(false)
	var reflected := await surface.artwork()
	assert(original.get_size() == Vector2i(256, 256))
	assert(original.get_data() != reflected.get_data(), "Export must render the mirror")
	original.flip_x()
	assert(original.get_data() == reflected.get_data(), "Exported pixels must mirror exactly around the layer center")
	surface.add_object("text", "杜甫", 64, Color.RED)
	var above := await surface.artwork()
	surface.reorder_selected("bottom")
	var below := await surface.artwork()
	assert(above.get_data() != below.get_data(), "Export must respect layer order around Dufu")
	var decoded := Store.decode(Store.encode(surface.state))
	surface.state = decoded
	surface.refresh()
	var restored := await surface.artwork()
	assert(restored.get_data() == below.get_data(), "Reloaded artwork must export identical pixels")
	surface.select_object(0)
	surface.selected_object().position = Vector2(-500, -500)
	surface.select_object(1)
	surface.selected_object().position = Vector2(-500, -500)
	var outside := await surface.artwork()
	assert(outside.get_pixel(128, 128).is_equal_approx(Color("fffdf7")), "Off-paper layers and selection cannot leak into export")
	surface.free()
