class_name ColonistSprite
extends Node2D
## One colonist on screen. Draws a frame of the walk sheet described by
## data/colonists.json — eight facing rows (S, SE, E, NE, N, NW, W, SW), each a
## row of walk frames — anchored so the figure's feet stand on the ground point.
##
## Until that art exists the sprite falls back to a procedural figure in the
## project palette, the same way BuildingSprite falls back to a drawn block:
## small, readable, and honest about being a placeholder. Dropping
## `assets/colonist.png` in and pointing the JSON at it is the whole swap — no
## code change.

const PLACEHOLDER_SUIT := Color("c9764a")
const PLACEHOLDER_SUIT_DK := Color("8f4f30")
const PLACEHOLDER_HELMET := Color("cfe3ea")
const PLACEHOLDER_VISOR := Color("2a1d15")
const SHADOW := Color(0, 0, 0, 0.28)

var _tex: Texture2D = null
var _frame_size := Vector2(16, 24)
var _anchor := Vector2(8, 22)
var _walk_frames := 4
var _facing := 0
var _frame := 0

func configure(tex: Texture2D, cfg: Dictionary) -> void:
	_tex = tex
	var fs: Array = cfg.get("frame_size", [16, 24])
	_frame_size = Vector2(float(fs[0]), float(fs[1]))
	var an: Array = cfg.get("anchor", [_frame_size.x / 2.0, _frame_size.y - 2.0])
	_anchor = Vector2(float(an[0]), float(an[1]))
	_walk_frames = maxi(1, int(cfg.get("walk_frames", 4)))
	queue_redraw()

## `facing` is a ColonistCrowd facing index (0..7); `frame` is the walk-cycle
## step, already advanced by the view so every colonist doesn't march in step.
func set_pose(facing: int, frame: int) -> void:
	if facing == _facing and frame == _frame:
		return
	_facing = facing
	_frame = frame
	queue_redraw()

func _draw() -> void:
	if _tex != null:
		var src := Rect2(
			Vector2(_frame % _walk_frames, _facing) * _frame_size, _frame_size)
		draw_texture_rect_region(_tex, Rect2(-_anchor, _frame_size), src)
		return
	_draw_placeholder()

# A 10px figure: shadow diamond on the ground, boots swinging with the walk
# cycle, a suit body, and a helmet whose visor only shows on the four facings
# that look toward the camera.
func _draw_placeholder() -> void:
	var swing: float = [0.0, 1.0, 0.0, -1.0][_frame % 4]
	draw_colored_polygon(PackedVector2Array([
		Vector2(-4, 0), Vector2(0, -2), Vector2(4, 0), Vector2(0, 2)]), SHADOW)

	# Legs: one forward, one back, crossing at mid-stride.
	draw_line(Vector2(-1.5, -1.0), Vector2(-1.5 + swing * 1.6, -5.0),
		PLACEHOLDER_SUIT_DK, 2.0)
	draw_line(Vector2(1.5, -1.0), Vector2(1.5 - swing * 1.6, -5.0),
		PLACEHOLDER_SUIT_DK, 2.0)

	# Torso and pack.
	draw_rect(Rect2(-3.0, -12.0, 6.0, 7.0), PLACEHOLDER_SUIT)
	draw_rect(Rect2(-3.0, -12.0, 6.0, 2.0), PLACEHOLDER_SUIT_DK)

	# Helmet, with a visor on the camera-facing rows (S, SE, SW).
	draw_circle(Vector2(0, -14.0), 3.0, PLACEHOLDER_HELMET)
	if _facing == 0 or _facing == 1 or _facing == 7:
		var lean := 0.0
		if _facing == 1:
			lean = 1.0
		elif _facing == 7:
			lean = -1.0
		draw_circle(Vector2(lean, -14.2), 1.4, PLACEHOLDER_VISOR)
