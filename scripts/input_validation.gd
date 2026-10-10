extends RefCounted
## Input rules shared by the authored color controls.

static func is_rgb_hex(value: String) -> bool:
	return value.length() == 6 and Color.html_is_valid(value)
