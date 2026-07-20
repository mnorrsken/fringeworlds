class_name IsoCamera
extends Camera2D
## Camera controls: WASD/arrows + middle-mouse-drag panning, stepped integer
## zoom. Zoom is driven by ALL of: mouse wheel, trackpad two-finger scroll
## (pan gesture) and pinch (magnify gesture) — needed on macOS, where a trackpad
## / Magic Mouse never emit wheel events — plus keyboard +/-. Integer factors
## keep pixels crisp.

const ZOOM_STEPS: Array[float] = [1.0, 2.0, 3.0, 4.0]
const PAN_SPEED := 260.0  # world px/sec at zoom 1x

# Gestures fire many small events; accumulate until a threshold, then step once.
const PAN_GESTURE_PER_STEP := 14.0   # accumulated scroll px per zoom step
const MAGNIFY_PER_STEP := 0.18       # accumulated pinch factor per zoom step

var _zoom_index := 1
var _pan_accum := 0.0
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
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(-1)
	elif event is InputEventPanGesture:
		# Trackpad / Magic Mouse scroll. Up (negative y) zooms in, like the wheel.
		_pan_accum += event.delta.y
		while _pan_accum <= -PAN_GESTURE_PER_STEP:
			_pan_accum += PAN_GESTURE_PER_STEP
			zoom_by(1)
		while _pan_accum >= PAN_GESTURE_PER_STEP:
			_pan_accum -= PAN_GESTURE_PER_STEP
			zoom_by(-1)
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
		if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			zoom_by(1)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			zoom_by(-1)

## Steps the zoom by `steps` levels (clamped), keeping integer factors.
func zoom_by(steps: int) -> void:
	_zoom_index = clampi(_zoom_index + steps, 0, ZOOM_STEPS.size() - 1)
	_apply_zoom()

func _apply_zoom() -> void:
	var z := ZOOM_STEPS[_zoom_index]
	zoom = Vector2(z, z)
