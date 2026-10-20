extends RefCounted
## Bind the authored workspace scenes; compact screens only adjust existing nodes.
const TARGET := 56.0
const GAP := 8.0
const PANEL_TITLES := {"palette": "调色板", "layers": "图层设置", "canvas": "画布设置"}
var _page: Control
var _ui: Control
var _drawer: Control
var _scroll: ScrollContainer
var _toolbar: ScrollContainer
var _tool_row: HBoxContainer
var _palette_button: Button
var _content: VBoxContainer
var _sections: Dictionary = {}
var _active_panel := ""
var _picker: ColorPicker
var _hex: LineEdit
var _width: HSlider
var _size_x: SpinBox
var _size_y: SpinBox
var _rgb: Array[SpinBox] = []
var _history: Array[Button] = []
var _history_empty: Label
var _mirrors: Dictionary = {}
var _syncing := false
var _layer_picker: OptionButton
var _layer_actions: Array[Button] = []
var _shown_color := Color(-1, -1, -1)

func apply(page: Control, extent: Vector2, state: RefCounted, _refresh: Callable) -> void:
	_page = page
	bind(page)
	for path in ["Frame/BrandTitle", "Frame/HeaderRule", "Frame/Title", "Frame/Subtitle", "ToolsTitle", "ColorPalette", "WidthLabel", "WidthSlider", "CanvasSize", "LayerTools", "TopicLabel", "EditObjectButton", "DeleteObjectButton", "DeselectButton", "DrawingStatus", "ToolBrush", "ToolEraser", "ToolMove", "AddTextButton", "StickerButton", "ChangeTopicButton", "ReferenceButton", "RestartButton"]:
		state.hide(page.get_node(path))
	for path in ["UndoButton", "RedoButton", "ZoomOutButton", "ZoomLabel", "ZoomInButton", "FitViewButton", "SubmitButton", "Frame/BackButton", "TopicPrompt", "ViewHint", "Frame/StorageHint"]:
		state.put(page.get_node(path), "visible", true)
	state.put(page.get_node("TopicPrompt"), "autowrap_mode", TextServer.AUTOWRAP_OFF)
	state.put(page.get_node("TopicPrompt"), "clip_text", true)
	state.put(page.get_node("TopicPrompt"), "text_overrun_behavior", TextServer.OVERRUN_TRIM_ELLIPSIS)
	for path in ["UndoButton", "RedoButton", "SubmitButton", "Frame/BackButton", "FitViewButton"]:
		state.font(page.get_node(path), 20)
	var landscape := extent.x > extent.y and extent.y < 600
	var wide := extent.x >= 1100 and not landscape
	page.surface.touch_controls = not wide
	if landscape:
		var paths := ["Frame/BackButton", "UndoButton", "RedoButton", "ZoomOutButton", "ZoomLabel", "ZoomInButton", "FitViewButton", "SubmitButton"]
		var widths := [56, 56, 56, 56, 40, 56, 88, 56]
		var x := 8.0
		for i in paths.size():
			state.rect(page.get_node(paths[i]), Rect2(x, 8, widths[i], TARGET))
			state.font(page.get_node(paths[i]), 16)
			x += widths[i] + 4
		state.hide(page.get_node("TopicPrompt"))
		state.rect(page.canvas_view, Rect2(8, 72, extent.x - 16, maxf(80, extent.y - 160)))
		state.rect(_toolbar, Rect2(8, extent.y - 64, extent.x - 16, TARGET))
		_status_layout(extent, extent.y - 84, state)
	else:
		var header_width := 56.0 if not wide else 64.0
		for i in 3:
			var path: String = ["Frame/BackButton", "UndoButton", "RedoButton"][i]
			state.rect(page.get_node(path), Rect2(8 + i * (header_width + (8 if wide else 4)), 8, header_width, TARGET))
			state.font(page.get_node(path), 16 if not wide else 20)
		state.rect(page.get_node("SubmitButton"), Rect2(extent.x - (64 if not wide else 96), 8, 56 if not wide else 88, TARGET))
		state.font(page.get_node("SubmitButton"), 16 if not wide else 20)
		if wide:
			state.font(page.get_node("TopicPrompt"), 20)
			state.rect(page.get_node("TopicPrompt"), Rect2(304, 8, extent.x - 408, TARGET))
			state.rect(page.canvas_view, Rect2(8, 72, extent.x - 16, extent.y - 168))
			state.rect(_toolbar, Rect2(8, extent.y - 72, extent.x - 328, TARGET))
			_zoom_layout(extent.x - 304, extent.y - 72, state)
			_status_layout(extent, extent.y - 92, state)
		else:
			state.font(page.get_node("TopicPrompt"), 14)
			state.rect(page.get_node("TopicPrompt"), Rect2(8, 72, extent.x - 16, 20))
			state.rect(page.canvas_view, Rect2(8, 96, extent.x - 16, maxf(80, extent.y - 248)))
			state.rect(_toolbar, Rect2(8, extent.y - 128, extent.x - 16, TARGET))
			_zoom_layout((extent.x - 288) / 2, extent.y - 64, state)
			_status_layout(extent, extent.y - 148, state)
	# A failed save keeps its existing retry action available in the header.
	state.rect(page.get_node("Frame/StorageRetry"), page.get_node("SubmitButton").get_rect())
	state.font(page.get_node("Frame/StorageRetry"), 16)
	if page.get_node("Frame/StorageRetry").visible: state.hide(page.get_node("SubmitButton"))
	_layout_drawer(extent, state)
	sync_controls()

func _zoom_layout(x: float, y: float, state: RefCounted) -> void:
	var paths := ["ZoomOutButton", "ZoomLabel", "ZoomInButton", "FitViewButton"]
	var widths := [56, 40, 56, 112]
	for i in paths.size():
		state.rect(_page.get_node(paths[i]), Rect2(x, y, widths[i], TARGET))
		state.font(_page.get_node(paths[i]), 16 if i == 1 else 20)
		x += widths[i] + GAP

func _status_layout(extent: Vector2, y: float, state: RefCounted) -> void:
	state.rect(_page.get_node("Frame/StorageHint"), Rect2(8, y, 100, 16))
	state.rect(_page.get_node("ViewHint"), Rect2(116, y, extent.x - 124, 16))
	for path in ["Frame/StorageHint", "ViewHint"]:
		state.font(_page.get_node(path), 12)
		state.put(_page.get_node(path), "clip_text", true)

func open_panel(id: String) -> void:
	if not _sections.has(id): return
	_page.cancel_touch_navigation()
	_page.surface.finish()
	_active_panel = id
	for key in _sections: _sections[key].visible = key == id
	_drawer.get_node("Title").text = PANEL_TITLES[id]
	_drawer.show()
	_scroll.scroll_vertical = 0
	sync_controls()

func close_tools() -> bool:
	if not is_instance_valid(_drawer) or not _drawer.visible: return false
	_drawer.hide()
	_active_panel = ""
	return true

func activate_desktop(page: Control) -> void:
	bind(page)
	_page.surface.touch_controls = false
	_update_save_action()
	sync_controls()

func bind(page: Control) -> void:
	_page = page
	if is_instance_valid(_ui): return
	_ui = page.get_node("MobileUI")
	_toolbar = _ui.get_node("Toolbar")
	_tool_row = _toolbar.get_node("Tools")
	_palette_button = _tool_row.get_node("PaletteButton")
	_drawer = _ui.get_node("Drawer")
	_scroll = _drawer.get_node("Scroll")
	var stack: VBoxContainer = _scroll.get_node("Content")
	for id in PANEL_TITLES:
		_sections[id] = stack.get_node(id.capitalize() + "Panel")
	_content = _sections.palette
	_picker = _content.get_node("ColorPicker")
	_hex = _content.get_node("HexInput")
	_width = _content.get_node("BrushWidth")
	_history_empty = _content.get_node("EmptyHint")
	_layer_picker = _sections.layers.get_node("LayerPicker")
	_size_x = _sections.canvas.get_node("Dimensions/CanvasWidth")
	_size_y = _sections.canvas.get_node("Dimensions/CanvasHeight")
	_palette_button.pressed.connect(open_panel.bind("palette"))
	_tool_row.get_node("LayersButton").pressed.connect(open_panel.bind("layers"))
	_tool_row.get_node("CanvasButton").pressed.connect(open_panel.bind("canvas"))
	_drawer.get_node("CloseButton").pressed.connect(close_tools)
	_drawer.get_node("Shade").gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed: close_tools())
	for path in ["ToolBrush", "ToolEraser", "ToolMove", "AddTextButton", "StickerButton", "ChangeTopicButton", "ReferenceButton", "RestartButton"]:
		_bind_action(_tool_row.get_node(path), _page.get_node(path))
	for path in ["EditObjectButton", "DeleteObjectButton", "DeselectButton"]:
		_bind_action(_sections.layers.get_node("SelectionActions/" + path), _page.get_node(path), true)
	for i in 10:
		var original: Button = _page.palette.get_node("History%d" % i)
		var button: Button = _content.get_node("RecentColors/History%d" % i)
		button.pressed.connect(func():
			if not original.disabled:
				original.pressed.emit()
				sync_controls())
		_history.append(button)
	_width.value_changed.connect(func(value: float): _page.width_slider.value = value)
	_picker.color_changed.connect(_change_color)
	_hex.text_submitted.connect(_submit_color)
	_hex.focus_exited.connect(func(): _submit_color(_hex.text))
	for i in 3:
		var input: SpinBox = _content.get_node("RGB/" + ["RedInput", "GreenInput", "BlueInput"][i])
		input.value_changed.connect(func(value: float):
			if _syncing: return
			var color: Color = _picker.color
			color[i] = value / 255.0
			_change_color(color))
		_rgb.append(input)
	_layer_picker.item_selected.connect(func(index: int):
		_page.select_layer(index)
		sync_controls())
	for group in ["OrderUp", "OrderDown", "Mirrors", "Center"]:
		for button in _sections.layers.get_node(group).get_children():
			var action: String = button.get_meta("action")
			button.pressed.connect(func():
				_page.layer_action(action)
				sync_controls())
			_layer_actions.append(button)
	_sections.canvas.get_node("ApplySizeButton").pressed.connect(_apply_canvas_size)
	_page.get_node("Frame/StorageRetry").visibility_changed.connect(_update_save_action)
	var touch_scroll: Node = _ui.get_node("TouchToolbar")
	touch_scroll.scroll = _toolbar
	touch_scroll.can_scroll = func(): return not _drawer.visible and _page.get_node("ToolBrush").focus_mode != Control.FOCUS_NONE
	touch_scroll.gesture_finished.connect(sync_controls)

func _bind_action(button: Button, original: Button, dismiss: bool = false) -> void:
	_mirrors[button] = original
	button.pressed.connect(func():
		if original.disabled: return
		if dismiss: close_tools()
		original.pressed.emit()
		sync_controls())

func _apply_canvas_size() -> void:
	_size_x.apply()
	_size_y.apply()
	_page.canvas_width.value = _size_x.value
	_page.canvas_height.value = _size_y.value
	_page.apply_canvas_size()
	close_tools()

func _update_save_action() -> void:
	if is_instance_valid(_page):
		_page.get_node("SubmitButton").visible = not _page.get_node("Frame/StorageRetry").visible

func _layout_drawer(extent: Vector2, state: RefCounted) -> void:
	var width := minf(extent.x - 24, 440)
	var left := (extent.x - width) / 2
	state.rect(_drawer.get_node("Panel"), Rect2(left, 8, width, extent.y - 16))
	state.rect(_drawer.get_node("Title"), Rect2(left + 12, 16, width - 104, TARGET))
	state.rect(_drawer.get_node("CloseButton"), Rect2(left + width - 84, 16, 72, TARGET))
	state.rect(_scroll, Rect2(left + 12, 80, width - 24, extent.y - 100))

func sync_controls() -> void:
	if not is_instance_valid(_ui) or _picker == null: return
	_syncing = true
	_width.set_value_no_signal(_page.surface.pen_width)
	_picker.color = _page.surface.ink
	_hex.text = "#" + _picker.color.to_html(false).to_upper()
	for i in range(3): _rgb[i].set_value_no_signal(roundi(_picker.color[i] * 255))
	_size_x.set_value_no_signal(_page.surface.canvas_size().x)
	_size_y.set_value_no_signal(_page.surface.canvas_size().y)
	_sections.canvas.get_node("TopicPrompt").text = _page.get_node("TopicPrompt").text
	for button in _mirrors:
		button.disabled = _mirrors[button].disabled
		if button.toggle_mode: button.set_pressed_no_signal(_mirrors[button].button_pressed)
	_layer_picker.clear()
	for index in _page.layer_picker.item_count:
		_layer_picker.add_item(_page.layer_picker.get_item_text(index), _page.layer_picker.get_item_id(index))
	_layer_picker.select(_page.layer_picker.selected)
	var popup: PopupMenu = _page.layer_menu.get_popup()
	for button in _layer_actions:
		var action: String = button.get_meta("action")
		var index: int = _page.LAYER_ACTIONS.find(action)
		var item := popup.get_item_index(index)
		button.disabled = _page.layer_menu.disabled or item < 0 or popup.is_item_disabled(item)
		if button.toggle_mode and not _page.surface.selected_object().is_empty():
			var value: Vector2 = _page.surface.render_scale(_page.surface.selected_object())
			button.set_pressed_no_signal(value.x < 0 if action == "flip_h" else value.y < 0)
	var used := 0
	for i in range(_history.size()):
		var original: Button = _page.palette.get_node("History%d" % i)
		_history[i].disabled = original.disabled
		_history[i].visible = not original.disabled
		if not original.disabled: used += 1
		for key in ["normal", "hover", "pressed", "disabled"]:
			_history[i].add_theme_stylebox_override(key, original.get_theme_stylebox(key))
	_history_empty.visible = used == 0
	_sync_swatch()
	_page.get_node("Frame/StorageHint").tooltip_text = _page.get_node("Frame/StorageHint").text
	var hint: Label = _page.get_node("ViewHint")
	hint.text = "拖动移动 · 边柄镜像 · 双指缩放" if _page.surface.selecting else "单指绘画 · 双指缩放/平移"
	if _tool_row.size.x > _toolbar.size.x: hint.text = "工具条左右滑动 · 双指缩放"
	hint.tooltip_text = _page.drawing_status.text
	_syncing = false

func _sync_swatch() -> void:
	var color: Color = _page.surface.ink
	if color == _shown_color: return
	_shown_color = color
	var button: Button = _palette_button
	button.tooltip_text = "调色板 · 当前颜色 #" + color.to_html(false).to_upper()
	for key in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := button.get_theme_stylebox(key).duplicate() as StyleBoxFlat
		style.bg_color = color.lightened(0.12) if key == "hover" else color
		button.add_theme_stylebox_override(key, style)
	var text_color := Color("243d35") if color.get_luminance() > 0.5 else Color.WHITE
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, text_color)

func _change_color(color: Color) -> void:
	if _syncing: return
	_page.color_changed.emit(color)
	sync_controls()

func _submit_color(text: String) -> void:
	if not is_instance_valid(_page) or _syncing: return
	if _page.palette.InputValidation.is_rgb_hex(text.trim_prefix("#")):
		_change_color(Color.html(text))
		_hex.remove_theme_color_override("font_color")
	else:
		_hex.add_theme_color_override("font_color", Color("a44332"))
