extends RefCounted
## Gallery drafts are views of persisted snapshots, never extra saved works.
const Drawing = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")
const TOPICS = [-1, 0, 1, 2, 3, 4, 5]

static func build(document: Dictionary, topic_title: Callable) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for work in document.works:
		entries.append(work)
	for topic in TOPICS:
		var key := str(topic)
		if not document.drafts.has(key): continue
		var encoded: Dictionary = document.drafts[key]
		var state := Store.decode(encoded)
		if state.is_empty() or not Drawing.has_creation_in(state): continue
		if _matches_saved_work(state, topic, document.works): continue
		entries.append({
			"id": "draft-" + key,
			"topic": topic,
			"title": str(topic_title.call(topic)) + " · 草稿",
			"data": encoded,
			"draft": true,
			"state": state,
		})
	return entries

static func _matches_saved_work(state: Dictionary, topic: int, works: Array) -> bool:
	if state.work_id.is_empty(): return false
	for work in works:
		if work.id != state.work_id or int(work.topic) != topic: continue
		var saved := Store.decode(work.data)
		if saved.is_empty(): return false
		if state.background_id != saved.background_id: return false
		# Revision counters can repeat after replacing or restarting a draft.
		return state.next_id == saved.next_id and state.objects == saved.objects and state.pixels.get_data() == saved.pixels.get_data()
	return false
