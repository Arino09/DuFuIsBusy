extends Node
## Routes semantic keys from AudioHooks and the UI binder to the Wwise events and RTPCs named in one TSV.
## Every event plays on this node as the single game object; without Wwise (Linux CI, headless) calls are only recorded.

const Hooks = preload("res://scripts/audio/audio_hooks.gd")
const Table = preload("res://scripts/audio/audio_table.gd")
const Binder = preload("res://scripts/audio/audio_ui_binder.gd")
const TABLE_PATH := "res://audio/audio_events.tsv"
const BANK := "Main"
const RTPC_INTERVAL_MS := 33
const RELOAD_INTERVAL := 1.0

var table: RefCounted = Table.new()
var binder: RefCounted
## Backend calls ("post X", "rtpc Y=1") kept when Wwise is absent, so tests can assert routing.
var calls: PackedStringArray = []
var running := false
var wwise: Object
var verbose := false
var _facts: Dictionary = {}
var _pending_facts: Dictionary = {}
var _rtpc: Dictionary = {}
var _reported: Dictionary = {}
var _table_time := 0
var _reload_wait := 0.0

func _init() -> void:
	binder = Binder.new(cue)

func _enter_tree() -> void:
	Hooks.sink = self

func _exit_tree() -> void:
	if Hooks.sink == self: Hooks.sink = null
	binder.detach(get_tree())

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var headless := DisplayServer.get_name() == "headless"
	verbose = OS.has_feature("editor") and not headless
	load_table(Table.from_file(TABLE_PATH))
	_table_time = FileAccess.get_modified_time(TABLE_PATH)
	binder.attach(get_tree())
	# Browsers only allow audio after a user gesture, so Web starts on the first press (see _input).
	if not OS.has_feature("web") or headless or not Engine.has_singleton("Wwise"): start.call_deferred()

func load_table(next: RefCounted) -> void:
	for message in next.errors: print("AUDIO_TABLE_INVALID: ", message)
	table = next

## Initializes Wwise when available, then replays current facts and RTPCs that arrived earlier.
func start() -> void:
	if running: return
	running = true
	var runtime := get_node_or_null("/root/WwiseRuntimeManager")
	var bank_loaded := false
	if DisplayServer.get_name() != "headless" and runtime and runtime.has_method("initialize") and runtime.initialize():
		wwise = Engine.get_singleton("Wwise")
		bank_loaded = wwise.load_bank(BANK)
		wwise.register_listener(self)
	print("AUDIO_STATUS wwise=%s bank=%s keys=%d table_errors=%d" % [wwise != null, bank_loaded, table.entries.size(), table.errors.size()])
	cue("app.boot")
	for name in _facts:
		if not _facts[name].is_empty(): cue("%s.enter.%s" % [name, _facts[name]])
	for key in _rtpc: _send_rtpc(key)

func cue(key: String) -> void:
	if not running: return
	var event: Variant = table.lookup(key)
	if event == null:
		if verbose and not _reported.has(key):
			_reported[key] = true
			print("AUDIO_UNMAPPED: ", key)
		return
	if event.is_empty(): return
	if verbose: print("AUDIO: %s -> %s" % [key, event])
	if wwise == null:
		_record("post " + event)
	elif wwise.post_event(event, self) == 0 and verbose and not _reported.has(event):
		_reported[event] = true
		print("AUDIO_POST_FAILED: %s (not in bank %s yet?)" % [event, BANK])

## Facts are committed once per frame, so a dialog swap (close + open) or a page reload makes one transition.
func fact(name: String, value: String) -> void:
	if _pending_facts.is_empty(): _commit_facts.call_deferred()
	_pending_facts[name] = value

func _commit_facts() -> void:
	var pending := _pending_facts
	_pending_facts = {}
	for name in pending:
		var old: String = _facts.get(name, "")
		var new: String = pending[name]
		if old == new: continue
		_facts[name] = new
		if not old.is_empty(): cue("%s.exit.%s" % [name, old])
		if not new.is_empty(): cue("%s.enter.%s" % [name, new])

func param(key: String, value: float) -> void:
	var state: Dictionary = _rtpc.get(key, {"value": NAN, "sent": NAN, "time": -RTPC_INTERVAL_MS})
	state.value = value
	_rtpc[key] = state
	if running and Time.get_ticks_msec() - state.time >= RTPC_INTERVAL_MS: _send_rtpc(key)

func _send_rtpc(key: String) -> void:
	var state: Dictionary = _rtpc[key]
	if state.value == state.sent: return
	state.sent = state.value
	state.time = Time.get_ticks_msec()
	var rtpc: Variant = table.lookup("rtpc." + key)
	if rtpc == null or rtpc.is_empty(): return
	if wwise == null: _record("rtpc %s=%s" % [rtpc, state.value])
	else: wwise.set_rtpc_value(rtpc, state.value, null)

func _process(delta: float) -> void:
	# Trailing edge of the RTPC throttle: the last value always reaches Wwise.
	if running:
		var now := Time.get_ticks_msec()
		for key in _rtpc:
			if _rtpc[key].value != _rtpc[key].sent and now - _rtpc[key].time >= RTPC_INTERVAL_MS: _send_rtpc(key)
	if verbose:
		_reload_wait += delta
		if _reload_wait >= RELOAD_INTERVAL:
			_reload_wait = 0.0
			_reload_if_changed()

func _reload_if_changed() -> void:
	var time := FileAccess.get_modified_time(TABLE_PATH)
	if time == _table_time: return
	_table_time = time
	var next: RefCounted = Table.from_file(TABLE_PATH)
	if next.errors.is_empty():
		table = next
		_reported.clear()
		print("AUDIO_TABLE_RELOADED: %d keys" % table.entries.size())
	else:
		for message in next.errors: print("AUDIO_TABLE_INVALID: ", message)

func _input(event: InputEvent) -> void:
	binder.observe(event)
	if not running and (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey):
		start()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		cue("test.play")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: fact("app.focus", "out")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: fact("app.focus", "in")

func _record(call: String) -> void:
	if calls.size() >= 1000: calls.clear()
	calls.append(call)
