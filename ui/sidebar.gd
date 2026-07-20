extends PanelContainer
## Dune II-style right-hand command sidebar: title, current mode, hovered-tile
## info, stockpile, and a build menu generated from Defs.buildings. It only
## reports intent via signals and displays state pushed to it — no game logic.

signal build_requested(type_id: String)
signal demolish_requested()

const AMBER := Color("d9a441")
const SAND := Color("c9b892")
const DIM := Color("7a6f5f")

@onready var _title: Label = $Margin/VBox/Title
@onready var _mode: Label = $Margin/VBox/ModeLabel
@onready var _tile_header: Label = $Margin/VBox/TileHeader
@onready var _tile_info: Label = $Margin/VBox/TileInfo
@onready var _stock_header: Label = $Margin/VBox/StockHeader
@onready var _stock_info: Label = $Margin/VBox/StockInfo
@onready var _build_header: Label = $Margin/VBox/BuildHeader
@onready var _build_list: VBoxContainer = $Margin/VBox/BuildList
@onready var _demolish: Button = $Margin/VBox/DemolishBtn
@onready var _hint: Label = $Margin/VBox/Hint

func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("17140f")
	sb.border_color = Color("4a4038")
	sb.border_width_left = 3
	sb.content_margin_left = 8
	add_theme_stylebox_override("panel", sb)

	_title.add_theme_color_override("font_color", AMBER)
	_title.add_theme_font_size_override("font_size", 18)
	for h in [_tile_header, _stock_header, _build_header]:
		h.add_theme_color_override("font_color", AMBER)
	_mode.add_theme_color_override("font_color", SAND)
	_hint.add_theme_color_override("font_color", DIM)

	_demolish.pressed.connect(func() -> void: demolish_requested.emit())
	_hint.text = "LMB place / select\nRMB demolish / cancel\nWASD+MMB pan  ·  wheel zoom\nEsc cancel  ·  F1 debug"

## Builds one button per building definition.
func populate(buildings: Dictionary) -> void:
	for child in _build_list.get_children():
		child.queue_free()
	for id in buildings:
		var def: Dictionary = buildings[id]
		var btn := Button.new()
		btn.text = "%s\n  %s" % [def.name, _cost_text(def.cost)]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.tooltip_text = def.get("desc", "")
		btn.pressed.connect(_on_build_pressed.bind(id))
		_build_list.add_child(btn)

func _on_build_pressed(id: String) -> void:
	build_requested.emit(id)

func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for r in cost:
		parts.append("%d %s" % [int(cost[r]), r])
	return ", ".join(parts)

func set_mode_label(text: String) -> void:
	_mode.text = "◈ %s" % text

func set_tile_info(cell: Vector2i, terrain: String, occupant: String) -> void:
	var t := "(%d, %d)\n%s" % [cell.x, cell.y, terrain]
	if occupant != "":
		t += "\n▶ %s" % occupant
	_tile_info.text = t

func set_stockpile(stock: Dictionary) -> void:
	var lines := []
	for r in stock:
		lines.append("%s  %d" % [r, int(stock[r])])
	_stock_info.text = "\n".join(lines)
