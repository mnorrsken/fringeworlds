class_name BuildingSprite
extends Node2D
## Draws one or more 1x1 iso "block" tiles for a building. Placed buildings spawn
## one BuildingSprite PER footprint cell (so a y-sorted parent depth-sorts each
## tile individually — a multi-tile building drawn as a single node sorts at one
## depth and overlaps neighbours wrongly). The placement ghost uses a single
## sprite holding all footprint cells, drawn back-to-front (it renders on top, so
## per-tile interleaving with other buildings isn't needed).
##
## Milestone 8: placed blocks carry a bit of detail (a recessed roof panel, warm
## edge lines) and idle animation — blinking indicator lamps, and rising exhaust
## smoke on industrial buildings. Ghosts stay flat and static.

const WALL_H := 14.0

var _color := Color.WHITE
var _cells: Array = []
var _ghost := false
var _valid := true
var _smoke := false
var _dimmed := false
var _t := 0.0            # animation clock (seconds)
var _redraw_accum := 0.0

func configure(color: Color, cells: Array, ghost := false, smoke := false) -> void:
	_color = color
	_ghost = ghost
	_smoke = smoke and not ghost
	set_process(not ghost)  # placed buildings animate; the ghost is static
	_update_modulate()
	set_cells(cells)

func set_cells(cells: Array) -> void:
	_cells = cells
	_reposition()
	queue_redraw()

func set_valid(valid: bool) -> void:
	if valid == _valid:
		return
	_valid = valid
	_update_modulate()

## Dims a placed building that's been shut down (power / worker / idle). Also
## kills its lamps and smoke, so a dark, still building reads as "off".
func set_dimmed(dimmed: bool) -> void:
	if _ghost:
		return
	_dimmed = dimmed
	modulate = Color(0.5, 0.5, 0.55) if dimmed else Color.WHITE

func _process(delta: float) -> void:
	# Throttle redraws to ~12 fps — plenty for blinking lamps and drifting smoke.
	_t += delta
	_redraw_accum += delta
	if _redraw_accum >= 0.08:
		_redraw_accum = 0.0
		queue_redraw()

# Anchor at the front-most cell so a y-sorted parent orders this sprite correctly.
func _reposition() -> void:
	if _cells.is_empty():
		return
	var front: Vector2i = _cells[0]
	for c in _cells:
		if c.x + c.y > front.x + front.y:
			front = c
	position = IsoGrid.grid_to_screen(front)

func _update_modulate() -> void:
	if _ghost:
		modulate = Color(0.5, 1.0, 0.5, 0.6) if _valid else Color(1.0, 0.45, 0.45, 0.6)
	else:
		modulate = Color.WHITE

func _draw() -> void:
	# Back-to-front within this sprite (matters only for the multi-cell ghost).
	var ordered := _cells.duplicate()
	ordered.sort_custom(func(a, b): return (a.x + a.y) < (b.x + b.y))
	for c in ordered:
		_draw_block(c)

func _draw_block(cell: Vector2i) -> void:
	var hw := IsoGrid.TILE_W / 2.0
	var hh := IsoGrid.TILE_H / 2.0
	var base := IsoGrid.grid_to_screen(cell) - position
	var top := base + Vector2(0, -hh)
	var right := base + Vector2(hw, 0)
	var bottom := base + Vector2(0, hh)
	var left := base + Vector2(-hw, 0)
	var up := Vector2(0, -WALL_H)
	var edge := Palette.EDGE

	# Two side walls (left shadowed, right lit-ish) and the top face.
	draw_colored_polygon(PackedVector2Array([left, bottom, bottom + up, left + up]),
		_color.darkened(0.45))
	draw_colored_polygon(PackedVector2Array([right, bottom, bottom + up, right + up]),
		_color.darkened(0.24))
	var top_face := PackedVector2Array([top + up, right + up, bottom + up, left + up])
	draw_colored_polygon(top_face, _color)

	# A recessed roof panel gives the flat top some structure.
	var ctr := (top + right + bottom + left) / 4.0 + up
	var inset := PackedVector2Array([
		ctr.lerp(top + up, 0.62), ctr.lerp(right + up, 0.62),
		ctr.lerp(bottom + up, 0.62), ctr.lerp(left + up, 0.62)])
	draw_colored_polygon(inset, _color.darkened(0.14))

	# Warm outlines around the top face and down the near edges.
	draw_polyline(top_face + PackedVector2Array([top + up]), edge, 1.0)
	draw_line(left, left + up, edge, 1.0)
	draw_line(right, right + up, edge, 1.0)
	draw_line(bottom, bottom + up, edge, 1.0)

	if _ghost:
		return
	_draw_lamps(cell, ctr)
	if _smoke and not _dimmed:
		_draw_smoke(ctr + Vector2(0, -3))

# Two indicator lamps that blink out of phase; dark when the building is shut.
func _draw_lamps(cell: Vector2i, ctr: Vector2) -> void:
	var phase := cell.x * 0.9 + cell.y * 1.7
	for i in 2:
		var lit := 0.5 + 0.5 * sin(_t * 2.6 + phase + i * 2.3)
		var col: Color = Palette.LIGHT_OFF if _dimmed else Palette.LIGHT_ON.lerp(Palette.LIGHT_OFF, 1.0 - lit)
		draw_circle(ctr + Vector2(-6 + i * 12, 3), 1.6, col)

# A few exhaust puffs rising and fading on a loop.
func _draw_smoke(origin: Vector2) -> void:
	for i in 3:
		var t := fmod(_t * 0.5 + i * 0.34, 1.0)
		var off := Vector2(sin((_t + i) * 1.3) * 3.0, -t * 22.0 - 5.0)
		var col := Palette.SMOKE
		col.a = (1.0 - t) * 0.5
		draw_circle(origin + off, 2.0 + t * 3.5, col)
