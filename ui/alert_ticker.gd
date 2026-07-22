extends VBoxContainer
## Fading stack of recent alerts, driven entirely by Events.alert. Screen-space,
## holds no game logic — it just renders what the sim announces. Newest on top;
## each entry fades and frees itself after a few seconds.

const MAX_ALERTS := 4
const HOLD := 5.0    # seconds fully visible before fading
const FADE := 1.2    # fade-out duration

# By AlertMonitor.Level: 0 = info, 1 = warning, 2 = critical.
const COLORS := {
	0: Color("cdb98a"),  # info  — sand
	1: Color("e0902f"),  # warn  — amber-orange
	2: Color("e0503f"),  # crit  — red
}

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	Events.alert.connect(_on_alert)

func _on_alert(text: String, level: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", COLORS.get(level, COLORS[0]))
	# A dark outline keeps the text legible over any terrain colour.
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(lbl)
	move_child(lbl, 0)  # newest on top
	while get_child_count() > MAX_ALERTS:
		var old := get_child(get_child_count() - 1)
		remove_child(old)
		old.queue_free()

	# Tween is bound to the label, so a capped-out label frees cleanly.
	var tw := lbl.create_tween()
	tw.tween_interval(HOLD)
	tw.tween_property(lbl, "modulate:a", 0.0, FADE)
	tw.tween_callback(lbl.queue_free)
