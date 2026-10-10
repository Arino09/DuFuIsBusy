extends SceneTree
const Surface = preload("res://scripts/drawing_surface.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var surface = Surface.new()
	surface.state = Surface.new_state()
	surface.size = Vector2(1040, 330)
	root.add_child(surface)
	assert(not surface.has_ink())
	surface.erasing = true
	surface.begin(Vector2(30, 30), -1)
	surface.finish()
	assert(surface.state.undo.is_empty())
	surface.erasing = false
	surface.begin(Vector2(-10, -10), -1)
	assert(not surface.active)
	surface.begin(Vector2(450, 150), -1)
	surface.move_pen(Vector2(550, 150))
	surface.finish()
	assert(surface.has_ink() and surface.state.undo.size() == 1)
	var original = surface.state.pixels.get_data()
	surface.erasing = true
	surface.pen_width = 56
	surface.begin(Vector2(430, 150), -1)
	surface.move_pen(Vector2(570, 150))
	surface.finish()
	assert(not surface.has_ink())
	surface.travel(false)
	assert(surface.state.pixels.get_data() == original)
	surface.travel(true)
	assert(not surface.has_ink())
	surface.erasing = false
	surface.begin(Vector2(1039, 329), -1)
	surface.move_pen(Vector2(1200, 500))
	assert(not surface.active and surface.has_ink())
	assert(surface.state.redo.is_empty())
	var state = surface.state
	surface.queue_free()
	await process_frame
	var rebuilt = Surface.new()
	rebuilt.state = state
	rebuilt.size = Vector2(1040, 330)
	root.add_child(rebuilt)
	assert(rebuilt.has_ink())
	assert(rebuilt.artwork().get_size() == Vector2i(1040, 330))
	for i in range(25):
		rebuilt.begin(Vector2(300 + i * 20, 100), -1)
		rebuilt.finish()
	assert(rebuilt.state.undo.size() == 20)
	rebuilt.travel(false)
	assert(rebuilt.state.redo.size() == 1)
	rebuilt.begin(Vector2(900, 250), -1)
	rebuilt.finish()
	assert(rebuilt.state.redo.is_empty())
	print("DRAWING_TESTS_PASSED")
	quit()
