extends RefCounted
## Compact canvas chrome. The artwork and desktop controls keep their identities.
var _page: Control
var _ui: Control
var _drawer: Control
var _scroll: ScrollContainer
var _content: VBoxContainer
var _picker: ColorPicker
var _hex: LineEdit
var _width: HSlider
var _size_x: SpinBox
var _size_y: SpinBox
var _rgb: Array[SpinBox] = []
var _history: Array[Button] = []
var _mirrors: Dictionary = {}
var _refresh: Callable
var _syncing := false

func apply(page: Control, extent: Vector2, state: RefCounted, refresh: Callable) -> void:
	_page = page
	_refresh = refresh
	if not is_instance_valid(_ui): _build()
	_ui.show()
	_ui.size = extent
	for path in ["ToolsTitle", "ColorPalette", "WidthLabel", "WidthSlider", "CanvasSize", "TopicLabel", "ReferenceButton", "RestartButton", "EditObjectButton", "DeleteObjectButton", "DeselectButton", "ViewHint"]:
		state.hide(page.get_node(path))
	state.put(page.get_node("TopicPrompt"), "autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)
	state.font(page.get_node("TopicPrompt"), 16 if extent.x < 360 else 18)
	state.put(page.get_node("DrawingStatus"), "clip_text", true)
	state.font(page.get_node("DrawingStatus"), 16)
	state.put(page.get_node("FitViewButton"), "text", "适应")
	state.put(page.get_node("Frame/Title"), "text", "画布")
	var landscape := extent.x > extent.y and extent.x >= 480
	var tools := ["ToolBrush", "ToolEraser", "ToolMove", "AddTextButton", "StickerButton"]
	if landscape:
		state.rect(page.get_node("TopicPrompt"), Rect2(96, 12, extent.x - 328, 44))
		state.font(page.get_node("TopicPrompt"), 16)
		state.rect(page.get_node("ChangeTopicButton"), Rect2(extent.x - 220, 12, 92, 44))
		var tool_width := minf(72, (extent.x - 224) / 5)
		var x := 12.0
		for path in tools:
			state.rect(page.get_node(path), Rect2(x, 64, tool_width, 44))
			x += tool_width + 4
		_ui.get_node("ToolsButton").position = Vector2(x, 64)
		_ui.get_node("ToolsButton").size = Vector2(60, 44)
		x += 64
		for path in ["UndoButton", "RedoButton"]:
			state.rect(page.get_node(path), Rect2(x, 64, 52, 44))
			state.font(page.get_node(path), 18)
			x += 56
		state.rect(page.canvas_view, Rect2(12, 116, extent.x - 24, maxf(100, extent.y - 180)))
		x = 12
		for path in ["ZoomOutButton", "ZoomLabel", "ZoomInButton", "FitViewButton"]:
			state.rect(page.get_node(path), Rect2(x, extent.y - 56, 60 if path != "FitViewButton" else 80, 44))
			x += 64
		state.rect(page.get_node("SubmitButton"), Rect2(extent.x - 136, extent.y - 56, 124, 44))
		state.hide(page.get_node("DrawingStatus"))
		state.hide(page.get_node("Frame/StorageHint"))
	else:
		state.put(page.get_node("DrawingStatus"), "visible", true)
		state.put(page.get_node("Frame/StorageHint"), "visible", true)
		state.put(page.get_node("ViewHint"), "visible", true)
		state.put(page.get_node("ViewHint"), "text", "双指缩放 · 拖动画布")
		state.font(page.get_node("ViewHint"), 16)
		state.font(page.get_node("UndoButton"), 18)
		state.font(page.get_node("RedoButton"), 18)
		state.rect(page.get_node("TopicPrompt"), Rect2(16, 64, extent.x - 116, 44))
		state.rect(page.get_node("ChangeTopicButton"), Rect2(extent.x - 92, 64, 76, 44))
		var tool_width := (extent.x - 40) / 5
		for i in range(tools.size()):
			state.rect(page.get_node(tools[i]), Rect2(12 + i * (tool_width + 4), 116, tool_width, 44))
		_ui.get_node("ToolsButton").position = Vector2(12, 168)
		_ui.get_node("ToolsButton").size = Vector2(64, 44)
		state.rect(page.get_node("UndoButton"), Rect2(84, 168, 52, 44))
		state.rect(page.get_node("RedoButton"), Rect2(144, 168, 52, 44))
		state.rect(page.get_node("SubmitButton"), Rect2(extent.x - 104, 168, 92, 44))
		state.font(page.get_node("SubmitButton"), 18)
		state.rect(page.canvas_view, Rect2(12, 220, extent.x - 24, maxf(120, extent.y - 344)))
		var widths := [44, 64, 44, 92]
		var x := 12.0
		var paths := ["ZoomOutButton", "ZoomLabel", "ZoomInButton", "FitViewButton"]
		for i in range(paths.size()):
			state.rect(page.get_node(paths[i]), Rect2(x, extent.y - 116, widths[i], 44))
			x += widths[i] + 8
		state.rect(page.get_node("DrawingStatus"), Rect2(16, extent.y - 66, 64, 24))
		state.rect(page.get_node("ViewHint"), Rect2(88, extent.y - 66, extent.x - 104, 24))
	_layout_drawer(extent)
	if _drawer.visible: _sync()

func close() -> void:
	if is_instance_valid(_ui): _ui.hide()
	if is_instance_valid(_drawer): _drawer.hide()

func close_tools() -> bool:
	if not is_instance_valid(_drawer) or not _drawer.visible: return false
	_drawer.hide()
	return true

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(44, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	_content.add_child(label)

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	return row

func _mirror(parent: Node, path: String, dismiss: bool = false) -> void:
	var original: Button = _page.get_node(path)
	var button := _button(parent, original.text, func():
		if original.disabled: return
		if dismiss: _drawer.hide()
		original.pressed.emit()
		_refresh.call())
	_mirrors[button] = original

func _build() -> void:
	_ui = Control.new()
	_ui.name = "MobileUI"
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(_ui)
	var tools := _button(_ui, "工具", func():
		_page.cancel_touch_navigation()
		_page.surface.finish()
		_drawer.show()
		_scroll.scroll_vertical = 0
		_sync())
	tools.name = "ToolsButton"
	_drawer = Control.new()
	_drawer.name = "Drawer"
	_ui.add_child(_drawer)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.12, 0.115, 0.1, 0.42)
	_drawer.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed: _drawer.hide())
	var panel := Panel.new()
	panel.name = "Panel"
	_drawer.add_child(panel)
	var title := Label.new()
	title.name = "Title"
	title.text = "画笔与画布"
	title.add_theme_font_size_override("font_size", 26)
	_drawer.add_child(title)
	var close_button := _button(_drawer, "收起", func(): _drawer.hide())
	close_button.name = "CloseButton"
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.scroll_deadzone = 12
	_drawer.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	_scroll.add_child(_content)
	_label("笔刷粗细")
	_width = HSlider.new()
	_width.min_value = 4
	_width.max_value = 56
	_width.step = 4
	_width.custom_minimum_size.y = 44
	_width.value_changed.connect(func(value: float): _page.width_slider.value = value)
	_content.add_child(_width)
	_label("颜色")
	_picker = ColorPicker.new()
	_picker.name = "ColorPicker"
	_picker.edit_alpha = false
	_picker.edit_intensity = false
	_picker.color_modes_visible = false
	_picker.sliders_visible = false
	_picker.hex_visible = false
	_picker.presets_visible = false
	_picker.sampler_visible = false
	_picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	_picker.add_theme_constant_override("sv_width", 200)
	_picker.add_theme_constant_override("sv_height", 200)
	_picker.add_theme_constant_override("h_width", 24)
	_picker.color_changed.connect(_change_color)
	_content.add_child(_picker)
	var rgb_row := _row()
	for i in range(3):
		var input := SpinBox.new()
		input.prefix = ["R", "G", "B"][i]
		input.max_value = 255
		input.custom_minimum_size = Vector2(76, 44)
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.value_changed.connect(func(value: float):
			if _syncing: return
			var color: Color = _picker.color
			color[i] = value / 255.0
			_change_color(color))
		rgb_row.add_child(input)
		_rgb.append(input)
	_hex = LineEdit.new()
	_hex.name = "HexInput"
	_hex.custom_minimum_size.y = 44
	_hex.max_length = 7
	_hex.placeholder_text = "#243D35"
	_hex.text_submitted.connect(_submit_color)
	_hex.focus_exited.connect(func(): _submit_color(_hex.text))
	_content.add_child(_hex)
	_label("最近使用")
	var history := HFlowContainer.new()
	_content.add_child(history)
	for i in range(10):
		var original: Button = _page.palette.get_node("History%d" % i)
		var button := _button(history, "", func():
			if not original.disabled:
				original.pressed.emit()
				_sync())
		button.custom_minimum_size = Vector2(48, 44)
		button.size_flags_horizontal = Control.SIZE_FILL
		_history.append(button)
	_label("选中图层")
	var actions := _row()
	for path in ["EditObjectButton", "DeleteObjectButton", "DeselectButton"]: _mirror(actions, path, true)
	_label("画布尺寸 · 缩小会裁切，可撤销")
	var sizes := _row()
	_size_x = SpinBox.new()
	_size_y = SpinBox.new()
	for field in [_size_x, _size_y]:
		field.min_value = 256
		field.max_value = 2048
		field.suffix = "px"
		field.custom_minimum_size = Vector2(100, 44)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sizes.add_child(field)
	_button(_content, "应用尺寸", func():
		_size_x.apply()
		_size_y.apply()
		_page.canvas_width.value = _size_x.value
		_page.canvas_height.value = _size_y.value
		_page.apply_canvas_size()
		_drawer.hide())
	var more := _row()
	_mirror(more, "ReferenceButton", true)
	_mirror(more, "RestartButton", true)
	_label("单指画画 / 移动图层\n双指缩放、拖动画布")
	_drawer.hide()

func _layout_drawer(extent: Vector2) -> void:
	_drawer.size = extent
	var width := minf(extent.x - 24, 440)
	var left := (extent.x - width) / 2
	var panel: Control = _drawer.get_node("Panel")
	panel.position = Vector2(left, 8)
	panel.size = Vector2(width, extent.y - 16)
	_drawer.get_node("Title").position = Vector2(left + 12, 16)
	_drawer.get_node("Title").size = Vector2(width - 104, 44)
	_drawer.get_node("CloseButton").position = Vector2(left + width - 84, 16)
	_drawer.get_node("CloseButton").size = Vector2(72, 44)
	_scroll.position = Vector2(left + 12, 68)
	_scroll.size = Vector2(width - 24, extent.y - 88)

func _sync() -> void:
	_syncing = true
	_width.set_value_no_signal(_page.surface.pen_width)
	_picker.color = _page.surface.ink
	_hex.text = "#" + _picker.color.to_html(false).to_upper()
	for i in range(3): _rgb[i].set_value_no_signal(roundi(_picker.color[i] * 255))
	_size_x.set_value_no_signal(_page.surface.canvas_size().x)
	_size_y.set_value_no_signal(_page.surface.canvas_size().y)
	for button in _mirrors: button.disabled = _mirrors[button].disabled
	for i in range(_history.size()):
		var original: Button = _page.palette.get_node("History%d" % i)
		_history[i].disabled = original.disabled
		for key in ["normal", "hover", "pressed", "disabled"]:
			_history[i].add_theme_stylebox_override(key, original.get_theme_stylebox(key))
	_syncing = false

func _change_color(color: Color) -> void:
	if _syncing: return
	_page.color_changed.emit(color)
	_sync()

func _submit_color(text: String) -> void:
	if not is_instance_valid(_page) or _syncing: return
	if _page.palette.InputValidation.is_rgb_hex(text.trim_prefix("#")):
		_change_color(Color.html(text))
		_hex.remove_theme_color_override("font_color")
	else:
		_hex.add_theme_color_override("font_color", Color("a44332"))
