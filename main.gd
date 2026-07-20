extends Node2D
## Milestone 1 game root: generate a map, view it, drive the camera, and pick the
## tile under the cursor. The debug coordinate overlay stays available behind F1
## for the whole project lifetime (Milestone 1 asks for it; the plan wants it
## kept — coordinate conversion is the first thing to suspect when visuals look
## wrong).

const MAP_SIZE := 64
const DEFAULT_SEED := 1337

@onready var _terrain: TerrainView = $TerrainView
@onready var _camera: IsoCamera = $Camera
@onready var _debug: CanvasLayer = $Debug
@onready var _label: Label = $Debug/Label

var _map: ColonyMap
var _hover := Vector2i(-1, -1)

func _ready() -> void:
	_map = ColonyMap.new(MAP_SIZE, MAP_SIZE)
	_map.generate(DEFAULT_SEED)
	_terrain.render_map(_map)
	_camera.position = IsoGrid.grid_to_screen(Vector2i(MAP_SIZE / 2, MAP_SIZE / 2))

func _process(_delta: float) -> void:
	var cell := IsoGrid.screen_to_grid(get_global_mouse_position())
	if cell != _hover:
		_hover = cell
		queue_redraw()
	_update_label()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F1:
		_debug.visible = not _debug.visible

func _update_label() -> void:
	if not _debug.visible:
		return
	var terrain := "—"
	if _map.in_bounds(_hover):
		terrain = ColonyMap.TERRAIN_NAMES[_map.get_terrain(_hover)]
	_label.text = "cell (%d, %d)   %s\nzoom %dx   seed %d   FPS %d\n[WASD/MMB] pan  [wheel] zoom  [F1] debug" % [
		_hover.x, _hover.y, terrain,
		int(_camera.zoom.x), _map.seed, Engine.get_frames_per_second(),
	]

func _draw() -> void:
	if not _map.in_bounds(_hover):
		return
	var c := IsoGrid.grid_to_screen(_hover)
	var hw := IsoGrid.TILE_W / 2.0
	var hh := IsoGrid.TILE_H / 2.0
	var pts := PackedVector2Array([
		c + Vector2(0, -hh), c + Vector2(hw, 0), c + Vector2(0, hh), c + Vector2(-hw, 0),
		c + Vector2(0, -hh),
	])
	draw_polyline(pts, Color(1.0, 0.95, 0.4), 1.5)
