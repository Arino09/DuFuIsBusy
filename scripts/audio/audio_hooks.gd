extends RefCounted
## Game code states what happened, what is current and continuous values; it never names Wwise objects.
## Without a running AudioDirector (tests, audio removed) every call is a no-op.

static var sink: Object

## A moment, e.g. "canvas.object.add.dufu_greatsword".
static func cue(key: String) -> void:
	if is_instance_valid(sink): sink.cue(key)

## A current state; changes become "<name>.exit.<old>" and "<name>.enter.<new>" at the end of the frame.
static func fact(name: String, value: Variant) -> void:
	if is_instance_valid(sink): sink.fact(name, "" if value == null else str(value))

## A continuous value sent to the RTPC listed under "rtpc.<key>".
static func param(key: String, value: float, immediate: bool = false) -> void:
	if is_instance_valid(sink): sink.param(key, value, immediate)
