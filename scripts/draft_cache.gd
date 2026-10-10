extends RefCounted
## Cache only the expensive layer encoding; submission and work IDs remain live.
const Store = preload("res://scripts/local_store.gd")
var _entries: Dictionary = {}

func seed(topic: int, state: Dictionary, data: Dictionary) -> void:
	_entries[topic] = {"source": state, "revision": state.revision, "data": data.duplicate(true)}

func encode(topic: int, state: Dictionary) -> Dictionary:
	var entry: Dictionary = _entries.get(topic, {})
	# Resetting or opening a work can replace a draft at the same revision.
	if entry.is_empty() or not is_same(entry.source, state) or entry.revision != state.revision:
		entry = {"source": state, "revision": state.revision, "data": _encode(state)}
		_entries[topic] = entry
	# Callers may attach a work ID or keep this snapshot as an immutable work.
	var encoded: Dictionary = entry.data.duplicate(true)
	encoded.background_id = state.background_id
	encoded.submitted = state.submitted
	encoded.work_id = state.get("work_id", "")
	return encoded

func _encode(state: Dictionary) -> Dictionary:
	return Store.encode(state)
