extends PanelContainer
## Dune II-style right-hand command sidebar: title, current mode, hovered-tile
## info, stockpile, and a build menu generated from Defs.buildings. It only
## reports intent via signals and displays state pushed to it — no game logic.

signal build_requested(type_id: String)
signal demolish_requested()

const AMBER := Color("d9a441")
const SAND := Color("c9b892")
const DIM := Color("7a6f5f")

@onready var _title: Label = $Margin/Scroll/VBox/Title
@onready var _mode: Label = $Margin/Scroll/VBox/ModeLabel
@onready var _speed: Label = $Margin/Scroll/VBox/SpeedLabel
@onready var _tile_header: Label = $Margin/Scroll/VBox/TileHeader
@onready var _tile_info: Label = $Margin/Scroll/VBox/TileInfo
@onready var _stock_header: Label = $Margin/Scroll/VBox/StockHeader
@onready var _stock_info: Label = $Margin/Scroll/VBox/StockInfo
@onready var _power_header: Label = $Margin/Scroll/VBox/PowerHeader
@onready var _power_info: Label = $Margin/Scroll/VBox/PowerInfo
@onready var _colony_header: Label = $Margin/Scroll/VBox/ColonyHeader
@onready var _colony_info: Label = $Margin/Scroll/VBox/ColonyInfo
@onready var _build_header: Label = $Margin/Scroll/VBox/BuildHeader
@onready var _build_list: VBoxContainer = $Margin/Scroll/VBox/BuildList
@onready var _demolish: Button = $Margin/Scroll/VBox/DemolishBtn
@onready var _hint: Label = $Margin/Scroll/VBox/Hint

func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("17140f")
	sb.border_color = Color("4a4038")
	sb.border_width_left = 3
	sb.content_margin_left = 8
	add_theme_stylebox_override("panel", sb)

	_title.add_theme_color_override("font_color", AMBER)
	_title.add_theme_font_size_override("font_size", 18)
	for h in [_tile_header, _stock_header, _power_header, _colony_header, _build_header]:
		h.add_theme_color_override("font_color", AMBER)
	_mode.add_theme_color_override("font_color", SAND)
	_speed.add_theme_color_override("font_color", SAND)
	_hint.add_theme_color_override("font_color", DIM)

	_demolish.pressed.connect(func() -> void: demolish_requested.emit())
	_hint.text = "LMB place / select\nRMB demolish / cancel\nWASD pan  ·  Z / pinch zoom\nP prospect  ·  M overhead map\nSpace pause · 1/3 speed · F1"

## Builds one button per building definition.
func populate(buildings: Dictionary) -> void:
	for child in _build_list.get_children():
		child.queue_free()
	for id in buildings:
		var def: Dictionary = buildings[id]
		var btn := Button.new()
		btn.text = "%s  ·  %s" % [def.name, _cost_text(def.cost)]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
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

func set_tile_info(cell: Vector2i, terrain: String, occupant: String,
		reading: String = "") -> void:
	var t := "(%d, %d)\n%s" % [cell.x, cell.y, terrain]
	if reading != "":
		t += "\n◇ %s" % reading
	if occupant != "":
		t += "\n▶ %s" % occupant
	_tile_info.text = t

## Pushes the live economy each frame: stockpile with per-second rates, power
## supply vs. demand, and the current speed.
func set_economy(stock: Dictionary, rates: Dictionary, power_produced: int,
		power_consumed: int, speed: float) -> void:
	var lines := []
	for r in stock:
		var rate: float = rates.get(r, 0.0)
		var suffix := ""
		if absf(rate) > 0.001:
			suffix = "  %+.1f/s" % rate
		lines.append("%s  %d%s" % [r, int(stock[r]), suffix])
	_stock_info.text = "\n".join(lines) if not lines.is_empty() else "—"

	var deficit := power_consumed > power_produced
	_power_info.text = "%d / %d used" % [power_consumed, power_produced]
	_power_info.add_theme_color_override("font_color",
		Color("d65a4a") if deficit else SAND)

	if speed <= 0.0:
		_speed.text = "❚❚ PAUSED"
	else:
		_speed.text = "▶ %dx" % int(speed)

## Population / housing capacity / workforce use.
func set_colony(population: int, cap: int, workers_used: int) -> void:
	_colony_info.text = "pop %d / %d\nworkers %d / %d" % [
		population, cap, workers_used, population]
	var crowded := population >= cap
	_colony_info.add_theme_color_override("font_color",
		Color("d6a84a") if crowded else SAND)
