extends Control

const INK = Color("243d35")
const BROWN = Color("766148")
const RED = Color("aa4937")
const PAPER = Color("f8f4e9")
const MUTED = Color("857b68")
const SERIF = preload("res://assets/fonts/SourceSerifSC.otf")
const SANS = preload("res://assets/fonts/SourceSansSC.otf")
const Paper = preload("res://scripts/ink_paper.gd")
const TOPICS = ["交通", "科幻", "武侠", "田园"]
const TITLES = ["行路人间", "机甲盛唐", "剑影江湖", "田园闲居"]
const PROMPTS = ["至少出现一种交通工具", "让杜甫拥有一身未来机甲", "给诗人安排一次江湖奇遇", "让杜甫忙里偷闲，归园田居"]
const IDEAS = ["骑车赶诗会", "机甲也吟诗", "剑气与诗意", "田间好时光", "星际送秋风", "雨夜逛长安"]
var page: Control
var overlay: Control
var current := "home"
var topic := 0
var gallery_tab := 0
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
	show_page("home")

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
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(state, type, INK)
		t.set_color("font_disabled_color", type, MUTED)
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

func label_at(text: String, area: Rect2, font_size: int = 22, color: Color = INK, serif: bool = false, parent: Control = page) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if serif: l.add_theme_font_override("font", SERIF)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect(l, area, parent)
	return l

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
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
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
	label_at("UI 预览 · 开发中", Rect2(1243, 26, 155, 33), 15, BROWN)
	line_at(Rect2(52, 78, 1336, 1))
	label_at("不必画得像，尽管想得妙。", Rect2(52, 845, 800, 30), 16, BROWN, true)
	label_at("杜甫很忙  /  界面演示", Rect2(1160, 845, 240, 30), 15, BROWN)
	if id != "home":
		button_at("← 返回首页", Rect2(1210, 104, 178, 48), func(): show_page("home"))
	match id:
		"home": home()
		"levels": levels()
		"canvas": canvas()
		"gallery": gallery()
		"settings": settings_page()
	is_busy = false
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
	label_at("杜\n甫", Rect2(792, 230, 164, 230), 92, INK, true)
	label_at("很\n忙", Rect2(976, 305, 92, 184), 60, RED, true)
	line_at(Rect2(788, 564, 340, 1))
	label_at("原像素材待接入", Rect2(791, 590, 358, 38), 23, BROWN)
	label_at("当前为排版占位，不是可编辑人物素材", Rect2(779, 639, 420, 34), 17, MUTED)

func levels() -> void:
	heading("命题画卷", "选一幅画卷，给杜甫一个忙起来的理由。所有主题都可自由试选。")
	for i in range(4):
		var x := 74 + i * 327
		line_at(Rect2(x - 7, 267, 310, 10), BROWN)
		panel_at(Rect2(x, 277, 296, 435), Color("f6f0e1"))
		label_at("零" + ["一", "二", "三", "四"][i], Rect2(x + 24, 298, 80, 33), 19, RED, true)
		label_at(TOPICS[i], Rect2(x + 34, 352, 238, 74), 49, INK, true)
		label_at(TITLES[i], Rect2(x + 36, 452, 238, 38), 24, BROWN, true)
		var l := label_at(PROMPTS[i], Rect2(x + 30, 505, 242, 80), 19, BROWN)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button_at("展开画卷  →", Rect2(x + 28, 621, 240, 57), func(): topic = i; show_page("canvas"), true)
		line_at(Rect2(x - 7, 712, 310, 10), BROWN)
	label_at("没有标准答案，也没有不及格。放心大胆地想。", Rect2(75, 766, 1020, 38), 22, BROWN, true)

func canvas() -> void:
	heading("创作画布", "画笔、贴纸、文字 · 先试试创作界面的布局与切换")
	panel_at(Rect2(74, 238, 1294, 67), Color("e2e7d9"), page, Color("b5c0a8"))
	label_at("本关命题", Rect2(95, 249, 125, 42), 21, INK, true)
	label_at(PROMPTS[topic] if topic >= 0 else "自由创作：诗人今天想怎么忙，就怎么忙", Rect2(234, 249, 883, 42), 23, INK)
	button_at("换个主题", Rect2(1193, 249, 156, 44), func(): show_page("levels"))
	panel_at(Rect2(74, 327, 198, 471))
	label_at("创作工具", Rect2(96, 344, 164, 35), 23, INK, true)
	for i in range(5):
		var tool: String = ["笔刷", "橡皮", "色盘", "贴纸", "文字"][i]
		button_at(tool + (" · 已选" if selected_tool == tool else ""), Rect2(91, 397 + i * 65, 164, 52), func(): choose_tool(tool), tool == selected_tool)
	label_at("工具交互预览", Rect2(96, 741, 170, 32), 17, MUTED)
	panel_at(Rect2(294, 327, 790, 471), Color("faf7ef"))
	label_at("画布预览  /  尚未开放绘制", Rect2(323, 344, 700, 36), 19, BROWN)
	line_at(Rect2(324, 392, 729, 1))
	panel_at(Rect2(531, 419, 310, 191), Color("ede9df"), page, Color("d2c6b0"))
	label_at("杜甫半身像", Rect2(571, 458, 250, 56), 32, INK, true)
	label_at("原始素材待接入 · 保留区域", Rect2(554, 527, 282, 35), 17, MUTED)
	panel_at(Rect2(450, 632, 474, 124), Color("f1f1e4"), page, Color("bac4ad"))
	label_at("待补区域", Rect2(613, 646, 200, 38), 24, INK, true)
	label_at("以后在这里，把脑洞画出来", Rect2(548, 694, 350, 35), 19, BROWN)
	panel_at(Rect2(1106, 327, 262, 471), Color("ebe5d7"))
	label_at("创作小笺", Rect2(1130, 348, 216, 44), 29, INK, true)
	var note := label_at("画得好不好不重要，\n好玩就很了不起。\n\n本次仅展示 UI。\n绘画、拼贴、评分、\n保存与导出尚未实现。", Rect2(1130, 413, 222, 230), 19, BROWN)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button_at("提交说明", Rect2(1128, 683, 218, 55), func(): info("这次先看界面", "还没有作品被绘制、评分或保存。\n当前演示仅支持主题与工具界面切换。"), true)

func choose_tool(tool: String) -> void:
	selected_tool = tool
	show_page("canvas")
	if tool == "贴纸": sticker_list()
	elif tool == "色盘": info("色盘预览", "墨绿  ·  棕褐  ·  朱红  ·  宣纸白\n这些是界面配色。画笔颜色选择尚未开放。")
	else: info(tool + " · UI 预览", "已选中" + tool + "工具。\n绘画与文字编辑尚未实现，不会修改画布。")

func gallery() -> void:
	heading("画廊", "同一张画像，也能有万千种忙法。")
	button_at("我的作品", Rect2(74, 238, 220, 57), func(): gallery_tab = 0; show_page("gallery"), gallery_tab == 0)
	button_at("灵感画廊", Rect2(309, 238, 220, 57), func(): gallery_tab = 1; show_page("gallery"), gallery_tab == 1)
	label_at("构图示例 · 非保存作品", Rect2(1040, 246, 330, 38), 18, BROWN)
	if gallery_tab == 0:
		panel_at(Rect2(74, 322, 1294, 475))
		label_at("画卷尚空，脑洞先行。", Rect2(414, 425, 800, 66), 42, INK, true)
		label_at("本次 UI 预览不会创建或保存作品。", Rect2(485, 527, 600, 39), 22, BROWN)
		button_at("去看看创作画布", Rect2(559, 613, 320, 61), func(): topic = -1; show_page("canvas"), true)
	else:
		for i in range(6):
			var x := 74 + (i % 3) * 440
			var y := 321 + (i / 3) * 247
			panel_at(Rect2(x, y, 414, 226))
			panel_at(Rect2(x + 16, y + 16, 122, 146), Color("e5e4d6"))
			label_at(["行", "机", "侠", "田", "星", "雨"][i], Rect2(x + 45, y + 35, 100, 90), 60, INK, true)
			label_at(IDEAS[i], Rect2(x + 157, y + 26, 240, 52), 29, INK, true)
			label_at("文字构图示意", Rect2(x + 158, y + 88, 240, 32), 17, MUTED)
			button_at("查看示例  →", Rect2(x + 157, y + 131, 238, 53), func(): example(i))
			label_at("原始示例图片待接入", Rect2(x + 18, y + 180, 370, 30), 15, MUTED)

func example(index: int) -> void:
	var descriptions := ["想象杜甫骑着自行车，\n一手扶车把，一路收集诗意。", "想象墨色机甲与一卷古诗相遇，\n诗圣也可以拥有未来装备。", "想象披风随风，长剑在侧，\n今天的诗人也有侠客心。", "想象一头牛、一把锄头，\n让忙碌的杜甫休息一下。", "想象一艘飞船穿过星河，\n把秋风送到更远的地方。", "想象霓虹点亮长安雨夜，\n诗意藏在街头巷尾。"]
	info(IDEAS[index], descriptions[index] + "\n\n这是文字构图示例，不是原始成品图或可编辑素材。")

func settings_page() -> void:
	heading("设置", "调整体验，让想象按自己的节奏来。")
	panel_at(Rect2(74, 248, 626, 558))
	panel_at(Rect2(730, 248, 638, 558), Color("e8e7d9"))
	label_at("体验偏好", Rect2(104, 265, 540, 56), 29, INK, true)
	label_at("音量", Rect2(106, 344, 122, 45), 22)
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
		label_at(["音效偏好", "音乐偏好"][i], Rect2(106, 413 + i * 62, 235, 46), 22)
		var toggle := CheckButton.new()
		toggle.text = "开启" if settings[key] else "关闭"
		toggle.button_pressed = settings[key]
		rect(toggle, Rect2(440, 413 + i * 62, 209, 46))
		toggle.toggled.connect(func(v): settings[key] = v; toggle.text = "开启" if v else "关闭"; save_settings())
	label_at("语言", Rect2(106, 543, 125, 43), 22)
	label_at("简体中文", Rect2(440, 543, 210, 43), 22, BROWN)
	label_at("画质偏好", Rect2(106, 606, 234, 46), 22)
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
	var result := config.save("user://settings.cfg")
	settings_status = "设置已保存在本机；不进行云端同步。" if result == OK else "本地写入失败；偏好仅在当前会话生效。"

func reset_confirm() -> void:
	modal("恢复默认设置？", "仅重置音量、音效、音乐和画质偏好。\n不会删除任何作品；此预览没有作品存档。")
	button_at("确认恢复", Rect2(795, 575, 202, 58), func(): settings = {"volume":70.0,"sound":true,"music":true,"quality":1,"motion":false}; save_settings(); show_page("settings"), true, overlay)
	button_at("取消", Rect2(566, 575, 202, 58), close_overlay, false, overlay)

func exit_info() -> void:
	info("诗圣先歇一会儿", "网页不会擅自关闭你的标签页。\n想休息时直接关闭本页，随时可以回来继续看。")

func modal(title: String, body: String) -> void:
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
	panel_at(Rect2(395, 252, 650, 414), PAPER, overlay)
	label_at(title, Rect2(433, 288, 570, 69), 36, INK, true, overlay)
	var l := label_at(body, Rect2(435, 378, 570, 159), 22, BROWN, false, overlay)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button_at("×", Rect2(972, 271, 48, 48), close_overlay, false, overlay).grab_focus()
	print("UI_DIALOG:", title)

func info(title: String, body: String) -> void:
	modal(title, body)
	button_at("知道了", Rect2(793, 575, 207, 57), close_overlay, true, overlay)

func sticker_list() -> void:
	modal("贴纸目录 · UI 预览", "")
	for i in range(4):
		button_at(["交通工具", "未来机甲", "江湖物件", "田园风物"][i], Rect2(434 + (i % 2) * 285, 371 + (i / 2) * 72, 267, 56), func(): info("素材准备中", "贴纸资源尚未接入，当前不能放置或拖拽。\n白底拼图和合成示例不会当作分层贴纸使用。"), false, overlay)
	label_at("仅目录预览，尚未提供可放置贴纸。", Rect2(438, 538, 568, 38), 19, MUTED, false, overlay)
	button_at("返回画布", Rect2(793, 587, 207, 52), close_overlay, true, overlay)

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
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(overlay): close_overlay()
		elif current != "home": show_page("home")
		get_viewport().set_input_as_handled()
