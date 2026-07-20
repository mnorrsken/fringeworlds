class_name IsoCamera
extends Camera2D
## Camera controls: WASD/arrows + middle-mouse-drag panning. Zoom is toggled
## 1x<->2x on Z (the primary control), with pinch (magnify gesture) and keyboard
## +/- as secondary fine zoom. Scroll/wheel intentionally does NOT zoom — on a
## trackpad that was too twitchy. Zoom stays at integer factors for crisp pixels.

const ZOOM_STEPS: Array[float] = [1.0, 2.0, 3.0, 4.0]
const PAN_SPEED := 420.0  # world px/sec at zoom 1x

# Pinch fires many small events; accumulate to a threshold, then step once.
const MAGNIFY_PER_STEP := 0.18

var _zoom_index := 1
var _magnify_accum := 0.0

func _ready() -> void:
	_apply_zoom()

func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		# Divide by zoom so pan speed feels constant on screen at any zoom.
		position += dir.normalized() * PAN_SPEED * delta / zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		position -= event.relative / zoom.x
	elif event is InputEventMagnifyGesture:
		# Pinch. factor > 1 = fingers apart = zoom in.
		_magnify_accum += event.factor - 1.0
		while _magnify_accum >= MAGNIFY_PER_STEP:
			_magnify_accum -= MAGNIFY_PER_STEP
			zoom_by(1)
		while _magnify_accum <= -MAGNIFY_PER_STEP:
			_magnify_accum += MAGNIFY_PER_STEP
			zoom_by(-1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z:
			toggle_zoom()
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			zoom_by(1)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			zoom_by(-1)

## Toggles between 1x and 2x. From any higher zoom, snaps back to 1x first.
func toggle_zoom() -> void:
	_zoom_index = 1 if _zoom_index == 0 else 0
	_apply_zoom()

## Steps the zoom by `steps` levels (clamped), keeping integer factors.
func zoom_by(steps: int) -> void:
	_zoom_index = clampi(_zoom_index + steps, 0, ZOOM_STEPS.size() - 1)
	_apply_zoom()

func _apply_zoom() -> void:
	var z := ZOOM_STEPS[_zoom_index]
	zoom = Vector2(z, z)
