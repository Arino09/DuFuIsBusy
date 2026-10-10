extends RefCounted
## Synchronous, atomic same-browser storage. No reliance on Web IDBFS flush timing.
const VERSION = 2
const KEY = "DuFuIsBusy.art.v2"
const PATH = "user://art-v2.json"
const TEMP_PATH = "user://art-v2.tmp"
const Drawing = preload("res://scripts/drawing_surface.gd")
const Backgrounds = preload("res://scripts/artwork_backgrounds.gd")
var document: Dictionary = empty_document()
var previous_raw := ""
var writable := true
var error := ""

static func empty_document() -> Dictionary:
	return {"version": VERSION, "drafts": {}, "works": [], "completed_topics": [], "next_id": 1, "topic": 0, "page": "home", "tools": {"color": "243d35", "width": 12, "tool": "笔刷"}}

static func encode(state: Dictionary) -> Dictionary:
	var objects: Array = []
	for object in state.objects:
		objects.append({"id": object.id, "kind": object.kind, "position": [object.position.x, object.position.y], "scale": object.scale, "rotation": object.rotation, "text": object.get("text", ""), "font_size": object.get("font_size", 32), "color": object.get("color", Color("243d35")).to_html(false)})
	return {"background_id": state.background_id, "pixels": Marshalls.raw_to_base64(state.pixels.save_png_to_buffer()), "objects": objects, "next_id": state.next_id, "revision": state.revision, "submitted": state.submitted, "work_id": state.get("work_id", "")}

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func decode(data: Variant) -> Dictionary:
	if not data is Dictionary or not data.get("pixels") is String or not data.get("objects") is Array: return {}
	var background: Variant = data.get("background_id")
	if not background is String or not Backgrounds.is_valid(background): return {}
	if data.pixels.length() > 4000000 or data.objects.is_empty() or data.objects.size() > 25: return {}
	var pixels := Image.new()
	if pixels.load_png_from_buffer(Marshalls.base64_to_raw(data.pixels)) != OK or pixels.get_size() != Vector2i(Drawing.WIDTH, Drawing.HEIGHT): return {}
	pixels.convert(Image.FORMAT_RGBA8)
	var state := Drawing.new_state(background)
	state.pixels = pixels
	state.objects = []
	var ids: Array = []
	for index in range(data.objects.size()):
		var item: Variant = data.objects[index]
		if not item is Dictionary: return {}
		if not item.get("kind") in ["avatar", "text"] and not Drawing.STICKER_TEXTURES.has(item.get("kind")): return {}
		if (index == 0) != (item.kind == "avatar"): return {}
		if not number(item.get("id")) or item.id < 0 or item.id != int(item.id) or ids.has(int(item.id)): return {}
		ids.append(int(item.id))
		if not item.get("position") is Array or item.position.size() != 2: return {}
		if not number(item.position[0]) or not number(item.position[1]): return {}
		if item.position[0] < 0 or item.position[0] > Drawing.WIDTH or item.position[1] < 0 or item.position[1] > Drawing.HEIGHT: return {}
		if not number(item.get("scale")) or item.scale <= 0 or item.scale > 2: return {}
		if not number(item.get("rotation")) or absf(item.rotation) > PI + 0.001: return {}
		if item.kind == "avatar" and item.rotation != 0: return {}
		if not item.get("text") is String or item.text.length() > 24: return {}
		if item.kind == "text" and item.text.strip_edges().is_empty(): return {}
		if not number(item.get("font_size")) or item.font_size < 16 or item.font_size > 64: return {}
		if not item.get("color") is String or item.color.length() != 6 or not Color.html_is_valid(item.color): return {}
		state.objects.append({"id":int(item.id), "kind":item.kind, "position":Vector2(item.position[0],item.position[1]), "scale":float(item.scale), "rotation":float(item.rotation), "text":item.text, "font_size":int(item.font_size), "color":Color.html(item.color)})
	for field in ["next_id", "revision", "submitted"]:
		if not number(data.get(field)) or data[field] != int(data[field]): return {}
	if data.next_id <= ids.max() or data.revision < 0 or data.submitted < -1 or data.submitted > data.revision: return {}
	if not data.get("work_id") is String: return {}
	state.next_id = int(data.next_id)
	state.revision = int(data.revision)
	state.submitted = int(data.submitted)
	state.work_id = data.work_id
	return state

func read_document() -> bool:
	var raw: Variant
	if OS.has_feature("web"):
		raw = JavaScriptBridge.eval("(function(){try{return JSON.stringify({ok:true,value:localStorage.getItem('%s')||''});}catch(e){return JSON.stringify({ok:false});}})()" % KEY)
		var response: Variant = JSON.parse_string(raw) if raw is String else null
		if not response is Dictionary or not response.get("ok", false):
			writable = false
			error = "浏览器存储不可用；创作仅在内存中，关闭会丢失。"
			return false
		raw = response.value
	else:
		raw = FileAccess.get_file_as_string(PATH) if FileAccess.file_exists(PATH) else ""
	previous_raw = raw
	if raw.is_empty(): return true
	var parser := JSON.new()
	var parsed_ok := parser.parse(raw) == OK
	var data: Variant = parser.data if parsed_ok else null
	if not validate_document(data):
		writable = false
		error = "本地存档格式异常，已保护原数据，停止写入；请勿清理浏览器数据。"
		return false
	document = data
	return true

static func validate_document(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION: return false
	if not data.get("drafts") is Dictionary or not data.get("works") is Array: return false
	if not data.get("completed_topics") is Array: return false
	var completed: Array = []
	for id in data.completed_topics:
		if not number(id) or id != int(id) or not int(id) in [0, 1, 2, 3] or int(id) in completed: return false
		completed.append(int(id))
	if not number(data.get("next_id")) or data.next_id < 1 or data.next_id != int(data.next_id): return false
	if not data.get("page") in ["home", "levels", "canvas", "gallery", "settings"] or not number(data.get("topic")): return false
	if data.topic != int(data.topic) or not int(data.topic) in [-1,0,1,2,3]: return false
	if not data.get("tools") is Dictionary: return false
	var tools: Dictionary = data.tools
	if not tools.get("color") is String or tools.color.length() != 6 or not Color.html_is_valid(tools.color): return false
	if not number(tools.get("width")) or tools.width < 4 or tools.width > 56 or not tools.get("tool") in ["笔刷", "橡皮", "移动"]: return false
	for key in data.drafts:
		if not key in ["-1", "0", "1", "2", "3"] or decode(data.drafts[key]).is_empty(): return false
	var ids: Array = []
	for work in data.works:
		if not work is Dictionary or not work.get("id") is String or ids.has(work.id): return false
		if not work.id.begins_with("work-") or not work.id.trim_prefix("work-").is_valid_int(): return false
		if int(work.id.trim_prefix("work-")) < 1 or int(work.id.trim_prefix("work-")) >= data.next_id: return false
		ids.append(work.id)
		if not number(work.get("topic")) or not int(work.topic) in [-1,0,1,2,3] or not work.get("title") is String: return false
		if decode(work.get("data")).is_empty() or not work.get("preview") is String: return false
		var picture := Image.new()
		if work.preview.length() > 4000000 or picture.load_png_from_buffer(Marshalls.base64_to_raw(work.preview)) != OK or picture.get_size() != Vector2i(Drawing.WIDTH, Drawing.HEIGHT): return false
	return true

func write_document(candidate: Dictionary) -> bool:
	if not writable: return false
	var raw := JSON.stringify(candidate)
	if OS.has_feature("web"):
		var code := "(function(){try{if((localStorage.getItem(%s)||'')!==%s)return 'conflict';localStorage.setItem(%s,%s);return 'ok';}catch(e){return e.name==='QuotaExceededError'?'quota':'unavailable';}})()" % [JSON.stringify(KEY),JSON.stringify(previous_raw),JSON.stringify(KEY),JSON.stringify(raw)]
		var result: Variant = JavaScriptBridge.eval(code)
		if result != "ok":
			if result == "conflict": error = "其他标签页已修改存档；本页未覆盖。请先导出当前画作，再刷新。"
			elif result == "quota": error = "存储空间不足，尚未保存；请导出 PNG 备份，再整理浏览器存储。"
			else: error = "浏览器拒绝写入，尚未保存；请导出 PNG 并检查站点存储权限。"
			return false
	else:
		var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
		if file == null:
			error = "本地文件无法写入，尚未保存。"
			return false
		file.store_string(raw)
		file.flush()
		var status := file.get_error()
		file.close()
		if status != OK or DirAccess.rename_absolute(TEMP_PATH, PATH) != OK:
			error = "本地写入失败，尚未保存。"
			return false
	document = candidate
	previous_raw = raw
	error = ""
	return true
