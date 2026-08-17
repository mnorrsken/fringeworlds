extends Control
## The dust storm you can see: an ochre veil over the whole screen with wind-blown
## streaks tearing across it. Purely a view of `Sim.colony.weather` — it holds no
## state the sim cares about and never writes back.
##
## Screen-space on purpose. The storm is weather, not a thing standing on a tile,
## so it doesn't pan or zoom with the map; drawing it in world space would make it
## a patch of dust the camera can drive out of.
##
## The veil fades in and out over FADE seconds rather than snapping, because the
## alert and the sidebar countdown have already told the player it's coming — the
## sky darkening is the confirmation, and a hard cut reads as a bug.

## Ochre haze the storm lays over the map.
const VEIL := Color("a8763c")
const VEIL_ALPHA := 0.30
## Streaks of blown dust. Paler than the veil, or they vanish into it.
const STREAK := Color("f0dcb4")
const STREAKS := 110
const FADE := 1.6            # seconds to reach full strength, and to clear

var _strength := 0.0         # 0 clear .. 1 full storm
var _t := 0.0
# Per-streak constants: y, length, speed, alpha, phase. Fixed at startup so the
# streaks don't reshuffle every frame into visual noise.
var _streaks: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260817
	for i in STREAKS:
		_streaks.append({
			"y": rng.randf(),
			"len": rng.randf_range(90.0, 340.0),
			"speed": rng.randf_range(320.0, 900.0),
			"alpha": rng.randf_range(0.18, 0.55),
			"phase": rng.randf(),
			"thick": 1.0 if rng.randf() < 0.6 else 2.0,
		})

func _process(delta: float) -> void:
	var want := 0.0
	if Sim.colony != null and Sim.colony.weather.is_storming():
		want = 1.0
	# Ease toward the target; the sim's pause shouldn't freeze the fade mid-way,
	# so this runs on real time rather than sim ticks.
	_strength = move_toward(_strength, want, delta / FADE)
	visible = _strength > 0.001
	if not visible:
		return
	_t += delta
	queue_redraw()

func _draw() -> void:
	var r := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, r), Color(VEIL, VEIL_ALPHA * _strength))
	for s in _streaks:
		# Wrap across the screen with a margin either side, so a streak enters and
		# leaves rather than popping into existence at the edge.
		var span: float = r.x + 400.0
		var x: float = fposmod(float(s.phase) * span - _t * float(s.speed), span) - 200.0
		var y: float = float(s.y) * r.y
		var col := Color(STREAK, float(s.alpha) * _strength)
		draw_line(Vector2(x, y), Vector2(x + float(s.len), y + 6.0), col, float(s.thick))
