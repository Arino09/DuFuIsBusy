extends Control
## Owns palette inputs; the app applies the selected color to the canvas.

signal color_applied(color: Color)

const InputValidation = preload("res://scripts/input_validation.gd")

@onready var _swatches: Control = $Swatches
@onready var _hex_input: LineEdit = $HexInput
@onready var _error: Label = $ErrorLabel
@onready var _apply_button: Button = $ApplyButton

func _ready() -> void:
	for child in _swatches.get_children():
		var swatch: Button = child
		var code: String = swatch.get_meta("color")
		swatch.pressed.connect(_apply_swatch.bind(Color.html(code)))
	_hex_input.text_changed.connect(_clear_error)
	_apply_button.pressed.connect(_apply_custom_color)

func configure(color: Color) -> void:
	_hex_input.text = color.to_html(false)
	_error.text = ""

func _clear_error(_value: String) -> void:
	_error.text = ""

func _apply_swatch(color: Color) -> void:
	color_applied.emit(color)

func _apply_custom_color() -> void:
	if not InputValidation.is_rgb_hex(_hex_input.text):
		_error.text = "色号需为 6 位，例如 3A9D8F。"
		return
	color_applied.emit(Color.html(_hex_input.text))
