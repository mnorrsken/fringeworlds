class_name BuildingSprite
extends Node2D
## Draws one or more 1x1 iso "block" tiles for a building. Placed buildings spawn
## one BuildingSprite PER footprint cell (so a y-sorted parent depth-sorts each
## tile individually — a multi-tile building drawn as a single node sorts at one
## depth and overlaps neighbours wrongly). The placement ghost uses a single
## sprite holding all footprint cells, drawn back-to-front (it renders on top, so
## per-tile interleaving with other buildings isn't needed).

const WALL_H := 14.0

var _color := Color.WHITE
var _cells: Array = []
var _ghost := false
var _valid := true

func configure(color: Color, cells: Array, ghost := false) -> void:
	_color = color
	_ghost = ghost
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

## Dims a placed building that's been shut down (power / worker / idle).
func set_dimmed(dimmed: bool) -> void:
	if _ghost:
		return
	modulate = Color(0.45, 0.45, 0.52) if dimmed else Color.WHITE

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
	var edge := _color.darkened(0.55)

	draw_colored_polygon(PackedVector2Array([left, bottom, bottom + up, left + up]),
		_color.darkened(0.40))
	draw_colored_polygon(PackedVector2Array([right, bottom, bottom + up, right + up]),
		_color.darkened(0.22))
	var top_face := PackedVector2Array([top + up, right + up, bottom + up, left + up])
	draw_colored_polygon(top_face, _color)
	draw_polyline(top_face + PackedVector2Array([top + up]), edge, 1.0)
	draw_line(left, left + up, edge, 1.0)
	draw_line(right, right + up, edge, 1.0)
	draw_line(bottom, bottom + up, edge, 1.0)
