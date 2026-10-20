extends SceneTree
## Phone/tablet layouts keep the authored controls reachable and restore desktop geometry.
## Run: Godot --headless --path . --script res://tests/mobile_pages_test.gd

const Layout = preload("res://scripts/ui/mobile_pages.gd")
const LayoutState = preload("res://scripts/ui/layout_state.gd")
const PAGES := {
	"home": preload("res://scenes/pages/home.tscn"),
	"levels": preload("res://scenes/pages/levels.tscn"),
	"gallery": preload("res://scenes/pages/gallery.tscn"),
	"settings": preload("res://scenes/pages/settings.tscn"),
}
const SIZES := [Vector2(320, 568), Vector2(390, 844), Vector2(844, 390), Vector2(768, 1024)]
const WORKS := [{"title": "山中杜甫"}, {"title": "出门去踏青"}, {"title": "草堂"}, {"title": "新的旅程"}]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition: return
	failures.append(message)
	push_error(message)

func controls(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child in node.get_children():
		if child.name in ["Frame", "DraftPreview", "DrawingSurface"]: continue
		if child is Control: result.append(child)
		result.append_array(controls(child))
	return result

func verify_layout(page: Control, extent: Vector2, height: float) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(extent.x, height)).grow(0.5)
	for control in controls(page):
		if not control.is_visible_in_tree(): continue
		check(bounds.encloses(control.get_global_rect()), "%s overflows %s: %s" % [control.get_path(), extent, control.get_global_rect()])
		if control is BaseButton or control is Slider:
			check(control.size.x >= 55.9 and control.size.y >= 55.9, "%s has a small touch target at %s: %s" % [control.get_path(), extent, control.size])
		if control.get_parent() is GridContainer:
			for content in controls(control):
				check(control.get_global_rect().grow(0.5).encloses(content.get_global_rect()), "%s overflows its gallery card at %s: %s" % [content.get_path(), extent, content.get_global_rect()])

func run() -> void:
	for id in PAGES:
		var page: Control = PAGES[id].instantiate()
		root.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		page.size = Vector2(1440, 900)
		if id == "gallery":
			page.refresh(WORKS, 0, "全部", 0, func(_work): return null)
			# Hidden containers defer layout; expose both only for the desktop snapshot.
			page.get_node("Examples").show()
		await process_frame
		await process_frame
		var baseline := {}
		for control in controls(page): baseline[control] = Rect2(control.position, control.size)
		for extent in SIZES:
			var state := LayoutState.new()
			if id == "gallery": page.refresh(WORKS, 0, "全部", 0, func(_work): return null)
			page.size = extent
			var height := Layout.apply(page, id, extent, state)
			page.size = Vector2(extent.x, height)
			await process_frame
			await process_frame
			verify_layout(page, extent, height)
			if id == "gallery":
				page.refresh([], 0, "全部", 0, Callable())
				height = Layout.apply(page, id, extent, state)
				page.size = Vector2(extent.x, height)
				await process_frame
				await process_frame
				verify_layout(page, extent, height)
				for filter in ["全部", "武侠", "科幻"]:
					page.refresh([], 1, filter, 0, Callable())
					height = Layout.apply(page, id, extent, state)
					page.size = Vector2(extent.x, height)
					await process_frame
					await process_frame
					verify_layout(page, extent, height)
				page.refresh([], 1, "全部", 0, Callable())
				page.refresh(WORKS, 0, "全部", 0, func(_work): return null)
				page.get_node("Examples").show()
			state.restore()
			page.size = Vector2(1440, 900)
			await process_frame
			await process_frame
			for control in baseline:
				var before: Rect2 = baseline[control]
				check(control.position.is_equal_approx(before.position) and control.size.is_equal_approx(before.size), "%s did not restore desktop geometry after %s: %s versus %s" % [control.get_path(), extent, Rect2(control.position, control.size), before])
		# Rotation reuses the same state object without restoring in between.
		var rotation_state := LayoutState.new()
		for extent in [Vector2(844, 390), Vector2(320, 568), Vector2(768, 1024), Vector2(390, 844)]:
			if id == "gallery": page.refresh(WORKS, 0, "全部", 0, func(_work): return null)
			page.size = extent
			var height := Layout.apply(page, id, extent, rotation_state)
			page.size = Vector2(extent.x, height)
			await process_frame
			await process_frame
			verify_layout(page, extent, height)
		rotation_state.restore()
		page.queue_free()
		await process_frame
	if failures.is_empty(): print("mobile_pages_test: PASS")
	else: print("mobile_pages_test: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
