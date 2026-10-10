extends SceneTree
## Exercises the authored canvas scene without accessing player storage.

const CanvasScene = preload("res://scenes/pages/canvas.tscn")
const Surface = preload("res://scripts/drawing_surface.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var page = CanvasScene.instantiate()
	page.prepare(Surface.new_state(), 0, "")
	root.add_child(page)
	page.refresh_tools("移动", Color.BLACK, 8)
	var surface = page.surface
	surface.select_at(Surface.DEFAULT_POSITION)
	assert(page.object_buttons["左转"].disabled and page.object_buttons["右转"].disabled)
	assert(not page.object_buttons["缩小"].disabled and not page.object_buttons["放大"].disabled)
	assert(not page.object_buttons["左转"].tooltip_text.is_empty())
	var revision = surface.state.revision
	page.object_action("左转")
	page.object_action("右转")
	assert(surface.state.revision == revision and surface.state.undo.is_empty())
	assert(is_zero_approx(surface.selected_object().rotation))
	surface.begin(Surface.DEFAULT_POSITION, -1)
	surface.move_pen(Surface.DEFAULT_POSITION + Vector2(180, 0))
	surface.finish()
	assert(surface.selected_object().position.is_equal_approx(Surface.DEFAULT_POSITION + Vector2(180, 0)))
	page.object_action("缩小")
	assert(is_equal_approx(surface.selected_object().scale, 0.85))
	for kind in ["text", "weapon_du"]:
		surface.add_object(kind, "杜甫")
		assert(not page.object_buttons["左转"].disabled and not page.object_buttons["右转"].disabled)
		assert(page.object_buttons["左转"].tooltip_text == "向左旋转 15 度")
		page.object_action("右转")
		assert(is_equal_approx(surface.selected_object().rotation, PI / 12))
		page.object_action("左转")
		assert(is_zero_approx(surface.selected_object().rotation))
	page.refresh_tools("笔刷", Color.BLACK, 8)
	assert(page.object_buttons["左转"].disabled and page.object_buttons["右转"].disabled)
	page.queue_free()
	await process_frame
	print("AVATAR_ROTATION_TESTS_PASSED")
	quit()

