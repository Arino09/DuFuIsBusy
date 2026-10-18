@tool
extends Control
## Build each category from the same registry used by saved artwork.
signal sticker_selected(kind: String)

const Stickers = preload("res://scripts/sticker_catalog.gd")
var category_buttons: Dictionary = {}
var _mobile_layout := false
var _available_width := 0.0

func _ready() -> void:
	for category in Stickers.CATEGORIES:
		var entry: Dictionary = Stickers.CATEGORIES[category]
		var button := Button.new()
		button.name = category
		button.text = "%s · %d" % [entry.label, entry.ids.size()]
		button.custom_minimum_size = Vector2(180, 44)
		button.toggle_mode = true
		button.theme_type_variation = &"SelectableButton"
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(show_category.bind(category))
		$Categories.add_child(button)
		category_buttons[category] = button
	show_category("food")

func show_category(category: String) -> void:
	for key in category_buttons:
		category_buttons[key].set_pressed_no_signal(key == category)
	for card in $Scroll/Grid.get_children():
		$Scroll/Grid.remove_child(card)
		card.queue_free()
	$Scroll.scroll_vertical = 0
	for kind in Stickers.CATEGORIES[category].ids:
		var card := PanelContainer.new()
		card.name = kind
		card.custom_minimum_size = Vector2(184, 240)
		card.add_theme_stylebox_override("panel", $Scroll/Grid.get_theme_stylebox("panel", "StickerCard"))
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 6)
		card.add_child(column)
		var preview := TextureRect.new()
		preview.name = "Preview"
		preview.custom_minimum_size = Vector2(0, 140)
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture = Stickers.TEXTURES[kind]
		column.add_child(preview)
		var label := Label.new()
		label.name = "Name"
		label.text = Stickers.NAMES[kind]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 23)
		column.add_child(label)
		var button := Button.new()
		button.name = "UseButton"
		button.text = "使用"
		button.tooltip_text = "添加%s到画布" % Stickers.NAMES[kind]
		button.custom_minimum_size.y = 40
		button.theme_type_variation = &"PrimaryButton"
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		column.add_child(button)
		column.name = "Content"
		_configure_card(card)
		$Scroll/Grid.add_child(card)
		# Let the automatic audio binding run before selecting removes this dialog.
		button.pressed.connect(func(): sticker_selected.emit(kind))
	_update_cards()

func set_mobile_layout(enabled: bool, available_width: float = 0.0) -> void:
	_mobile_layout = enabled
	_available_width = available_width
	$Categories.add_theme_constant_override("h_separation", 8 if enabled else 12)
	for button in category_buttons.values():
		button.custom_minimum_size = Vector2(124 if enabled else 180, 48 if enabled else 44)
		if enabled: button.add_theme_font_size_override("font_size", 18)
		else: button.remove_theme_font_size_override("font_size")
	_update_cards()

func _update_cards() -> void:
	if not is_node_ready(): return
	var grid: GridContainer = $Scroll/Grid
	grid.columns = 2 if _mobile_layout else 5
	grid.add_theme_constant_override("h_separation", 8 if _mobile_layout else 12)
	for card in grid.get_children():
		_configure_card(card)

func _configure_card(card: PanelContainer) -> void:
	# Configure before adding to the grid, so a category change never briefly
	# forces its parent back to the desktop column width.
	var card_width := maxf(100.0, (_available_width - 24.0) / 2.0) if _mobile_layout else 184.0
	card.custom_minimum_size = Vector2(card_width, 232 if _mobile_layout else 240)
	var preview: TextureRect = card.get_node("Content/Preview")
	preview.custom_minimum_size.y = 100 if _mobile_layout else 140
	var label: Label = card.get_node("Content/Name")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if _mobile_layout else TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.y = 46 if _mobile_layout else 0
	label.add_theme_font_size_override("font_size", 18 if _mobile_layout else 23)
	var button: Button = card.get_node("Content/UseButton")
	button.custom_minimum_size.y = 48 if _mobile_layout else 40
	if _mobile_layout: button.add_theme_font_size_override("font_size", 20)
	else: button.remove_theme_font_size_override("font_size")
