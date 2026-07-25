extends RefCounted
## Guards the `fx` overlay contract in data/buildings.json (see
## render/building_fx.gd): effect kinds the renderer knows, and anchor offsets
## that actually land on the building's art rather than floating in space.
##
## Anchor offsets are pixels from the sprite anchor — the bottom centre of the
## front footprint cell — so for an N-tile-wide building drawn at 64*N square,
## a valid `at` is x in [-32N, 32N] and y in [-(64N - 16), 16].

const TILE_H := 32

func _buildings() -> Array:
	return JSON.parse_string(
		FileAccess.get_file_as_string("res://data/buildings.json"))

func test_fx_entries_use_known_types(t: Object) -> void:
	for def in _buildings():
		for fx in def.get("fx", []):
			t.ok(fx is Dictionary, "%s: fx entry must be an object" % def.id)
			t.ok(BuildingFX.TYPES.has(fx.get("type", "")),
				"%s: unknown fx type '%s'" % [def.id, fx.get("type", "")])

func test_fx_anchors_land_on_the_sprite(t: Object) -> void:
	for def in _buildings():
		var span: float = 64.0 * float(def.get("size", 1))
		for fx in def.get("fx", []):
			var at: Array = fx.get("at", [])
			t.eq(at.size(), 2, "%s: fx '%s' needs an [x, y] anchor" % [def.id, fx.type])
			if at.size() != 2:
				continue
			t.ok(absf(float(at[0])) <= span * 0.5,
				"%s: fx '%s' x anchor off the sprite" % [def.id, fx.type])
			t.ok(float(at[1]) <= TILE_H / 2.0 and float(at[1]) >= -(span - TILE_H / 2.0),
				"%s: fx '%s' y anchor off the sprite" % [def.id, fx.type])

func test_fx_colors_and_periods_are_valid(t: Object) -> void:
	for def in _buildings():
		for fx in def.get("fx", []):
			if fx.has("color"):
				t.ok(Color.html_is_valid(str(fx.color)),
					"%s: fx '%s' bad colour '%s'" % [def.id, fx.type, fx.color])
			if fx.has("period"):
				t.ok(float(fx.period) > 0.0, "%s: fx '%s' needs a positive period"
					% [def.id, fx.type])

func test_lamp_blinks_dark_for_most_of_its_cycle(t: Object) -> void:
	var period := 2.0
	var duty := 0.2
	# Peak sits in the middle of the lit window, and the lamp is dark outside it.
	t.eq(snappedf(BuildingFX.lamp_intensity(period * duty * 0.5, period, duty), 0.01), 1.0,
		"lamp is fully lit mid-window")
	t.eq(BuildingFX.lamp_intensity(0.0, period, duty), 0.0, "dark at the cycle start")
	t.eq(BuildingFX.lamp_intensity(period * duty, period, duty), 0.0,
		"dark at the window's end")
	t.eq(BuildingFX.lamp_intensity(period * 0.5, period, duty), 0.0, "dark mid-cycle")

func test_lamp_intensity_repeats_every_period(t: Object) -> void:
	var lit := BuildingFX.lamp_intensity(0.3, 2.0, 0.4)
	t.ok(lit > 0.0, "0.3s into a 2.0s/0.4-duty cycle is lit")
	t.eq(snappedf(BuildingFX.lamp_intensity(0.3 + 2.0 * 3, 2.0, 0.4), 0.001),
		snappedf(lit, 0.001), "same point three cycles later")

# Only art-backed buildings get fx overlays — the procedural fallback block
# draws its own lamps and smoke, and has no pixel anchors to hang them on.
func test_fx_only_on_buildings_with_art(t: Object) -> void:
	for def in _buildings():
		if def.has("fx"):
			t.ok(str(def.get("sprite", "")) != "",
				"%s: fx declared without a sprite" % def.id)
