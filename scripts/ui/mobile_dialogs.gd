extends RefCounted
## Reflow existing dialog controls without changing controller-facing node paths.

const GAP := 10.0
const BUTTON_HEIGHT := 48.0

static func apply(dialog: Control, id: String, extent: Vector2, state) -> float:
	var panel_width := minf(680.0, extent.x - 24.0)
	var left := (extent.x - panel_width) / 2.0
	var x := left + 16.0
	var width := panel_width - 32.0
	var y := 24.0
	var title: Label = dialog.get_node("Frame/Title")
	var title_height := _label(title, state, Rect2(x, y, width - 54.0, 48.0), 26)
	_rect(dialog, "Frame/CloseButton", Rect2(x + width - 48.0, y, 48.0, 48.0), state, 24)
	y += maxf(48.0, title_height) + GAP
	match id:
		"busy":
			state.hide(dialog.get_node("Frame/Body"))
			state.hide(dialog.get_node("Frame/CloseButton"))
		"text_editor":
			state.hide(dialog.get_node("Frame/Body"))
			y += _label(dialog.get_node("TextLabel"), state, Rect2(x, y, width, 30), 20) + 6
			_rect(dialog, "TextInput", Rect2(x, y, width, BUTTON_HEIGHT), state, 22)
			y += BUTTON_HEIGHT + 16
			_rect(dialog, "FontSizeLabel", Rect2(x, y, 64, BUTTON_HEIGHT), state, 20)
			_rect(dialog, "FontSizeInput", Rect2(x + 76, y, width - 76, BUTTON_HEIGHT), state, 20)
			var size_input: SpinBox = dialog.get_node("FontSizeInput")
			state.font(size_input.get_line_edit(), 20)
			y += BUTTON_HEIGHT + GAP
			_rect(dialog, "ColorLabel", Rect2(x, y, 64, BUTTON_HEIGHT), state, 20)
			_rect(dialog, "ColorInput", Rect2(x + 76, y, width - 76, BUTTON_HEIGHT), state, 20)
			y += BUTTON_HEIGHT + GAP
			# Reserve two lines for validation after an invalid submit.
			_label(dialog.get_node("ErrorLabel"), state, Rect2(x, y, width, 60), 18)
			y += 70
			y = _buttons(dialog, ["ApplyButton"], x, y, width, state)
		"sticker_picker":
			y += _body(dialog, state, x, y, width) + GAP
			dialog.set_mobile_layout(true, width)
			var categories: HFlowContainer = dialog.get_node("Categories")
			var columns := maxi(1, int(floor((width + 8.0) / 132.0)))
			var rows := int(ceil(float(categories.get_child_count()) / columns))
			var category_height := rows * 48.0 + (rows - 1) * 8.0
			state.rect(categories, Rect2(x, y, width, category_height))
			y += category_height + GAP
			var list_height := maxf(230.0, minf(600.0, extent.y - y - 28.0))
			_rect(dialog, "Scroll", Rect2(x, y, width, list_height), state)
			y += list_height
		"play_notice":
			y += _body(dialog, state, x, y, width) + GAP
			var statement: RichTextLabel = dialog.get_node("Statement")
			state.font(statement, 20)
			var statement_height := maxf(220.0, minf(560.0, extent.y - y - 100.0))
			state.rect(statement, Rect2(x, y, width, statement_height))
			y += statement_height + 16
			y = _buttons(dialog, ["OkayButton"], x, y, width, state)
		"sticker_catalog":
			state.hide(dialog.get_node("Frame/Body"))
			var sample_height := 116.0
			var sample_width := (width - 32.0) / 3.0
			_rect(dialog, "ReferencePanel", Rect2(x, y, width, sample_height * 2.0 + 36.0), state)
			var names := ["SampleDu", "SamplePink", "SampleSilver", "SampleBlue", "SampleViolet"]
			for index in names.size():
				_rect(dialog, names[index], Rect2(x + 8 + (index % 3) * (sample_width + 8), y + 10 + (index / 3) * (sample_height + 12), sample_width, sample_height), state)
			y += sample_height * 2.0 + 48.0
			y += _label(dialog.get_node("WeaponTitle"), state, Rect2(x, y, width, 32), 24) + 2
			y += _label(dialog.get_node("WeaponCaption"), state, Rect2(x, y, width, 28), 20) + GAP
			y = _buttons(dialog, ["WeaponButton"], x, y, width, state) + 8
			y += _label(dialog.get_node("SceneTitle"), state, Rect2(x, y, width, 32), 24) + GAP
			y = _buttons(dialog, ["CityButton", "MarketButton", "BrandButton"], x, y, width, state)
			var note: Label = dialog.get_node("MissingMaterialsNote")
			y += _label(note, state, Rect2(x, y, width, 28), 18) + GAP
			y = _buttons(dialog, ["BackButton"], x, y, width, state)
		"submission_result", "work_view", "image_view":
			var picture_height := maxf(160.0, minf(width * 0.62, extent.y * 0.48))
			var picture_path := "Picture" if id == "image_view" else "Artwork"
			_rect(dialog, picture_path, Rect2(x, y, width, picture_height), state)
			if id == "work_view":
				_rect(dialog, "DraftPreview", Rect2(x, y, width, picture_height), state)
			y += picture_height + GAP
			if id == "submission_result":
				y += _label(dialog.get_node("Remark"), state, Rect2(x, y, width, 32), 20) + GAP
			y += _body(dialog, state, x, y, width) + GAP
			if id == "submission_result":
				y = _buttons(dialog, ["SaveButton", "SaveAsButton", "DownloadButton", "ContinueButton"], x, y, width, state)
			elif id == "work_view":
				y = _buttons(dialog, ["EditButton", "DownloadButton"], x, y, width, state)
			else:
				y = _buttons(dialog, ["BackButton"], x, y, width, state)
		_:
			y += _body(dialog, state, x, y, width) + 20
			var paths: Array = ["CancelButton", "ConfirmButton"]
			if id == "info": paths = ["OkayButton"]
			elif id == "save_confirmation": paths = ["ContinueButton", "GalleryButton", "NextButton"]
			y = _buttons(dialog, paths, x, y, width, state)
	var bottom := y + 16.0
	state.rect(dialog.get_node("Frame/Panel"), Rect2(left, 12, panel_width, bottom - 12))
	return maxf(extent.y, bottom + 12.0)

static func _body(dialog: Control, state, x: float, y: float, width: float) -> float:
	return _label(dialog.get_node("Frame/Body"), state, Rect2(x, y, width, 32), 20)

static func _label(label: Label, state, bounds: Rect2, font_size: int) -> float:
	state.font(label, font_size)
	state.put(label, "autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)
	state.put(label, "vertical_alignment", VERTICAL_ALIGNMENT_TOP)
	var font := label.get_theme_font("font")
	var measured := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, bounds.size.x, font_size)
	bounds.size.y = maxf(bounds.size.y, measured.y + 8.0)
	state.rect(label, bounds)
	return bounds.size.y

static func _rect(dialog: Control, path: String, bounds: Rect2, state, font_size: int = 0) -> void:
	var control: Control = dialog.get_node(path)
	if font_size > 0: state.font(control, font_size)
	state.rect(control, bounds)

static func _buttons(dialog: Control, paths: Array, x: float, y: float, width: float, state) -> float:
	var visible_paths: Array = []
	for path in paths:
		if dialog.get_node(path).visible: visible_paths.append(path)
	var columns := 2 if width >= 320.0 and visible_paths.size() > 1 else 1
	var button_width := (width - GAP * (columns - 1)) / columns
	for index in visible_paths.size():
		var path: String = visible_paths[index]
		var bounds := Rect2(x + (index % columns) * (button_width + GAP), y + (index / columns) * (BUTTON_HEIGHT + GAP), button_width, BUTTON_HEIGHT)
		_rect(dialog, path, bounds, state, 20)
	return y + ceil(float(visible_paths.size()) / columns) * (BUTTON_HEIGHT + GAP)
