extends Node
## Owns the Wwise engine lifecycle (init, rendering, suspend, shutdown); routing lives in AudioDirector.
## The singleton is looked up at runtime so this parses where the extension has no library (Linux CI).
## Keep the autoload name: the Wwise editor plugin re-adds its own manager when "WwiseRuntimeManager" is missing.

const WEB_DRIVER_PATH := "res://scripts/audio/wwise_web_audio_driver.js"
var wwise: Object = Engine.get_singleton("Wwise") if Engine.has_singleton("Wwise") else null
var web_render_callback: JavaScriptObject

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if wwise and OS.has_feature("web"):
		web_render_callback = JavaScriptBridge.create_callback(_web_audio_tick)
		JavaScriptBridge.get_interface("window").wwiseRenderAudio = web_render_callback
		JavaScriptBridge.eval(FileAccess.get_file_as_string(WEB_DRIVER_PATH), true)

## On Web, call from a user gesture before posting events.
func initialize() -> bool:
	if wwise == null: return false
	if not wwise.is_initialized():
		# This checkout ships Web banks, which also work with the Windows runtime.
		# Prefer dedicated Windows banks when they have been generated.
		if OS.has_feature("windows"):
			var bank_root: String = ProjectSettings.get_setting("wwise/common_user_settings/root_output_path", "")
			if not FileAccess.file_exists(bank_root.path_join("Windows/Init.bnk")) and FileAccess.file_exists(bank_root.path_join("Web/Init.bnk")):
				ProjectSettings.set_setting("wwise/project_settings/windows_platform_info", "res://Wwise/resources/Web.tres")
				print("AUDIO_BANK_FALLBACK: Windows banks missing; using bundled Web banks")
		if OS.has_feature("web"):
			ProjectSettings.set_setting("wwise/common_user_settings/samples_per_frame", 3) # 2048 samples
			ProjectSettings.set_setting("wwise/common_user_settings/number_of_refills_in_voice", 1) # four buffers
		wwise.init()
	return wwise.is_initialized()

func is_running() -> bool:
	return wwise != null and wwise.is_initialized()

func _web_audio_tick(_arguments: Array) -> void:
	if is_running(): wwise.render_audio()

func _process(_delta: float) -> void:
	if is_running(): wwise.render_audio()

func _notification(what: int) -> void:
	if not is_running(): return
	if what == NOTIFICATION_APPLICATION_PAUSED: wwise.suspend(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED: wwise.wakeup_from_suspend()
	elif what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_CRASH: wwise.shutdown()
