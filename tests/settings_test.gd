extends SceneTree
## Player settings/browser storage are never accessed; native fixtures use OS temp.
const SettingsStore = preload("res://scripts/settings_store.gd")

class MemorySettings:
	extends "res://scripts/settings_store.gd"
	var web := false
	var native: Variant = null
	var web_text: Variant = ""
	var native_reads := 0
	var web_reads := 0
	var native_writes := 0
	var web_writes := 0
	var fail_writes := false
	var written: Dictionary = {}

	func _is_web() -> bool:
		return web

	func _read_native() -> Variant:
		native_reads += 1
		return native

	func _read_web() -> Variant:
		web_reads += 1
		return web_text

	func _write_native(values: Dictionary) -> bool:
		native_writes += 1
		if fail_writes: return false
		written = values
		return true

	func _write_web(values: Dictionary) -> bool:
		web_writes += 1
		if fail_writes: return false
		written = values
		return true

class BackupFailureSettings:
	extends "res://scripts/settings_store.gd"

	func _backup_invalid_config() -> bool:
		return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var expected := {"volume": 70.0, "sound": true, "music": true, "quality": 1, "motion": false}
	assert(SettingsStore.defaults() == expected)
	var changed_default := SettingsStore.defaults()
	changed_default.volume = 12.0
	assert(SettingsStore.defaults() == expected, "Defaults shared mutable state")
	for raw in [null, [], "settings", true, 10, {}]:
		assert(SettingsStore.normalize(raw) == expected)

	var normalized := SettingsStore.normalize({"volume": 35, "quality": 0.0, "sound": false, "music": false, "motion": true, "unknown": "ignored"})
	assert(normalized == {"volume": 35.0, "quality": 0, "sound": false, "music": false, "motion": true})
	assert(normalized.volume is float and normalized.quality is int)
	for value in ["23", true, null, [], {}, NAN, INF, -INF]:
		assert(SettingsStore.normalize({"volume": value}).volume == 70.0)
		assert(SettingsStore.normalize({"quality": value}).quality == 1)
	for value in [0.25, -0.25, 1.25]:
		assert(SettingsStore.normalize({"quality": value}).quality == 1, "Fractional quality should default")
	for value in [-100, -1.0e100]:
		assert(SettingsStore.normalize({"volume": value}).volume == 0.0)
		assert(SettingsStore.normalize({"quality": value}).quality == 0)
	for value in [200, 1.0e100]:
		assert(SettingsStore.normalize({"volume": value}).volume == 100.0)
		assert(SettingsStore.normalize({"quality": value}).quality == 1)
	for value in [0, 1, "false", "true", null, [], {}]:
		assert(SettingsStore.normalize({"sound": value, "music": value, "motion": value}) == expected, "Boolean settings accepted non-bools")
	var raw := {"volume": 25, "sound": false}
	var first := SettingsStore.normalize(raw)
	first.sound = true
	assert(raw.sound == false and SettingsStore.normalize(raw).sound == false)

	var store := MemorySettings.new()
	assert(store.load_settings() == expected)
	store.native = {"volume": 150, "quality": 0.5, "sound": false, "motion": 1}
	var native_expected := SettingsStore.normalize(store.native)
	assert(store.load_settings() == native_expected)
	assert(store.native_reads == 2 and store.web_reads == 0, "Native settings read Web storage")
	assert(store.native_writes == 0 and store.web_writes == 0, "Loading rewrote preferences")
	assert(store.save_settings(store.native))
	assert(store.written == native_expected and store.native_writes == 1 and store.web_writes == 0)
	store.written.volume = 5.0
	assert(store.native.volume == 150, "Saving retained caller's mutable dictionary")
	store.fail_writes = true
	assert(not store.save_settings({"volume": 10}))
	assert(store.written.volume == 5.0, "Failed native save changed stored data")

	store.web = true
	store.fail_writes = false
	for text in [null, "", "bad JSON", "[]", "null", "false"]:
		store.web_text = text
		assert(store.load_settings() == expected, "Unavailable Web settings should use defaults")
	assert(store.native_reads == 2 and store.web_reads == 6, "Web settings read ConfigFile")
	store.web_text = '{"volume":21,"quality":0,"sound":false,"music":"false","extra":1}'
	var web_expected := {"volume": 21.0, "quality": 0, "sound": false, "music": true, "motion": false}
	assert(store.load_settings() == web_expected)
	assert(store.native_writes == 2 and store.web_writes == 0, "Loading wrote to a backend")
	store.web_text = '{}'
	assert(store.load_settings() == expected, "Present Web document was merged with unrelated native values")
	assert(store.native_reads == 2 and store.web_reads == 8, "Web settings read ConfigFile")
	assert(store.save_settings({"volume": -10, "quality": 0.3, "music": false}))
	assert(store.written == {"volume": 0.0, "quality": 1, "sound": true, "music": false, "motion": false})
	assert(store.native_writes == 2 and store.web_writes == 1, "Web save also wrote ConfigFile")
	store.fail_writes = true
	assert(not store.save_settings({"volume": 99}))
	assert(store.written.volume == 0.0, "Failed Web save changed stored data")
	assert(test_native_files())
	print("SETTINGS_TESTS_PASSED")
	quit()

func test_native_files() -> bool:
	var temp_root := OS.get_environment("TEMP") if OS.get_name() == "Windows" else OS.get_environment("TMPDIR")
	if temp_root.is_empty(): temp_root = "/tmp"
	var fixture_dir := temp_root.path_join("dufu-settings-test-" + Crypto.new().generate_random_bytes(12).hex_encode())
	assert(not DirAccess.dir_exists_absolute(fixture_dir))
	assert(DirAccess.make_dir_absolute(fixture_dir) == OK)
	var path := fixture_dir.path_join("settings.cfg")
	var native_store := SettingsStore.new(path)
	assert(native_store.load_settings() == SettingsStore.defaults())
	assert(not FileAccess.file_exists(path), "Reading absent settings created a file")
	assert(native_store.save_settings({"volume": 101, "quality": 0.0, "sound": false}))
	assert(native_store.load_settings() == SettingsStore.normalize({"volume": 101, "quality": 0.0, "sound": false}))
	var config := ConfigFile.new()
	assert(config.load(path) == OK)
	config.set_value("unrelated", "keep", "existing content")
	assert(config.save(path) == OK)
	assert(native_store.save_settings({"volume": 30}))
	assert(config.load(path) == OK)
	assert(config.get_value("unrelated", "keep") == "existing content", "Saving removed an unrelated section")

	var invalid_text := "[unrelated]\nkeep=\"partially parsed\"\n[settings]\nvolume=bad(\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(invalid_text)
	file.close()
	var previous_print_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	var damaged_values := native_store.load_settings()
	Engine.print_error_messages = previous_print_errors
	assert(damaged_values == SettingsStore.defaults())
	assert(FileAccess.get_file_as_string(path) == invalid_text, "Loading damaged settings modified the file")
	assert(not FileAccess.file_exists(path + ".invalid"), "Loading damaged settings created a backup")

	var failed_backup := BackupFailureSettings.new()
	failed_backup.native_path = path
	Engine.print_error_messages = false
	var saved_without_backup := failed_backup.save_settings(SettingsStore.defaults())
	Engine.print_error_messages = previous_print_errors
	assert(not saved_without_backup)
	assert(FileAccess.get_file_as_string(path) == invalid_text, "Failed backup did not preserve the damaged file")
	Engine.print_error_messages = false
	var repaired := native_store.save_settings(SettingsStore.defaults())
	Engine.print_error_messages = previous_print_errors
	assert(repaired, "Reset could not repair a malformed configuration")
	assert(FileAccess.get_file_as_string(path + ".invalid") == invalid_text)
	assert(native_store.load_settings() == SettingsStore.defaults())
	config = ConfigFile.new()
	assert(config.load(path) == OK)
	assert(not config.has_section("unrelated"), "Repair retained partially parsed configuration data")

	# Another damaged file gets a new backup; the previous backup is untouched.
	var second_invalid := "[settings]\nquality=broken(\n"
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(second_invalid)
	file.close()
	Engine.print_error_messages = false
	var repaired_again := native_store.save_settings({"volume": 12.0, "music": false})
	Engine.print_error_messages = previous_print_errors
	assert(repaired_again)
	assert(FileAccess.get_file_as_string(path + ".invalid") == invalid_text)
	assert(FileAccess.get_file_as_string(path + ".invalid.1") == second_invalid)
	assert(native_store.load_settings() == SettingsStore.normalize({"volume": 12.0, "music": false}))
	var unavailable := SettingsStore.new(fixture_dir.path_join("missing").path_join("settings.cfg"))
	assert(not unavailable.save_settings(SettingsStore.defaults()), "Missing parent directory was reported as saved")

	# Clean up only the exact fixture files created above, without recursive deletes.
	for file_path in [path, path + ".invalid", path + ".invalid.1"]:
		assert(DirAccess.remove_absolute(file_path) == OK)
	assert(DirAccess.remove_absolute(fixture_dir) == OK)
	return true
