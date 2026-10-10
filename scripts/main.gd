extends Control

const INK = Color("243d35")
const BROWN = Color("766148")
const RED = Color("aa4937")
const PAPER = Color("f8f4e9")
const MUTED = Color("857b68")
const SERIF = preload("res://assets/fonts/SourceSerifSC.otf")
const SANS = preload("res://assets/fonts/SourceSansSC.otf")
const LocalStore = preload("res://scripts/local_store.gd")
var local_store := LocalStore.new()
var storage_hint: Label
var storage_retry: Button
var gallery_page := 0
var storage_status := ""
const Drawing = preload("res://scripts/drawing_surface.gd")
var web_blur_callback: JavaScriptObject
var drawings: Dictionary = {}
var drawing: Control
var pen_color := INK
var pen_width := 12
var object_buttons: Dictionary = {}
var submitting := false
var undo_button: Button
var redo_button: Button
var drawing_status: Label
const Paper = preload("res://scripts/ink_paper.gd")
const TOPICS = ["交通", "科幻", "武侠", "田园"]
const TOPIC_COLORS = [Color("926736"), Color("486879"), Color("944f42"), Color("4e704f")]
const TOPIC_TINTS = [Color("f4ead5"), Color("e4ebed"), Color("f2e4dc"), Color("e7ecdd")]
const EXAMPLE_TOPICS = ["武侠", "科幻", "市井", "脑洞"]
const EXAMPLE_IMAGES = ["sword-hero.jpg", "scifi-warrior.jpg", "night-market.jpg", "restroom.jpg"]
const TITLES = ["行路人间", "机甲盛唐", "剑影江湖", "田园闲居"]
const PROMPTS = ["至少出现一种交通工具", "让杜甫拥有一身未来机甲", "给诗人安排一次江湖奇遇", "让杜甫忙里偷闲，归园田居"]
const IDEAS = ["剑影江湖", "机甲诗圣", "夜市小憩", "人有三急"]
var page: Control
var overlay: Control
var current := "home"
var topic := 0
var gallery_tab := 0
var gallery_filter := "全部"
var selected_tool := "笔刷"
var settings := {"volume": 70.0, "sound": true, "music": true, "quality": 1, "motion": false}
var settings_status := "设置保存在本机；不进行云端同步。"
var config := ConfigFile.new()
var is_busy := false
var suspended_focus: Array[Control] = []

func _ready() -> void:
	theme = make_theme()
	if config.load("user://settings.cfg") == OK:
		for key in settings:
			settings[key] = config.get_value("settings", key, settings[key])
	if OS.has_feature("web"):
		web_blur_callback = JavaScriptBridge.create_callback(_web_focus_lost)
		JavaScriptBridge.get_interface("window").addEventListener("blur", web_blur_callback)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", web_blur_callback)
		JavaScriptBridge.get_interface("window").addEventListener("pagehide", web_blur_callback)
		JavaScriptBridge.get_interface("window").addEventListener("beforeunload", web_blur_callback)
		var saved: Variant = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('DuFuIsBusy.settings.v1') || '';}catch(e){return '';}})()")
		if saved is String and not saved.is_empty():
			var parsed: Variant = JSON.parse_string(saved)
			if parsed is Dictionary:
				for key in settings:
					if parsed.has(key) and (typeof(parsed[key]) == typeof(settings[key]) or (parsed[key] is float and settings[key] is int)):
						settings[key] = parsed[key]
				settings.volume = clampf(float(settings.volume), 0.0, 100.0)
				settings.quality = clampi(int(settings.quality), 0, 1)
	local_store.read_document()
	for key in local_store.document.drafts:
		drawings[int(key)] = LocalStore.decode(local_store.document.drafts[key])
	topic = int(local_store.document.topic)
	pen_color = Color.html(local_store.document.tools.color)
	pen_width = int(local_store.document.tools.width)
	selected_tool = local_store.document.tools.tool
	show_page(local_store.document.page)

func _web_focus_lost(_arguments: Array) -> void:
	if is_instance_valid(drawing): drawing.finish()
	if is_instance_valid(page): autosave()

func _exit_tree() -> void:
	if OS.has_feature("web") and web_blur_callback:
		JavaScriptBridge.get_interface("window").removeEventListener("blur", web_blur_callback)
		JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange", web_blur_callback)
		JavaScriptBridge.get_interface("window").removeEventListener("pagehide", web_blur_callback)
		JavaScriptBridge.get_interface("window").removeEventListener("beforeunload", web_blur_callback)

func box(color: Color, border: Color = Color("d8cfb9"), width: int = 1, radius: int = 5) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = SANS
	t.default_font_size = 20
	t.set_color("font_color", "Label", INK)
	for type in ["Button", "CheckButton", "OptionButton"]:
		t.set_stylebox("normal", type, box(PAPER))
		t.set_stylebox("hover", type, box(Color("e4e8db"), INK))
		t.set_stylebox("pressed", type, box(Color("d4decd"), INK, 2))
		t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), RED, 3))
		t.set_stylebox("disabled", type, box(Color("eae4d6")))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(state, type, INK)
		t.set_color("font_disabled_color", type, MUTED)
	t.set_stylebox("normal", "LineEdit", box(Color("fffdf7"), BROWN))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), RED, 2))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_stylebox("panel", "PopupMenu", box(PAPER, BROWN))
	t.set_stylebox("hover", "PopupMenu", box(Color("e2e7d9"), INK))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_stylebox("panel", "Panel", box(PAPER))
	t.set_stylebox("slider", "HSlider", box(Color("d6cdb9"), Color("d6cdb9"), 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(INK, INK, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(RED, RED, 0, 3))
	return t

func rect(node: Control, area: Rect2, parent: Control = page) -> Control:
	parent.add_child(node)
	node.position = area.position
	node.size = area.size
	return node

func label_at(text: String, area: Rect2, font_size: int = 22, color: Color = INK, serif: bool = false, parent: Control = page, wrap: bool = false) -> Label:
	var l := Label.new()
	if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if serif: l.add_theme_font_override("font", SERIF)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect(l, area, parent)
	l.text = text
	return l

func texture_at(path: String, area: Rect2, parent: Control = page) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = load(path) as Texture2D
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect(picture, area, parent)
	return picture

func panel_at(area: Rect2, color: Color = PAPER, parent: Control = page, border: Color = Color("d8cfb9")) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(color, border))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect(p, area, parent)
	return p

func button_at(text: String, area: Rect2, callback: Callable, primary: bool = false, parent: Control = page) -> Button:
	var b := Button.new()
	b.text = text
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		b.add_theme_stylebox_override("normal", box(INK, INK))
		b.add_theme_stylebox_override("hover", box(Color("365448"), INK))
		b.add_theme_stylebox_override("pressed", box(Color("172b24"), INK))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(key, PAPER)
	rect(b, area, parent)
	b.pressed.connect(callback)
	return b

func line_at(area: Rect2, color: Color = Color("d2c8b1"), parent: Control = page) -> void:
	var c := ColorRect.new()
	c.color = color
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect(c, area, parent)

func show_page(id: String) -> void:
	if is_busy: return
	is_busy = true
	close_overlay()
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	current = id
	page = Control.new()
	page.name = id.capitalize()
	add_child(page)
	page.size = Vector2(1440, 900)
	var background := Paper.new()
	rect(background, Rect2(0, 0, 1440, 900))
	label_at("杜 甫 很 忙", Rect2(52, 25, 220, 38), 24, INK, true)
	label_at("单机 · 命题续画 · 万千想象", Rect2(278, 30, 350, 30), 15, BROWN)
	panel_at(Rect2(1225, 26, 163, 33), Color("e6ddca"))
	label_at("本地创作 · 试玩版", Rect2(1243, 26, 155, 33), 15, BROWN)
	line_at(Rect2(52, 78, 1336, 1))
	label_at("不必画得像，尽管想得妙。", Rect2(52, 845, 800, 30), 16, BROWN, true)
	label_at("杜甫很忙  /  轻松续画", Rect2(1160, 845, 240, 30), 15, BROWN)
	if id != "home":
		button_at("← 返回首页", Rect2(1210, 104, 178, 48), func(): show_page("home"))
	match id:
		"home": home()
		"levels": levels()
		"canvas": canvas()
		"gallery": gallery()
		"settings": settings_page()
	storage_hint = label_at("", Rect2(52, 807, 1110, 33), 15, BROWN)
	storage_retry = button_at("重试本地保存", Rect2(1180, 806, 208, 36), retry_storage)
	storage_retry.add_theme_font_size_override("font_size", 16)
	for mode in ["normal", "hover", "pressed", "focus", "disabled"]:
		var compact := box(PAPER, RED)
		compact.content_margin_top = 2
		compact.content_margin_bottom = 2
		storage_retry.add_theme_stylebox_override(mode, compact)
	storage_retry.size = Vector2(208, 36)
	is_busy = false
	autosave()
	print("UI_PAGE:", id)

func heading(title: String, subtitle: String) -> void:
	label_at(title, Rect2(72, 106, 850, 64), 44, INK, true)
	label_at(subtitle, Rect2(74, 178, 1100, 36), 19, BROWN)

func home() -> void:
	label_at("一张画像，无数种可能", Rect2(98, 154, 510, 42), 23, BROWN, true)
	label_at("杜甫很忙", Rect2(89, 207, 630, 116), 90, INK, true)
	label_at("今天，给诗圣安排点新活儿。", Rect2(98, 338, 520, 44), 25, BROWN)
	button_at("开始闯关   →", Rect2(100, 414, 345, 68), func(): show_page("levels"), true)
	button_at("自由创作", Rect2(100, 498, 345, 62), func(): topic = -1; show_page("canvas"))
	button_at("画廊", Rect2(100, 576, 165, 58), func(): gallery_tab = 1; show_page("gallery"))
	button_at("设置", Rect2(280, 576, 165, 58), func(): show_page("settings"))
	button_at("暂歇片刻", Rect2(100, 653, 345, 52), exit_info)
	label_at("无需评分，脑洞就是答案。", Rect2(101, 732, 480, 35), 19, BROWN, true)
	panel_at(Rect2(728, 150, 510, 606), Color("ede7d8"), page, Color("bbae90"))
	line_at(Rect2(707, 138, 554, 12), BROWN)
	line_at(Rect2(707, 753, 554, 12), BROWN)
	label_at("诗\n圣\n今\n日\n休\n笔", Rect2(1165, 200, 45, 348), 26, BROWN, true)
	texture_at("res://assets/characters/dufu-avatar.png", Rect2(758, 203, 420, 420))
	panel_at(Rect2(781, 186, 115, 39), RED, page, RED)
	label_at("诗圣上线", Rect2(795, 187, 107, 38), 19, PAPER, true)
	line_at(Rect2(788, 635, 340, 1))
	label_at("不忙写诗，忙着出圈。", Rect2(790, 650, 391, 47), 27, INK, true)
	label_at("一张画像 · 万千想象", Rect2(820, 704, 380, 34), 19, BROWN)

func levels() -> void:
	heading("命题画卷", "选一幅画卷，给杜甫一个忙起来的理由。所有主题都可自由试选。")
	for i in range(4):
		var x := 74 + i * 327
		var accent: Color = TOPIC_COLORS[i]
		line_at(Rect2(x - 7, 267, 310, 10), accent)
		panel_at(Rect2(x, 277, 296, 435), TOPIC_TINTS[i], page, accent)
		label_at("零" + ["一", "二", "三", "四"][i], Rect2(x + 24, 298, 80, 33), 19, accent, true)
		label_at(TOPICS[i], Rect2(x + 34, 352, 238, 74), 49, accent, true)
		label_at(TITLES[i], Rect2(x + 36, 452, 238, 38), 24, BROWN, true)
		var l := label_at(PROMPTS[i], Rect2(x + 30, 505, 242, 80), 19, BROWN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if drawings.has(i) and drawings[i].submitted >= 0:
			label_at("已过关" if drawings[i].submitted == drawings[i].revision else "画卷已修改，可再次提交", Rect2(x + 30, 582, 242, 29), 16, accent)
		var enter := button_at("展开画卷  →", Rect2(x + 28, 621, 240, 57), func(): topic = i; show_page("canvas"), true)
		enter.add_theme_stylebox_override("normal", box(accent, accent))
		line_at(Rect2(x - 7, 712, 310, 10), accent)
	label_at("没有标准答案，也没有不及格。放心大胆地想。", Rect2(75, 766, 1020, 38), 22, BROWN, true)

func canvas() -> void:
	heading("创作画布", "绘画、文字、贴纸与诗圣自由摆放 · 鼠标或单指操作")
	panel_at(Rect2(74, 238, 1294, 67), Color("e2e7d9"))
	label_at("本关命题", Rect2(95, 249, 125, 42), 21, INK, true)
	label_at(PROMPTS[topic] if topic >= 0 else "自由创作：诗人今天想怎么忙，就怎么忙", Rect2(234, 249, 883, 42), 23)
	button_at("换个主题", Rect2(1193, 249, 156, 44), func(): show_page("levels"))
	panel_at(Rect2(74, 327, 198, 471))
	label_at("创作工具", Rect2(96, 340, 164, 35), 23, INK, true)
	for i in range(2):
		var tool: String = ["笔刷", "橡皮"][i]
		button_at(tool, Rect2(91 + i * 86, 389, 78, 45), func(): set_tool(tool), selected_tool == tool).add_theme_font_size_override("font_size", 18)
	button_at("选择 / 移动", Rect2(91, 444, 164, 45), func(): set_tool("移动"), selected_tool == "移动").add_theme_font_size_override("font_size", 18)
	button_at("文字", Rect2(91, 499, 78, 45), func(): text_editor(false)).add_theme_font_size_override("font_size", 18)
	button_at("贴纸", Rect2(177, 499, 78, 45), sticker_picker).add_theme_font_size_override("font_size", 18)
	var color_button := button_at("调色盘", Rect2(91, 554, 164, 45), palette_dialog)
	color_button.add_theme_stylebox_override("normal", box(PAPER, pen_color, 3))
	color_button.tooltip_text = "当前画笔色号：#" + pen_color.to_html(false)
	var width_label := label_at("笔宽 · %d" % pen_width, Rect2(94, 604, 155, 28), 18, BROWN)
	var width_choice := HSlider.new()
	width_choice.min_value = 4
	width_choice.max_value = 56
	width_choice.step = 4
	width_choice.value = pen_width
	rect(width_choice, Rect2(91, 637, 164, 27))
	width_choice.value_changed.connect(func(value): pen_width = int(value); drawing.pen_width = pen_width; width_label.text = "笔宽 · %d" % pen_width; print("DRAW_WIDTH:", pen_width); autosave())
	button_at("素材参考", Rect2(91, 683, 164, 43), sticker_list)
	button_at("重新创作", Rect2(91, 736, 164, 43), restart_confirm)
	panel_at(Rect2(294, 327, 1074, 471))
	object_buttons.clear()
	var actions := ["编辑", "缩小", "放大", "左转", "右转", "删除", "取消"]
	for i in range(actions.size()):
		var action: String = actions[i]
		object_buttons[action] = button_at(action, Rect2(311 + i * 107, 337, 99, 42), func(): object_action(action))
		object_buttons[action].add_theme_font_size_override("font_size", 18)
	undo_button = button_at("撤销", Rect2(1080, 337, 120, 42), func(): drawing.travel(false))
	redo_button = button_at("重做", Rect2(1216, 337, 132, 42), func(): drawing.travel(true))
	drawing_status = label_at("", Rect2(313, 733, 810, 29), 16, BROWN)
	if not drawings.has(topic): drawings[topic] = Drawing.new_state()
	drawing = Drawing.new()
	drawing.state = drawings[topic]
	drawing.ink = pen_color
	drawing.pen_width = pen_width
	drawing.erasing = selected_tool == "橡皮"
	drawing.selecting = selected_tool == "移动"
	rect(drawing, Rect2(311, 397, 1040, 330))
	drawing.changed.connect(func(): update_drawing_controls(); autosave())
	drawing.selection_changed.connect(update_drawing_controls)
	update_drawing_controls()
	label_at("草稿自动保存于此浏览器；完成后提交并存入画廊。", Rect2(313, 767, 735, 24), 15, MUTED)
	button_at("提交作品 →", Rect2(1131, 743, 213, 43), submit_artwork, true)

func update_drawing_controls() -> void:
	var state: Dictionary = drawings[topic]
	undo_button.disabled = state.undo.is_empty()
	redo_button.disabled = state.redo.is_empty()
	var object: Dictionary = drawing.selected_object() if drawing.selecting else {}
	for action in object_buttons:
		object_buttons[action].disabled = object.is_empty()
	object_buttons["编辑"].disabled = object.is_empty() or object.kind != "text"
	object_buttons["删除"].disabled = object.is_empty() or object.kind == "avatar"
	var tip := "选择 / 移动：点选对象后拖动；空白处取消" if drawing.selecting else "橡皮只擦笔迹" if drawing.erasing else "画笔不会移动对象"
	if not object.is_empty(): tip = "已选：" + {"avatar":"杜甫", "text":"文字", "star":"星星", "cloud":"祥云", "seal":"忙字印章"}[object.kind] + " · 拖动移动，上方可变换"
	drawing_status.text = tip + " · 历史 %d / 20" % state.undo.size()
	print("DRAW_STATE:", topic, ":", state.revision, ":", drawing.has_creation(), ":", state.undo.size(), ":", state.redo.size())
	print("OBJECT_STATE:", state.objects.size(), ":", state.selected)

func set_tool(tool: String) -> void:
	drawing.finish()
	selected_tool = tool
	show_page("canvas")

func object_action(action: String) -> void:
	match action:
		"编辑": text_editor(true)
		"缩小": drawing.transform_selected(0.85, 0)
		"放大": drawing.transform_selected(1.15, 0)
		"左转": drawing.transform_selected(1, -PI / 12)
		"右转": drawing.transform_selected(1, PI / 12)
		"删除": drawing.remove_selected()
		"取消":
			drawings[topic].selected = -1
			drawing.queue_redraw()
			update_drawing_controls()

func palette_dialog() -> void:
	drawing.finish()
	modal("调色盘", "选择一种颜色，或输入六位十六进制色号，例如 3A9D8F。", true)
	var colors := ["243d35", "aa4937", "416f9a", "d4a337", "151515", "ffffff", "7547a0", "d66c98", "45a99b", "7d913d", "8b583c", "ed8b3a"]
	for i in range(colors.size()):
		var code: String = colors[i]
		var swatch := button_at("#" + code.to_upper(), Rect2(246 + (i % 6) * 158, 260 + (i / 6) * 94, 140, 70), func(): apply_color(Color(code)), false, overlay)
		swatch.add_theme_stylebox_override("normal", box(Color(code)))
		swatch.add_theme_color_override("font_color", Color.BLACK if Color(code).get_luminance() > 0.45 else Color.WHITE)
		swatch.add_theme_font_size_override("font_size", 17)
	label_at("自定义色号", Rect2(247, 501, 210, 45), 22, INK, false, overlay)
	var hex := LineEdit.new()
	hex.max_length = 6
	hex.text = pen_color.to_html(false)
	rect(hex, Rect2(450, 501, 300, 48), overlay)
	var error := label_at("", Rect2(247, 573, 800, 40), 19, RED, false, overlay)
	hex.text_changed.connect(func(_value): error.text = "")
	button_at("应用颜色", Rect2(794, 501, 220, 48), func():
		if hex.text.length() != 6 or not Color.html_is_valid(hex.text): error.text = "请输入六位有效色号，如 3A9D8F。"; return
		apply_color(Color.html(hex.text)), true, overlay)

func apply_color(color: Color) -> void:
	pen_color = color
	selected_tool = "笔刷"
	show_page("canvas")
	print("COLOR_CHANGED:", color.to_html(false))

func text_editor(edit: bool) -> void:
	drawing.finish()
	if not edit and drawings[topic].objects.size() >= 25:
		info("画布有点热闹", "最多容纳 24 个文字或贴纸，请先删除一个。")
		return
	var object: Dictionary = drawing.selected_object() if edit else {}
	modal("编辑文字" if edit else "添加文字", "")
	label_at("文字（最多 24 字）", Rect2(435, 353, 550, 38), 19, BROWN, false, overlay)
	var editor := LineEdit.new()
	editor.max_length = 24
	editor.text = object.text if edit else ""
	editor.placeholder_text = "给诗圣配一句台词"
	editor.add_theme_font_override("font", Drawing.CREATIVE_FONT)
	rect(editor, Rect2(435, 397, 567, 49), overlay)
	label_at("字号", Rect2(435, 470, 90, 44), 19, INK, false, overlay)
	var font_size := SpinBox.new()
	font_size.min_value = 16
	font_size.max_value = 64
	font_size.step = 2
	font_size.value = object.font_size if edit else 32
	rect(font_size, Rect2(525, 470, 137, 44), overlay)
	label_at("色号", Rect2(702, 470, 86, 44), 19, INK, false, overlay)
	var color := LineEdit.new()
	color.max_length = 6
	color.text = (object.color if edit else pen_color).to_html(false)
	rect(color, Rect2(788, 470, 214, 44), overlay)
	var error := label_at("", Rect2(435, 523, 570, 40), 17, RED, false, overlay)
	editor.text_changed.connect(func(_value): error.text = "")
	color.text_changed.connect(func(_value): error.text = "")
	button_at("应用文字", Rect2(793, 575, 207, 57), func():
		var text := editor.text.strip_edges()
		if text.is_empty(): error.text = "写点什么再应用吧。"; return
		if color.text.length() != 6 or not Color.html_is_valid(color.text): error.text = "请输入六位有效色号。"; return
		for character in text:
			if not Drawing.CREATIVE_FONT.has_char(character.unicode_at(0)): error.text = "有字形不支持，请换用汉字、英文或常用标点。"; return
		if edit: drawing.edit_text(text, int(font_size.value), Color.html(color.text))
		else: drawing.add_object("text", text, int(font_size.value), Color.html(color.text))
		selected_tool = "移动"
		show_page("canvas")
		print("TEXT_APPLIED:", text), true, overlay)
	editor.grab_focus()
	# Re-clicking the already focused LineEdit can blur Godot's DOM IME host.
	# Re-enable the engine IME through its public API after the click is handled.
	if OS.has_feature("web") and not DisplayServer.is_touchscreen_available():
		editor.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed: restore_text_ime.call_deferred(editor))

func restore_text_ime(editor: LineEdit) -> void:
	if is_instance_valid(editor) and editor.has_focus():
		DisplayServer.window_set_ime_active(true)

func sticker_picker() -> void:
	drawing.finish()
	if drawings[topic].objects.size() >= 25:
		info("画布有点热闹", "最多容纳 24 个文字或贴纸，请先删除一个。")
		return
	modal("原创贴纸", "原创代码图形，可移动、缩放、旋转与删除。", true)
	for i in range(3):
		var kind: String = ["star", "cloud", "seal"][i]
		var sample := Drawing.new()
		sample.state = Drawing.new_state()
		sample.state.objects = [{"id": 1, "kind": kind, "position": Vector2(120, 90), "scale": 1.3, "rotation": 0.0}]
		sample.preview_only = true
		rect(sample, Rect2(254 + i * 323, 254, 240, 190), overlay)
		label_at(["星星", "祥云", "忙字印章"][i], Rect2(254 + i * 323, 466, 240, 45), 28, INK, true, overlay)
		button_at("添加贴纸", Rect2(254 + i * 323, 535, 240, 56), func(): drawing.add_object(kind); selected_tool = "移动"; show_page("canvas"), true, overlay)

func restart_confirm() -> void:
	modal("重新创作？", "将重建当前命题草稿，杜甫回到原位。已存入画廊的作品不受影响。")
	button_at("取消", Rect2(566, 575, 202, 58), close_overlay, false, overlay)
	button_at("清空画卷", Rect2(795, 575, 202, 58), func(): drawings[topic] = Drawing.new_state(); show_page("canvas"), true, overlay)

func submit_artwork() -> void:
	if submitting: return
	drawing.finish()
	if not drawing.has_creation():
		info("诗圣还在等你落笔", "画一点、写一句、贴一张，
或给杜甫挪个位置，都算创作！")
		print("SUBMIT_EMPTY")
		return
	var state: Dictionary = drawings[topic]
	if state.submitted != state.revision or state.result == null:
		submitting = true
		# Block interaction during the one-frame offscreen capture.
		modal("正在装裱", "请稍候，正在合成当前画卷。")
		var captured: Image = await drawing.artwork()
		submitting = false
		state.result = ImageTexture.create_from_image(captured)
		state.submitted = state.revision
	var remarks := ["车到山前必有路，诗圣今天不走路。", "安得机甲千万套，大庇诗人不加班。", "笔下自有江湖在，杜某先干一碗茶。", "采菊东篱下，今天不打卡。"]
	var remark: String = remarks[topic] if topic >= 0 else "这脑洞，连我的胡子都忍不住翘起来了。"
	modal("妙哉！本关已通过", "本地点评 · 有创作就过关。
草稿自动保存；画廊需点击保存。", true)
	var art := TextureRect.new()
	art.texture = state.result
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect(art, Rect2(214, 230, 1012, 330), overlay)
	label_at(remark, Rect2(235, 581, 980, 60), 27, INK, true, overlay)
	button_at("重新创作", Rect2(462, 644, 235, 49), restart_confirm, false, overlay)
	button_at("继续编辑", Rect2(718, 644, 235, 49), close_overlay, false, overlay)
	button_at("选下一幅", Rect2(974, 644, 235, 49), func(): show_page("levels"), true, overlay)
	button_at("保存新版本" if not state.get("work_id", "").is_empty() else "保存到画廊", Rect2(216, 644, 224, 49), func(): save_work(false), true, overlay)
	button_at("另存新作", Rect2(746, 716, 225, 48), func(): save_work(true), false, overlay)
	button_at("下载 PNG", Rect2(991, 716, 218, 48), func(): download_image(state.result.get_image()), false, overlay)
	autosave()
	print("SUBMIT_OK:", topic, ":", state.submitted)

func storage_candidate() -> Dictionary:
	var candidate: Dictionary = local_store.document.duplicate(true)
	for key in drawings: candidate.drafts[str(key)] = LocalStore.encode(drawings[key])
	candidate.page = current
	candidate.topic = topic
	candidate.tools = {"color":pen_color.to_html(false),"width":pen_width,"tool":selected_tool}
	return candidate

func update_storage_status(ok: bool) -> void:
	if is_instance_valid(storage_retry): storage_retry.visible = not ok
	storage_status = "草稿已自动保存 · 仅此浏览器与此站点，清理站点数据会丢失。" if ok else local_store.error
	if is_instance_valid(storage_hint):
		storage_hint.text = storage_status
		storage_hint.add_theme_color_override("font_color", BROWN if ok else RED)
	print("STORAGE_OK" if ok else "STORAGE_ERROR:", "" if ok else local_store.error)

func autosave() -> void:
	if not is_instance_valid(page): return
	update_storage_status(local_store.write_document(storage_candidate()))

func retry_storage() -> void:
	if not local_store.writable:
		var retry := LocalStore.new()
		if retry.read_document():
			local_store = retry
			for key in local_store.document.drafts:
				var restored_topic := int(key)
				if not drawings.has(restored_topic) or drawings[restored_topic].revision == 0:
					drawings[restored_topic] = LocalStore.decode(local_store.document.drafts[key])
			show_page(current)
			return
	autosave()
	if not local_store.error.is_empty(): info("本地保存未完成", local_store.error)

func save_work(as_new: bool) -> void:
	var state: Dictionary = drawings[topic]
	if state.result == null or state.submitted != state.revision:
		info("先看看最新画卷", "请重新提交当前画卷后再保存作品。")
		return
	var candidate := storage_candidate()
	var id: String = "" if as_new else state.get("work_id", "")
	var index := -1
	for i in range(candidate.works.size()):
		if candidate.works[i].id == id: index = i
	# Completed works are immutable: changed drafts become new versions.
	if index >= 0 and candidate.works[index].data.revision != state.revision: index = -1
	if index == -1:
		id = "work-%d" % int(candidate.next_id)
		candidate.next_id += 1
	var encoded := LocalStore.encode(state)
	encoded.work_id = id
	var title: String = candidate.works[index].title if index >= 0 else (TOPICS[topic] if topic >= 0 else "自由创作") + " · " + id.trim_prefix("work-")
	var work := {"id":id,"topic":topic,"title":title,"data":encoded,"preview":Marshalls.raw_to_base64(state.result.get_image().save_png_to_buffer())}
	if index == -1: candidate.works.append(work)
	candidate.drafts[str(topic)] = encoded
	if not local_store.write_document(candidate):
		update_storage_status(false)
		info("作品尚未保存", local_store.error + "\n原有画廊作品没有被改动。可返回点评页下载 PNG。")
		return
	state.work_id = id
	update_storage_status(true)
	modal("已保存到我的画廊", title + "\n草稿可继续编辑；修改后保存为新版本，不覆盖画廊旧作。")
	button_at("继续编辑", Rect2(566, 575, 202, 58), close_overlay, false, overlay)
	button_at("我的画廊", Rect2(795, 575, 202, 58), func(): gallery_tab = 0; gallery_page = 0; show_page("gallery"), true, overlay)
	print("WORK_SAVED:", id, ":", local_store.document.works.size())

func work_texture(work: Dictionary) -> ImageTexture:
	var image := Image.new()
	image.load_png_from_buffer(Marshalls.base64_to_raw(work.preview))
	return ImageTexture.create_from_image(image)

func my_gallery() -> void:
	var works: Array = local_store.document.works
	label_at("本地完成作品 · %d 幅" % works.size(), Rect2(74, 307, 580, 42), 20, BROWN)
	if works.is_empty():
		panel_at(Rect2(74, 359, 1294, 427))
		label_at("画卷尚空，脑洞先行。", Rect2(414, 422, 800, 66), 42, INK, true)
		label_at("草稿在画布自动保存；提交后可存入这里。", Rect2(420, 528, 760, 39), 22, BROWN)
		button_at("去创作", Rect2(559, 623, 320, 61), func(): show_page("canvas"), true)
		return
	gallery_page = clampi(gallery_page, 0, (works.size() - 1) / 4)
	button_at("上一页", Rect2(1000, 308, 168, 42), func(): gallery_page -= 1; show_page("gallery")).disabled = gallery_page == 0
	button_at("下一页", Rect2(1190, 308, 178, 42), func(): gallery_page += 1; show_page("gallery")).disabled = (gallery_page + 1) * 4 >= works.size()
	for slot in range(mini(4, works.size() - gallery_page * 4)):
		var work: Dictionary = works[works.size() - 1 - gallery_page * 4 - slot]
		var x := 74 + (slot % 2) * 660
		var y := 365 + (slot / 2) * 213
		panel_at(Rect2(x, y, 634, 199))
		var picture := TextureRect.new()
		picture.texture = work_texture(work)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect(picture, Rect2(x + 15, y + 15, 280, 165))
		label_at(work.title, Rect2(x + 310, y + 16, 306, 46), 24, INK, true)
		button_at("查看作品", Rect2(x + 310, y + 77, 302, 46), func(): view_work(work))
		button_at("打开编辑", Rect2(x + 310, y + 134, 302, 46), func(): open_work_confirm(work))

func view_work(work: Dictionary) -> void:
	modal(work.title, "本地保存的完成作品。打开编辑只生成草稿，旧作保持不变。", true)
	var picture := TextureRect.new()
	picture.texture = work_texture(work)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect(picture, Rect2(214, 230, 1012, 420), overlay)
	button_at("打开编辑", Rect2(740, 654, 220, 49), func(): open_work_confirm(work), true, overlay)
	button_at("下载 PNG", Rect2(985, 654, 220, 49), func(): download_image(picture.texture.get_image()), false, overlay)
	print("WORK_VIEW:", work.id)

func open_work_confirm(work: Dictionary) -> void:
	modal("打开已存画作？", "将替换该命题当前草稿，画廊原作保持不变。\n要保留当前草稿，请先将它存入画廊。")
	button_at("取消", Rect2(566, 575, 202, 58), close_overlay, false, overlay)
	button_at("打开编辑", Rect2(795, 575, 202, 58), func():
		topic = int(work.topic)
		drawings[topic] = LocalStore.decode(work.data)
		drawings[topic].work_id = work.id
		selected_tool = "移动"
		show_page("canvas")
		print("WORK_OPEN:", work.id), true, overlay)

func download_image(image: Image) -> void:
	var filename := "dufu-artwork.png"
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(image.save_png_to_buffer(), filename, "image/png")
		print("PNG_DOWNLOAD_REQUESTED")
	else:
		var path := "user://" + filename
		if image.save_png(path) == OK: info("PNG 已导出", ProjectSettings.globalize_path(path))
		else: info("PNG 导出失败", "无法写入本地文件。")

func gallery() -> void:
	heading("画廊", "同一张画像，也能有万千种忙法。")
	button_at("我的作品", Rect2(74, 238, 220, 57), func(): gallery_tab = 0; show_page("gallery"), gallery_tab == 0)
	button_at("灵感画廊", Rect2(309, 238, 220, 57), func(): gallery_tab = 1; show_page("gallery"), gallery_tab == 1)
	label_at("合成示例 · 仅供欣赏" if gallery_tab == 1 else "可编辑图层 · 本机保存", Rect2(1040, 246, 330, 38), 18, BROWN)
	if gallery_tab == 0:
		my_gallery()
	else:
		label_at("主题筛选", Rect2(74, 309, 130, 44), 20, BROWN)
		var filters := ["全部", "武侠", "科幻", "市井", "脑洞"]
		for i in range(filters.size()):
			var filter: String = filters[i]
			button_at(filter, Rect2(205 + i * 136, 309, 121, 44), func(): gallery_filter = filter; show_page("gallery"), gallery_filter == filter)
		var visible_indices: Array[int] = []
		for i in range(IDEAS.size()):
			if gallery_filter == "全部" or EXAMPLE_TOPICS[i] == gallery_filter:
				visible_indices.append(i)
		label_at("显示 %d 幅示例" % visible_indices.size(), Rect2(1142, 312, 230, 38), 18, BROWN)
		for slot in range(visible_indices.size()):
			var i := visible_indices[slot]
			var x := 74 + (slot % 2) * 660
			var y := 373 + (slot / 2) * 214
			panel_at(Rect2(x, y, 634, 199))
			panel_at(Rect2(x + 13, y + 13, 275, 173), Color("e4dfd2"))
			texture_at("res://assets/examples/" + EXAMPLE_IMAGES[i], Rect2(x + 16, y + 16, 269, 167))
			label_at(IDEAS[i], Rect2(x + 311, y + 14, 302, 47), 30, INK, true)
			label_at(EXAMPLE_TOPICS[i] + " · 预制示例", Rect2(x + 313, y + 70, 290, 32), 18, MUTED)
			button_at("查看大图", Rect2(x + 309, y + 111, 299, 48), func(): example(i))
			label_at("合成图片，不可分层编辑", Rect2(x + 313, y + 165, 300, 26), 15, MUTED)
		print("UI_FILTER:", gallery_filter, ":", visible_indices.size())

func example(index: int) -> void:
	image_dialog(IDEAS[index], "res://assets/examples/" + EXAMPLE_IMAGES[index], EXAMPLE_TOPICS[index] + " · 原始合成示例，仅供欣赏，不是已保存作品或可编辑图层。", "返回画廊")

func image_dialog(title: String, path: String, caption: String, back_label: String, back_action: Callable = Callable()) -> void:
	modal(title, caption, true)
	texture_at(path, Rect2(214, 218, 1012, 467), overlay)
	button_at(back_label, Rect2(1010, 717, 216, 48), back_action if back_action.is_valid() else close_overlay, true, overlay)

func settings_page() -> void:
	heading("设置", "调整体验，让想象按自己的节奏来。")
	panel_at(Rect2(74, 248, 626, 558))
	panel_at(Rect2(730, 248, 638, 558), Color("e8e7d9"))
	label_at("体验偏好", Rect2(104, 265, 540, 56), 29, INK, true)
	label_at("音量", Rect2(151, 344, 100, 45), 22)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 100
	volume.step = 1
	volume.value = settings.volume
	rect(volume, Rect2(250, 352, 295, 32))
	var value_label := label_at(str(int(settings.volume)) + "%", Rect2(565, 344, 95, 43), 22, BROWN)
	volume.value_changed.connect(func(v): settings.volume = v; value_label.text = str(int(v)) + "%"; save_settings())
	for i in range(2):
		var key: String = ["sound", "music"][i]
		label_at(["音效偏好", "音乐偏好"][i], Rect2(151, 413 + i * 62, 235, 46), 22)
		var toggle := CheckButton.new()
		toggle.text = "开启" if settings[key] else "关闭"
		toggle.button_pressed = settings[key]
		rect(toggle, Rect2(440, 413 + i * 62, 209, 46))
		toggle.toggled.connect(func(v): settings[key] = v; toggle.text = "开启" if v else "关闭"; save_settings())
	label_at("语言", Rect2(151, 543, 125, 43), 22)
	label_at("简体中文", Rect2(440, 543, 210, 43), 22, BROWN)
	label_at("画质偏好", Rect2(151, 606, 234, 46), 22)
	var quality := OptionButton.new()
	quality.add_item("标准")
	quality.add_item("高清")
	quality.select(int(settings.quality))
	rect(quality, Rect2(440, 606, 209, 47))
	quality.item_selected.connect(func(i): settings.quality = i; save_settings())
	button_at("恢复默认设置", Rect2(106, 697, 270, 55), reset_confirm)
	label_at("关于本作", Rect2(767, 271, 542, 55), 32, INK, true)
	var about := label_at("从一张残缺画像出发，\n用画笔、贴纸与文字，\n续出千千万万个忙碌的杜甫。\n\n没有严格评分，也没有标准答案。\n让创意做主，让诗圣放个假。", Rect2(769, 350, 544, 246), 25, INK, true)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line_at(Rect2(768, 632, 560, 1))
	var note := label_at("当前没有音频；音量、开关与画质保存为本地偏好，\n尚不改变音频或渲染效果。\n" + settings_status, Rect2(768, 657, 561, 120), 17, BROWN)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func save_settings() -> void:
	for key in settings: config.set_value("settings", key, settings[key])
	var saved_ok: bool
	if OS.has_feature("web"):
		var payload := JSON.stringify(JSON.stringify(settings))
		saved_ok = JavaScriptBridge.eval("(function(){try{localStorage.setItem('DuFuIsBusy.settings.v1', %s);return true;}catch(e){return false;}})()" % payload) == true
	else:
		saved_ok = config.save("user://settings.cfg") == OK
	settings_status = "设置已保存在本机；不进行云端同步。" if saved_ok else "本地写入失败；偏好仅在当前会话生效。"

func reset_confirm() -> void:
	modal("恢复默认设置？", "仅重置音量、音效、音乐和画质偏好。\n不会删除当前会话的画卷。")
	button_at("确认恢复", Rect2(795, 575, 202, 58), func(): settings = {"volume":70.0,"sound":true,"music":true,"quality":1,"motion":false}; save_settings(); show_page("settings"), true, overlay)
	button_at("取消", Rect2(566, 575, 202, 58), close_overlay, false, overlay)

func exit_info() -> void:
	info("诗圣先歇一会儿", "网页不会擅自关闭你的标签页。\n想休息时直接关闭本页，随时可以回来继续看。")

func modal(title: String, body: String, large: bool = false) -> void:
	close_overlay()
	for control in page.find_children("*", "Control", true, false):
		if control.focus_mode != Control.FOCUS_NONE:
			control.set_meta("previous_focus_mode", control.focus_mode)
			suspended_focus.append(control)
			control.focus_mode = Control.FOCUS_NONE
	overlay = Control.new()
	overlay.name = "Dialog"
	add_child(overlay)
	overlay.size = Vector2(1440, 900)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.16, 0.12, 0.58)
	rect(shade, Rect2(0, 0, 1440, 900), overlay)
	if large:
		panel_at(Rect2(182, 140, 1076, 648), PAPER, overlay)
		label_at(title, Rect2(214, 157, 906, 54), 32, INK, true, overlay)
		var caption := label_at(body, Rect2(216, 708, 500, 62), 18, BROWN, false, overlay, true)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.size = Vector2(500, 62)
		button_at("×", Rect2(1186, 157, 48, 48), close_overlay, false, overlay).grab_focus()
		print("UI_DIALOG:", title)
		return
	panel_at(Rect2(395, 252, 650, 414), PAPER, overlay)
	label_at(title, Rect2(433, 288, 570, 69), 36, INK, true, overlay)
	var l := label_at(body, Rect2(435, 378, 570, 159), 22, BROWN, false, overlay, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size = Vector2(570, 159)
	button_at("×", Rect2(972, 271, 48, 48), close_overlay, false, overlay).grab_focus()
	print("UI_DIALOG:", title)

func info(title: String, body: String) -> void:
	modal(title, body)
	button_at("知道了", Rect2(793, 575, 207, 57), close_overlay, true, overlay)

func sticker_list() -> void:
	modal("贴纸目录 · UI 预览", "仅查看源素材，尚不能放置、拖拽或编辑贴纸。", true)
	panel_at(Rect2(218, 228, 375, 462), Color.WHITE, overlay)
	texture_at("res://assets/stickers/weapon-sheet.jpg", Rect2(230, 239, 351, 435), overlay)
	label_at("幻想武器", Rect2(643, 231, 530, 52), 30, INK, true, overlay)
	label_at("五件武器的白底源拼图，尚未拆分为贴纸。", Rect2(645, 287, 559, 38), 19, BROWN, false, overlay)
	button_at("查看武器源图", Rect2(645, 344, 558, 55), func(): image_dialog("幻想武器源图", "res://assets/stickers/weapon-sheet.jpg", "白底拼图仅作目录预览，不是五张独立透明贴纸。", "返回目录", sticker_list), true, overlay)
	label_at("场景参考", Rect2(643, 427, 530, 44), 26, INK, true, overlay)
	button_at("科幻都市", Rect2(645, 489, 266, 55), func(): image_dialog("科幻都市", "res://assets/backgrounds/scifi-city.jpg", "原始场景背景预览，当前不能应用到画布。", "返回目录", sticker_list), false, overlay)
	button_at("烟火夜市", Rect2(931, 489, 272, 55), func(): image_dialog("烟火夜市", "res://assets/backgrounds/night-market.jpg", "原始场景背景预览，当前不能应用到画布。", "返回目录", sticker_list), false, overlay)
	label_at("交通与田园素材仍待补充。", Rect2(645, 587, 557, 45), 19, MUTED, false, overlay)
	button_at("返回画布", Rect2(1010, 717, 216, 48), close_overlay, true, overlay)

func close_overlay() -> void:
	for control in suspended_focus:
		if is_instance_valid(control):
			control.focus_mode = control.get_meta("previous_focus_mode", Control.FOCUS_ALL)
	suspended_focus.clear()
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	overlay = null

func _unhandled_key_input(event: InputEvent) -> void:
	if submitting: return
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(overlay): close_overlay()
		elif current == "canvas" and drawings[topic].selected >= 0:
			object_action("取消")
		elif current != "home": show_page("home")
		get_viewport().set_input_as_handled()
