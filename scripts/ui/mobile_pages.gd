extends RefCounted
## Reflow the existing pages, keeping their paths and controller state intact.

const MARGIN := 16.0
const TOP := 104.0

static func apply(page: Control, id: String, extent: Vector2, state) -> float:
	match id.to_lower():
		"home": return _home(page, extent, state)
		"levels": return _levels(page, extent, state)
		"gallery": return _gallery(page, extent, state)
		"settings": return _settings(page, extent, state)
	return extent.y

static func _place(page: Control, path: String, bounds: Rect2, state, font_size: int = 0) -> Control:
	var control := page.get_node(path) as Control
	if font_size > 0: state.font(control, font_size)
	if control is BaseButton or control is Slider:
		bounds.size = bounds.size.max(Vector2(56, 56))
	# Release the desktop label's one-line minimum width before assigning its bounds.
	if control is Label: state.put(control, "autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)
	state.rect(control, bounds)
	return control

static func _wrap(control: Control, state) -> void:
	state.put(control, "autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)

static func _home(page: Control, extent: Vector2, state) -> float:
	var width := extent.x - MARGIN * 2.0
	if width >= 600.0:
		var left_width := width * 0.52
		var portrait_size := minf(width - left_width - 16.0, 360.0)
		var landscape := extent.y < 600.0
		if landscape: portrait_size = minf(portrait_size, maxf(180.0, extent.y - TOP - 44.0))
		state.put(_place(page, "GameTitle", Rect2(MARGIN, TOP, left_width, 70.0), state, 64), "horizontal_alignment", HORIZONTAL_ALIGNMENT_LEFT)
		state.put(_place(page, "Tagline", Rect2(MARGIN + 4.0, TOP + 66.0, left_width, 32.0), state, 22), "horizontal_alignment", HORIZONTAL_ALIGNMENT_LEFT)
		_place(page, "Portrait", Rect2(MARGIN + left_width + 16.0, TOP, portrait_size, portrait_size), state)
		var action_width := (left_width - 12.0) * 0.5
		_place(page, "LevelsButton", Rect2(MARGIN, TOP + 110.0, action_width, 52.0), state, 22)
		_place(page, "FreeDrawButton", Rect2(MARGIN + action_width + 12.0, TOP + 110.0, action_width, 52.0), state, 22)
		var utility_count := 4 if landscape else 3
		var small_width := (left_width - 8.0 * (utility_count - 1)) / utility_count
		for index in range(utility_count):
			_place(page, ["GalleryButton", "SettingsButton", "ExitButton", "NoticeButton"][index], Rect2(MARGIN + index * (small_width + 8.0), TOP + 178.0, small_width, 48.0), state, 18 if index == 3 else 22)
		if not landscape: _place(page, "NoticeButton", Rect2(MARGIN, TOP + 242.0, left_width, 44.0), state, 20)
		return maxf(extent.y, TOP + maxf(portrait_size, 226.0 if landscape else 286.0) + 44.0)
	var title := _place(page, "GameTitle", Rect2(MARGIN, TOP, width, 72.0), state, 64 if width >= 340.0 else 56)
	state.put(title, "horizontal_alignment", HORIZONTAL_ALIGNMENT_CENTER)
	var tagline := _place(page, "Tagline", Rect2(MARGIN, TOP + 72.0, width, 32.0), state, 22)
	state.put(tagline, "horizontal_alignment", HORIZONTAL_ALIGNMENT_CENTER)
	var portrait_size := minf(width * 0.68, 240.0)
	_place(page, "Portrait", Rect2((extent.x - portrait_size) * 0.5, TOP + 112.0, portrait_size, portrait_size), state)
	var y := TOP + 124.0 + portrait_size
	_place(page, "LevelsButton", Rect2(MARGIN, y, width, 54.0), state, 24)
	_place(page, "FreeDrawButton", Rect2(MARGIN, y + 66.0, width, 52.0), state, 22)
	var small_width := (width - 16.0) / 3.0
	for index in range(3):
		_place(page, ["GalleryButton", "SettingsButton", "ExitButton"][index], Rect2(MARGIN + index * (small_width + 8.0), y + 132.0, small_width, 48.0), state, 22)
	_place(page, "NoticeButton", Rect2(MARGIN, y + 192.0, width, 44.0), state, 20)
	return maxf(extent.y, y + 280.0)

static func _levels(page: Control, extent: Vector2, state) -> float:
	var width := extent.x - MARGIN * 2.0
	var wide := width >= 600.0
	var row_height := 134.0 if wide else 182.0
	var rows := page.get_children().filter(func(child: Node): return child.has_meta("topic_id"))
	for index in rows.size():
		var row := _place(page, "Topic%d" % (index + 1), Rect2(MARGIN, TOP + index * row_height, width, row_height), state)
		_place(row, "Number", Rect2(0.0, 0.0, 38.0, 44.0), state, 22)
		_place(row, "Title", Rect2(42.0, 0.0, width - 160.0, 44.0), state, 26)
		_place(row, "EnterButton", Rect2(width - 108.0, 0.0, 108.0, 48.0), state, 22)
		if wide:
			state.rect(row.get_node("Title"), Rect2(42.0, 0.0, 190.0, 44.0))
			_wrap(_place(row, "Prompt", Rect2(248.0, 0.0, width - 376.0, 58.0), state, 22), state)
			_wrap(_place(row, "Status", Rect2(248.0, 62.0, width - 256.0, 42.0), state, 19), state)
		else:
			_wrap(_place(row, "Prompt", Rect2(0.0, 64.0, width, 58.0), state, 22), state)
			_wrap(_place(row, "Status", Rect2(0.0, 126.0, width, 40.0), state, 19), state)
		_place(row, "Divider", Rect2(0.0, row_height - 10.0, width, 1.0), state)
	return maxf(extent.y, TOP + rows.size() * row_height + 44.0)

static func _settings(page: Control, extent: Vector2, state) -> float:
	# The game uses landscape orientation; keep a horizontal form at every size.
	var width := minf(extent.x - 40.0, 720.0)
	var x := (extent.x - width) * 0.5
	var y := 80.0
	_place(page, "VolumeCaption", Rect2(x, y, 80.0, 56.0), state, 26)
	_place(page, "VolumeSlider", Rect2(x + 88.0, y, width - 168.0, 56.0), state)
	_place(page, "VolumeLabel", Rect2(x + width - 64.0, y, 64.0, 56.0), state, 24)
	y += 68.0
	var row_width := (width - 24.0) * 0.5
	for index in range(2):
		var caption: String = ["SoundToggleCaption", "MusicToggleCaption"][index]
		var toggle: String = ["SoundToggle", "MusicToggle"][index]
		var row_x := x + index * (row_width + 24.0)
		_place(page, caption, Rect2(row_x, y, 72.0, 64.0), state, 26)
		_place(page, toggle, Rect2(row_x + row_width - 148.0, y, 148.0, 64.0), state, 24)
	y += 80.0
	_place(page, "Divider", Rect2(x, y, width, 1.0), state)
	var reset_width := minf(240.0, width * 0.46)
	_place(page, "ResetButton", Rect2(x, y + 16.0, reset_width, 64.0), state, 24)
	_wrap(_place(page, "SettingsNote", Rect2(x + reset_width + 24.0, y + 16.0, width - reset_width - 24.0, 64.0), state, 18), state)
	return maxf(extent.y, y + 92.0)

static func _gallery(page: Control, extent: Vector2, state) -> float:
	var width := extent.x - MARGIN * 2.0
	var welcome_width := minf(width, 360.0)
	_place(page, "Welcome", Rect2(MARGIN, TOP, width, 52.0), state, 28 if width >= 340.0 else 24)
	var tab_width := (width - 12.0) * 0.5
	for index in range(2):
		var tab := _place(page, ["MyWorksTab", "ExamplesTab"][index], Rect2(MARGIN + index * (tab_width + 12.0), TOP + 64.0, tab_width, 52.0), state)
		state.font(tab, 24)
	var works := _place(page, "MyWorks", Rect2(MARGIN, TOP + 132.0, width, 0.0), state)
	_wrap(_place(works, "CountLabel", Rect2(0.0, 0.0, width, 38.0), state, 20), state)
	_place(works, "PreviousButton", Rect2(0.0, 46.0, tab_width, 48.0), state, 22)
	_place(works, "NextButton", Rect2(tab_width + 12.0, 46.0, tab_width, 48.0), state, 22)
	var empty := _place(works, "EmptyState", Rect2(0.0, 48.0, width, 248.0), state)
	_place(empty, "Title", Rect2(0.0, 24.0, width, 48.0), state, 30)
	_wrap(_place(empty, "Subtitle", Rect2(0.0, 80.0, width, 64.0), state, 20), state)
	var create_width := minf(width, 240.0)
	_place(empty, "CreateButton", Rect2((width - create_width) * 0.5, 164.0, create_width, 52.0), state, 22)
	var work_grid_height := _gallery_cards(works.get_node("Cards"), width, 108.0, false, state)
	var works_height := 296.0 if empty.visible else 108.0 + work_grid_height
	state.rect(works, Rect2(MARGIN, TOP + 132.0, width, works_height))
	var examples := _place(page, "Examples", Rect2(MARGIN, TOP + 132.0, width, 0.0), state)
	var filter_columns := 5 if width >= 420.0 else 3
	var filter_width := (width - 8.0 * (filter_columns - 1)) / filter_columns
	for index in range(5):
		var name: String = ["FilterAll", "FilterWuxia", "FilterSciFi", "FilterMarket", "FilterFun"][index]
		_place(examples, name, Rect2((index % filter_columns) * (filter_width + 8.0), floorf(float(index) / filter_columns) * 64.0, filter_width, 56.0), state, 20)
	var filter_height := ceilf(5.0 / filter_columns) * 64.0
	_place(examples, "CountLabel", Rect2(0.0, filter_height, width, 32.0), state, 20)
	var examples_grid_y := filter_height + 40.0
	var examples_height := examples_grid_y + _gallery_cards(examples.get_node("Cards"), width, examples_grid_y, true, state)
	state.rect(examples, Rect2(MARGIN, TOP + 132.0, width, examples_height))
	return maxf(extent.y, TOP + 132.0 + (examples_height if examples.visible else works_height) + 44.0)

static func _gallery_cards(grid: GridContainer, width: float, top: float, example: bool, state) -> float:
	var columns := 2 if width >= 600.0 else 1
	var card_width := (width - 16.0 * (columns - 1)) / columns
	var picture_height := minf(224.0, card_width * 0.52)
	var card_height := picture_height + 116.0
	state.put(grid, "columns", columns)
	state.put(grid, "theme_override_constants/h_separation", 16)
	state.put(grid, "theme_override_constants/v_separation", 20)
	var count := 0
	for child in grid.get_children():
		var card := child as Control
		if card.visible: count += 1
		state.put(card, "custom_minimum_size", Vector2(card_width, card_height))
		for path in ["Picture", "PictureBackground", "DraftPreview"]:
			if card.has_node(path): _place(card, path, Rect2(0.0, 0.0, card_width, picture_height), state)
		var title_width := card_width - 76.0 if example else card_width
		_wrap(_place(card, "Title", Rect2(0.0, picture_height + 6.0, title_width, 40.0), state, 22), state)
		var action_width := (card_width - 12.0) * 0.5
		_place(card, "ViewButton", Rect2(0.0, picture_height + 52.0, action_width, 48.0), state, 22)
		if example:
			_place(card, "TopicLabel", Rect2(card_width - 68.0, picture_height + 10.0, 68.0, 32.0), state, 19)
			_place(card, "Caption", Rect2(action_width + 12.0, picture_height + 52.0, action_width, 48.0), state, 19)
		else:
			_place(card, "EditButton", Rect2(action_width + 12.0, picture_height + 52.0, action_width, 48.0), state, 22)
	var rows := ceili(float(count) / columns)
	var height := rows * card_height + maxi(0, rows - 1) * 20.0
	state.rect(grid, Rect2(0.0, top, width, height))
	return height
