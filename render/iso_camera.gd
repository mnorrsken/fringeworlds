class_name IsoCamera
extends Camera2D
## Camera controls: WASD + middle-mouse-drag panning, stepped integer zoom on
## the mouse wheel. Zoom stays at integer factors to keep pixels crisp.

const ZOOM_STEPS: Array[float] = [1.0, 2.0, 3.0, 4.0]
const PAN_SPEED := 260.0  # world px/sec at zoom 1x

var _zoom_index := 1

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
			_zoom_index = clampi(_zoom_index + 1, 0, ZOOM_STEPS.size() - 1)
			_apply_zoom()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_index = clampi(_zoom_index - 1, 0, ZOOM_STEPS.size() - 1)
			_apply_zoom()

func _apply_zoom() -> void:
	var z := ZOOM_STEPS[_zoom_index]
	zoom = Vector2(z, z)
