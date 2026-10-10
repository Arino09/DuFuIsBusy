extends RefCounted
## Both storage backends share one settings schema; reading never writes data.
const PATH = "user://settings.cfg"
const SECTION = "settings"
const KEY = "DuFuIsBusy.settings.v1"
var native_path: String

func _init(path: String = PATH) -> void:
	native_path = path

static func defaults() -> Dictionary:
	return {"volume": 70.0, "sound": true, "music": true, "quality": 1, "motion": false}

static func normalize(raw: Variant) -> Dictionary:
	var values := defaults()
	if not raw is Dictionary: return values
	var volume: Variant = raw.get("volume")
	if _finite_number(volume): values.volume = clampf(float(volume), 0.0, 100.0)
	var quality: Variant = raw.get("quality")
	if _finite_number(quality) and floorf(float(quality)) == float(quality):
		# Clamp before converting: a finite float can still exceed the int range.
		values.quality = int(clampf(float(quality), 0.0, 1.0))
	for key in ["sound", "music", "motion"]:
		if raw.get(key) is bool: values[key] = raw[key]
	return values

static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func load_settings() -> Dictionary:
	if not _is_web(): return normalize(_read_native())
	var text: Variant = _read_web()
	if text is String and not text.is_empty():
		var parser := JSON.new()
		if parser.parse(text) == OK:
			return normalize(parser.data)
	return defaults()

func save_settings(values: Dictionary) -> bool:
	var normalized := normalize(values)
	return _write_web(normalized) if _is_web() else _write_native(normalized)

func _is_web() -> bool:
	return OS.has_feature("web")

func _read_native() -> Variant:
	var config := ConfigFile.new()
	if config.load(native_path) != OK: return null
	var raw: Dictionary = {}
	for key in defaults():
		if config.has_section_key(SECTION, key): raw[key] = config.get_value(SECTION, key)
	return raw

func _write_native(values: Dictionary) -> bool:
	# Preserve unrelated sections and keep a damaged file before repairing it.
	var config := ConfigFile.new()
	var loaded := config.load(native_path)
	if loaded == ERR_PARSE_ERROR:
		if not _backup_invalid_config(): return false
		config.clear()
	elif loaded != OK and loaded != ERR_FILE_NOT_FOUND:
		return false
	for key in values: config.set_value(SECTION, key, values[key])
	return config.save(native_path) == OK

func _backup_invalid_config() -> bool:
	var backup := native_path + ".invalid"
	var index := 1
	while FileAccess.file_exists(backup) or DirAccess.dir_exists_absolute(backup):
		backup = native_path + ".invalid.%d" % index
		index += 1
	return DirAccess.copy_absolute(native_path, backup) == OK

func _read_web() -> Variant:
	return JavaScriptBridge.eval("(function(){try{return localStorage.getItem(%s) || ''; }catch(e){return '';}})()" % JSON.stringify(KEY))

func _write_web(values: Dictionary) -> bool:
	var payload := JSON.stringify(JSON.stringify(values))
	return JavaScriptBridge.eval("(function(){try{localStorage.setItem(%s, %s);return true;}catch(e){return false;}})()" % [JSON.stringify(KEY), payload]) == true
