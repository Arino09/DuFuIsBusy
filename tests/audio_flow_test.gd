extends SceneTree
## Plays real scenes against the shipped audio table and checks which events a player would hear.
## Run: Godot --headless --path . --script res://tests/audio_flow_test.gd
const UiTest = preload("res://tests/ui_scene_test.gd")
const Store = preload("res://scripts/local_store.gd")
const MainScene = preload("res://scenes/main.tscn")

var director: Node

func _initialize() -> void:
	call_deferred("run")

func heard(action: Callable) -> PackedStringArray:
	director.calls.clear()
	action.call()
	await process_frame
	return PackedStringArray(Array(director.calls).filter(func(call: String): return call.begins_with("post ")))

func expect(label: String, got: PackedStringArray, want: Array) -> void:
	assert(got == PackedStringArray(want), "%s: heard %s, expected %s" % [label, got, want])

func press(view: Node, path: NodePath) -> void:
	var control: BaseButton = view.get_node(path)
	assert(control.is_visible_in_tree() and not control.disabled, "Cannot press " + str(path))
	control.pressed.emit()

func run() -> void:
	director = root.get_node("AudioDirector")
	await process_frame
	assert(director.running and director.wwise == null, "Headless routes without Wwise")
	var app = MainScene.instantiate()
	app.set_script(UiTest.IsolatedApp)
	app.saved_document = Store.empty_document()
	app.saved_document.completed_topics = [0, 1]
	root.add_child(app)
	await process_frame
	# Dismiss the startup notice before exercising home-page buttons.
	app.close_overlay()
	await process_frame

	# Page transitions play their dedicated exit and enter events once.
	expect("Start game", await heard(func(): press(app.page, "LevelsButton")), ["post Play_SFX_Exit_Home", "post Play_SFX_Enter_Level"])
	expect("Start a level", await heard(func(): press(app.page, "Topic3/EnterButton")), ["post Play_SFX_Exit_Levels", "post Play_SFX_Enter_Canvas"])
	assert(app.current == "canvas")

	# No generic UI event is authored; tool changes are silent.
	expect("Eraser tool", await heard(func(): press(app.page, "ToolEraser")), [])
	expect("Move tool", await heard(func(): press(app.page, "ToolMove")), [])
	expect("Brush tool", await heard(func(): press(app.page, "ToolBrush")), [])

	# Each brush stroke starts and stops its loop; RTPCs are checked in audio_test.gd.
	expect("Brush stroke", await heard(func():
		app.drawing.begin(Vector2(500, 150), -1)
		app.drawing.move_pen(Vector2(600, 180))
		app.drawing.finish()), ["post Play_SFX_Brush_Loop", "post Stop_SFX_Brush_Loop"])
	expect("Undo", await heard(func(): press(app.page, "UndoButton")), [])
	expect("Redo", await heard(func(): press(app.page, "RedoButton")), [])
	app.apply_color(Color("3a9d8f"))
	expect("Eraser stroke", await heard(func():
		app.drawing.erasing = true
		app.drawing.begin(Vector2(520, 160), -1)
		app.drawing.finish()
		app.drawing.erasing = false), [])

	# Dialogs and layer edits remain silent until dedicated events are authored.
	expect("Open stickers", await heard(func(): press(app.page, "StickerButton")), [])
	expect("Add sticker", await heard(func(): press(app.overlay, "Scroll/Grid/food_authority/Content/UseButton")), [])
	expect("Delete layer", await heard(func(): press(app.page, "DeleteObjectButton")), [])
	expect("Open stickers again", await heard(func(): press(app.page, "StickerButton")), [])
	expect("Close dialog", await heard(func(): press(app.overlay, "Frame/CloseButton")), [])
	expect("Open text editor", await heard(func(): press(app.page, "AddTextButton")), [])
	app.overlay.get_node("TextInput").text = "诗圣摸鱼"
	expect("Add text", await heard(func(): press(app.overlay, "ApplyButton")), [])
	expect("Clear draft prompt", await heard(func(): press(app.page, "RestartButton")), [])
	expect("Cancel clearing", await heard(func(): press(app.overlay, "CancelButton")), [])
	expect("Clear draft prompt again", await heard(func(): press(app.page, "RestartButton")), [])
	expect("Confirm clearing", await heard(func(): press(app.overlay, "ConfirmButton")), [])

	# Submit, save and unlock the next level.
	press(app.page, "ToolBrush")
	app.drawing.begin(Vector2(500, 150), -1)
	app.drawing.move_pen(Vector2(600, 180))
	app.drawing.finish()
	var state: Dictionary = app.drawings[app.topic]
	state.result = ImageTexture.create_from_image(state.pixels)
	state.submitted = state.revision
	expect("Submit", await heard(func(): press(app.page, "SubmitButton")), [])
	expect("Save work", await heard(func(): press(app.overlay, "SaveButton")), [])
	press(app.overlay, "GalleryButton")
	await process_frame

	# Sound toggle and volume slider have no authored UI feedback.
	app.show_page("settings")
	await process_frame
	var sound: BaseButton = app.page.get_node("SoundToggle")
	app.page.get_viewport().gui_release_focus()
	director.binder.last_input_ms = Time.get_ticks_msec()
	sound.grab_focus()
	var before := sound.button_pressed
	expect("Sound toggle", await heard(func(): sound.button_pressed = not before), [])
	sound.button_pressed = before
	var slider: Slider = app.page.get_node("VolumeSlider")
	slider.grab_focus()
	director.binder.last_input_ms = Time.get_ticks_msec()
	expect("Volume tick", await heard(func(): slider.value = clampf(slider.value + 5, 0, 100)), [])
	var music: BaseButton = app.page.get_node("MusicToggle")
	music.grab_focus()
	director.binder.last_input_ms = Time.get_ticks_msec()
	music.set_pressed_no_signal(true)
	expect("Music off", await heard(func(): music.button_pressed = false), ["post Stop_Music_Theme"])
	director.binder.last_input_ms = Time.get_ticks_msec()
	expect("Music on", await heard(func(): music.button_pressed = true), ["post Play_Music_Theme"])
	print("AUDIO_FLOW_TESTS_PASSED")
	quit()
