extends PanelContainer
## Dune II-style right-hand command sidebar: title, current mode, hovered-tile
## info, stockpile, and a build menu generated from Defs.buildings. It only
## reports intent via signals and displays state pushed to it — no game logic.

signal build_requested(type_id: String)
signal demolish_requested()

const AMBER := Color("d9a441")
const SAND := Color("c9b892")
const DIM := Color("7a6f5f")
const GREEN := Color("6bbf59")
const RED := Color("d65a4a")

@onready var _title: Label = $Margin/VBox/Title
@onready var _mode: Label = $Margin/VBox/ModeLabel
@onready var _speed: Label = $Margin/VBox/SpeedLabel
@onready var _tile_header: Label = $Margin/VBox/TileHeader
@onready var _tile_info: Label = $Margin/VBox/TileInfo
@onready var _power_header: Label = $Margin/VBox/PowerHeader
@onready var _power_info: Label = $Margin/VBox/PowerInfo
@onready var _colony_header: Label = $Margin/VBox/ColonyHeader
@onready var _colony_info: Label = $Margin/VBox/ColonyInfo
@onready var _inspect_sep: HSeparator = $Margin/VBox/SepInspect
@onready var _inspect_header: Label = $Margin/VBox/InspectHeader
@onready var _inspect_info: Label = $Margin/VBox/InspectInfo
@onready var _build_header: Label = $Margin/VBox/BuildHeader
@onready var _build_list: VBoxContainer = $Margin/VBox/Scroll/BuildList
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
	for h in [_tile_header, _power_header, _colony_header,
			_inspect_header, _build_header]:
		h.add_theme_color_override("font_color", AMBER)
	_mode.add_theme_color_override("font_color", SAND)
	_speed.add_theme_color_override("font_color", SAND)
	_hint.add_theme_color_override("font_color", DIM)

	_demolish.pressed.connect(func() -> void: demolish_requested.emit())
	_hint.text = "LMB place/inspect · RMB demolish · WASD pan · Z zoom · P/O/M overlays · Space,1,3 speed · F1"

var _build_buttons: Dictionary = {}  # building id -> Button

## Builds one button per building definition.
func populate(buildings: Dictionary) -> void:
	for child in _build_list.get_children():
		child.queue_free()
	_build_buttons.clear()
	for id in buildings:
		var def: Dictionary = buildings[id]
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.set_meta("label", "%s  ·  %s" % [def.name, _cost_text(def.cost)])
		btn.set_meta("desc", str(def.get("desc", "")))
		btn.pressed.connect(_on_build_pressed.bind(id))
		_build_list.add_child(btn)
		_build_buttons[id] = btn

## Locks a build button whose prerequisites aren't met. `locks` maps building id
## -> reason string ("" == unlocked).
func set_locks(locks: Dictionary) -> void:
	for id in _build_buttons:
		var btn: Button = _build_buttons[id]
		var reason := str(locks.get(id, ""))
		var locked := reason != ""
		btn.disabled = locked
		btn.text = str(btn.get_meta("label")) + ("  🔒" if locked else "")
		btn.tooltip_text = reason if locked else str(btn.get_meta("desc"))

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

## Pushes the live power balance and speed each frame. The stockpile lives in the
## top resource bar now, not here.
func set_economy(power_produced: int, power_consumed: int, speed: float) -> void:
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

## Shows the clicked building's live state ("why am I idle" + I/O + workers), or
## hides the whole section when `rep` is empty (nothing selected). `rep` is the
## dictionary from Colony.building_report().
func set_inspector(rep: Dictionary) -> void:
	var show := not rep.is_empty()
	_inspect_sep.visible = show
	_inspect_header.visible = show
	_inspect_info.visible = show
	if not show:
		return

	var running: bool = rep.active and str(rep.idle_reason) == ""
	var lines := [str(rep.name)]
	if running:
		lines.append("● running")
	else:
		var why := str(rep.idle_reason)
		lines.append("○ idle" + (": " + why if why != "" else ""))

	var power := int(rep.power)
	if power != 0:
		lines.append("power %+d" % power)
	if int(rep.workers) > 0:
		lines.append("workers %d" % int(rep.workers))
	if int(rep.capacity) > 0:
		lines.append("houses +%d" % int(rep.capacity))
	if rep.get("scans", false):
		lines.append("surveys for deposits")
	if rep.has("recipe"):
		var recipe: Dictionary = rep.recipe
		var ins := _flow_text(recipe.get("inputs", {}))
		if ins != "":
			lines.append("in:  " + ins)
		lines.append("out: " + _flow_text(recipe.get("outputs", {})))
		lines.append("progress %d/%d" % [int(rep.progress), int(recipe.ticks)])
	if rep.has("mine"):
		var m: Dictionary = rep.mine
		lines.append("mining %s" % str(m.resource))
		lines.append("richness %d%%  (%.2f/t)" % [
			int(round(float(m.richness) * 100)), float(m.per_tick)])

	_inspect_info.text = "\n".join(lines)
	_inspect_info.add_theme_color_override("font_color", GREEN if running else RED)

func _flow_text(flow: Dictionary) -> String:
	var parts := []
	for r in flow:
		parts.append("%d %s" % [int(flow[r]), r])
	return ", ".join(parts)
