extends SceneTree
const Drawing = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var surface = Drawing.new()
	surface.state = Drawing.new_state()
	surface.size = Vector2(1040, 330)
	root.add_child(surface)
	surface.begin(Vector2(500, 150), -1)
	surface.move_pen(Vector2(600, 180))
	surface.finish()
	surface.add_object("text", "麒麟献瑞，诗圣摸鱼。", 44, Color("3a9d8f"))
	surface.transform_selected(0.8, PI / 6)
	surface.add_object("cloud")
	surface.state.objects[0].position = Vector2(840, 170)
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
		assert(actual.text == expected.get("text", ""))
		assert(actual.color == expected.get("color", Color("243d35")))
	assert(loaded.work_id == "work-1" and loaded.submitted == surface.state.submitted)
	assert(loaded.undo.is_empty() and loaded.redo.is_empty())
	assert(Store.decode({}).is_empty())
	var invalid = encoded.duplicate(true)
	invalid.objects[0].kind = "unknown"
	assert(Store.decode(invalid).is_empty())
	invalid = encoded.duplicate(true)
	invalid.objects[1].color = "oops"
	assert(Store.decode(invalid).is_empty())
	var document = Store.empty_document()
	document.drafts["-1"] = encoded
	document.next_id = 2
	document.works.append({"id":"work-1","topic":-1,"title":"自由创作 · 1","data":encoded,"preview":encoded.pixels})
	assert(Store.validate_document(JSON.parse_string(JSON.stringify(document))))
	var original = document.duplicate(true)
	document.works[0].data.objects[1].text = "另一个版本"
	assert(original.works[0].data.objects[1].text == "麒麟献瑞，诗圣摸鱼。")
	document.version = 99
	assert(not Store.validate_document(document))
	print("STORAGE_TESTS_PASSED")
	quit()
