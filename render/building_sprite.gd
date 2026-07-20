class_name BuildingSprite
extends Node2D
## A lightweight iso "block" representing one placed building (or the placement
## ghost). Draws relative to its node position, which is set to the building's
## front (bottom) tile so a y-sorted parent orders overlapping buildings right.

const WALL_H := 16.0

var _color := Color.WHITE
var _size := 1
var _origin := Vector2i.ZERO
var _ghost := false
var _valid := true

func configure(def: Dictionary, origin: Vector2i, ghost := false) -> void:
	_color = def.get("color_value", Color.WHITE)
	_size = int(def.get("size", 1))
	_origin = origin
	_ghost = ghost
	_reposition()
	_update_modulate()
	queue_redraw()

func set_origin(origin: Vector2i) -> void:
	if origin == _origin:
		return
	_origin = origin
	_reposition()
	queue_redraw()

func set_valid(valid: bool) -> void:
	if valid == _valid:
		return
	_valid = valid
	_update_modulate()

## Dims a placed building that's been shut down (power deficit / idle).
func set_dimmed(dimmed: bool) -> void:
	if _ghost:
		return
	modulate = Color(0.45, 0.45, 0.52) if dimmed else Color.WHITE

func _reposition() -> void:
	var front := _origin + Vector2i(_size - 1, _size - 1)
	position = IsoGrid.grid_to_screen(front)

func _update_modulate() -> void:
	if _ghost:
		modulate = Color(0.5, 1.0, 0.5, 0.6) if _valid else Color(1.0, 0.45, 0.45, 0.6)
	else:
		modulate = Color.WHITE

func _draw() -> void:
	var hw := IsoGrid.TILE_W / 2.0
	var hh := IsoGrid.TILE_H / 2.0
	var s := _size
	# Footprint diamond corners, in this node's local space.
	var top := IsoGrid.grid_to_screen(_origin) + Vector2(0, -hh) - position
	var right := IsoGrid.grid_to_screen(_origin + Vector2i(s - 1, 0)) + Vector2(hw, 0) - position
	var bottom := IsoGrid.grid_to_screen(_origin + Vector2i(s - 1, s - 1)) + Vector2(0, hh) - position
	var left := IsoGrid.grid_to_screen(_origin + Vector2i(0, s - 1)) + Vector2(-hw, 0) - position
	var up := Vector2(0, -WALL_H)
	var edge := _color.darkened(0.55)

	# Side walls (left is more in shadow than right).
	draw_colored_polygon(PackedVector2Array([left, bottom, bottom + up, left + up]), _color.darkened(0.40))
	draw_colored_polygon(PackedVector2Array([right, bottom, bottom + up, right + up]), _color.darkened(0.22))
	# Lit top face.
	var top_face := PackedVector2Array([top + up, right + up, bottom + up, left + up])
	draw_colored_polygon(top_face, _color)
	# Outlines.
	draw_polyline(top_face + PackedVector2Array([top + up]), edge, 1.0)
	draw_line(left, left + up, edge, 1.0)
	draw_line(right, right + up, edge, 1.0)
	draw_line(bottom, bottom + up, edge, 1.0)
