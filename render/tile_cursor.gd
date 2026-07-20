class_name TileCursor
extends Node2D
## The hover highlight. Lives on a high z_index so its border draws ON TOP of the
## terrain and buildings (a plain _draw on the game root renders under the
## TileMapLayer, which is why the highlight was previously hidden).

var cell := Vector2i.ZERO:
	set(value):
		cell = value
		queue_redraw()

## When true (demolish mode) the border turns red.
var demolish := false:
	set(value):
		demolish = value
		queue_redraw()

func _draw() -> void:
	var c := IsoGrid.grid_to_screen(cell)
	var hw := IsoGrid.TILE_W / 2.0
	var hh := IsoGrid.TILE_H / 2.0
	var pts := PackedVector2Array([
		c + Vector2(0, -hh), c + Vector2(hw, 0),
		c + Vector2(0, hh), c + Vector2(-hw, 0), c + Vector2(0, -hh),
	])
	var col := Color(1.0, 0.4, 0.4) if demolish else Color(1.0, 0.95, 0.4)
	# Dark backing line first, bright line on top — reads clearly over any tile.
	draw_polyline(pts, Color(0, 0, 0, 0.6), 3.0)
	draw_polyline(pts, col, 1.5)
