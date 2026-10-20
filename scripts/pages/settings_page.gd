extends Control
## Binds preference controls once; the app owns persistence and reset confirmation.

signal preference_changed(key: String, value: Variant)
signal reset_requested

@onready var _volume: HSlider = $VolumeSlider
@onready var _volume_label: Label = $VolumeLabel
@onready var _sound: CheckButton = $SoundToggle
@onready var _music: CheckButton = $MusicToggle
@onready var _quality: OptionButton = $QualityOption
@onready var _note: Label = $SettingsNote

func _ready() -> void:
	_volume.value_changed.connect(_on_volume_changed)
	_sound.toggled.connect(_on_toggle_changed.bind("sound", _sound))
	_music.toggled.connect(_on_toggle_changed.bind("music", _music))
	_quality.item_selected.connect(_on_quality_selected)
	$ResetButton.pressed.connect(func(): reset_requested.emit())

func refresh(values: Dictionary, status: String) -> void:
	_volume.set_value_no_signal(values.volume)
	_volume_label.text = str(int(values.volume)) + "%"
	_refresh_toggle(_sound, values.sound)
	_refresh_toggle(_music, values.music)
	_quality.select(int(values.quality))
	update_status(status)

func update_status(status: String) -> void:
	_note.text = str(_note.get_meta("description")) if status.is_empty() else status

func _refresh_toggle(toggle: CheckButton, enabled: bool) -> void:
	toggle.set_pressed_no_signal(enabled)
	toggle.text = "开启" if enabled else "关闭"

func _on_volume_changed(value: float) -> void:
	_volume_label.text = str(int(value)) + "%"
	preference_changed.emit("volume", value)

func _on_toggle_changed(enabled: bool, key: String, toggle: CheckButton) -> void:
	toggle.text = "开启" if enabled else "关闭"
	preference_changed.emit(key, enabled)

func _on_quality_selected(index: int) -> void:
	preference_changed.emit("quality", index)
