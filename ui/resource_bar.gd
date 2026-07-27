extends PanelContainer
## Top-of-screen status bar: the stockpile on the left, the colony's two
## standing numbers (power and crew) on the right, and the help button.
##
## One entry per resource, shown as its coloured glyph + amount + per-second
## rate — no words, so it stays compact. Screen-space and stateless: main.gd
## pushes live values each frame; this only displays them. A resource stays
## hidden until the colony actually has some (or a non-zero rate), so the bar
## reveals ore/parts/xenite as the chain comes online.

signal help_requested()

const SAND := Color("c9b892")
const RED := Color("d65a4a")
const AMBER := Color("d6a84a")

@onready var _hbox: HBoxContainer = $Margin/HBox/Resources
@onready var _power: Label = $Margin/HBox/Stats/Power
@onready var _colonists: Label = $Margin/HBox/Stats/Colonists
@onready var _help: Button = $Margin/HBox/Stats/HelpBtn

var _entries: Dictionary = {}  # resource id -> Label

func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("17140f")
	sb.border_color = Color("4a4038")
	sb.border_width_bottom = 3
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	add_theme_stylebox_override("panel", sb)

	for lbl in [_power, _colonists]:
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.add_theme_color_override("font_color", SAND)
	_power.tooltip_text = "Power drawn / generated. Over budget shuts down the newest buildings."
	_colonists.tooltip_text = "Colonists / housing capacity, and how many are staffing buildings."
	_help.pressed.connect(func() -> void:
		Audio.ui_click()
		help_requested.emit())

## Builds one (hidden) glyph label per resource. `power` is a capacity balance,
## not a stockpiled good, so it gets its own readout on the right instead.
func populate(resources: Dictionary) -> void:
	for c in _hbox.get_children():
		c.queue_free()
	_entries.clear()
	for id in resources:
		if id == "power":
			continue
		var def: Dictionary = resources[id]
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.add_theme_color_override("font_color", Color.html(str(def.get("color", "ffffff"))))
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP  # so the tooltip shows on hover
		var desc := str(def.get("desc", ""))
		lbl.tooltip_text = str(def.get("name", id)) + ("\n" + desc if desc != "" else "")
		lbl.set_meta("glyph", str(def.get("glyph", "•")))
		lbl.visible = false
		_hbox.add_child(lbl)
		_entries[id] = lbl

## Updates amounts/rates each frame; hides resources the colony has none of.
func set_resources(stock: Dictionary, rates: Dictionary) -> void:
	for id in _entries:
		var lbl: Label = _entries[id]
		var amount := int(stock.get(id, 0))
		var rate: float = rates.get(id, 0.0)
		if amount <= 0 and absf(rate) <= 0.05:
			lbl.visible = false
			continue
		lbl.visible = true
		var text := "%s %d" % [str(lbl.get_meta("glyph")), amount]
		if absf(rate) > 0.05:
			text += "  %+.1f" % rate
		lbl.text = text

## The two standing numbers, kept out of the scrolling stockpile list because
## they're balances rather than stock: power turns red when demand outstrips
## supply (buildings are being shut down), housing ambers when the colony is
## full and can no longer grow.
func set_stats(power_produced: int, power_consumed: int,
		population: int, capacity: int, workers_used: int) -> void:
	_power.text = "⚡ %d/%d" % [power_consumed, power_produced]
	_power.add_theme_color_override("font_color",
		RED if power_consumed > power_produced else SAND)
	_colonists.text = "☻ %d/%d  ⚒ %d" % [population, capacity, workers_used]
	_colonists.add_theme_color_override("font_color",
		AMBER if population >= capacity else SAND)
