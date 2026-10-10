extends Control

## Coordinates navigation, session state, dialogs and persistence.
## Each complex page owns its controls and updates its existing scene in place.
const PAGE_SCENES = {
	"home": preload("res://scenes/pages/home.tscn"),
	"levels": preload("res://scenes/pages/levels.tscn"),
	"canvas": preload("res://scenes/pages/canvas.tscn"),
	"gallery": preload("res://scenes/pages/gallery.tscn"),
	"settings": preload("res://scenes/pages/settings.tscn"),
}
const DIALOG_SCENES = {
	"palette": preload("res://scenes/dialogs/palette.tscn"),
	"text_editor": preload("res://scenes/dialogs/text_editor.tscn"),
	"sticker_picker": preload("res://scenes/dialogs/sticker_picker.tscn"),
	"restart_confirmation": preload("res://scenes/dialogs/restart_confirmation.tscn"),
	"submission_result": preload("res://scenes/dialogs/submission_result.tscn"),
	"save_confirmation": preload("res://scenes/dialogs/save_confirmation.tscn"),
	"work_view": preload("res://scenes/dialogs/work_view.tscn"),
	"open_work_confirmation": preload("res://scenes/dialogs/open_work_confirmation.tscn"),
	"image_view": preload("res://scenes/dialogs/image_view.tscn"),
	"reset_confirmation": preload("res://scenes/dialogs/reset_confirmation.tscn"),
	"info": preload("res://scenes/dialogs/info.tscn"),
	"busy": preload("res://scenes/dialogs/busy.tscn"),
	"sticker_catalog": preload("res://scenes/dialogs/sticker_catalog.tscn"),
}

const INK = Color("243d35")
const MUTED = Color("77736a")
const RED = Color("a44332")
const CanvasPage = preload("res://scripts/pages/canvas_page.gd")
const GalleryPage = preload("res://scripts/pages/gallery_page.gd")
const GalleryEntries = preload("res://scripts/gallery_entries.gd")
const LevelProgress = preload("res://scripts/level_progress.gd")
const SettingsPage = preload("res://scripts/pages/settings_page.gd")
const SettingsStore = preload("res://scripts/settings_store.gd")
const ContentCatalog = preload("res://scripts/content_catalog.gd")
const PaletteDialog = preload("res://scripts/dialogs/palette_dialog.gd")
const TextEditorDialog = preload("res://scripts/dialogs/text_editor_dialog.gd")
const DraftCache = preload("res://scripts/draft_cache.gd")
var draft_cache := DraftCache.new()
var content_catalog := ContentCatalog.new()
var _draft_save_pending := false
var _settings_pending := false
const LocalStore = preload("res://scripts/local_store.gd")
var local_store := LocalStore.new()
var storage_hint: Label
var storage_retry: Button
var gallery_page := 0
var storage_status := ""
const Drawing = preload("res://scripts/drawing_surface.gd")
var web_blur_callback: JavaScriptObject
var drawings: Dictionary = {}
var completed_topics: Array[int] = []
var drawing: Drawing
var pen_color := INK
var pen_width := 12
var submitting := false
var page: Control
var overlay: Control
var current := "home"
var topic := 0
var gallery_tab := 0
var gallery_filter := "全部"
var selected_tool := "笔刷"
var settings := SettingsStore.defaults()
var settings_store := SettingsStore.new()
var settings_status := ""
var is_busy := false
var suspended_focus: Array[Control] = []
var previous_focus: Control
@onready var page_host: Control = $PageHost
@onready var dialog_host: Control = $DialogHost
@onready var preference_save_timer: Timer = $PreferenceSaveTimer

func _ready() -> void:
	settings = settings_store.load_settings()
	if OS.has_feature("web"):
		web_blur_callback = JavaScriptBridge.create_callback(_web_focus_lost)
		JavaScriptBridge.get_interface("window").addEventListener("blur", web_blur_callback)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", web_blur_callback)
		JavaScriptBridge.get_interface("window").addEventListener("pagehide", web_blur_callback)
		JavaScriptBridge.get_interface("window").addEventListener("beforeunload", web_blur_callback)
	local_store.read_document()
	completed_topics = LevelProgress.completed_from_document(local_store.document)
	for key in local_store.document.drafts:
		drawings[int(key)] = LocalStore.decode(local_store.document.drafts[key])
		draft_cache.seed(int(key), drawings[int(key)], local_store.document.drafts[key])
	topic = int(local_store.document.topic)
	pen_color = Color.html(local_store.document.tools.color)
	pen_width = int(local_store.document.tools.width)
	selected_tool = local_store.document.tools.tool
	show_page(local_store.document.page)

func _web_focus_lost(_arguments: Array) -> void:
	if is_instance_valid(drawing): drawing.finish()
	flush_pending_saves()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(page): _web_focus_lost([])

func _exit_tree() -> void:
	flush_pending_saves()
	if OS.has_feature("web") and web_blur_callback:
		JavaScriptBridge.get_interface("window").removeEventListener("blur", web_blur_callback)
		JavaScriptBridge.get_interface("document").removeEventListener("visibilitychange", web_blur_callback)
		JavaScriptBridge.get_interface("window").removeEventListener("pagehide", web_blur_callback)
		JavaScriptBridge.get_interface("window").removeEventListener("beforeunload", web_blur_callback)

func show_page(id: String) -> void:
	if is_busy or submitting: return
	is_busy = true
	if is_instance_valid(drawing): drawing.finish()
	flush_pending_saves()
	close_overlay()
	for child in page_host.get_children():
		page_host.remove_child(child)
		child.queue_free()
	drawing = null
	current = id if PAGE_SCENES.has(id) else "home"
	if current == "canvas" and not _topic_unlocked(topic): current = "levels"
	page = PAGE_SCENES[current].instantiate()
	if current == "canvas":
		if not drawings.has(topic): drawings[topic] = Drawing.new_state(_topic_background(topic))
		var view: CanvasPage = page
		view.prepare(drawings[topic], topic, content_catalog.get_topic(topic).prompt)
		drawing = view.surface
	page_host.add_child(page)
	bind_button(page, "Frame/BackButton", show_page.bind("home"))
	storage_hint = page.get_node("Frame/StorageHint")
	storage_retry = page.get_node("Frame/StorageRetry")
	storage_retry.pressed.connect(retry_storage)
	match current:
		"home": home()
		"levels": levels()
		"canvas": canvas()
		"gallery": gallery()
		"settings": settings_page()
	is_busy = false
	autosave()
	print("UI_PAGE:", current)

func bind_button(view: Node, path: NodePath, callback: Callable) -> void:
	var button: BaseButton = view.get_node(path)
	button.pressed.connect(callback)

func home() -> void:
	bind_button(page, "LevelsButton", show_page.bind("levels"))
	bind_button(page, "FreeDrawButton", _start_topic.bind(-1))
	bind_button(page, "GalleryButton", _show_gallery.bind(1))
	bind_button(page, "SettingsButton", show_page.bind("settings"))
	bind_button(page, "ExitButton", exit_info)

func _start_topic(id: int) -> void:
	if not _allow_topic(id): return
	topic = id
	show_page("canvas")

func _topic_unlocked(id: int) -> bool:
	return LevelProgress.is_unlocked(id, completed_topics, content_catalog.topic_ids())

func _allow_topic(id: int) -> bool:
	if _topic_unlocked(id): return true
	info("关卡未解锁", "先保存上一关的完成作品。")
	return false

func _topic_background(id: int) -> String:
	return content_catalog.get_topic(id).background_id

func _show_gallery(tab: int) -> void:
	gallery_tab = tab
	if tab == 0: gallery_page = 0
	show_page("gallery")

func levels() -> void:
	for id in content_catalog.topic_ids():
		var definition := content_catalog.get_topic(id)
		var card: Control = page.get_node(definition.node_path)
		var status: Label = card.get_node("Status")
		var unlocked := _topic_unlocked(id)
		status.visible = true
		status.text = "已完成" if id in completed_topics else "待完成" if unlocked else "未解锁"
		var enter: Button = card.get_node("EnterButton")
		enter.disabled = not unlocked
		enter.text = "重画" if id in completed_topics else "开始" if unlocked else "未解锁"
		bind_button(card, "EnterButton", _start_topic.bind(id))

func canvas() -> void:
	var view: CanvasPage = page
	view.tool_requested.connect(set_tool)
	view.width_changed.connect(_set_pen_width)
	view.action_requested.connect(_canvas_action)
	view.artwork_changed.connect(autosave)
	view.refresh_tools(selected_tool, pen_color, pen_width)

func _canvas_action(action: String) -> void:
	match action:
		"levels": show_page("levels")
		"text": text_editor(false)
		"edit_text": text_editor(true)
		"stickers": sticker_picker()
		"palette": palette_dialog()
		"reference": sticker_list()
		"restart": restart_confirm()
		"submit": submit_artwork()

func _set_pen_width(width: int) -> void:
	pen_width = width
	queue_autosave()

func _refresh_canvas_tools() -> void:
	var view: CanvasPage = page
	view.refresh_tools(selected_tool, pen_color, pen_width)

func set_tool(tool: String) -> void:
	drawing.finish()
	selected_tool = tool
	_refresh_canvas_tools()
	autosave()
	# Keep the existing browser automation's active-page notification.
	print("UI_PAGE:canvas")

func palette_dialog() -> void:
	drawing.finish()
	var view: PaletteDialog = modal("palette")
	view.color_applied.connect(apply_color)
	view.configure(pen_color)

func apply_color(color: Color) -> void:
	pen_color = color
	close_overlay()
	set_tool("笔刷")
	print("COLOR_CHANGED:", color.to_html(false))

func text_editor(edit: bool) -> void:
	drawing.finish()
	if not edit and drawings[topic].objects.size() >= 25:
		info("数量已满", "文字和贴纸最多 24 个，删除一个后再添加。")
		return
	var object: Dictionary = drawing.selected_object() if edit else {}
	var view: TextEditorDialog = modal("text_editor", "编辑文字" if edit else "")
	view.text_applied.connect(_apply_text.bind(edit))
	view.configure(object, pen_color)

func _apply_text(text: String, font_size: int, color: Color, edit: bool) -> void:
	selected_tool = "移动"
	_refresh_canvas_tools()
	if edit: drawing.edit_text(text, font_size, color)
	else: drawing.add_object("text", text, font_size, color)
	close_overlay()
	print("UI_PAGE:canvas")
	print("TEXT_APPLIED:", text)

func sticker_picker() -> void:
	drawing.finish()
	if drawings[topic].objects.size() >= 25:
		info("数量已满", "文字和贴纸最多 24 个，删除一个后再添加。")
		return
	modal("sticker_picker")
	for item in [["AddDuButton", "weapon_du"], ["AddPinkButton", "weapon_pink"], ["AddSilverButton", "weapon_silver"], ["AddBlueButton", "weapon_blue"], ["AddVioletButton", "weapon_violet"]]:
		var kind: String = item[1]
		bind_button(overlay, item[0], _add_sticker.bind(kind))

func _add_sticker(kind: String) -> void:
	selected_tool = "移动"
	_refresh_canvas_tools()
	drawing.add_object(kind)
	close_overlay()
	print("UI_PAGE:canvas")

func restart_confirm() -> void:
	modal("restart_confirmation")
	bind_button(overlay, "CancelButton", close_overlay)
	bind_button(overlay, "ConfirmButton", _restart_drawing)

func _restart_drawing() -> void:
	drawings[topic] = Drawing.new_state(_topic_background(topic))
	show_page("canvas")

func submit_artwork() -> void:
	if submitting: return
	drawing.finish()
	if not drawing.has_creation():
		info("还没有修改", "画几笔、添加文字或贴纸，也可以移动杜甫。")
		print("SUBMIT_EMPTY")
		return
	var state: Dictionary = drawings[topic]
	if state.submitted != state.revision or state.result == null:
		submitting = true
		modal("busy")
		var captured: Image = await drawing.artwork()
		submitting = false
		state.result = ImageTexture.create_from_image(captured)
		state.submitted = state.revision
	modal("submission_result")
	if topic == -1 or topic in completed_topics or topic == content_catalog.topic_ids().back():
		overlay.get_node("Frame/Body").text = "保存后可在画廊查看。"
	overlay.get_node("Artwork").texture = state.result
	overlay.get_node("Remark").text = content_catalog.get_topic(topic).remark
	bind_button(overlay, "ContinueButton", close_overlay)
	if not state.get("work_id", "").is_empty(): overlay.get_node("SaveButton").text = "保存新版本"
	bind_button(overlay, "SaveButton", save_work.bind(false))
	bind_button(overlay, "SaveAsButton", save_work.bind(true))
	bind_button(overlay, "DownloadButton", _download_texture.bind(state.result))
	autosave()
	print("SUBMIT_OK:", topic, ":", state.submitted)

func storage_candidate() -> Dictionary:
	var candidate: Dictionary = local_store.document.duplicate(true)
	for key in drawings: candidate.drafts[str(key)] = draft_cache.encode(key, drawings[key])
	candidate.page = current
	candidate.topic = topic
	candidate.completed_topics = completed_topics.duplicate()
	candidate.tools = {"color":pen_color.to_html(false),"width":pen_width,"tool":selected_tool}
	return candidate

func update_storage_status(ok: bool) -> void:
	if is_instance_valid(storage_retry): storage_retry.visible = not ok
	storage_status = ("草稿已保存" if current == "canvas" else "") if ok else local_store.error
	if is_instance_valid(storage_hint):
		storage_hint.text = storage_status
		storage_hint.add_theme_color_override("font_color", MUTED if ok else RED)
	print("STORAGE_OK" if ok else "STORAGE_ERROR:", "" if ok else local_store.error)

func autosave() -> void:
	if not is_instance_valid(page): return
	var saved_ok := local_store.write_document(storage_candidate())
	# Failed writes remain pending for retry, focus loss or exit; no retry loop.
	_draft_save_pending = not saved_ok
	update_storage_status(saved_ok)
	if saved_ok and current == "gallery": _refresh_gallery()

func queue_autosave() -> void:
	_draft_save_pending = true
	preference_save_timer.start()

func queue_settings_save() -> void:
	_settings_pending = true
	preference_save_timer.start()

func flush_pending_saves() -> void:
	preference_save_timer.stop()
	if _draft_save_pending: autosave()
	if _settings_pending:
		_settings_pending = false
		save_settings()

func retry_storage() -> void:
	if not local_store.writable:
		var retry := LocalStore.new()
		if retry.read_document():
			local_store = retry
			completed_topics = LevelProgress.completed_from_document(local_store.document)
			for key in local_store.document.drafts:
				var restored_topic := int(key)
				if not drawings.has(restored_topic) or drawings[restored_topic].revision == 0:
					drawings[restored_topic] = LocalStore.decode(local_store.document.drafts[key])
					draft_cache.seed(restored_topic, drawings[restored_topic], local_store.document.drafts[key])
			show_page(current)
			return
	autosave()
	if not local_store.error.is_empty(): info("保存失败", local_store.error)

func save_work(as_new: bool) -> void:
	var state: Dictionary = drawings[topic]
	if state.result == null or state.submitted != state.revision:
		info("作品有新修改", "返回画布，点击“完成作品”后再保存。")
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
	var encoded: Dictionary = candidate.drafts[str(topic)]
	encoded.work_id = id
	var title: String = candidate.works[index].title if index >= 0 else content_catalog.get_topic(topic).title + " · " + id.trim_prefix("work-")
	var work := {"id":id,"topic":topic,"title":title,"data":encoded,"preview":Marshalls.raw_to_base64(state.result.get_image().save_png_to_buffer())}
	if index == -1: candidate.works.append(work)
	candidate.drafts[str(topic)] = encoded
	candidate.completed_topics = LevelProgress.mark_completed(topic, completed_topics, content_catalog.topic_ids())
	if not local_store.write_document(candidate):
		# A later flush retries the draft, not the explicitly saved gallery work.
		_draft_save_pending = true
		update_storage_status(false)
		info("保存失败", local_store.error + "\n可重新打开“完成作品”，下载图片备份。")
		return
	_draft_save_pending = false
	state.work_id = id
	completed_topics = LevelProgress.completed_from_document(local_store.document)
	update_storage_status(true)
	var ids := content_catalog.topic_ids()
	var next_index := ids.find(topic) + 1
	var has_next := topic >= 0 and next_index < ids.size()
	var message := title
	if has_next: message += "\n下一关已解锁：" + content_catalog.get_topic(ids[next_index]).title
	elif topic >= 0: message += "\n全部关卡已完成。"
	modal("save_confirmation", "", message)
	bind_button(overlay, "ContinueButton", close_overlay)
	bind_button(overlay, "GalleryButton", _show_gallery.bind(0))
	overlay.get_node("NextButton").text = "下一关" if has_next else "选关"
	if has_next: bind_button(overlay, "NextButton", _start_topic.bind(ids[next_index]))
	else: bind_button(overlay, "NextButton", show_page.bind("levels"))
	print("WORK_SAVED:", id, ":", local_store.document.works.size())

func work_texture(work: Dictionary) -> ImageTexture:
	var image := Image.new()
	image.load_png_from_buffer(Marshalls.base64_to_raw(work.preview))
	return ImageTexture.create_from_image(image)

func _refresh_gallery() -> void:
	var view: GalleryPage = page
	var entries := GalleryEntries.build(local_store.document, _gallery_topic_title)
	view.refresh(entries, gallery_tab, gallery_filter, gallery_page, work_texture)
	gallery_page = view.page_index

func _gallery_topic_title(id: int) -> String:
	return content_catalog.get_topic(id).title

func _set_gallery_tab(value: int) -> void:
	gallery_tab = value
	_refresh_gallery()
	print("UI_PAGE:gallery")

func _set_gallery_filter(value: String) -> void:
	gallery_filter = value
	_refresh_gallery()
	print("UI_PAGE:gallery")

func _set_gallery_page(value: int) -> void:
	gallery_page = value
	_refresh_gallery()
	print("UI_PAGE:gallery")

func view_work(work: Dictionary) -> void:
	modal("work_view", work.title)
	var is_draft: bool = work.get("draft", false)
	var picture: TextureRect = overlay.get_node("Artwork")
	picture.visible = not is_draft
	var preview = overlay.get_node("DraftPreview")
	preview.visible = is_draft
	if is_draft:
		preview.set_state(work.state)
		overlay.get_node("Frame/Body").text = "草稿"
		overlay.get_node("EditButton").text = "继续编辑"
	else:
		picture.texture = work_texture(work)
	bind_button(overlay, "EditButton", open_work_confirm.bind(work))
	overlay.get_node("DownloadButton").visible = not is_draft
	if not is_draft: bind_button(overlay, "DownloadButton", _download_texture.bind(picture.texture))
	print("WORK_VIEW:", work.id)

func open_work_confirm(work: Dictionary) -> void:
	if not _allow_topic(int(work.topic)): return
	if work.get("draft", false):
		_open_draft(work)
		return
	modal("open_work_confirmation")
	bind_button(overlay, "CancelButton", close_overlay)
	bind_button(overlay, "ConfirmButton", _open_work.bind(work))

func _open_draft(work: Dictionary) -> void:
	if not _allow_topic(int(work.topic)): return
	topic = int(work.topic)
	# Continue the live draft, including undo history and any writes still pending.
	# A persisted gallery snapshot must never replace newer unsaved edits.
	if not drawings.has(topic): drawings[topic] = LocalStore.decode(work.data)
	show_page("canvas")
	print("DRAFT_OPEN:", topic)

func _open_work(work: Dictionary) -> void:
	if not _allow_topic(int(work.topic)): return
	topic = int(work.topic)
	drawings[topic] = LocalStore.decode(work.data)
	drawings[topic].work_id = work.id
	selected_tool = "移动"
	show_page("canvas")
	print("WORK_OPEN:", work.id)

func _download_texture(texture: Texture2D) -> void:
	download_image(texture.get_image())

func download_image(image: Image) -> void:
	var filename := "dufu-artwork.png"
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(image.save_png_to_buffer(), filename, "image/png")
		print("PNG_DOWNLOAD_REQUESTED")
	else:
		var path := "user://" + filename
		if image.save_png(path) == OK: info("图片已导出", ProjectSettings.globalize_path(path))
		else: info("导出失败", "无法写入文件，请检查存储空间和写入权限。")

func gallery() -> void:
	var view: GalleryPage = page
	view.tab_requested.connect(_set_gallery_tab)
	view.filter_requested.connect(_set_gallery_filter)
	view.page_requested.connect(_set_gallery_page)
	view.create_requested.connect(show_page.bind("canvas"))
	view.view_work_requested.connect(view_work)
	view.edit_work_requested.connect(open_work_confirm)
	view.example_requested.connect(example)
	_refresh_gallery()

func example(index: int) -> void:
	var definition := content_catalog.get_example(index)
	image_dialog(definition.title, definition.image_path, definition.category + " · 示例", "返回画廊")

func image_dialog(title: String, path: String, caption: String, back_label: String, back_action: Callable = Callable()) -> void:
	modal("image_view", title, caption)
	overlay.get_node("Picture").texture = load(path) as Texture2D
	overlay.get_node("BackButton").text = back_label
	bind_button(overlay, "BackButton", back_action if back_action.is_valid() else close_overlay)

func settings_page() -> void:
	var view: SettingsPage = page
	view.preference_changed.connect(_set_preference)
	view.reset_requested.connect(reset_confirm)
	view.refresh(settings, settings_status)

func _set_preference(key: String, value: Variant) -> void:
	settings[key] = value
	if key == "volume":
		queue_settings_save()
	else:
		_settings_pending = false
		save_settings()

func update_settings_note() -> void:
	if current == "settings" and is_instance_valid(page):
		var view: SettingsPage = page
		view.update_status(settings_status)

func save_settings() -> void:
	_settings_pending = false
	settings = SettingsStore.normalize(settings)
	var saved_ok := settings_store.save_settings(settings)
	_settings_pending = not saved_ok
	settings_status = "已保存" if saved_ok else "设置保存失败，请检查存储空间后重试。"
	update_settings_note()

func reset_confirm() -> void:
	modal("reset_confirmation")
	bind_button(overlay, "ConfirmButton", _reset_settings)
	bind_button(overlay, "CancelButton", close_overlay)

func _reset_settings() -> void:
	settings = SettingsStore.defaults()
	_settings_pending = false
	save_settings()
	close_overlay()
	var view: SettingsPage = page
	view.refresh(settings, settings_status)

func exit_info() -> void:
	info("退出游戏", "直接关闭窗口或浏览器标签页即可。")

func modal(scene_id: String, title: String = "", body: String = "") -> Control:
	close_overlay()
	previous_focus = get_viewport().gui_get_focus_owner()
	for control in page.find_children("*", "Control", true, false):
		if control.focus_mode != Control.FOCUS_NONE:
			control.set_meta("previous_focus_mode", control.focus_mode)
			suspended_focus.append(control)
			control.focus_mode = Control.FOCUS_NONE
	overlay = DIALOG_SCENES[scene_id].instantiate()
	if not title.is_empty(): overlay.get_node("Frame/Title").text = title
	if not body.is_empty(): overlay.get_node("Frame/Body").text = body
	dialog_host.add_child(overlay)
	var close_button: Button = overlay.get_node("Frame/CloseButton")
	close_button.pressed.connect(close_overlay)
	if close_button.visible: close_button.grab_focus()
	print("UI_DIALOG:", overlay.get_node("Frame/Title").text)
	return overlay

func info(title: String, body: String) -> void:
	modal("info", title, body)
	bind_button(overlay, "OkayButton", close_overlay)

func sticker_list() -> void:
	modal("sticker_catalog")
	bind_button(overlay, "WeaponButton", sticker_picker)
	bind_button(overlay, "CityButton", image_dialog.bind("科幻都市", "res://assets/backgrounds/scifi-city.jpg", "参考图片", "返回素材", sticker_list))
	bind_button(overlay, "MarketButton", image_dialog.bind("烟火夜市", "res://assets/backgrounds/night-market.jpg", "参考图片", "返回素材", sticker_list))
	bind_button(overlay, "BackButton", close_overlay)

func close_overlay() -> void:
	for control in suspended_focus:
		if is_instance_valid(control):
			control.focus_mode = control.get_meta("previous_focus_mode", Control.FOCUS_ALL)
	suspended_focus.clear()
	if is_instance_valid(overlay):
		dialog_host.remove_child(overlay)
		overlay.queue_free()
	overlay = null
	if is_instance_valid(previous_focus) and previous_focus.is_inside_tree() and previous_focus.is_visible_in_tree():
		previous_focus.grab_focus()
	previous_focus = null

func _unhandled_key_input(event: InputEvent) -> void:
	if submitting: return
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(overlay): close_overlay()
		elif current == "canvas" and drawings[topic].selected >= 0:
			var view: CanvasPage = page
			view.object_action("取消")
		elif current != "home": show_page("home")
		get_viewport().set_input_as_handled()
