extends RefCounted
## Completed works, rather than submissions or drafts, advance the level sequence.

static func completed_from_document(document: Dictionary) -> Array[int]:
	var completed: Array[int] = []
	for topic in document.completed_topics:
		completed.append(int(topic))
	return completed

static func is_unlocked(topic: int, completed: Array[int], ordered_topics: Array[int]) -> bool:
	if topic == -1:
		return true
	var topic_index := ordered_topics.find(topic)
	if topic_index < 0:
		return false
	for previous in ordered_topics.slice(0, topic_index):
		if not completed.has(previous):
			return false
	return true

static func mark_completed(topic: int, completed: Array[int], ordered_topics: Array[int]) -> Array[int]:
	var updated: Array[int] = completed.duplicate()
	if ordered_topics.has(topic) and is_unlocked(topic, completed, ordered_topics) and not updated.has(topic):
		updated.append(topic)
	var ordered: Array[int] = []
	for authored_topic in ordered_topics:
		if updated.has(authored_topic):
			ordered.append(authored_topic)
	return ordered
