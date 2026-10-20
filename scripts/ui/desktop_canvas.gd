extends RefCounted
## Shared canvas theme; workspace geometry lives in mobile_canvas.gd.

static func configure(page: Control) -> void:
	var theme := page.theme.duplicate() as Theme
	theme.default_font_size = 20
	var normal := _style(Color("fbfaf5"), Color("c9c4b8"))
	var hover := _style(Color("f1eee4"), Color("9eaa9e"))
	var pressed := _style(Color("e6e6dc"), Color("879888"))
	var disabled := _style(Color("f1efe8"), Color("dedad0"))
	var selected := _style(Color("243d35"), Color("243d35"))
	var primary := _style(Color("a44332"), Color("a44332"))
	var primary_hover := _style(Color("b44e3b"), Color("b44e3b"))
	for type in ["Button", "QuietButton", "SelectableButton", "PrimaryButton", "MenuButton", "OptionButton"]:
		if type in ["QuietButton", "SelectableButton", "PrimaryButton"]: theme.set_type_variation(type, "Button")
		theme.set_font_size("font_size", type, 20)
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var style := disabled if state == "disabled" else hover if state == "hover" else pressed if state in ["pressed", "hover_pressed"] else normal
			if type == "SelectableButton" and state in ["pressed", "hover_pressed"]: style = selected
			if type == "PrimaryButton" and state != "disabled": style = primary_hover if state == "hover" else primary
			theme.set_stylebox(state, type, style)
		for key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			theme.set_color(key, type, Color("292824"))
		theme.set_color("font_disabled_color", type, Color("99968d"))
		if type == "PrimaryButton":
			for key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]: theme.set_color(key, type, Color("fffdf7"))
		if type == "SelectableButton":
			for key in ["font_pressed_color", "font_hover_pressed_color"]: theme.set_color(key, type, Color("fffdf7"))
	var field := _style(Color("fffdf7"), Color("b7b1a4"))
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_font_size("font_size", "LineEdit", 20)
	page.theme = theme
	page.get_node("Frame/StorageRetry").theme = theme
	for parent in [page, page.get_node("LayerTools"), page.get_node("CanvasSize")]:
		for child in parent.get_children():
			if child is BaseButton:
				if child is Button: child.flat = false
				child.add_theme_font_size_override("font_size", 20)
				for key in ["normal", "hover", "pressed", "hover_pressed", "disabled"]: child.remove_theme_stylebox_override(key)
	page.get_node("ToolsTitle").text = "画笔与颜色"
	page.get_node("LayerTools/LayerMenu").text = "顺序与镜像"
	page.get_node("LayerTools/CenterLayerButton").text = "移回中央"
	page.get_node("DeselectButton").text = "取消选择"
	page.get_node("LayerTools/LayerPicker").fit_to_longest_item = false
	for path in ["TopicPrompt", "DrawingStatus", "ViewHint", "CanvasSize/SizeHint"]:
		page.get_node(path).clip_text = true
	for path in ["ToolsTitle", "WidthLabel", "TopicLabel", "TopicPrompt", "DrawingStatus", "ViewHint", "ZoomLabel", "CanvasSize/SizeLabel", "CanvasSize/TimesLabel", "CanvasSize/SizeHint"]:
		page.get_node(path).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for path in ["CanvasSize/SizeLabel", "CanvasSize/TimesLabel", "CanvasSize/SizeHint"]:
		page.get_node(path).add_theme_font_size_override("font_size", 20)
	for path in ["CanvasSize/CanvasWidth", "CanvasSize/CanvasHeight"]:
		page.get_node(path).get_line_edit().add_theme_font_size_override("font_size", 20)

static func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

