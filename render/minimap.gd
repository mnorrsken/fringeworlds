class_name Minimap
extends Control
## Top-down overhead map (toggled on M). Renders the terrain from above as a
## scaled image, overlays building markers and the current camera view rectangle,
## and lets you click to jump the camera. A view of sim state — no game logic.

const CELL_PX := 4  # minimap pixels per map cell

var _map: ColonyMap
var _camera: Camera2D
var _tex: ImageTexture

## Builds the (static) terrain texture and sizes the control. Call once.
func setup(map: ColonyMap, camera: Camera2D) -> void:
	_map = map
	_camera = camera
	var img := Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
	for y in map.height:
		for x in map.width:
			img.set_pixel(x, y, TerrainView.TERRAIN_COLORS[map.get_terrain(Vector2i(x, y))])
	_tex = ImageTexture.create_from_image(img)
	custom_minimum_size = Vector2(map.width, map.height) * CELL_PX
	queue_redraw()

func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # buildings and camera view move; terrain is cached

func _draw() -> void:
	if _map == null:
		return
	var s := float(CELL_PX)
	var full := Rect2(Vector2.ZERO, Vector2(_map.width, _map.height) * s)
	draw_texture_rect(_tex, full, false)

	for id in Sim.colony.buildings:
		var inst: Dictionary = Sim.colony.buildings[id]
		var def: Dictionary = Defs.buildings[inst.type]
		var bs := int(def.size)
		draw_rect(Rect2(Vector2(inst.origin) * s, Vector2(bs, bs) * s),
			def.get("color_value", Color.WHITE))

	_draw_view_rect(s)
	draw_rect(full, Color(0.65, 0.60, 0.50), false, 1.0)

# The camera's visible region is a rotated quad in grid space.
func _draw_view_rect(s: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var half := vp * 0.5 / _camera.zoom.x
	var offsets := [
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	]
	var pts := PackedVector2Array()
	for o in offsets:
		pts.append(_world_to_grid_f(_camera.position + o) * s)
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.85), 1.0)

# Unrounded inverse of IsoGrid.grid_to_screen (kept local; IsoGrid returns ints).
func _world_to_grid_f(pos: Vector2) -> Vector2:
	var hw := IsoGrid.TILE_W / 2.0
	var hh := IsoGrid.TILE_H / 2.0
	var u := (pos.x - hw) / hw
	var v := (pos.y - hh) / hh
	return Vector2((u + v) * 0.5, (v - u) * 0.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		var cell := (mb.position / float(CELL_PX)).floor()
		_camera.position = IsoGrid.grid_to_screen(Vector2i(int(cell.x), int(cell.y)))
