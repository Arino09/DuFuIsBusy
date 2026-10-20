extends Node
## Horizontal drags starting on a toolbar button scroll without activating it.
signal gesture_finished
var scroll: ScrollContainer
var can_scroll := Callable()
var _pointer := -1
var _start := Vector2.ZERO
var _offset := 0
var _dragging := false
var _blocked: Dictionary = {}

func _ready() -> void:
	get_window().focus_exited.connect(_reset)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(scroll) or not scroll.is_visible_in_tree(): return
	if can_scroll.is_valid() and not can_scroll.call():
		if _pointer >= 0: _reset()
		return
	if event is InputEventScreenTouch:
		if event.pressed and _pointer < 0 and scroll.get_global_rect().has_point(event.position):
			_pointer = event.index
			_start = event.position
			_offset = scroll.scroll_horizontal
		elif not event.pressed and event.index == _pointer:
			_pointer = -1
			# Keep signals blocked through the companion emulated mouse release.
			_reset.call_deferred()
	elif event is InputEventScreenDrag and event.index == _pointer:
		var delta: Vector2 = event.position - _start
		if not _dragging and absf(delta.x) > 12 and absf(delta.x) > absf(delta.y):
			_dragging = true
			for button in scroll.get_child(0).get_children():
				if button is BaseButton:
					_blocked[button] = button.is_blocking_signals()
					button.set_block_signals(true)
		if _dragging:
			scroll.scroll_horizontal = _offset - roundi(delta.x)
			get_viewport().set_input_as_handled()

func _reset() -> void:
	var finished := _dragging
	_pointer = -1
	_dragging = false
	for button in _blocked:
		if is_instance_valid(button): button.set_block_signals(_blocked[button])
	_blocked.clear()
	if finished: gesture_finished.emit()

func _exit_tree() -> void:
	_dragging = false
	_reset()
