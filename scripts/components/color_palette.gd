extends Control
## Embedded RGB/HSV controls. History is supplied by the drawing session.

signal color_changed(color: Color)

const InputValidation = preload("res://scripts/input_validation.gd")
var color := Color("243d35")
var hsv_mode := false
var _hsv := Vector3.ZERO
var _syncing := false
var _sliders: Array[HSlider] = []
var _values: Array[SpinBox] = []
var _labels: Array[Label] = []
var _gradients: Array[Gradient] = []
var _history_buttons: Array[Button] = []
var _rgb: Button
var _hsv_button: Button
var _wheel: ColorPicker
var _hex: LineEdit
var _preview: ColorRect

func _ready() -> void:
	# A local compact theme keeps the page's large button padding out of inputs.
	var compact := Theme.new()
	compact.default_font = get_theme_default_font()
	compact.default_font_size = 16
	var field := StyleBoxFlat.new()
	field.bg_color = Color("fffdf7")
	field.border_color = Color("b7b1a4")
	field.set_border_width_all(1)
	field.content_margin_left = 5
	field.content_margin_right = 5
	field.content_margin_top = 2
	field.content_margin_bottom = 2
	for type in ["Button", "LineEdit"]:
		compact.set_stylebox("normal", type, field)
		compact.set_color("font_color", type, Color("292824"))
		compact.set_color("font_hover_color", type, Color("292824"))
		compact.set_color("font_focus_color", type, Color("292824"))
	var selected := field.duplicate() as StyleBoxFlat
	selected.bg_color = Color("243d35")
	compact.set_stylebox("pressed", "Button", selected)
	compact.set_stylebox("hover_pressed", "Button", selected)
	compact.set_color("font_pressed_color", "Button", Color.WHITE)
	compact.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	compact.set_color("font_color", "Label", Color("77736a"))
	theme = compact
	_rgb = _mode_button("RGB", 0, false)
	_hsv_button = _mode_button("HSV", 99, true)
	for i in range(3):
		var label := Label.new()
		_place(label, Vector2(0, 30 + i * 24), Vector2(18, 22))
		_labels.append(label)
		var slider := HSlider.new()
		_place(slider, Vector2(22, 30 + i * 24), Vector2(100, 22))
		var gradient := Gradient.new()
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.width = 128
		texture.height = 8
		var track := StyleBoxTexture.new()
		track.texture = texture
		track.content_margin_top = 4
		track.content_margin_bottom = 4
		slider.add_theme_stylebox_override("slider", track)
		slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
		slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
		_gradients.append(gradient)
		slider.value_changed.connect(_channel_changed.bind(i))
		_sliders.append(slider)
		var value := SpinBox.new()
		_place(value, Vector2(128, 30 + i * 24), Vector2(66, 22))
		value.value_changed.connect(_channel_changed.bind(i))
		_values.append(value)
	_wheel = ColorPicker.new()
	_wheel.name = "Wheel"
	_wheel.edit_alpha = false
	_wheel.edit_intensity = false
	_wheel.color_modes_visible = false
	_wheel.sliders_visible = false
	_wheel.hex_visible = false
	_wheel.presets_visible = false
	_wheel.sampler_visible = false
	_wheel.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	_wheel.add_theme_constant_override("sv_width", 136)
	_wheel.add_theme_constant_override("sv_height", 136)
	_wheel.add_theme_constant_override("h_width", 12)
	_place(_wheel, Vector2(25, 106), Vector2(144, 136))
	_wheel.color_changed.connect(_wheel_changed)
	_preview = ColorRect.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_preview, Vector2(0, 250), Vector2(28, 26))
	_hex = LineEdit.new()
	_hex.name = "HexInput"
	_hex.max_length = 7
	_hex.tooltip_text = "输入六位色号，按回车应用"
	_place(_hex, Vector2(36, 250), Vector2(158, 26))
	_hex.text_submitted.connect(_submit_hex)
	_hex.focus_exited.connect(func(): _submit_hex(_hex.text))
	var history_label := Label.new()
	history_label.text = "最近使用 · 最多 10 色"
	_place(history_label, Vector2(0, 280), Vector2(194, 20))
	for i in range(10):
		var button := Button.new()
		button.name = "History%d" % i
		_place(button, Vector2((i % 5) * 40, 304 + (i / 5) * 22), Vector2(34, 18))
		button.pressed.connect(_recall.bind(button))
		_history_buttons.append(button)
	_hsv = Vector3(color.h, color.s, color.v)
	set_color(color)
	set_history([])

func _place(control: Control, at: Vector2, extent: Vector2) -> void:
	add_child(control)
	control.position = at
	control.size = extent

func _mode_button(title: String, x: float, hsv: bool) -> Button:
	var button := Button.new()
	button.name = title
	button.text = title
	button.toggle_mode = true
	_place(button, Vector2(x, 0), Vector2(95, 26))
	button.pressed.connect(set_mode.bind(hsv))
	return button

func set_mode(hsv: bool) -> void:
	hsv_mode = hsv
	_sync_controls()

func set_color(value: Color) -> void:
	if color != value or not is_node_ready():
		_hsv = Vector3(value.h, value.s, value.v)
	color = value
	if is_instance_valid(_wheel): _sync_controls()

func _sync_controls() -> void:
	_syncing = true
	_rgb.set_pressed_no_signal(not hsv_mode)
	_hsv_button.set_pressed_no_signal(hsv_mode)
	var channels := [_hsv.x * 360, _hsv.y * 100, _hsv.z * 100] if hsv_mode else [color.r * 255, color.g * 255, color.b * 255]
	for i in range(3):
		_labels[i].text = ["H", "S", "V"][i] if hsv_mode else ["R", "G", "B"][i]
		var maximum := (360 if i == 0 else 100) if hsv_mode else 255
		_sliders[i].max_value = maximum
		_values[i].max_value = maximum
		_sliders[i].set_value_no_signal(channels[i])
		_values[i].set_value_no_signal(channels[i])
		var stops := PackedColorArray()
		var offsets := PackedFloat32Array()
		for step in range(7):
			var fraction := step / 6.0
			var stop := color
			if hsv_mode:
				var hsv := _hsv
				hsv[i] = fraction
				stop = Color.from_hsv(hsv.x, hsv.y, hsv.z)
			else:
				stop[i] = fraction
			stops.append(stop)
			offsets.append(fraction)
		_gradients[i].offsets = offsets
		_gradients[i].colors = stops
		_values[i].tooltip_text = ("色相 0–360°" if i == 0 else "饱和度 0–100%" if i == 1 else "明度 0–100%") if hsv_mode else "%s 0–255" % _labels[i].text
	_wheel.color = color
	_preview.color = color
	_hex.text = "#" + color.to_html(false).to_upper()
	_hex.remove_theme_color_override("font_color")
	_syncing = false

func _channel_changed(value: float, index: int) -> void:
	if _syncing: return
	if hsv_mode:
		_hsv[index] = value / (360.0 if index == 0 else 100.0)
		color = Color.from_hsv(_hsv.x, _hsv.y, _hsv.z)
	else:
		color[index] = value / 255.0
		_hsv = Vector3(color.h, color.s, color.v)
	_sync_controls()
	color_changed.emit(color)

func _wheel_changed(value: Color) -> void:
	if _syncing: return
	color = value
	_hsv = Vector3(value.h, value.s, value.v)
	_sync_controls()
	color_changed.emit(color)

func _submit_hex(text: String) -> void:
	var code := text.trim_prefix("#")
	if not InputValidation.is_rgb_hex(code):
		_hex.add_theme_color_override("font_color", Color("a44332"))
		_hex.tooltip_text = "色号需为 6 位，例如 3A9D8F"
		return
	set_color(Color.html(code))
	color_changed.emit(color)

func set_history(history: Array) -> void:
	for i in range(_history_buttons.size()):
		var button := _history_buttons[i]
		button.disabled = i >= history.size()
		button.tooltip_text = "画笔或文字使用的颜色会保留在这里" if button.disabled else "#" + str(history[i]).to_upper()
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e8e3d8") if button.disabled else Color.html(history[i])
		style.border_color = Color("aaa394")
		style.set_border_width_all(1)
		for state in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, style)
		if not button.disabled: button.set_meta("color", history[i])

func _recall(button: Button) -> void:
	set_color(Color.html(button.get_meta("color")))
	color_changed.emit(color)
