extends PanelContainer
## The readout for whatever is under the cursor: terrain, the prospecting
## reading, and — when a building is there — its live state. It follows the
## mouse, so "what is this?" is answered where you're already looking instead of
## in a corner of the sidebar.
##
## Screen-space and stateless: main.gd pushes the hovered tile each frame and
## this only formats it. It never accepts mouse input (`MOUSE_FILTER_IGNORE`
## everywhere), so it can sit under the cursor without blocking clicks.

const GREEN := Color("6bbf59")
const RED := Color("d65a4a")
const AMBER := Color("d9a441")
const SAND := Color("c9b892")
const DIM := Color("7a6f5f")

## Gap between the cursor and the panel's corner.
const CURSOR_OFFSET := Vector2(18, 18)
## Keeps the panel clear of the screen edge when it flips sides.
const EDGE_MARGIN := 8.0

@onready var _title: Label = $Margin/VBox/Title
@onready var _body: Label = $Margin/VBox/Body

func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.06, 0.94)
	sb.border_color = Color("4a4038")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", sb)
	_title.add_theme_color_override("font_color", AMBER)
	_title.add_theme_font_size_override("font_size", 15)
	_body.add_theme_font_size_override("font_size", 13)
	top_level = true   # position in screen space, ignoring the parent's layout

## Shows the readout for a tile. `report` is Colony.building_report() for the
## building there, or {} for bare ground. Passing an out-of-bounds tile (or
## hovering the UI) should call hide_info() instead.
func show_tile(terrain: String, reading: String, report: Dictionary) -> void:
	visible = true
	if report.is_empty():
		_title.text = terrain
		_title.add_theme_color_override("font_color", AMBER)
		_body.text = reading if reading != "" else "Unsurveyed"
		_body.add_theme_color_override("font_color", SAND if reading != "" else DIM)
		return

	var running: bool = report.active and str(report.idle_reason) == ""
	_title.text = str(report.name)
	var title_col := RED
	if not report.get("enabled", true):
		title_col = DIM   # off on purpose isn't a problem to flag
	elif running:
		title_col = GREEN
	_title.add_theme_color_override("font_color", title_col)
	_body.text = "\n".join(_lines(report, terrain, reading))
	_body.add_theme_color_override("font_color", SAND)

func hide_info() -> void:
	visible = false

## Keeps the panel next to the cursor, flipping it away from the screen edges so
## it never runs off the bottom-right (where it would otherwise spend most of its
## time, given the sidebar).
func place_at(cursor: Vector2) -> void:
	# Shrink back to fit the current text. Without this the panel keeps the
	# largest size it has ever had, so moving from a building onto bare ground
	# leaves a mostly-empty box hanging off the cursor.
	reset_size()
	var view := get_viewport_rect().size
	var panel := size
	var pos := cursor + CURSOR_OFFSET
	if pos.x + panel.x > view.x - EDGE_MARGIN:
		pos.x = cursor.x - panel.x - CURSOR_OFFSET.x
	if pos.y + panel.y > view.y - EDGE_MARGIN:
		pos.y = cursor.y - panel.y - CURSOR_OFFSET.y
	position = pos.clamp(Vector2(EDGE_MARGIN, EDGE_MARGIN), view - panel - Vector2(EDGE_MARGIN, EDGE_MARGIN))

# Same facts the sidebar's inspector used to show, in reading order: why it's
# idle first (that's why you hovered), then what it does, then the terrain it
# stands on.
func _lines(report: Dictionary, terrain: String, reading: String) -> Array:
	var out := []
	var enabled: bool = report.get("enabled", true)
	var running: bool = report.active and str(report.idle_reason) == ""
	if not enabled:
		# Its own line, not an idle reason: the colony isn't failing, you did this.
		out.append("◌ switched off")
	elif running:
		out.append("● running")
	else:
		var why := str(report.idle_reason)
		out.append("○ idle" + (": " + why if why != "" else ""))

	var power := int(report.power)
	if power != 0:
		var now := int(report.get("power_now", power))
		# A dimmed panel says so here rather than quietly under-reporting: the
		# grid figure in the top bar is the first thing a storm moves.
		if now == power:
			out.append("power %+d" % power)
		else:
			out.append("power %+d  (dust storm: %+d)" % [power, now])
	if int(report.workers) > 0:
		out.append("workers %d" % int(report.workers))
	if int(report.capacity) > 0:
		out.append("houses +%d" % int(report.capacity))
	if int(report.get("life_support", 0)) > 0:
		out.append("sustains %d colonists" % int(report.life_support))
	if report.get("scans", false):
		out.append("surveys for deposits")
	var buffer: Dictionary = report.get("buffer", {})
	if not buffer.is_empty():
		var held := []
		for res in buffer:
			held.append("%d %s" % [int(buffer[res]), res])
		out.append("holding " + ", ".join(held))
	var storage: Dictionary = report.get("storage", {})
	if not storage.is_empty():
		var parts := []
		for res in storage:
			parts.append("%s %d" % [res, int(storage[res])])
		out.append("stores " + ", ".join(parts))
	if report.has("recipe"):
		var recipe: Dictionary = report.recipe
		var ins := _flow(recipe.get("inputs", {}))
		if ins != "":
			out.append("in:  " + ins)
		out.append("out: " + _flow(recipe.get("outputs", {})))
		out.append("progress %d/%d" % [int(report.progress), int(recipe.ticks)])
	if report.has("mine"):
		var m: Dictionary = report.mine
		out.append("mining %s  (%.2f/t)" % [str(m.resource), float(m.per_tick)])
		# The reserve is the whole patch the machine reaches, not just the tile it
		# stands on, so say how many tiles are still feeding it.
		var left := int(round(float(m.get("remaining", 0.0))))
		var tiles := int(m.get("tiles", 0))
		if left <= 0:
			out.append("reserve worked out")
		else:
			out.append("reserve %d left across %d tile%s" % [
				left, tiles, "" if tiles == 1 else "s"])

	# The only place the switch is advertised — there's no click-to-select panel
	# to hang a button on, so the hint lives where you're already looking.
	if report.get("can_toggle", false):
		out.append("[T] switch " + ("on" if not enabled else "off"))

	out.append("")
	out.append(terrain + ("  ·  " + reading if reading != "" else ""))
	return out

func _flow(flow: Dictionary) -> String:
	var parts := []
	for r in flow:
		parts.append("%d %s" % [int(flow[r]), r])
	return ", ".join(parts)
