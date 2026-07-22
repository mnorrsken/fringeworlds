extends PanelContainer
## Top-of-screen stockpile bar. One entry per resource, shown as its coloured
## glyph + amount + per-second rate — no words, so it stays compact. Screen-space
## and stateless: main.gd pushes the live stockpile/rates each frame; this only
## displays them. A resource stays hidden until the colony actually has some (or
## a non-zero rate), so the bar reveals ore/parts/xenite as the chain comes online.

@onready var _hbox: HBoxContainer = $Margin/HBox

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

## Builds one (hidden) glyph label per resource. `power` is a capacity balance,
## not a stockpiled good, so it's skipped here — the sidebar shows it instead.
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
		lbl.tooltip_text = str(def.get("name", id))
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
