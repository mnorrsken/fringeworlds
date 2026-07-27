extends PanelContainer
## Dune II-style right-hand command sidebar: what you're doing (mode, speed) and
## what you can build.
##
## The colony's standing numbers live in the top bar, and anything about a
## specific tile or building is a hover readout (ui/hover_panel.gd), so this
## panel stays a command surface rather than a dashboard. It only reports intent
## via signals and displays state pushed to it — no game logic.

signal build_requested(type_id: String)
signal demolish_requested()

const AMBER := Color("d9a441")
const SAND := Color("c9b892")

@onready var _title: Label = $Margin/VBox/Title
@onready var _mode: Label = $Margin/VBox/ModeLabel
@onready var _speed: Label = $Margin/VBox/SpeedLabel
@onready var _build_header: Label = $Margin/VBox/BuildHeader
@onready var _build_list: VBoxContainer = $Margin/VBox/Scroll/BuildList
@onready var _demolish: Button = $Margin/VBox/DemolishBtn

var _build_buttons: Dictionary = {}  # building id -> Button

func _ready() -> void:
	# Slightly smaller default text across the whole sidebar (Title keeps its own
	# larger override). A Theme's default_font_size propagates to all descendants,
	# including the build buttons created later.
	var th := Theme.new()
	th.default_font_size = 14
	theme = th

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("17140f")
	sb.border_color = Color("4a4038")
	sb.border_width_left = 3
	sb.content_margin_left = 8
	add_theme_stylebox_override("panel", sb)

	_title.add_theme_color_override("font_color", AMBER)
	_title.add_theme_font_size_override("font_size", 18)
	_build_header.add_theme_color_override("font_color", AMBER)
	_mode.add_theme_color_override("font_color", SAND)
	_speed.add_theme_color_override("font_color", SAND)

	_demolish.tooltip_text = "Removes a building and refunds %d%% of its cost." \
		% int(round(Defs.balance.demolish_refund * 100))
	_demolish.pressed.connect(func() -> void:
		Audio.ui_click()
		demolish_requested.emit())

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
	Audio.ui_click()
	build_requested.emit(id)

func _cost_text(cost: Dictionary) -> String:
	var parts := []
	for r in cost:
		parts.append("%d %s" % [int(cost[r]), r])
	return ", ".join(parts) if not parts.is_empty() else "free"

func set_mode_label(text: String) -> void:
	_mode.text = "◈ %s" % text

## Game speed, pushed each frame. Power and crew moved to the top bar.
func set_speed(speed: float) -> void:
	if speed <= 0.0:
		_speed.text = "❚❚ PAUSED"
	else:
		_speed.text = "▶ %dx" % int(speed)
