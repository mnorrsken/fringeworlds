extends RefCounted
## Tech unlocks: buildings gated behind having built their prerequisites.

func _defs() -> Dictionary:
	return {
		"solar": {
			"name": "Solar", "size": 1, "cost": {}, "power": 10, "workers": 0,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"survey": {
			"name": "Survey", "size": 1, "cost": {}, "power": 0, "workers": 0,
			"requires_built": ["solar"],
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"mine": {
			"name": "Mine", "size": 1, "cost": {}, "power": 0, "workers": 0,
			"requires_built": ["survey"],
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

func _colony() -> Colony:
	return Colony.new(ColonyMap.new(16, 16), _defs(), {})

func test_no_prereq_is_unlocked(t: Object) -> void:
	var c := _colony()
	t.ok(c.is_unlocked("solar"), "solar has no prerequisites")

func test_locked_until_prereq_built(t: Object) -> void:
	var c := _colony()
	t.ok(not c.is_unlocked("survey"), "survey locked before solar exists")
	t.ok(not c.can_place("survey", Vector2i(2, 2)).ok, "cannot place a locked building")
	c.place("solar", Vector2i(0, 0))
	t.ok(c.is_unlocked("survey"), "survey unlocks once solar is built")
	t.ok(c.can_place("survey", Vector2i(2, 2)).ok, "can place after unlock")

func test_missing_prereqs_reported(t: Object) -> void:
	var c := _colony()
	t.eq(c.missing_prereqs("survey"), ["solar"], "missing prereq listed")
	c.place("solar", Vector2i(0, 0))
	t.eq(c.missing_prereqs("survey"), [], "no missing prereqs after building")

func test_unlock_survives_demolish(t: Object) -> void:
	var c := _colony()
	var solar = c.place("solar", Vector2i(0, 0))
	c.demolish_at(solar.origin)
	t.ok(c.is_unlocked("survey"), "unlock persists after the prerequisite is demolished")

func test_chained_unlocks(t: Object) -> void:
	var c := _colony()
	t.ok(not c.is_unlocked("mine"), "mine locked at start")
	c.place("solar", Vector2i(0, 0))
	t.ok(not c.is_unlocked("mine"), "mine still locked with only solar")
	c.place("survey", Vector2i(2, 2))
	t.ok(c.is_unlocked("mine"), "mine unlocks after survey")
