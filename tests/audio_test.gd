extends SceneTree
## Audio routing runs against the AudioDirector autoload; without Wwise it only records backend calls.
const Table = preload("res://scripts/audio/audio_table.gd")
const Hooks = preload("res://scripts/audio/audio_hooks.gd")

const FIXTURE := "key\tevent\tnote\n# comment\n\nui.press\tPlay_Click\n\nui.press.quiet\t\tblank falls back\nui.press.quiet.Mute\t-\tsilenced\nui.toggle_on\tPlay_Toggle\nui.drag\tPlay_Tick\ndialog.enter\tPlay_Open\ndialog.exit\tPlay_Close\ndialog.enter.busy\t-\nrtpc.setting.volume\tVolume_Master\n\"quoted.key\"\t\"Play_\"\"Q\"\"\"\n"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_table()
	test_encodings()
	test_shipped_table()
	test_wwise_project()
	test_shipped_routing()
	await test_brush_audio()
	await test_routing()
	print("AUDIO_TESTS_PASSED")
	quit()

func test_table() -> void:
	var table := Table.new()
	table.parse(FIXTURE)
	assert(table.errors.is_empty(), "Fixture parses cleanly")
	assert(table.lookup("ui.press.primary.Go") == "Play_Click", "Unknown leaves fall back to the parent key")
	assert(table.lookup("ui.press.quiet.Close") == "Play_Click", "Blank rows fall back further up")
	assert(table.lookup("ui.press.quiet.Mute") == "", "A dash silences without falling back")
	assert(table.lookup("canvas.undo") == null, "Keys outside the table are unmapped")
	assert(table.lookup("quoted.key") == "Play_\"Q\"", "Excel-style quoted cells are unwrapped")
	var broken := Table.new()
	broken.parse("key\tevent\nui.press\tA\nui.press\tB\nbad key\tC\n")
	assert(broken.errors.size() == 2, "Duplicate and malformed keys are reported")
	assert(broken.errors[0].contains(":3"), "Errors carry line numbers")
	assert(broken.lookup("ui.press") == "A", "Good rows still load")
	var headless := Table.new()
	headless.parse("name\tvalue\nui.press\tA\n")
	assert(headless.errors.size() == 1 and headless.entries.is_empty(), "A missing header is reported")

func test_encodings() -> void:
	var utf16 := PackedByteArray([0xFF, 0xFE])
	utf16.append_array("key\tevent\nui.press\tPlay_Click\n".to_utf16_buffer())
	var table := Table.new()
	table.parse_bytes(utf16, "utf16.tsv")
	assert(table.errors.is_empty() and table.lookup("ui.press") == "Play_Click", "UTF-16LE (Excel Unicode Text) decodes")
	var gbk := Table.new()
	# "你" in GBK; decoding it as UTF-8 would print an engine error.
	gbk.parse_bytes(PackedByteArray([0x6B, 0x65, 0x79, 0x09, 0xC4, 0xE3]), "gbk.tsv")
	assert(gbk.errors.size() == 1 and gbk.errors[0].contains("UTF-8"), "GBK files ask for a UTF-8 re-save")

func test_shipped_table() -> void:
	assert(root.get_node_or_null("AudioDirector") != null, "AudioDirector must be autoloaded to receive game events")
	var runtime := root.get_node_or_null("WwiseRuntimeManager")
	assert(runtime != null and runtime.has_method("initialize"), "Use the project Wwise manager, not the addon default")
	var bank_root: String = ProjectSettings.get_setting("wwise/common_user_settings/root_output_path", "")
	assert(FileAccess.file_exists(bank_root.path_join("Web/Init.bnk")), "Wwise bank root points at the bundled banks")
	for platform in ["windows", "web"]:
		var info: String = ProjectSettings.get_setting("wwise/project_settings/" + platform + "_platform_info", "")
		assert(ResourceLoader.exists(info), "Wwise platform resource is configured: " + platform)
	var table: RefCounted = Table.from_file("res://addons/Wwise/wwise_project/DuFuIsBusy/audio_events.tsv")
	assert(table.errors.is_empty(), "Shipped audio table has no errors: %s" % [table.errors])
	assert(table.lookup("test.play") != "", "F9 test key points at a real event")
	# Every literal key in game code must reach a row, so designers see every hook in the table.
	var used := {}
	for path in ["res://scripts/main.gd", "res://scripts/drawing_surface.gd", "res://scripts/pages/canvas_page.gd"]:
		var source := FileAccess.get_file_as_string(path)
		var calls := RegEx.create_from_string("AudioHooks\\.(cue|fact|param)\\(\"([^\"]+)\"")
		for found in calls.search_all(source):
			var key := found.get_string(2)
			match found.get_string(1):
				"fact": key += ".enter.x"
				"param": key = "rtpc." + key
			used[key] = true
	for key in ["message.notice", "canvas.drag.begin.paint", "canvas.object.add.dufu_greatsword", "canvas.object.select.avatar"]: used[key] = true
	for key in used:
		if key.ends_with(".enter.x"):
			var name: String = key.trim_suffix(".enter.x")
			assert(table.entries.keys().any(func(k: String): return k.begins_with(name + ".")), "State has rows: " + name)
		elif key.ends_with("."):
			assert(table.entries.keys().any(func(k: String): return k.begins_with(key)), "Dynamic keys have rows: " + key)
		else: assert(table.lookup(key) != null, "Game key has a row: " + key)
	var presets := ConfigFile.new()
	assert(presets.load("res://export_presets.cfg") == OK, "Export presets load")
	for section in ["preset.0", "preset.1"]:
		assert(str(presets.get_value(section, "include_filter", "")).contains("addons/Wwise/wwise_project/DuFuIsBusy/audio_events.tsv"), "Exports ship the audio table: " + section)
		assert(str(presets.get_value(section, "include_filter", "")).contains("GeneratedSoundBanks/Web/*.bnk"), "Exports ship the shared banks: " + section)

const WWISE_PROJECT := "res://addons/Wwise/wwise_project/DuFuIsBusy/"
const BANK_PATH := "GeneratedSoundBanks/Web/Main.bnk"

## Every event the table names must exist in the Wwise project and in the generated bank, or posting it fails silently.
func test_wwise_project() -> void:
	if not FileAccess.file_exists(WWISE_PROJECT + "Events/Default Work Unit.wwu"):
		print("AUDIO_TEST_SKIPPED: no Wwise project in this checkout")
		return
	var table: RefCounted = Table.from_file("res://addons/Wwise/wwise_project/DuFuIsBusy/audio_events.tsv")
	var authored := {}
	for found in RegEx.create_from_string("<Event Name=\"([^\"]+)\"").search_all(FileAccess.get_file_as_string(WWISE_PROJECT + "Events/Default Work Unit.wwu")):
		authored[found.get_string(1)] = true
	var banked := bank_event_ids(FileAccess.get_file_as_bytes(WWISE_PROJECT + BANK_PATH))
	assert(not authored.is_empty() and not banked.is_empty(), "The Wwise project lists events and the Web bank was generated")
	var used := {}
	for key in table.entries:
		var event: String = table.entries[key]
		if event.is_empty() or event == Table.SILENT or key.begins_with("rtpc."): continue
		used[event] = key
	assert(used.size() >= 5, "The table uses every authored event kind")
	for event in used:
		assert(authored.has(event), "Event exists in the Wwise project: %s (row %s)" % [event, used[event]])
		assert(banked.has(fnv1(event)), "Event is in Main.bnk (regenerate the bank?): %s" % event)
	for key in table.entries:
		if key.begins_with("rtpc."):
			var expected: String = {"rtpc.canvas.drag_speed": "Brush_Speed", "rtpc.canvas.erase_speed": "Eraser_Speed"}.get(key, "")
			assert(table.entries[key] in [expected, Table.SILENT], "Only authored Game Parameters are mapped: " + key)

## Event ids in a bank's HIRC chunk (object type 4).
func bank_event_ids(bytes: PackedByteArray) -> Dictionary:
	var ids := {}
	var at := 0
	while at + 8 <= bytes.size():
		var size := bytes.decode_u32(at + 4)
		if bytes.slice(at, at + 4).get_string_from_ascii() == "HIRC":
			var cursor := at + 12
			for _i in bytes.decode_u32(at + 8):
				var length := bytes.decode_u32(cursor + 1)
				if bytes[cursor] == 4: ids[bytes.decode_u32(cursor + 5)] = true
				cursor += 5 + length
		at += 8 + size
	return ids

## Wwise names hash with FNV-1 over the lowercased name.
func fnv1(name: String) -> int:
	var hash := 2166136261
	for byte in name.to_lower().to_utf8_buffer():
		hash = (hash * 16777619) & 0xFFFFFFFF
		hash ^= byte
	return hash

## Check the actual authored events rather than the retired instrument placeholders.
func test_shipped_routing() -> void:
	var table: RefCounted = Table.from_file("res://addons/Wwise/wwise_project/DuFuIsBusy/audio_events.tsv")
	var expected := {
		"app.boot": "Play_Music_Theme", "test.play": "Play_SFX_Enter_Home",
		"ui.toggle_on.default.MusicToggle": "Play_Music_Theme", "ui.toggle_off.default.MusicToggle": "Stop_Music_Theme",
		"canvas.drag.begin.paint": "Play_SFX_Brush_Loop", "canvas.drag.end.paint": "Stop_SFX_Brush_Loop",
		"rtpc.canvas.drag_speed": "Brush_Speed", "canvas.drag.begin.erase": "Play_SFX_Eraser_Loop",
		"ui.press.primary.EnterButton": "Play_SFX_UI_Click", "canvas.drag.begin.move.avatar": "",
		"canvas.drag.begin.move.dufu_greatsword": "", "canvas.object.add.dufu_cyber_long_blade": "",
		"canvas.object.remove.dufu_greatsword": "", "dialog.enter.play_notice": "",
	}
	for page in ["home", "levels", "canvas", "gallery", "settings"]:
		var suffix: String = {"home": "Home", "levels": "Level", "canvas": "Canvas", "gallery": "Gallery", "settings": "And_Enter_Settings"}[page]
		expected["page.enter." + page] = "Play_SFX_Enter_" + suffix
		var exit_suffix: String = {"home": "Home", "levels": "Levels", "canvas": "Canvas", "gallery": "Gallery", "settings": "And_Exit_Settings"}[page]
		expected["page.exit." + page] = "Play_SFX_Exit_" + exit_suffix
	for key in expected:
		assert(table.lookup(key) == expected[key], "Incorrect mapping: " + key)

func test_brush_audio() -> void:
	var director: Node = root.get_node("AudioDirector")
	await process_frame
	var surface = load("res://scripts/drawing_surface.gd").new()
	root.add_child(surface)
	surface.set_process(false)
	director.calls.clear()
	surface.begin(Vector2(500, 150), -1)
	assert(director.calls == PackedStringArray(["rtpc Brush_Speed=0.0", "post Play_SFX_Brush_Loop"]), "Reset RTPC before starting exactly one loop")
	surface.move_pen(Vector2(600, 150))
	surface.move_pen(Vector2(700, 150))
	surface._process(0.1)
	var speed: float = director._rtpc["canvas.drag_speed"].value
	assert(speed > 10 and speed < 100, "Normal drawing has a useful 0–100 speed")
	for i in 10: surface._process(0.1)
	assert(director._rtpc["canvas.drag_speed"].value == 0.0, "Holding still decays to zero without a mouse event")
	surface.move_pen(Vector2(1000, 150))
	surface._process(0.001)
	assert(director._rtpc["canvas.drag_speed"].value <= 100, "Fast movement stays inside the Wwise range")
	director._send_rtpc("canvas.drag_speed")
	surface.finish()
	assert(director.calls[-2] == "post Stop_SFX_Brush_Loop" and director.calls[-1] == "rtpc Brush_Speed=0.0", "Lift stops and flushes zero even inside the throttle window")
	var count: int = director.calls.size()
	surface.finish()
	assert(director.calls.size() == count, "Repeated finish cannot stop twice")
	# A second finger cancels the provisional stroke, including its captured audio.
	director.calls.clear()
	surface.begin(Vector2(500, 150), 0)
	surface.move_pen(Vector2(600, 150))
	surface._process(0.1)
	director._send_rtpc("canvas.drag_speed")
	surface.erasing = true
	surface.cancel()
	assert(not surface.active and director.calls[-2] == "post Stop_SFX_Brush_Loop" and director.calls[-1] == "rtpc Brush_Speed=0.0", "Cancel stops the captured loop and immediately resets its speed")
	count = director.calls.size()
	surface.cancel()
	assert(director.calls.size() == count, "Repeated cancellation cannot stop twice")
	surface.erasing = false
	surface.begin(Vector2(500, 150), 0)
	surface.move_pen(Vector2(-1, 150))
	assert(not surface.active and director.calls[-1] == "post Stop_SFX_Brush_Loop", "Leaving paper stops a touch stroke")
	surface.begin(Vector2(500, 150), -1)
	surface.get_window().focus_exited.emit()
	assert(not surface.active and director.calls[-1] == "post Stop_SFX_Brush_Loop", "Focus loss stops the loop")
	surface.begin(Vector2(500, 150), -1)
	surface.erasing = true
	surface.finish()
	assert(director.calls[-1] == "post Stop_SFX_Brush_Loop", "End uses the captured stroke kind")
	director.calls.clear()
	surface.begin(Vector2(500, 150), -1)
	surface.move_pen(Vector2(600, 150))
	surface._process(0.1)
	surface.finish()
	assert(director.calls.has("post Play_SFX_Eraser_Loop") and director.calls.has("post Stop_SFX_Eraser_Loop"), "Erasing starts and stops its own loop")
	assert(director._rtpc["canvas.erase_speed"].value == 0.0, "Eraser speed resets on lift")
	assert(not director.calls.has("post Play_SFX_Brush_Loop"), "Erasing does not start the brush loop")
	surface.erasing = false
	surface.begin(Vector2(500, 150), -1)
	surface.free()
	assert(director.calls[-1] == "post Stop_SFX_Brush_Loop", "Removing the canvas stops the loop")

func test_routing() -> void:
	var director: Node = root.get_node("AudioDirector")
	assert(Hooks.sink == director, "The autoload receives AudioHooks calls")
	var table := Table.new()
	table.parse(FIXTURE)
	director.load_table(table)
	await process_frame
	assert(director.running and director.wwise == null, "Headless runs route without Wwise")
	director.calls.clear()

	Hooks.cue("ui.press.primary.Go")
	Hooks.cue("ui.press.quiet.Mute")
	Hooks.cue("canvas.undo")
	assert(director.calls == PackedStringArray(["post Play_Click"]), "Cues post the resolved event only")

	director.calls.clear()
	Hooks.fact("dialog", "busy")
	Hooks.fact("dialog", "submission_result")
	await process_frame
	assert(director.calls == PackedStringArray(["post Play_Open"]), "Same-frame swaps collapse into one enter")
	director.calls.clear()
	Hooks.fact("dialog", "")
	Hooks.fact("dialog", "submission_result")
	await process_frame
	assert(director.calls.is_empty(), "A value restored within the frame changes nothing")
	Hooks.fact("dialog", "")
	await process_frame
	assert(director.calls == PackedStringArray(["post Play_Close"]), "Leaving a state fires its exit key")

	director.calls.clear()
	Hooks.param("setting.volume", 50.0)
	Hooks.param("setting.volume", 50.0)
	Hooks.param("setting.unknown", 1.0)
	assert(director.calls == PackedStringArray(["rtpc Volume_Master=50.0"]), "RTPCs dedupe and skip unmapped keys")
	Hooks.param("setting.volume", 60.0)
	Hooks.param("setting.volume", 70.0)
	await create_timer(0.1).timeout
	assert(director.calls[-1] == "rtpc Volume_Master=70.0", "The throttle always delivers the last value")

	var button := Button.new()
	button.name = "Go"
	button.theme_type_variation = &"PrimaryButton"
	button.toggle_mode = true
	button.size = Vector2(100, 40)
	root.add_child(button)
	director.calls.clear()
	button.pressed.emit()
	assert(director.calls == PackedStringArray(["post Play_Click"]), "Buttons are wired automatically by role")
	director.calls.clear()
	director.binder.last_input_ms = -100000
	button.button_pressed = true
	assert(director.calls.is_empty(), "Code-driven toggles stay silent")
	button.button_pressed = false
	button.grab_focus()
	director.binder.last_input_ms = Time.get_ticks_msec()
	button.button_pressed = true
	assert(director.calls == PackedStringArray(["post Play_Toggle"]), "User toggles sound")
	var spin := SpinBox.new()
	root.add_child(spin)
	director.calls.clear()
	director.binder.last_input_ms = -100000
	spin.value = 5
	assert(director.calls.is_empty(), "Code-driven value changes stay silent")
	root.remove_child(button)
	root.add_child(button)
	director.calls.clear()
	button.pressed.emit()
	assert(director.calls.size() == 1, "Re-entering the tree does not connect twice")
	button.free()
	spin.free()
