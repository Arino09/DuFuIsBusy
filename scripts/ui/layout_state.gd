extends RefCounted
## Remember only properties changed by the compact layout, leaving session state alone.

var _properties: Dictionary = {}
var _fonts: Dictionary = {}
var _rects: Dictionary = {}
var _settling := false
var _generation := 0

func put(control: Control, property: String, value: Variant) -> void:
	if not _properties.has(control): _properties[control] = {}
	if not _properties[control].has(property):
		_properties[control][property] = control.get(property)
	control.set(property, value)

func rect(control: Control, bounds: Rect2) -> void:
	if not _properties.has(control): _properties[control] = {}
	for property in ["layout_mode", "anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom", "grow_horizontal", "grow_vertical"]:
		if not _properties[control].has(property):
			_properties[control][property] = control.get(property)
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.grow_horizontal = Control.GROW_DIRECTION_END
	control.grow_vertical = Control.GROW_DIRECTION_END
	control.position = bounds.position
	control.size = bounds.size
	_rects[control] = bounds
	if not _settling and control.is_inside_tree():
		_settling = true
		_settle_sizes(control.get_tree(), _generation)

func _settle_sizes(tree: SceneTree, generation: int) -> void:
	# Wrapped labels can initially report the minimum height for their old width.
	# Once font shaping/container notifications settle, shrink to the new bounds.
	await tree.process_frame
	if generation != _generation: return
	_settling = false
	for control in _rects:
		if is_instance_valid(control): control.size = _rects[control].size

func font(control: Control, value: int) -> void:
	var key := "normal_font_size" if control is RichTextLabel else "font_size"
	if not _fonts.has(control):
		_fonts[control] = [key, control.get_theme_font_size(key) if control.has_theme_font_size_override(key) else null]
	control.add_theme_font_size_override(key, value)

func hide(control: Control) -> void:
	put(control, "visible", false)

func restore() -> void:
	_generation += 1
	_settling = false
	_rects.clear()
	for control in _properties:
		if not is_instance_valid(control): continue
		for property in _properties[control]: control.set(property, _properties[control][property])
	for control in _fonts:
		if not is_instance_valid(control): continue
		var prior: Array = _fonts[control]
		if prior[1] == null: control.remove_theme_font_size_override(prior[0])
		else: control.add_theme_font_size_override(prior[0], prior[1])
	_properties.clear()
	_fonts.clear()
