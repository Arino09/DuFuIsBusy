extends SceneTree
## Encoded snapshots stay isolated from mutable draft state and gallery versions.
## All images and documents are kept in memory; player saves are never accessed.
const Drawing = preload("res://scripts/drawing_surface.gd")
const Store = preload("res://scripts/local_store.gd")

class CountingCache:
	extends "res://scripts/draft_cache.gd"
	var encodes := 0

	func _encode(state: Dictionary) -> Dictionary:
		encodes += 1
		return Store.encode(state)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var cache := CountingCache.new()
	var state := Drawing.new_state()
	var first := cache.encode(0, state)
	assert(cache.encodes == 1)
	assert(first == Store.encode(state))
	assert(cache.encode(0, state) == first and cache.encodes == 1)

	# Selection is session UI state; changing it must not trigger PNG encoding.
	state.selected = 0
	assert(cache.encode(0, state) == first and cache.encodes == 1)
	state.submitted = 0
	state.work_id = "work-1"
	var submitted := cache.encode(0, state)
	assert(cache.encodes == 1, "Submission metadata re-encoded unchanged pixels")
	assert(submitted.submitted == 0 and submitted.work_id == "work-1")
	assert(first.submitted == -1 and first.work_id == "", "Earlier output shared submission metadata")

	# Every returned dictionary owns its nested objects; callers may edit candidates.
	submitted.objects[0].position[0] = 700.0
	submitted.work_id = "corrupted-candidate"
	var fresh := cache.encode(0, state)
	assert(fresh.objects[0].position[0] == Drawing.DEFAULT_POSITION.x)
	assert(fresh.work_id == "work-1" and cache.encodes == 1)
	state.objects[0].position = Vector2(300, 170)
	state.revision += 1
	var changed := cache.encode(0, state)
	assert(cache.encodes == 2)
	assert(changed.objects[0].position == [300.0, 170.0])
	assert(first.objects[0].position[0] == Drawing.DEFAULT_POSITION.x)
	assert(changed == Store.encode(state))

	# Restart/open-work may replace a topic with another draft at the same revision.
	var replacement := Drawing.new_state()
	replacement.revision = state.revision
	replacement.pixels.set_pixel(500, 150, Color.RED)
	replacement.objects[0].position = Vector2(600, 170)
	var replaced := cache.encode(0, replacement)
	assert(cache.encodes == 3, "Equal revision on another state reused the previous draft")
	assert(replaced == Store.encode(replacement))
	assert(replaced.pixels != changed.pixels)
	assert(replaced.work_id == "" and replaced.submitted == -1)
	assert(cache.encode(1, state) == Store.encode(state))
	assert(cache.encodes == 4, "Different topics shared a revision-only cache key")
	assert(cache.encode(0, replacement) == replaced and cache.encodes == 4)

	# Loading an existing encoded draft can seed without another PNG encode.
	var seeded_data := Store.encode(replacement)
	var restored := Store.decode(seeded_data)
	cache.seed(2, restored, seeded_data)
	seeded_data.objects[0].position[0] = 5.0
	var seeded := cache.encode(2, restored)
	assert(cache.encodes == 4)
	assert(seeded == Store.encode(restored), "The seed retained mutable external data")
	restored.work_id = "work-9"
	restored.submitted = restored.revision
	var seeded_metadata := cache.encode(2, restored)
	assert(cache.encodes == 4)
	assert(seeded_metadata.work_id == "work-9" and seeded_metadata.submitted == restored.revision)
	assert(seeded.work_id == "" and seeded.submitted == -1)
	restored.objects[0].position = Vector2(450, 170)
	restored.revision += 1
	assert(cache.encode(2, restored) == Store.encode(restored))
	assert(cache.encodes == 5)
	print("DRAFT_CACHE_TESTS_PASSED")
	quit()
