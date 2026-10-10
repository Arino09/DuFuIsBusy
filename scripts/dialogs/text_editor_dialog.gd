extends Control
## Owns text input and validation; the app owns editing the selected object.

signal text_applied(text: String, font_size: int, color: Color)

const InputValidation = preload("res://scripts/input_validation.gd")
const CREATIVE_FONT = preload("res://assets/fonts/CreativeSansSC.otf")

@onready var _editor: LineEdit = $TextInput
@onready var _font_size: SpinBox = $FontSizeInput
@onready var _color_input: LineEdit = $ColorInput
@onready var _error: Label = $ErrorLabel
@onready var _apply_button: Button = $ApplyButton

func _ready() -> void:
	_editor.text_changed.connect(_clear_error)
	_color_input.text_changed.connect(_clear_error)
	_apply_button.pressed.connect(_apply_text)
	# Re-clicking a focused LineEdit can blur Godot's DOM IME host.
	if OS.has_feature("web") and not DisplayServer.is_touchscreen_available():
		_editor.gui_input.connect(_on_editor_gui_input)

func configure(object: Dictionary, color: Color) -> void:
	_editor.text = object.get("text", "")
	_font_size.value = object.get("font_size", 32)
	var text_color: Color = object.get("color", color)
	_color_input.text = text_color.to_html(false)
	_error.text = ""
	_editor.grab_focus()

func _clear_error(_value: String) -> void:
	_error.text = ""

func _apply_text() -> void:
	var text := _editor.text.strip_edges()
	if text.is_empty():
		_error.text = "请输入文字。"
		return
	if not InputValidation.is_rgb_hex(_color_input.text):
		_error.text = "色号需为 6 位，例如 3A9D8F。"
		return
	for character in text:
		if not CREATIVE_FONT.has_char(character.unicode_at(0)):
			_error.text = "无法显示“%s”，请替换这个字符。" % character
			return
	text_applied.emit(text, int(_font_size.value), Color.html(_color_input.text))

func _on_editor_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_restore_text_ime.call_deferred()

func _restore_text_ime() -> void:
	if is_instance_valid(_editor) and _editor.has_focus():
		DisplayServer.window_set_ime_active(true)
