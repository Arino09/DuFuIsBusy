extends SceneTree
## Stable content IDs survive card reorder; app details follow authored content.
const Catalog = preload("res://scripts/content_catalog.gd")
const LEVELS = preload("res://scenes/pages/levels.tscn")
const HOME = preload("res://scenes/pages/home.tscn")
const GALLERY = preload("res://scenes/pages/gallery.tscn")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalog := Catalog.new()
	assert(catalog.topic_ids() == [0, 1, 2, 3], "Existing save topic IDs must remain compatible")
	assert(catalog.example_ids() == [0, 1, 2, 3], "Existing example links must remain compatible")
	var levels := LEVELS.instantiate()
	var home := HOME.instantiate()
	var gallery := GALLERY.instantiate()
	for id in catalog.topic_ids():
		var entry := catalog.get_topic(id)
		var card := levels.get_node(entry.node_path)
		assert(entry.id == card.get_meta("topic_id"))
		assert(entry.title == card.get_node("Title").text and not entry.title.is_empty())
		assert(entry.prompt == card.get_node("Prompt").text and not entry.prompt.is_empty())
		assert(entry.remark == card.get_meta("remark") and not entry.remark.is_empty())
	var free := catalog.get_topic(-1)
	assert(free.id == -1 and free.title == home.get_node("FreeDrawButton").text)
	assert(free.prompt == home.get_node("FreeDrawButton").get_meta("prompt"))
	assert(free.remark == home.get_node("FreeDrawButton").get_meta("remark"))
	for id in catalog.example_ids():
		var entry := catalog.get_example(id)
		var card := gallery.get_node(entry.node_path)
		assert(entry.id == card.get_meta("example_id"))
		assert(entry.title == card.get_node("Title").text)
		assert(entry.category == card.get_meta("topic"))
		assert(card.get_node("TopicLabel").text.begins_with(entry.category + " · "))
		assert(entry.image_path == card.get_node("Picture").texture.resource_path)
		assert(ResourceLoader.exists(entry.image_path))

	# Scene edits must be reflected by every consumer, without a matching script edit.
	levels.get_node("Topic1/Title").text = "新主题"
	levels.get_node("Topic1/Prompt").text = "新提示"
	levels.get_node("Topic1").set_meta("remark", "新评语")
	levels.move_child(levels.get_node("Topic1"), levels.get_child_count() - 1)
	var edited_levels := PackedScene.new()
	assert(edited_levels.pack(levels) == OK)
	gallery.get_node("Examples/Cards/Example1/Title").text = "新示例"
	gallery.get_node("Examples/Cards/Example1/Picture").texture = gallery.get_node("Examples/Cards/Example2/Picture").texture
	gallery.get_node("Examples/Cards").move_child(gallery.get_node("Examples/Cards/Example1"), 3)
	var edited_gallery := PackedScene.new()
	assert(edited_gallery.pack(gallery) == OK)
	var edited := Catalog.new(edited_levels, HOME, edited_gallery)
	assert(edited.topic_ids() == catalog.topic_ids())
	assert(edited.get_topic(0).title == "新主题")
	assert(edited.get_topic(0).prompt == "新提示")
	assert(edited.get_topic(0).remark == "新评语")
	assert(edited.get_topic(1).title == catalog.get_topic(1).title)
	assert(edited.get_example(0).title == "新示例")
	assert(edited.get_example(0).image_path == catalog.get_example(1).image_path)
	assert(edited.get_example(1).title == catalog.get_example(1).title)
	# Card signals use the stable metadata ID after reordering, too.
	root.add_child(gallery)
	var selected := [-1]
	gallery.example_requested.connect(func(id: int): selected[0] = id)
	gallery.get_node("Examples/Cards/Example1/ViewButton").pressed.emit()
	assert(selected[0] == 0)
	levels.free()
	home.free()
	gallery.free()
	print("CONTENT_CATALOG_TESTS_PASSED")
	quit()
