extends RefCounted
## Camera zoom via macOS trackpad gestures (constructed input events fed
## directly to the handler). Guards the fix for "scroll doesn't zoom on Mac".

func _cam() -> IsoCamera:
	var c := IsoCamera.new()
	c._zoom_index = 1  # start at 2x (mid-range) so we can step either way
	c.zoom = Vector2(2, 2)
	return c

func test_pan_gesture_scroll_up_zooms_in(t: Object) -> void:
	var c := _cam()
	var ev := InputEventPanGesture.new()
	ev.delta = Vector2(0, -30)  # two-finger scroll up
	c._unhandled_input(ev)
	t.ok(c.zoom.x > 2.0, "trackpad scroll up zooms in")
	c.free()

func test_pan_gesture_scroll_down_zooms_out(t: Object) -> void:
	var c := _cam()
	var ev := InputEventPanGesture.new()
	ev.delta = Vector2(0, 30)  # two-finger scroll down
	c._unhandled_input(ev)
	t.ok(c.zoom.x < 2.0, "trackpad scroll down zooms out")
	c.free()

func test_magnify_gesture_zooms(t: Object) -> void:
	var c := _cam()
	var ev := InputEventMagnifyGesture.new()
	ev.factor = 1.5  # pinch out
	c._unhandled_input(ev)
	t.ok(c.zoom.x > 2.0, "pinch out zooms in")
	c.free()

func test_tiny_gesture_below_threshold_does_nothing(t: Object) -> void:
	var c := _cam()
	var ev := InputEventPanGesture.new()
	ev.delta = Vector2(0, -2)  # smaller than PAN_GESTURE_PER_STEP
	c._unhandled_input(ev)
	t.eq(c.zoom.x, 2.0, "sub-threshold scroll does not step zoom")
	c.free()
