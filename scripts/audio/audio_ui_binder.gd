extends RefCounted
## Wires every UI control to "ui.<verb>.<role>.<node name>" keys without per-scene code.
## Role: the "audio_role" meta, else the theme type variation ("PrimaryButton" -> "primary"), else "default".
## Value and toggle changes only count right after real input on that control, so code-driven updates stay silent.

const INPUT_WINDOW_MS := 250
const COMPOSITES := ["SpinBox", "ColorPicker", "PopupMenu"]

var emit: Callable
var last_input_ms := -100000
var last_motion_ms := -100000
var _bound: Dictionary = {}

func _init(emitter: Callable) -> void:
	emit = emitter

func attach(tree: SceneTree) -> void:
	tree.node_added.connect(bind_node)
	for node in tree.root.find_children("*", "Control", true, false): bind_node(node)

func detach(tree: SceneTree) -> void:
	if tree.node_added.is_connected(bind_node): tree.node_added.disconnect(bind_node)

func observe(event: InputEvent) -> void:
	var now := Time.get_ticks_msec()
	if event is InputEventMouseMotion:
		# Touch emulation produces mouse motion too; only a real pointer counts as hovering.
		if event.device != InputEvent.DEVICE_ID_EMULATION: last_motion_ms = now
		if event.button_mask != 0: last_input_ms = now
	elif event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventKey or event is InputEventJoypadButton:
		last_input_ms = now

func bind_node(node: Node) -> void:
	if not node is Control or _inside_composite(node): return
	var id := node.get_instance_id()
	if _bound.has(id): return
	if _bound.size() > 4096: _prune()
	_bound[id] = true
	if node is BaseButton:
		node.pressed.connect(_relay.bind(node, "press", false))
		node.toggled.connect(func(on: bool): _relay(node, "toggle_on" if on else "toggle_off", true))
		node.mouse_entered.connect(_hover.bind(node))
	if node is OptionButton:
		node.item_selected.connect(func(_index: int): _relay(node, "select", false))
	if node is Slider or node is SpinBox:
		node.value_changed.connect(func(_value: float): _relay(node, "drag", true))
	if node is LineEdit:
		node.text_changed.connect(func(_text: String): _relay(node, "type", false))
		node.text_submitted.connect(func(_text: String): _relay(node, "submit", false))

func key_for(control: Control, verb: String) -> String:
	return "ui.%s.%s.%s" % [verb, role_for(control), control.name]

static func role_for(control: Control) -> String:
	if control.has_meta("audio_role"): return str(control.get_meta("audio_role"))
	var variation := String(control.theme_type_variation)
	if not variation.is_empty(): return variation.to_snake_case().trim_suffix("_button")
	return "default"

func _relay(control: Control, verb: String, needs_intent: bool) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree(): return
	# Workspace buttons forward their actions to hidden legacy controls.
	# Only the visible button should contribute a click sound.
	if not control.is_visible_in_tree(): return
	if needs_intent and not _user_intent(control): return
	emit.call(key_for(control, verb))

func _hover(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree(): return
	if control is BaseButton and control.disabled: return
	# A page swap can place a button under a resting cursor; only real movement counts.
	if Time.get_ticks_msec() - last_motion_ms > INPUT_WINDOW_MS: return
	emit.call(key_for(control, "hover"))

func _user_intent(control: Control) -> bool:
	if Time.get_ticks_msec() - last_input_ms > INPUT_WINDOW_MS: return false
	return control.has_focus() or control.get_global_rect().has_point(control.get_global_mouse_position())

static func _inside_composite(node: Node) -> bool:
	var parent := node.get_parent()
	while parent:
		for type in COMPOSITES:
			if parent.is_class(type): return true
		parent = parent.get_parent()
	return false

func _prune() -> void:
	for id in _bound.keys():
		if not is_instance_id_valid(id): _bound.erase(id)
