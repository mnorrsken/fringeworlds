extends RefCounted
## Camera zoom controls: Z toggles 1x<->2x, pinch (magnify gesture) fine-zooms,
## and scroll does NOT zoom (guarding the "toggle on Z instead of scroll" change).

func _cam(index := 1) -> IsoCamera:
	var c := IsoCamera.new()
	c._zoom_index = index
	c._apply_zoom()
	return c

func test_z_toggles_1x_and_2x(t: Object) -> void:
	var c := _cam(0)  # 1x
	c.toggle_zoom()
	t.eq(c.zoom.x, 2.0, "Z from 1x -> 2x")
	c.toggle_zoom()
	t.eq(c.zoom.x, 1.0, "Z from 2x -> 1x")
	c.free()

func test_z_from_higher_zoom_snaps_to_1x(t: Object) -> void:
	var c := _cam(3)  # 4x
	c.toggle_zoom()
	t.eq(c.zoom.x, 1.0, "Z from 4x snaps back to 1x")
	c.free()

func test_z_key_event_toggles(t: Object) -> void:
	var c := _cam(0)
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.pressed = true
	c._unhandled_input(ev)
	t.eq(c.zoom.x, 2.0, "Z key event toggles zoom")
	c.free()

func test_pinch_zooms_in(t: Object) -> void:
	var c := _cam(1)  # 2x
	var ev := InputEventMagnifyGesture.new()
	ev.factor = 1.5  # pinch out
	c._unhandled_input(ev)
	t.ok(c.zoom.x > 2.0, "pinch out zooms in")
	c.free()

func test_scroll_does_not_zoom(t: Object) -> void:
	var c := _cam(1)  # 2x
	var ev := InputEventPanGesture.new()
	ev.delta = Vector2(0, -40)  # two-finger scroll — must be ignored for zoom
	c._unhandled_input(ev)
	t.eq(c.zoom.x, 2.0, "trackpad scroll no longer changes zoom")
	c.free()
