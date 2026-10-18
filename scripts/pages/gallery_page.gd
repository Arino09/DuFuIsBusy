extends Control
## Owns the authored gallery controls. Navigation and storage stay with the app.

signal tab_requested(tab: int)
signal filter_requested(filter: String)
signal page_requested(index: int)
signal create_requested
signal view_work_requested(work: Dictionary)
signal edit_work_requested(work: Dictionary)
signal example_requested(index: int)

const MY_WORKS_LIGHT = preload("res://assets/ui/gallery/my-works-light.png")
const MY_WORKS_DARK = preload("res://assets/ui/gallery/my-works-dark.png")
const EXAMPLES_LIGHT = preload("res://assets/ui/gallery/examples-light.png")
const EXAMPLES_DARK = preload("res://assets/ui/gallery/examples-dark.png")

var page_index := 0
var _slot_works: Array[Dictionary] = [{}, {}, {}, {}]

@onready var _my_works: Control = $MyWorks
@onready var _examples: Control = $Examples
@onready var _work_cards: Array[Node] = $MyWorks/Cards.get_children()
@onready var _example_cards: Array[Node] = $Examples/Cards.get_children()
@onready var _previous_button: Button = $MyWorks/PreviousButton
@onready var _next_button: Button = $MyWorks/NextButton
@onready var _filter_buttons: Array[Button] = [
	$Examples/FilterAll, $Examples/FilterWuxia, $Examples/FilterSciFi,
	$Examples/FilterMarket, $Examples/FilterFun,
]

func _ready() -> void:
	$MyWorksTab.toggled.connect(func(_pressed: bool): _update_tab_art())
	$ExamplesTab.toggled.connect(func(_pressed: bool): _update_tab_art())
	_update_tab_art()
	$MyWorksTab.pressed.connect(func(): tab_requested.emit(0))
	$ExamplesTab.pressed.connect(func(): tab_requested.emit(1))
	$MyWorks/EmptyState/CreateButton.pressed.connect(func(): create_requested.emit())
	_previous_button.pressed.connect(func(): page_requested.emit(page_index - 1))
	_next_button.pressed.connect(func(): page_requested.emit(page_index + 1))
	for slot in range(_work_cards.size()):
		_work_cards[slot].get_node("ViewButton").pressed.connect(_view_work.bind(slot))
		_work_cards[slot].get_node("EditButton").pressed.connect(_edit_work.bind(slot))
	for button in _filter_buttons:
		button.pressed.connect(_select_filter.bind(button.text))
		button.toggled.connect(func(_pressed: bool): _update_filter_focus(button))
		_update_filter_focus(button)
	for card in _example_cards:
		card.get_node("ViewButton").pressed.connect(_view_example.bind(int(card.get_meta("example_id"))))

func refresh(works: Array, tab: int, filter: String, requested_page: int, texture_provider: Callable) -> void:
	$MyWorksTab.set_pressed_no_signal(tab == 0)
	$ExamplesTab.set_pressed_no_signal(tab == 1)
	_update_tab_art()
	_my_works.visible = tab == 0
	_examples.visible = tab == 1
	page_index = clampi(requested_page, 0, maxi(0, ceili(works.size() / 4.0) - 1))
	if tab == 0:
		_refresh_works(works, texture_provider)
	else:
		_refresh_examples(filter)

func _update_tab_art() -> void:
	$MyWorksTab.icon = MY_WORKS_LIGHT if $MyWorksTab.button_pressed else MY_WORKS_DARK
	$ExamplesTab.icon = EXAMPLES_LIGHT if $ExamplesTab.button_pressed else EXAMPLES_DARK

func _update_filter_focus(button: Button) -> void:
	# Focused text must follow the selected background as well as the focus ring.
	button.add_theme_color_override("font_focus_color", Color("fbfaf5") if button.button_pressed else Color("292824"))

func _refresh_works(works: Array, texture_provider: Callable) -> void:
	var draft_count := 0
	for work in works:
		if work.get("draft", false): draft_count += 1
	$MyWorks/CountLabel.text = "%d 幅草稿，%d 幅完成作品" % [draft_count, works.size() - draft_count]
	$MyWorks/EmptyState.visible = works.is_empty()
	$MyWorks/Cards.visible = not works.is_empty()
	_previous_button.visible = not works.is_empty()
	_next_button.visible = not works.is_empty()
	_previous_button.disabled = page_index == 0
	_next_button.disabled = (page_index + 1) * 4 >= works.size()
	for slot in range(_work_cards.size()):
		var card: Control = _work_cards[slot]
		var index := works.size() - 1 - page_index * 4 - slot
		var occupied := index >= 0
		card.visible = occupied
		card.get_node("ViewButton").disabled = not occupied
		card.get_node("EditButton").disabled = not occupied
		_slot_works[slot] = works[index] if occupied else {}
		card.get_node("Title").text = _slot_works[slot].title if occupied else ""
		var is_draft: bool = occupied and _slot_works[slot].get("draft", false)
		var picture: TextureRect = card.get_node("Picture")
		picture.visible = occupied and not is_draft
		picture.texture = texture_provider.call(_slot_works[slot]) if occupied and not is_draft else null
		var preview = card.get_node("DraftPreview")
		preview.visible = is_draft
		preview.set_state(_slot_works[slot].state if is_draft else {})
		card.get_node("ViewButton").text = "查看草稿" if is_draft else "查看作品"
		card.get_node("EditButton").text = "继续编辑" if is_draft else "打开编辑"

func _refresh_examples(filter: String) -> void:
	for button in _filter_buttons:
		button.set_pressed_no_signal(filter == button.text)
		_update_filter_focus(button)
	var count := 0
	for card in _example_cards:
		card.visible = filter == $Examples/FilterAll.text or card.get_meta("topic") == filter
		if card.visible:
			count += 1
	$Examples/CountLabel.text = "显示 %d 幅示例" % count
	print("UI_FILTER:", filter, ":", count)

func _select_filter(filter: String) -> void:
	filter_requested.emit(filter)

func _view_example(index: int) -> void:
	example_requested.emit(index)

func _view_work(slot: int) -> void:
	if not _slot_works[slot].is_empty():
		view_work_requested.emit(_slot_works[slot])

func _edit_work(slot: int) -> void:
	if not _slot_works[slot].is_empty():
		edit_work_requested.emit(_slot_works[slot])
