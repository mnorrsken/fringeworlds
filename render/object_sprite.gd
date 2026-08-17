class_name ObjectSprite
extends Node2D
## One loose object on (or above) the map: a falling asteroid, a crashing one, or
## the chunk of ice it leaves behind.
##
## All three states of a kind share one frame box and one anchor — see the art
## contract in data/objects.json — so switching between them is only a change of
## texture and frame index, and the rock never jumps. Purely a view: it draws
## what it is told and reads nothing.

var _tex: Texture2D = null
var _frame_size := Vector2(48, 48)
var _anchor := Vector2(24, 43)
var _frames := 1
var _frame := 0

## `cfg` is one entry of data/objects.json (for frame_size/anchor).
func configure(cfg: Dictionary) -> void:
	var fs: Array = cfg.get("frame_size", [48, 48])
	_frame_size = Vector2(float(fs[0]), float(fs[1]))
	var an: Array = cfg.get("anchor", [_frame_size.x / 2.0, _frame_size.y - 4.0])
	_anchor = Vector2(float(an[0]), float(an[1]))
	queue_redraw()

## Swaps which animation is playing. `frames` is how many the strip holds (1 for
## a still).
func set_animation(tex: Texture2D, frames: int) -> void:
	if tex == _tex and frames == _frames:
		return
	_tex = tex
	_frames = maxi(1, frames)
	_frame = mini(_frame, _frames - 1)
	queue_redraw()

func set_frame(frame: int) -> void:
	var f := clampi(frame, 0, _frames - 1)
	if f == _frame:
		return
	_frame = f
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		return
	var src := Rect2(Vector2(_frame * _frame_size.x, 0.0), _frame_size)
	draw_texture_rect_region(_tex, Rect2(-_anchor, _frame_size), src)
