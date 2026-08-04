class_name IsoGrid
extends RefCounted
## The single source of truth for grid <-> screen coordinate conversion.
##
## Dimetric 2:1 projection, diamond-down layout, matching Godot's isometric
## TileMapLayer math exactly (verified in tests/test_iso_grid.gd). Cell (0,0) has
## its center at (TILE_W/2, TILE_H/2). Everything that needs to place or pick a
## tile goes through here — never re-derive the formula elsewhere.

const TILE_W := 64
const TILE_H := 32

## Screen/world position of a cell's CENTER (matches TileMapLayer.map_to_local).
static func grid_to_screen(cell: Vector2i) -> Vector2:
	var hw := TILE_W / 2.0
	var hh := TILE_H / 2.0
	return Vector2((cell.x - cell.y) * hw + hw, (cell.x + cell.y) * hh + hh)

## The cell whose diamond contains a screen/world position.
static func screen_to_grid(pos: Vector2) -> Vector2i:
	var g := screen_to_grid_f(pos)
	return Vector2i(roundi(g.x), roundi(g.y))

## Screen position of a FRACTIONAL grid position — the same projection as
## grid_to_screen(), but for things that stand between tiles rather than on one
## (colonists walking across the ground). Whole numbers land on cell centres.
static func grid_to_screen_f(p: Vector2) -> Vector2:
	var hw := TILE_W / 2.0
	var hh := TILE_H / 2.0
	return Vector2((p.x - p.y) * hw + hw, (p.x + p.y) * hh + hh)

## The exact fractional grid position under a screen point (grid_to_screen_f's
## inverse, without rounding to a cell).
static func screen_to_grid_f(pos: Vector2) -> Vector2:
	var hw := TILE_W / 2.0
	var hh := TILE_H / 2.0
	var u := (pos.x - hw) / hw  # == x - y
	var v := (pos.y - hh) / hh  # == x + y
	return Vector2((u + v) * 0.5, (v - u) * 0.5)

## Converts a screen-space *offset* (a delta, not a position) into the equivalent
## offset in grid units — the projection's linear part, with the half-tile origin
## shift left out. This is how a door anchor measured in pixels on a building's
## art becomes a point on the ground the sim side can walk to.
static func screen_offset_to_grid(off: Vector2) -> Vector2:
	var u := off.x / (TILE_W / 2.0)
	var v := off.y / (TILE_H / 2.0)
	return Vector2((u + v) * 0.5, (v - u) * 0.5)
