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
	var hw := TILE_W / 2.0
	var hh := TILE_H / 2.0
	var u := (pos.x - hw) / hw  # == cx - cy
	var v := (pos.y - hh) / hh  # == cx + cy
	return Vector2i(roundi((u + v) * 0.5), roundi((v - u) * 0.5))
