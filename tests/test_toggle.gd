extends RefCounted
## Switching buildings off by hand: what a stood-down building stops doing, what
## it keeps doing, and what the player isn't allowed to switch.

func _defs() -> Dictionary:
	return {
		"hub": {  # the colony controller — not switchable
			"name": "Hub", "size": 1, "cost": {}, "power": 20, "workers": 0,
			"colony_controller": true, "life_support": 4,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"drain": {  # 8 power, no output — the thing you'd want to stand down
			"name": "Drain", "size": 1, "cost": {}, "power": -8,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"smelt": {  # 5 power, 2 workers, 2 ore -> 1 metal every 2 ticks
			"name": "Smelt", "size": 1, "cost": {"metal": 10}, "power": -5, "workers": 2,
			"recipe": {"inputs": {"ore": 2}, "outputs": {"metal": 1}, "ticks": 2},
			"storage": {"ore": 100, "metal": 100},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

func _flat_map(n := 16) -> ColonyMap:
	var m := ColonyMap.new(n, n)
	for y in n:
		for x in n:
			m.set_terrain(Vector2i(x, y), ColonyMap.Terrain.REGOLITH)
	return m

func _colony(stock := {}) -> Colony:
	var c := Colony.new(_flat_map(), _defs(), stock)
	c.population = 0  # isolate building economics from colonist consumption
	return c

func test_switched_off_building_stops_running(t: Object) -> void:
	var c := _colony({"ore": 100, "metal": 100})
	c.place("hub", Vector2i(1, 1))
	var s = c.place("smelt", Vector2i(3, 1))
	c.population = 2
	for i in 4:
		c.tick()
	t.eq(int(c.stockpile.get("metal", 0)), 92, "smelter runs: 90 left after cost, +2 made")
	t.ok(c.toggle_at(Vector2i(3, 1)) == false, "toggling a running building returns off")
	t.ok(not s.active, "switching off takes effect immediately, not next tick")
	t.eq(str(s.idle_reason), Colony.OFF_REASON, "and says why")
	for i in 10:
		c.tick()
	t.eq(int(c.stockpile.get("metal", 0)), 92, "nothing produced while switched off")

func test_switching_back_on_resumes(t: Object) -> void:
	var c := _colony({"ore": 100, "metal": 100})
	c.place("hub", Vector2i(1, 1))
	c.place("smelt", Vector2i(3, 1))
	c.population = 2
	c.toggle_at(Vector2i(3, 1))
	for i in 6:
		c.tick()
	t.ok(c.toggle_at(Vector2i(3, 1)) == true, "toggling again returns on")
	for i in 4:
		c.tick()
	t.eq(int(c.stockpile.get("metal", 0)), 92, "production resumes once switched back on")

func test_off_building_frees_power(t: Object) -> void:
	# Hub makes 20; drain (8) is older, smelter (5) newer — both fit, so make it
	# tight by adding a second drain that gets shed.
	var c := _colony({"ore": 100, "metal": 100})
	c.place("hub", Vector2i(1, 1))
	c.place("drain", Vector2i(2, 1))
	c.place("drain", Vector2i(3, 1))
	var d3 = c.place("drain", Vector2i(4, 1))   # 24 > 20: newest is shed
	c.tick()
	t.ok(not d3.active, "newest consumer shed on deficit")
	c.toggle_at(Vector2i(2, 1))                  # stand the oldest one down
	c.tick()
	t.ok(d3.active, "freeing an older consumer's power lets the newest run")
	t.eq(c.power_consumed, 16, "the switched-off building draws nothing")

func test_off_building_frees_workers(t: Object) -> void:
	var c := _colony({"ore": 100, "metal": 100})
	c.place("hub", Vector2i(1, 1))
	c.place("smelt", Vector2i(3, 1))
	var s2 = c.place("smelt", Vector2i(4, 1))
	c.population = 2  # only enough for one smelter
	c.tick()
	t.ok(not s2.active, "second smelter has no workers")
	t.eq(str(s2.idle_reason), "No workers", "and says so")
	c.toggle_at(Vector2i(3, 1))
	c.tick()
	t.ok(s2.active, "standing the first smelter down staffs the second")

func test_off_generator_stops_producing_power(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(1, 1))
	c.place("drain", Vector2i(2, 1))
	c.tick()
	t.eq(c.power_produced, 20, "hub generates")
	# A generator that isn't the controller can be stood down, and then it makes
	# nothing: the switch is a real disconnect, not just an idle flag.
	var c2 := _colony()
	c2.defs["gen"] = {
		"name": "Gen", "size": 1, "cost": {}, "power": 12,
		"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
	}
	c2.place("gen", Vector2i(1, 1))
	c2.tick()
	t.eq(c2.power_produced, 12, "generator counted while on")
	c2.toggle_at(Vector2i(1, 1))
	c2.tick()
	t.eq(c2.power_produced, 0, "switched-off generator produces nothing")

func test_hub_cannot_be_switched_off(t: Object) -> void:
	var c := _colony()
	var hub = c.place("hub", Vector2i(1, 1))
	t.ok(not c.can_toggle(int(hub.id)), "the colony controller has no switch")
	t.ok(c.toggle_at(Vector2i(1, 1)) == null, "toggling it does nothing")
	t.ok(c.is_enabled(int(hub.id)), "and it stays on")

func test_toggle_empty_cell(t: Object) -> void:
	var c := _colony()
	t.ok(c.toggle_at(Vector2i(9, 9)) == null, "nothing to switch on bare ground")

func test_off_building_keeps_its_storage(t: Object) -> void:
	# Storage is physical: an unpowered warehouse still holds what's in it, and a
	# switched-off one is no different.
	var c := _colony({"metal": 100})
	c.place("hub", Vector2i(1, 1))
	c.place("smelt", Vector2i(3, 1))
	t.eq(c.storage_for("ore"), 100, "smelter's storage counts")
	c.toggle_at(Vector2i(3, 1))
	t.eq(c.storage_for("ore"), 100, "and still counts when switched off")

func test_off_building_flushes_its_hopper(t: Object) -> void:
	# Output already made isn't stranded by the switch — it drains into the store.
	var c := _colony({"ore": 100, "metal": 100})
	c.place("hub", Vector2i(1, 1))
	var s = c.place("smelt", Vector2i(3, 1))
	c.population = 2
	c.tick()
	s.buffer["metal"] = 3
	c.toggle_at(Vector2i(3, 1))
	var before := int(c.stockpile.get("metal", 0))
	c.tick()
	t.eq(int(c.stockpile.get("metal", 0)), before + 3, "the hopper empties into the store")
	t.ok(s.buffer.is_empty(), "and the hopper is left empty")

func test_no_hub_does_not_overwrite_the_switch(t: Object) -> void:
	# Losing the hub shuts everything down, but a building the player stood down
	# should still say so when the hub comes back.
	var c := _colony({"ore": 100, "metal": 100})
	var hub = c.place("hub", Vector2i(1, 1))
	var s = c.place("smelt", Vector2i(3, 1))
	c.toggle_at(Vector2i(3, 1))
	c.demolish_at(hub.origin)
	c.tick()
	t.eq(str(s.idle_reason), Colony.OFF_REASON, "still reads as switched off, not 'No colony hub'")

func test_switch_survives_save_load(t: Object) -> void:
	var c := _colony({"ore": 100, "metal": 100})
	c.place("hub", Vector2i(1, 1))
	var s = c.place("smelt", Vector2i(3, 1))
	c.toggle_at(Vector2i(3, 1))
	var round_trip := Colony.from_dict(c.map, c.defs,
		JSON.parse_string(JSON.stringify(c.to_dict())))
	t.ok(not round_trip.is_enabled(int(s.id)), "the switch is saved and restored")

func test_old_saves_default_to_on(t: Object) -> void:
	var c := _colony({"ore": 100, "metal": 100})
	c.place("hub", Vector2i(1, 1))
	var s = c.place("smelt", Vector2i(3, 1))
	var d := c.to_dict()
	for bd in d.buildings:
		bd.erase("enabled")   # a save written before the switch existed
	var loaded := Colony.from_dict(c.map, c.defs, d)
	t.ok(loaded.is_enabled(int(s.id)), "buildings from an old save are running")

func test_report_exposes_the_switch(t: Object) -> void:
	var c := _colony({"ore": 100, "metal": 100})
	var hub = c.place("hub", Vector2i(1, 1))
	var s = c.place("smelt", Vector2i(3, 1))
	var rep := c.building_report(int(s.id))
	t.ok(rep.enabled, "report says a fresh building is on")
	t.ok(rep.can_toggle, "and that it can be switched")
	c.toggle_at(Vector2i(3, 1))
	t.ok(not c.building_report(int(s.id)).enabled, "report follows the switch")
	t.ok(not c.building_report(int(hub.id)).can_toggle, "the hub reports no switch")
