extends SceneTree
const Drawing = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var surface = Drawing.new()
	surface.state = Drawing.new_state("country_road")
	surface.size = Vector2(1040, 330)
	root.add_child(surface)
	surface.begin(Vector2(500, 150), -1)
	surface.move_pen(Vector2(600, 180))
	surface.finish()
	surface.add_object("text", "麒麟献瑞，诗圣摸鱼。", 44, Color("3a9d8f"))
	surface.transform_selected(0.8, PI / 6)
	for kind in Drawing.STICKER_TEXTURES:
		surface.add_object(kind)
		surface.transform_selected(0.8, PI / 6)
	surface.state.objects[0].position = Vector2(840, 170)
	surface.state.objects[0].rotation = PI / 6
	surface.state.objects[0].scale_y = 1.4
	surface.state.work_id = "work-1"
	surface.state.submitted = surface.state.revision
	var encoded = Store.encode(surface.state)
	var loaded = Store.decode(JSON.parse_string(JSON.stringify(encoded)))
	assert(not loaded.is_empty())
	assert(loaded.pixels.get_data() == surface.state.pixels.get_data())
	for i in range(loaded.objects.size()):
		var actual = loaded.objects[i]
		var expected = surface.state.objects[i]
		assert(actual.id == expected.id and actual.kind == expected.kind)
		assert(actual.position.is_equal_approx(expected.position))
		assert(is_equal_approx(actual.scale, expected.scale) and is_equal_approx(actual.rotation, expected.rotation))
		assert(Drawing.object_scale(actual).is_equal_approx(Drawing.object_scale(expected)))
		assert(actual.text == expected.get("text", ""))
		assert(actual.color == expected.get("color", Color("243d35")))
	assert(loaded.work_id == "work-1" and loaded.submitted == surface.state.submitted)
	assert(loaded.background_id == "country_road" and loaded.revision == surface.state.revision)
	assert(Store.encode(Store.decode(encoded)) == encoded, "Current saves must round-trip without changing artwork or revisions")
	assert(loaded.undo.is_empty() and loaded.redo.is_empty())
	assert(Store.decode({}).is_empty())
	var legacy = encoded.duplicate(true)
	legacy.objects[0].erase("scale_y")
	assert(Drawing.object_scale(Store.decode(legacy).objects[0]) == Vector2.ONE)
	assert(Store.encode(Store.decode(legacy)) == legacy, "Uniform legacy saves must round-trip unchanged")
	for bad_scale in [0, -1, INF, NAN, "1", null, [1, 1]]:
		var bad_stretch = encoded.duplicate(true)
		bad_stretch.objects[0].scale_y = bad_scale
		assert(Store.decode(bad_stretch).is_empty(), "Invalid vertical scales must be rejected")
	var enlarged = encoded.duplicate(true)
	enlarged.objects[0].scale = 3.0
	enlarged.objects[0].scale_y = 4.0
	var restored = Store.decode(JSON.parse_string(JSON.stringify(enlarged)))
	assert(not restored.is_empty())
	assert(Drawing.object_scale(restored.objects[0]) == Vector2(3, 4))
	assert(Store.encode(Store.decode(enlarged)) == enlarged, "Scales above two must round-trip unchanged")
	var invalid = encoded.duplicate(true)
	invalid.objects[0].kind = "unknown"
	assert(Store.decode(invalid).is_empty())
	invalid = encoded.duplicate(true)
	invalid.objects[1].color = "oops"
	assert(Store.decode(invalid).is_empty())
	for kind in ["star", "cloud", "seal"]:
		invalid = encoded.duplicate(true)
		invalid.objects[2].kind = kind
		assert(Store.decode(invalid).is_empty(), "Unsupported stickers must be rejected")
	for field in ["background_id", "work_id"]:
		invalid = encoded.duplicate(true)
		invalid.erase(field)
		assert(Store.decode(invalid).is_empty(), "Required artwork fields cannot be omitted")
	for rotation in [0.0001, PI / 6, -PI / 6]:
		invalid = encoded.duplicate(true)
		invalid.objects[0].rotation = rotation
		assert(is_equal_approx(Store.decode(invalid).objects[0].rotation, rotation), "Avatar rotation must survive loading")
	invalid.objects[0].rotation = TAU
	assert(Store.decode(invalid).is_empty(), "Out-of-range rotations must still be rejected")
	var document = Store.empty_document()
	document.drafts["-1"] = encoded
	document.next_id = 2
	document.works.append({"id":"work-1","topic":-1,"title":"自由创作 · 1","data":encoded,"preview":encoded.pixels})
	assert(Store.validate_document(JSON.parse_string(JSON.stringify(document))))
	var original = document.duplicate(true)
	document.works[0].data.objects[1].text = "另一个版本"
	assert(original.works[0].data.objects[1].text == "麒麟献瑞，诗圣摸鱼。")
	var invalid_background: Dictionary = encoded.duplicate(true)
	invalid_background.background_id = "missing_scene"
	assert(Store.decode(invalid_background).is_empty())
	var invalid_document: Dictionary = original.duplicate(true)
	invalid_document.erase("completed_topics")
	assert(not Store.validate_document(invalid_document), "Saved progress is required")
	for progress in [[0, 0], [-1], [4], [0.5], "0"]:
		invalid_document.completed_topics = progress
		assert(not Store.validate_document(invalid_document), "Invalid completed topics were accepted")
	document.version = 1
	assert(not Store.validate_document(document), "Old save versions must be rejected")
	document.version = 99
	assert(not Store.validate_document(document))
	var history_document := Store.empty_document()
	history_document.tools.erase("color_history")
	assert(Store.validate_document(history_document), "Legacy saves should still load")
	for history in [["ff0000", "00ff00"], []]:
		history_document.tools.color_history = history
		assert(Store.validate_document(history_document))
	for history in ["bad", ["oops"], [42], ["ff0000", "FF0000"], ["ff0000", "000001", "000002", "000003", "000004", "000005", "000006", "000007", "000008", "000009", "000010"]]:
		history_document.tools.color_history = history
		assert(not Store.validate_document(history_document))
	print("STORAGE_TESTS_PASSED")
	quit()
