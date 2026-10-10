extends Control
## Owns the canvas controls; navigation, dialogs and persistence belong to main.

signal tool_requested(tool: String)
signal width_changed(width: int)
signal action_requested(action: String)
signal artwork_changed

const Drawing = preload("res://scripts/drawing_surface.gd")
const TOOL_NAMES = {"ToolBrush": "笔刷", "ToolEraser": "橡皮", "ToolMove": "移动"}
const OBJECT_ACTIONS = {
	"EditObjectButton": "编辑", "ShrinkButton": "缩小", "GrowButton": "放大",
	"RotateLeftButton": "左转", "RotateRightButton": "右转",
	"DeleteObjectButton": "删除", "DeselectButton": "取消",
}
const PAGE_ACTIONS = {
	"ChangeTopicButton": "levels", "AddTextButton": "text", "StickerButton": "stickers",
	"PaletteButton": "palette", "ReferenceButton": "reference",
	"RestartButton": "restart", "SubmitButton": "submit",
}
const OBJECT_NAMES = {
	"avatar": "杜甫", "text": "文字", "weapon_du": "杜甫重剑", "weapon_pink": "粉刃短刀",
	"weapon_silver": "银纹长剑", "weapon_blue": "冰蓝长刃", "weapon_violet": "紫晶巨剑",
}

var surface: Drawing
var topic_id := 0
var tool_buttons: Dictionary = {}
var object_buttons: Dictionary = {}
var palette_style: StyleBoxFlat

@onready var palette_button: Button = $PaletteButton
@onready var width_label: Label = $WidthLabel
@onready var width_slider: HSlider = $WidthSlider
@onready var undo_button: Button = $UndoButton
@onready var redo_button: Button = $RedoButton
@onready var drawing_status: Label = $DrawingStatus

func prepare(state: Dictionary, id: int, prompt: String) -> void:
	# Set the session before DrawingSurface._ready creates its image texture.
	surface = get_node("DrawingSurface")
	surface.state = state
	topic_id = id
	get_node("TopicPrompt").text = prompt

func _ready() -> void:
	if surface == null: surface = $DrawingSurface
	palette_style = palette_button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	palette_button.add_theme_stylebox_override("normal", palette_style)
	for node_name in TOOL_NAMES:
		var tool: String = TOOL_NAMES[node_name]
		var button := get_node(node_name) as Button
		tool_buttons[tool] = button
		button.pressed.connect(_request_tool.bind(tool))
	for node_name in OBJECT_ACTIONS:
		var action: String = OBJECT_ACTIONS[node_name]
		var button := get_node(node_name) as Button
		object_buttons[action] = button
		button.pressed.connect(object_action.bind(action))
	for node_name in PAGE_ACTIONS:
		var button := get_node(node_name) as Button
		button.pressed.connect(_request_action.bind(PAGE_ACTIONS[node_name]))
	width_slider.value_changed.connect(_on_width_changed)
	undo_button.pressed.connect(surface.travel.bind(false))
	redo_button.pressed.connect(surface.travel.bind(true))
	surface.changed.connect(_on_artwork_changed)
	surface.selection_changed.connect(update_controls)
	var tool := "移动" if surface.selecting else "橡皮" if surface.erasing else "笔刷"
	refresh_tools(tool, surface.ink, surface.pen_width)

func refresh_tools(tool: String, color: Color, width: int) -> void:
	surface.erasing = tool == "橡皮"
	surface.selecting = tool == "移动"
	surface.ink = color
	surface.pen_width = width
	surface.mouse_default_cursor_shape = Control.CURSOR_MOVE if surface.selecting else Control.CURSOR_CROSS
	for name in tool_buttons:
		tool_buttons[name].set_pressed_no_signal(name == tool)
	width_slider.set_value_no_signal(width)
	width_label.text = "粗细  %d" % width
	palette_style.border_color = color
	palette_button.tooltip_text = "颜色 #" + color.to_html(false)
	surface.queue_redraw()
	update_controls()

func update_controls() -> void:
	var state := surface.state
	undo_button.disabled = state.undo.is_empty()
	redo_button.disabled = state.redo.is_empty()
	var object: Dictionary = surface.selected_object() if surface.selecting else {}
	for action in object_buttons:
		object_buttons[action].disabled = object.is_empty()
	object_buttons["编辑"].disabled = object.is_empty() or object.kind != "text"
	object_buttons["删除"].disabled = object.is_empty() or object.kind == "avatar"
	var avatar_selected: bool = not object.is_empty() and object.kind == "avatar"
	for action in ["左转", "右转"]:
		object_buttons[action].disabled = object.is_empty() or avatar_selected
		object_buttons[action].tooltip_text = "杜甫可移动、缩放，不可旋转" if avatar_selected else "向左旋转 15 度" if action == "左转" else "向右旋转 15 度"
	drawing_status.text = "未选中" if surface.selecting else "橡皮" if surface.erasing else "画笔"
	if not object.is_empty(): drawing_status.text = "已选中：" + OBJECT_NAMES[object.kind]
	print("DRAW_STATE:", topic_id, ":", state.revision, ":", surface.has_creation(), ":", state.undo.size(), ":", state.redo.size())
	print("OBJECT_STATE:", state.objects.size(), ":", state.selected)

func object_action(action: String) -> void:
	match action:
		"编辑": action_requested.emit("edit_text")
		"缩小": surface.transform_selected(0.85, 0)
		"放大": surface.transform_selected(1.15, 0)
		"左转": surface.transform_selected(1, -PI / 12)
		"右转": surface.transform_selected(1, PI / 12)
		"删除": surface.remove_selected()
		"取消":
			surface.state.selected = -1
			surface.queue_redraw()
			update_controls()

func _request_tool(tool: String) -> void:
	tool_requested.emit(tool)

func _request_action(action: String) -> void:
	action_requested.emit(action)

func _on_width_changed(value: float) -> void:
	var width := int(value)
	surface.pen_width = width
	width_label.text = "粗细  %d" % width
	print("DRAW_WIDTH:", width)
	width_changed.emit(width)

func _on_artwork_changed() -> void:
	update_controls()
	artwork_changed.emit()
