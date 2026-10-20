extends Node
## A compact, touch-sized layout shares the same controls and session as desktop.
const LayoutState = preload("res://scripts/ui/layout_state.gd")
const MobilePages = preload("res://scripts/ui/mobile_pages.gd")
const MobileDialogs = preload("res://scripts/ui/mobile_dialogs.gd")
const DESKTOP_SIZE := Vector2i(1440, 900)

var app: Control
var compact := false
var _pending := false
var _applying := false
var _page: Control
var _dialog: Control
var _page_state = LayoutState.new()
var _dialog_state = LayoutState.new()
var _signature := Vector3.ZERO
var _poll := 0.0

func setup(controller: Control) -> void:
	app = controller
	get_window().size_changed.connect(refresh)
	_update_scale()

func refresh() -> void:
	if _pending or _applying: return
	_pending = true
	_apply.call_deferred()

func close_canvas_tools() -> bool:
	return is_instance_valid(app.page) and app.current == "canvas" and app.page.workspace_layout.close_tools()

func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.2: return
	_poll = 0
	var css := _device_extent()
	var signature := Vector3(css.x, css.y, _keyboard_height())
	if signature != _signature:
		_signature = signature
		refresh()

func _device_extent() -> Vector2:
	var pixels := Vector2(get_window().size)
	if OS.has_feature("web"):
		# Godot's Web canvas can use device pixels; breakpoints use CSS pixels.
		var browser = JavaScriptBridge.get_interface("window")
		if float(browser.innerWidth) > 0:
			return pixels * float(browser.innerWidth) / maxf(1, pixels.x)
	elif OS.has_feature("android") or OS.has_feature("ios"):
		return pixels / maxf(1, DisplayServer.screen_get_dpi() / 160.0)
	return pixels

func _update_scale() -> void:
	var extent := _device_extent()
	var touch_platform := OS.has_feature("android") or OS.has_feature("ios")
	if OS.has_feature("web"):
		touch_platform = float(JavaScriptBridge.get_interface("navigator").maxTouchPoints) > 0
	compact = extent.x >= 200 and extent.y >= 160 and (extent.x < 1000 or extent.y < 600 or (touch_platform and extent.x < 1440))
	var design := DESKTOP_SIZE
	if compact:
		extent *= maxf(1, 320.0 / extent.x)
		design = Vector2i(extent.round())
	if get_window().content_scale_size != design:
		get_window().content_scale_size = design

func _keyboard_height() -> float:
	if OS.has_feature("web"):
		var browser = JavaScriptBridge.get_interface("window")
		var visual = browser.visualViewport
		if visual != null:
			return maxf(0, float(browser.innerHeight) - float(visual.height))
	elif OS.has_feature("android") or OS.has_feature("ios"):
		return DisplayServer.virtual_keyboard_get_height() / maxf(1, get_window().get_final_transform().get_scale().y)
	return 0

func _usable_rect() -> Rect2:
	var bounds := Rect2(Vector2.ZERO, app.get_viewport_rect().size)
	if OS.has_feature("android") or OS.has_feature("ios"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var window_bounds := Rect2(Vector2(get_window().position), Vector2(get_window().size))
		safe = safe.intersection(window_bounds)
		if safe.has_area():
			bounds = get_window().get_final_transform().affine_inverse() * Rect2(safe.position - window_bounds.position, safe.size)
	elif OS.has_feature("web"):
		# Read CSS safe-area insets without depending on a custom export shell.
		var insets = JavaScriptBridge.eval("(function(){var e=document.createElement('div');e.style.cssText='position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';document.body.appendChild(e);var s=getComputedStyle(e);var v=[s.paddingLeft,s.paddingTop,s.paddingRight,s.paddingBottom].map(parseFloat);e.remove();return JSON.stringify(v)})()")
		var values = JSON.parse_string(str(insets))
		if values is Array and values.size() == 4:
			bounds.position += Vector2(values[0], values[1])
			bounds.size -= Vector2(values[0] + values[2], values[1] + values[3])
	# The browser often resizes its canvas itself; visualViewport contributes only
	# the keyboard area still covering that canvas. Native keyboards overlay it.
	bounds.size.y = maxf(160, bounds.size.y - _keyboard_height())
	return bounds

func _mobile_theme(target: Control, state: RefCounted) -> void:
	var theme := target.theme.duplicate() as Theme
	theme.default_font_size = 20
	for type in theme.get_type_list():
		for key in theme.get_font_size_list(type): theme.set_font_size(key, type, 20)
		for key in theme.get_stylebox_list(type):
			var style := theme.get_stylebox(key, type).duplicate() as StyleBox
			style.content_margin_left = 8
			style.content_margin_right = 8
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			theme.set_stylebox(key, type, style)
	state.put(target, "theme", theme)
	for control in target.find_children("*", "Control", true, false):
		if control.theme != null and control.name != "ColorPalette" and control.name != "Grid": state.put(control, "theme", theme)
		if control is Label or control is BaseButton or control is LineEdit or control is SpinBox or control is RichTextLabel:
			state.font(control, 20)

func _scroll_target(target: Control, host: Control, bounds: Rect2) -> ScrollContainer:
	var scroll: ScrollContainer
	if target.get_parent() is ScrollContainer:
		scroll = target.get_parent()
	else:
		var focused := get_viewport().gui_get_focus_owner()
		scroll = ScrollContainer.new()
		scroll.name = "MobileScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		scroll.follow_focus = true
		scroll.scroll_deadzone = 12
		host.add_child(scroll)
		target.reparent(scroll, false)
		if focused != null and target.is_ancestor_of(focused):
			focused.grab_focus.call_deferred()
			scroll.ensure_control_visible.call_deferred(focused)
	scroll.position = bounds.position
	scroll.size = bounds.size
	return scroll

func _unwrap(target: Control, host: Control) -> void:
	if target.get_parent() == host: return
	var focused := get_viewport().gui_get_focus_owner()
	var wrapper := target.get_parent()
	target.reparent(host, false)
	host.remove_child(wrapper)
	wrapper.queue_free()
	if focused != null and target.is_ancestor_of(focused): focused.grab_focus.call_deferred()

func _page_frame(page: Control, extent: Vector2) -> void:
	var s = _page_state
	for path in ["Frame/BrandTitle", "Frame/HeaderRule", "Frame/Subtitle"]: s.hide(page.get_node(path))
	s.rect(page.get_node("Frame/Title"), Rect2(16, 12, extent.x - 136, 44))
	s.font(page.get_node("Frame/Title"), 30)
	s.rect(page.get_node("Frame/BackButton"), Rect2(extent.x - 116, 8, 100, 56))
	s.rect(page.get_node("Frame/StorageHint"), Rect2(16, extent.y - 36, extent.x - 32, 28))
	s.font(page.get_node("Frame/StorageHint"), 16)
	s.put(page.get_node("Frame/StorageHint"), "clip_text", true)
	s.rect(page.get_node("Frame/StorageRetry"), Rect2(extent.x - 124, extent.y - 64, 108, 56))
	s.font(page.get_node("Frame/StorageRetry"), 18)

func _apply() -> void:
	_pending = false
	if not is_instance_valid(app): return
	_applying = true
	_update_scale()
	var page: Control = app.page
	if is_instance_valid(page):
		if page != _page:
			_page = page
			_page_state = LayoutState.new()
		if compact:
			if app.current == "canvas": page.set_desktop_layout(false)
			var bounds := _usable_rect()
			_mobile_theme(page, _page_state)
			var height := bounds.size.y
			if app.current == "canvas":
				_unwrap(page, app.page_host)
				_page_state.rect(page, bounds)
				_page_frame(page, bounds.size)
				page.workspace_layout.apply(page, bounds.size, _page_state, refresh)
			else:
				var scroll := _scroll_target(page, app.page_host, bounds)
				_page_state.put(page, "mouse_filter", Control.MOUSE_FILTER_PASS)
				height = maxf(height, MobilePages.apply(page, app.current, bounds.size, _page_state))
				_page_state.put(page, "custom_minimum_size", Vector2(bounds.size.x, height))
				_page_state.put(page, "size_flags_horizontal", Control.SIZE_EXPAND_FILL)
				_page_state.rect(page, Rect2(Vector2.ZERO, Vector2(bounds.size.x, height)))
				_page_frame(page, Vector2(bounds.size.x, height))
				scroll.queue_sort()
		else:
			_unwrap(page, app.page_host)
			_page_state.restore()
			if app.current == "canvas": page.set_desktop_layout(true)
	var dialog: Control = app.overlay
	if is_instance_valid(dialog):
		if dialog != _dialog:
			_dialog = dialog
			_dialog_state = LayoutState.new()
		if compact:
			var bounds := _usable_rect()
			_mobile_theme(dialog, _dialog_state)
			var scroll := _scroll_target(dialog, app.dialog_host, bounds)
			_dialog_state.put(dialog, "mouse_filter", Control.MOUSE_FILTER_PASS)
			_dialog_state.put(dialog.get_node("Frame/Shade"), "mouse_filter", Control.MOUSE_FILTER_PASS)
			var id := dialog.scene_file_path.get_file().get_basename()
			var height := maxf(bounds.size.y, MobileDialogs.apply(dialog, id, bounds.size, _dialog_state))
			_dialog_state.put(dialog, "custom_minimum_size", Vector2(bounds.size.x, height))
			_dialog_state.put(dialog, "size_flags_horizontal", Control.SIZE_EXPAND_FILL)
			_dialog_state.rect(dialog, Rect2(Vector2.ZERO, Vector2(bounds.size.x, height)))
			scroll.queue_sort()
			var focus := get_viewport().gui_get_focus_owner()
			if focus != null and dialog.is_ancestor_of(focus): scroll.ensure_control_visible.call_deferred(focus)
		else:
			_unwrap(dialog, app.dialog_host)
			_dialog_state.restore()
			if dialog.has_method("set_mobile_layout"): dialog.set_mobile_layout(false)
	_applying = false
