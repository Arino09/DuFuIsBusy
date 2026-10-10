extends SceneTree
const Progress = preload("res://scripts/level_progress.gd")
const TOPICS: Array[int] = [0, 1, 2, 3]

func _initialize() -> void:
	var fresh := Progress.completed_from_document({"completed_topics": []})
	assert(fresh.is_empty())
	assert(Progress.is_unlocked(0, fresh, TOPICS))
	assert(Progress.is_unlocked(-1, fresh, TOPICS))
	for topic in [1, 2, 3, 4, -2]:
		assert(not Progress.is_unlocked(topic, fresh, TOPICS))

	# Progress is explicit; neither submitted drafts nor saved works infer it.
	var saved := {"completed_topics": [], "drafts": {"0": {"submitted": 2}, "3": {"submitted": 8}}, "works": [{"topic": 2, "data": {"submitted": 1}}]}
	assert(Progress.completed_from_document(saved).is_empty())
	var durable := {"completed_topics": [0, 1], "works": [], "drafts": {}}
	var restored := Progress.completed_from_document(durable)
	assert(restored == [0, 1])
	restored.append(2)
	assert(durable.completed_topics == [0, 1], "Reading progress must return an independent array")
	assert(Progress.completed_from_document({"completed_topics": [2]}) == [2], "Reading progress must not auto-complete earlier levels")

	# Saving the current unlocked level advances one step and preserves its input.
	var first := Progress.mark_completed(0, fresh, TOPICS)
	assert(first == [0] and fresh.is_empty())
	assert(Progress.is_unlocked(1, first, TOPICS))
	assert(not Progress.is_unlocked(2, first, TOPICS))
	var next := Progress.mark_completed(1, first, TOPICS)
	assert(next == [0, 1] and first == [0], "Completion must not mutate the persisted input before saving succeeds")
	assert(Progress.mark_completed(-1, next, TOPICS) == next)
	assert(Progress.mark_completed(4, next, TOPICS) == next)
	assert(Progress.mark_completed(1, next, TOPICS) == next)
	assert(Progress.mark_completed(3, next, TOPICS) == next, "A locked level cannot skip or auto-complete its predecessors")
	assert(Progress.mark_completed(2, next, TOPICS) == [0, 1, 2])
	assert(Progress.mark_completed(3, [0, 1, 2], TOPICS) == TOPICS)
	assert(Progress.mark_completed(2, [], TOPICS).is_empty())
	assert(not Progress.is_unlocked(3, [2], TOPICS), "A later completion never grants missing earlier completions")
	assert(not Progress.is_unlocked(2, [0, 2], TOPICS))
	assert(Progress.is_unlocked(1, [0, 2], TOPICS))

	# Order comes from authored content, never from numeric adjacency or sort order.
	var reordered: Array[int] = [2, 0, 3, 1]
	assert(Progress.is_unlocked(2, [], reordered))
	assert(not Progress.is_unlocked(0, [], reordered))
	assert(Progress.mark_completed(0, [], reordered).is_empty())
	assert(Progress.mark_completed(2, [], reordered) == [2])
	assert(Progress.mark_completed(0, [2], reordered) == [2, 0])
	assert(Progress.mark_completed(3, [0, 2], reordered) == [2, 0, 3])
	assert(Progress.is_unlocked(3, [2, 0], reordered))
	assert(not Progress.is_unlocked(1, [2, 0], reordered))
	var empty: Array[int] = []
	assert(Progress.is_unlocked(-1, empty, empty))
	assert(not Progress.is_unlocked(0, empty, empty))
	assert(Progress.mark_completed(0, empty, empty).is_empty())
	print("LEVEL_PROGRESS_TESTS_PASSED")
	quit()
