extends SceneTree
## Draft discovery and de-duplication only read in-memory current-format documents.
const Drawing = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")
const Entries = preload("res://scripts/gallery_entries.gd")

func _initialize() -> void:
	call_deferred("run")

func title_for(topic: int) -> String:
	return "主题 %d" % topic

func run() -> void:
	var document := Store.empty_document()
	var blank := Drawing.new_state()
	# Visiting an empty canvas must not add an unfinished work to the gallery.
	document.drafts["0"] = Store.encode(blank)
	assert(Entries.build(document, title_for).is_empty())
	blank.objects[0].position += Vector2(0.2, 0)
	blank.objects[0].scale += 0.0001
	document.drafts["0"] = Store.encode(blank)
	assert(Entries.build(document, title_for).is_empty(), "Creation tolerances changed")

	var ink := Drawing.new_state()
	ink.pixels.set_pixel(700, 170, Color.RED)
	ink.revision = 1
	document.drafts["0"] = Store.encode(ink)
	var entries := Entries.build(document, title_for)
	assert(entries.size() == 1)
	assert(entries[0].id == "draft-0" and entries[0].draft and entries[0].topic == 0)
	assert(entries[0].title == "主题 0 · 草稿")
	assert(entries[0].state.pixels.get_pixel(700, 170) == Color.RED)
	# Repeated auto-saves replace the topic's entry instead of adding versions.
	ink.pixels.set_pixel(710, 170, Color.BLUE)
	ink.revision += 1
	document.drafts["0"] = Store.encode(ink)
	var updated := Entries.build(document, title_for)
	assert(updated.size() == 1 and updated[0].id == entries[0].id)
	assert(updated[0].state.revision == 2)
	assert(entries[0].state.pixels.get_pixel(710, 170).a == 0, "An earlier decoded snapshot was mutated")

	var moved := Drawing.new_state()
	moved.objects[0].position += Vector2(20, 0)
	document.drafts["-1"] = Store.encode(moved)
	var sticker := Drawing.new_state()
	sticker.objects.append({"id": 1, "kind": "weapon_du", "position": Vector2(500, 160), "scale": 1.0, "rotation": 0.0})
	sticker.next_id = 2
	document.drafts["3"] = Store.encode(sticker)
	var resized := Drawing.new_state()
	resized.objects[0].scale = 1.2
	document.drafts["1"] = Store.encode(resized)
	var painted := Drawing.new_state()
	painted.pixels.set_pixel(700, 180, Color.BLUE)
	document.drafts["2"] = Store.encode(painted)
	entries = Entries.build(document, title_for)
	assert(entries.size() == 5)
	for index in range(5):
		assert(entries[index].topic == index - 1, "Drafts have unstable ordering")

	# A saved snapshot is displayed once, even when submission metadata differs.
	ink.work_id = "work-1"
	ink.submitted = ink.revision
	var saved_data := Store.encode(ink)
	var saved := {"id": "work-1", "topic": 0, "title": "已保存", "data": saved_data, "preview": saved_data.pixels}
	document.works.append(saved)
	document.next_id = 2
	ink.revision += 10
	ink.submitted = -1
	document.drafts["0"] = Store.encode(ink)
	var before := JSON.stringify(document)
	entries = Entries.build(document, title_for)
	assert(entries.size() == 5 and entries[0] == saved)
	assert(JSON.stringify(document) == before, "Building entries modified persisted data")
	entries.remove_at(0)
	assert(document.works.size() == 1, "Gallery array mutations changed saved works")

	# Same revisions cannot hide replacements with different objects or pixels.
	ink.revision = saved_data.revision
	ink.pixels.set_pixel(720, 170, Color.GREEN)
	document.drafts["0"] = Store.encode(ink)
	entries = Entries.build(document, title_for)
	assert(entries.size() == 6 and entries[2].id == "draft-0")
	assert(saved.data == saved_data and Store.decode(saved.data).pixels.get_pixel(720, 170).a == 0)
	ink.pixels.set_pixel(720, 170, Color.TRANSPARENT)
	ink.objects[0].position += Vector2(30, 0)
	document.drafts["0"] = Store.encode(ink)
	assert(Entries.build(document, title_for).size() == 6)
	ink.objects[0].position = Drawing.DEFAULT_POSITION
	ink.next_id += 1
	document.drafts["0"] = Store.encode(ink)
	assert(Entries.build(document, title_for).size() == 6)
	ink.next_id = saved_data.next_id
	ink.work_id = "work-99"
	document.drafts["0"] = Store.encode(ink)
	assert(Entries.build(document, title_for).size() == 6, "Unrelated matching artwork hid a draft")
	ink.work_id = "work-1"
	document.drafts["0"] = Store.encode(ink)
	saved.topic = 1
	assert(Entries.build(document, title_for).size() == 6, "A saved work from another topic hid a draft")
	saved.topic = 0

	# Current-format JSON preserves draft discovery without display-only fields.
	var reloaded: Dictionary = JSON.parse_string(JSON.stringify(document))
	assert(Store.validate_document(reloaded))
	var restored := Entries.build(reloaded, title_for)
	assert(restored.size() == 5 and restored[0].id == "work-1")
	assert(restored[1].state.objects[0].position == moved.objects[0].position)
	assert(not reloaded.drafts["-1"].has("state") and not reloaded.drafts["-1"].has("draft"))

	print("GALLERY_ENTRIES_TESTS_PASSED")
	quit()
