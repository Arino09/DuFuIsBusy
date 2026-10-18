extends SceneTree
## Plays real scenes against the shipped audio table and checks which events a player would hear.
## Run: Godot --headless --path . --script res://tests/audio_flow_test.gd
const UiTest = preload("res://tests/ui_scene_test.gd")
const Store = preload("res://scripts/local_store.gd")
const MainScene = preload("res://scenes/main.tscn")

const BUTTON := "post Play_ui_button"
const LOW := "post Play_bass_clarinet_G2_1_mezzo_forte_normal"
const HIGH := "post Play_viola_Gs5_1_fortissimo_arco_normal"
const SOFT := "post Play_violin_B4_1_piano_arco_sul_tasto"

var director: Node

func _initialize() -> void:
	call_deferred("run")

func heard(action: Callable) -> PackedStringArray:
	director.calls.clear()
	action.call()
	await process_frame
	return director.calls.duplicate()

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

	# Pages: the press is heard at once, the page change one frame later.
	expect("Start game", await heard(func(): press(app.page, "LevelsButton")), [HIGH, SOFT])
	expect("Start a level", await heard(func(): press(app.page, "Topic3/EnterButton")), [HIGH, SOFT])
	assert(app.current == "canvas")

	# Tools: the button click only; the tool state rows are silent.
	expect("Eraser tool", await heard(func(): press(app.page, "ToolEraser")), [BUTTON])
	expect("Move tool", await heard(func(): press(app.page, "ToolMove")), [BUTTON])
	expect("Brush tool", await heard(func(): press(app.page, "ToolBrush")), [BUTTON])

	# One brush stroke: grab on begin, nothing on lift.
	expect("Brush stroke", await heard(func():
		app.drawing.begin(Vector2(500, 150), -1)
		app.drawing.move_pen(Vector2(600, 180))
		app.drawing.finish()), [SOFT])
	expect("Undo", await heard(func(): press(app.page, "UndoButton")), [BUTTON, SOFT])
	expect("Redo", await heard(func(): press(app.page, "RedoButton")), [BUTTON, SOFT])
	app.apply_color(Color("3a9d8f"))
	expect("Eraser stroke", await heard(func():
		app.drawing.erasing = true
		app.drawing.begin(Vector2(520, 160), -1)
		app.drawing.finish()
		app.drawing.erasing = false), [BUTTON])

	# Dialogs: open and close are heard; stickers add a high note and deleting one a low note.
	expect("Open stickers", await heard(func(): press(app.page, "StickerButton")), [BUTTON, SOFT])
	expect("Add sticker", await heard(func(): press(app.overlay, "Scroll/Grid/food_authority/Content/UseButton")), [BUTTON, HIGH, LOW])
	expect("Delete layer", await heard(func(): press(app.page, "DeleteObjectButton")), [LOW, LOW])
	expect("Open stickers again", await heard(func(): press(app.page, "StickerButton")), [BUTTON, SOFT])
	expect("Close dialog", await heard(func(): press(app.overlay, "Frame/CloseButton")), [SOFT, LOW])
	expect("Open text editor", await heard(func(): press(app.page, "AddTextButton")), [BUTTON, SOFT])
	app.overlay.get_node("TextInput").text = "诗圣摸鱼"
	expect("Add text", await heard(func(): press(app.overlay, "ApplyButton")), [BUTTON, HIGH, LOW])
	expect("Clear draft prompt", await heard(func(): press(app.page, "RestartButton")), [LOW, SOFT])
	expect("Cancel clearing", await heard(func(): press(app.overlay, "CancelButton")), [BUTTON, LOW])
	expect("Clear draft prompt again", await heard(func(): press(app.page, "RestartButton")), [LOW, SOFT])
	expect("Confirm clearing", await heard(func(): press(app.overlay, "ConfirmButton")), [LOW, LOW, LOW])

	# Submit, save and unlock the next level.
	press(app.page, "ToolBrush")
	app.drawing.begin(Vector2(500, 150), -1)
	app.drawing.move_pen(Vector2(600, 180))
	app.drawing.finish()
	var state: Dictionary = app.drawings[app.topic]
	state.result = ImageTexture.create_from_image(state.pixels)
	state.submitted = state.revision
	expect("Submit", await heard(func(): press(app.page, "SubmitButton")), [HIGH, HIGH])
	expect("Save work", await heard(func(): press(app.overlay, "SaveButton")), [HIGH, HIGH, LOW, SOFT])
	press(app.overlay, "GalleryButton")
	await process_frame

	# Settings toggles: on is high, off is low; the slider ticks softly.
	app.show_page("settings")
	await process_frame
	var sound: BaseButton = app.page.get_node("SoundToggle")
	app.page.get_viewport().gui_release_focus()
	director.binder.last_input_ms = Time.get_ticks_msec()
	sound.grab_focus()
	var before := sound.button_pressed
	expect("Sound toggle", await heard(func(): sound.button_pressed = not before), [HIGH if not before else LOW])
	sound.button_pressed = before
	var slider: Slider = app.page.get_node("VolumeSlider")
	slider.grab_focus()
	director.binder.last_input_ms = Time.get_ticks_msec()
	expect("Volume tick", await heard(func(): slider.value = clampf(slider.value + 5, 0, 100)), [SOFT])
	print("AUDIO_FLOW_TESTS_PASSED")
	quit()
