extends Control
## Main menu: New Game (seed + size), Continue (latest save), Load (pick a save),
## Quit. It only sets up Sim state (new_game / load_game) then switches to the
## game scene — it holds no game logic itself.

const GAME_SCENE := "res://main.tscn"
const SIZES := [48, 64, 96]

@onready var _seed_edit: LineEdit = $Center/Panel/Margin/VBox/Form/SeedRow/SeedEdit
@onready var _size_opt: OptionButton = $Center/Panel/Margin/VBox/Form/SizeRow/SizeOpt
@onready var _new_btn: Button = $Center/Panel/Margin/VBox/NewGameBtn
@onready var _continue_btn: Button = $Center/Panel/Margin/VBox/ContinueBtn
@onready var _load_btn: Button = $Center/Panel/Margin/VBox/LoadBtn
@onready var _quit_btn: Button = $Center/Panel/Margin/VBox/QuitBtn
@onready var _title: Label = $Center/Panel/Margin/VBox/Title

@onready var _load_panel: Control = $LoadPanel
@onready var _save_list: ItemList = $LoadPanel/Center/Panel/Margin/VBox/SaveList
@onready var _load_confirm: Button = $LoadPanel/Center/Panel/Margin/VBox/Buttons/LoadConfirm
@onready var _delete_btn: Button = $LoadPanel/Center/Panel/Margin/VBox/Buttons/DeleteBtn
@onready var _back_btn: Button = $LoadPanel/Center/Panel/Margin/VBox/Buttons/BackBtn

func _ready() -> void:
	Sim.active = false  # freeze any background sim while sitting at the menu
	_title.add_theme_color_override("font_color", Color("d9a441"))
	_title.add_theme_font_size_override("font_size", 34)

	for s in SIZES:
		_size_opt.add_item("%d × %d" % [s, s])
	_size_opt.select(1)  # default 64×64
	_seed_edit.text = str(randi() % 1000000)
	_seed_edit.placeholder_text = "number or word"

	_refresh_continue()
	_load_panel.visible = false

	_new_btn.pressed.connect(_on_new_game)
	_continue_btn.pressed.connect(_on_continue)
	_load_btn.pressed.connect(_on_load)
	_quit_btn.pressed.connect(func() -> void: get_tree().quit())
	_load_confirm.pressed.connect(_on_load_confirm)
	_delete_btn.pressed.connect(_on_delete)
	_back_btn.pressed.connect(func() -> void: _load_panel.visible = false)
	_save_list.item_activated.connect(func(_i: int) -> void: _on_load_confirm())

func _refresh_continue() -> void:
	var has := Sim.has_saves()
	_continue_btn.disabled = not has
	_load_btn.disabled = not has

func _on_new_game() -> void:
	Sim.new_game(_parse_seed(_seed_edit.text), SIZES[_size_opt.selected])
	get_tree().change_scene_to_file(GAME_SCENE)

# A blank field is a random seed; a plain number is used as-is; any other text is
# hashed to an int, so "hello" is a valid, repeatable seed.
func _parse_seed(text: String) -> int:
	text = text.strip_edges()
	if text == "":
		return randi()
	if text.is_valid_int():
		return int(text)
	return abs(hash(text))

func _on_continue() -> void:
	var name := Sim.latest_save()
	if name != "" and Sim.load_game(name):
		get_tree().change_scene_to_file(GAME_SCENE)

func _on_load() -> void:
	_refresh_saves()
	_load_panel.visible = true

func _refresh_saves() -> void:
	_save_list.clear()
	for n in Sim.list_saves():
		_save_list.add_item(n)
	if _save_list.item_count > 0:
		_save_list.select(0)

func _on_load_confirm() -> void:
	var sel := _save_list.get_selected_items()
	if sel.is_empty():
		return
	if Sim.load_game(_save_list.get_item_text(sel[0])):
		get_tree().change_scene_to_file(GAME_SCENE)

func _on_delete() -> void:
	var sel := _save_list.get_selected_items()
	if sel.is_empty():
		return
	Sim.delete_save(_save_list.get_item_text(sel[0]))
	_refresh_saves()
	_refresh_continue()
