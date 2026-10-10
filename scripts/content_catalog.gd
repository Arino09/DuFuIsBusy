extends RefCounted
## Authored scene text and metadata are the source of topic/example content.
## Reading SceneState avoids creating a second copy of the page controls.

class TopicDefinition:
	extends RefCounted
	var id: int
	var title: String
	var prompt: String
	var remark: String
	var background_id: String
	var node_path: NodePath

class ExampleDefinition:
	extends RefCounted
	var id: int
	var title: String
	var category: String
	var image_path: String
	var node_path: NodePath

var _topics: Dictionary = {}
var _examples: Dictionary = {}
var _topic_ids: Array[int] = []
var _example_ids: Array[int] = []

func _init(
	levels_scene: PackedScene = preload("res://scenes/pages/levels.tscn"),
	home_scene: PackedScene = preload("res://scenes/pages/home.tscn"),
	gallery_scene: PackedScene = preload("res://scenes/pages/gallery.tscn")
) -> void:
	var levels := _scene_properties(levels_scene)
	for path: String in levels:
		var properties: Dictionary = levels[path]
		if not properties.has("metadata/topic_id"): continue
		var entry := TopicDefinition.new()
		entry.id = properties["metadata/topic_id"]
		entry.node_path = NodePath(path)
		entry.title = levels[path + "/Title"]["text"]
		entry.prompt = levels[path + "/Prompt"]["text"]
		entry.remark = properties["metadata/remark"]
		entry.background_id = properties["metadata/background_id"]
		assert(entry.id >= 0 and not _topics.has(entry.id), "Topic IDs must be unique and nonnegative")
		_topics[entry.id] = entry
		_topic_ids.append(entry.id)
	_topic_ids.sort()

	var free_button: Dictionary = _scene_properties(home_scene)["FreeDrawButton"]
	var free := TopicDefinition.new()
	free.id = -1
	free.title = free_button["text"]
	free.prompt = free_button["metadata/prompt"]
	free.remark = free_button["metadata/remark"]
	free.background_id = free_button["metadata/background_id"]
	free.node_path = ^"FreeDrawButton"
	_topics[free.id] = free

	var gallery := _scene_properties(gallery_scene)
	for path: String in gallery:
		var properties: Dictionary = gallery[path]
		if not properties.has("metadata/example_id"): continue
		var entry := ExampleDefinition.new()
		entry.id = properties["metadata/example_id"]
		entry.node_path = NodePath(path)
		entry.title = gallery[path + "/Title"]["text"]
		entry.category = properties["metadata/topic"]
		var texture: Texture2D = gallery[path + "/Picture"]["texture"]
		entry.image_path = texture.resource_path
		assert(entry.id >= 0 and not _examples.has(entry.id), "Example IDs must be unique and nonnegative")
		_examples[entry.id] = entry
		_example_ids.append(entry.id)
	_example_ids.sort()

func topic_ids() -> Array[int]:
	return _topic_ids.duplicate()

func get_topic(id: int) -> TopicDefinition:
	return _topics[id]

func example_ids() -> Array[int]:
	return _example_ids.duplicate()

func get_example(id: int) -> ExampleDefinition:
	return _examples[id]

static func _scene_properties(scene: PackedScene) -> Dictionary:
	var state := scene.get_state()
	var nodes: Dictionary = {}
	for index in state.get_node_count():
		var properties: Dictionary = {}
		for property_index in state.get_node_property_count(index):
			properties[state.get_node_property_name(index, property_index)] = state.get_node_property_value(index, property_index)
		nodes[str(state.get_node_path(index)).trim_prefix("./")] = properties
	return nodes
