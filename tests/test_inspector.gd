extends RefCounted
## Building inspector: idle-reason tracking on the instance and the
## building_report() display payload the sidebar renders.

func _defs() -> Dictionary:
	return {
		"gen": {
			"name": "Gen", "size": 1, "cost": {}, "power": 5, "workers": 0,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"drain": {  # draws 8 power, more than one gen makes
			"name": "Drain", "size": 1, "cost": {}, "power": -8, "workers": 0,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"factory": {  # needs 3 workers, no power
			"name": "Factory", "size": 1, "cost": {}, "power": 0, "workers": 3,
			"recipe": {"inputs": {}, "outputs": {"parts": 1}, "ticks": 1},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"smelt": {  # needs 2 ore -> 1 metal, no power/workers
			"name": "Smelt", "size": 1, "cost": {}, "power": 0, "workers": 0,
			"recipe": {"inputs": {"ore": 2}, "outputs": {"metal": 1}, "ticks": 2},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

func _colony(stock := {}) -> Colony:
	var c := Colony.new(ColonyMap.new(16, 16), _defs(), stock)
	c.population = 0
	return c

func test_idle_reason_no_power(t: Object) -> void:
	var c := _colony()
	c.place("gen", Vector2i(1, 1))       # +5
	var d = c.place("drain", Vector2i(2, 1))  # needs 8 > 5
	c.tick()
	t.ok(not d.active, "drain shed on power deficit")
	t.eq(str(d.idle_reason), "No power", "idle reason names the power shortage")

func test_idle_reason_no_workers(t: Object) -> void:
	var c := _colony()
	c.population = 4
	c.place("factory", Vector2i(1, 1))
	var b = c.place("factory", Vector2i(2, 1))  # 3+3 = 6 workers > 4
	c.tick()
	t.ok(not b.active, "second factory idled for workers")
	t.eq(str(b.idle_reason), "No workers", "idle reason names the labor shortage")

func test_idle_reason_missing_inputs(t: Object) -> void:
	var c := _colony()  # no ore
	var s = c.place("smelt", Vector2i(1, 1))
	for i in 3:
		c.tick()
	t.ok(s.active, "smelter is powered/staffed — it's stalled, not shut down")
	t.ok(str(s.idle_reason).begins_with("Needs"), "idle reason names the missing input")
	t.ok("ore" in str(s.idle_reason), "the missing input is ore")

func test_idle_reason_clears_when_running(t: Object) -> void:
	var c := _colony({"ore": 100})
	var s = c.place("smelt", Vector2i(1, 1))
	for i in 3:
		c.tick()
	t.eq(str(s.idle_reason), "", "a producing building has no idle reason")

func test_building_report_shape(t: Object) -> void:
	var c := _colony({"ore": 100})
	var g = c.place("gen", Vector2i(1, 1))
	var s = c.place("smelt", Vector2i(2, 1))
	c.tick()
	var gr := c.building_report(g.id)
	t.eq(str(gr.name), "Gen", "report carries the display name")
	t.ok(gr.active, "generator is active")
	t.eq(int(gr.power), 5, "report carries power")
	t.ok(not gr.has("recipe"), "a generator has no recipe block")
	var sr := c.building_report(s.id)
	t.ok(sr.has("recipe"), "the smelter's report has its recipe")
	t.eq(int(sr.recipe.ticks), 2, "recipe tick count is exposed")

func test_building_report_missing_id(t: Object) -> void:
	var c := _colony()
	t.ok(c.building_report(999).is_empty(), "unknown id yields an empty report")
