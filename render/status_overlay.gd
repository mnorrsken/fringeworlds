extends Node2D
## Toggleable building-status overlay (key O). Power in this game is a global
## capacity balance, not a spatial network, so there's no coverage radius to
## draw — instead this marks every building with a dot: green if it's running,
## red if it's idle (no power, no workers, or stalled). Makes shutdowns obvious
## at a glance. A one-way read of sim state, like everything in render/.

const RUNNING := Color("6bbf59")
const IDLE := Color("e0503f")
const OUTLINE := Color(0, 0, 0, 0.7)
const DOT_R := 6.0

var _on := false

func toggle() -> void:
	_on = not _on
	visible = _on
	queue_redraw()

func _process(_delta: float) -> void:
	if _on:
		queue_redraw()

func _draw() -> void:
	if not _on or Sim.colony == null:
		return
	for id in Sim.colony.buildings:
		var inst: Dictionary = Sim.colony.buildings[id]
		var p := IsoGrid.grid_to_screen(_front_cell(inst.cells))
		var col: Color = RUNNING if inst.active else IDLE
		draw_circle(p, DOT_R + 1.5, OUTLINE)
		draw_circle(p, DOT_R, col)

# The front-most footprint cell (largest x + y), matching BuildingSprite's anchor.
func _front_cell(cells: Array) -> Vector2i:
	var best: Vector2i = cells[0]
	for c in cells:
		if c.x + c.y > best.x + best.y:
			best = c
	return best
