extends RefCounted
## Skyfall: the drop schedule, the fall → crash → landed sequence, and the object
## layer the rock ends up in.

func _balance() -> Balance:
	var b := Balance.new()
	# Fast weather-free skyfall so a test doesn't tick for minutes.
	b.storms_enabled = false
	b.asteroid_grace_ticks = 5
	b.asteroid_interval_ticks = 30
	b.asteroid_interval_jitter = 0
	b.asteroid_fall_ticks = 4
	b.asteroid_crash_ticks = 2
	b.asteroid_max_on_ground = 6
	return b

func _flat_map(n := 16) -> ColonyMap:
	var m := ColonyMap.new(n, n)
	for y in n:
		for x in n:
			m.set_terrain(Vector2i(x, y), ColonyMap.Terrain.REGOLITH)
	return m

func _colony(b: Balance = null) -> Colony:
	var c := Colony.new(_flat_map(), {}, {}, b if b != null else _balance())
	c.population = 0
	return c

# --- the map's object layer --------------------------------------------------

func test_map_holds_objects(t: Object) -> void:
	var m := _flat_map()
	var cell := Vector2i(3, 4)
	t.ok(not m.has_object(cell), "ground starts clear")
	m.set_object(cell, {"kind": "ice_asteroid"})
	t.ok(m.has_object(cell), "an object can be put on a tile")
	t.eq(str(m.get_object(cell).kind), "ice_asteroid", "and read back")
	t.eq(m.objects().size(), 1, "and shows up in the index the view reads")
	var taken := m.take_object(cell)
	t.eq(str(taken.kind), "ice_asteroid", "taking it returns it")
	t.ok(not m.has_object(cell), "and leaves the tile clear")
	t.eq(m.take_object(cell), {}, "taking from a clear tile gives nothing")

func test_objects_survive_save_load(t: Object) -> void:
	var m := _flat_map()
	m.set_object(Vector2i(2, 9), {"kind": "ice_asteroid"})
	var round_trip := ColonyMap.from_dict(
		JSON.parse_string(JSON.stringify(m.to_dict())))
	t.ok(round_trip.has_object(Vector2i(2, 9)), "the object comes back with the map")
	t.eq(str(round_trip.get_object(Vector2i(2, 9)).kind), "ice_asteroid", "intact")

func test_old_maps_load_without_objects(t: Object) -> void:
	var m := _flat_map()
	var d := m.to_dict()
	d.erase("objects")   # a save written before objects existed
	t.eq(ColonyMap.from_dict(d).objects().size(), 0, "loads with clear ground")

# --- the fall ----------------------------------------------------------------

func test_rock_falls_crashes_and_lands(t: Object) -> void:
	var c := _colony()
	var launched := -1
	var landed := -1
	var saw_crashing := false
	for i in 40:
		c.tick()
		for e in c.asteroid_events:
			if str(e.type) == "launch" and launched < 0:
				launched = i
			if str(e.type) == "impact" and landed < 0:
				landed = i
		if not c.asteroids.falling.is_empty() \
				and int(c.asteroids.falling[0].phase) == Asteroids.Phase.CRASHING:
			saw_crashing = true
		if landed >= 0:
			break   # stop on the first landing; the next drop is already due
	t.ok(launched >= 0, "a rock is released")
	t.ok(saw_crashing, "it crashes before it lands")
	t.eq(landed - launched, 6, "fall (4) then crash (2) ticks, then it's down")
	t.eq(c.map.objects().size(), 1, "and it leaves exactly one object behind")
	t.ok(c.asteroids.falling.is_empty(), "nothing left in the air")

func test_landed_rock_is_an_ice_asteroid(t: Object) -> void:
	var c := _colony()
	for i in 40:
		c.tick()
	var cells := c.map.objects().keys()
	t.eq(cells.size(), 1, "one landed")
	t.eq(str(c.map.get_object(cells[0]).kind), Asteroids.ICE, "it's an ice asteroid")

func test_grace_period_then_a_steady_cadence(t: Object) -> void:
	var c := _colony()
	var launches := []
	for i in 200:
		c.tick()
		for e in c.asteroid_events:
			if str(e.type) == "launch":
				launches.append(i)
	t.ok(launches.size() >= 3, "several drops over 200 ticks")
	t.eq(launches[0], 4, "the first waits out the grace period")
	t.eq(launches[1] - launches[0], 30, "then one every interval")

func test_rocks_only_land_on_open_ground(t: Object) -> void:
	var c := _colony()
	# Canyon everywhere but one patch: every rock has to find that patch.
	for y in c.map.height:
		for x in c.map.width:
			c.map.set_terrain(Vector2i(x, y), ColonyMap.Terrain.VOID)
	for dy in 5:
		for dx in 5:
			c.map.set_terrain(Vector2i(4 + dx, 4 + dy), ColonyMap.Terrain.REGOLITH)
	for i in 400:
		c.tick()
	var cells := c.map.objects().keys()
	t.ok(cells.size() >= 2, "rocks find the open ground (%d landed)" % cells.size())
	for cell in cells:
		t.ok(cell.x >= 4 and cell.x < 9 and cell.y >= 4 and cell.y < 9,
			"landed on open ground, not in the canyon (%s)" % cell)

func test_a_tile_only_takes_one(t: Object) -> void:
	var c := _colony()
	t.ok(c.can_hold_object(Vector2i(4, 4)), "clear ground is fair game")
	c.map.set_object(Vector2i(4, 4), {"kind": Asteroids.ICE})
	t.ok(not c.can_hold_object(Vector2i(4, 4)), "an occupied tile is not")

func test_canyons_and_crystal_are_refused(t: Object) -> void:
	var c := _colony()
	c.map.set_terrain(Vector2i(1, 1), ColonyMap.Terrain.VOID)
	c.map.set_terrain(Vector2i(2, 1), ColonyMap.Terrain.CRYSTAL)
	c.map.set_terrain(Vector2i(3, 1), ColonyMap.Terrain.ICE)
	t.ok(not c.can_hold_object(Vector2i(1, 1)), "nothing rests in a canyon")
	t.ok(not c.can_hold_object(Vector2i(2, 1)), "nor on impassable crystal")
	t.ok(c.can_hold_object(Vector2i(3, 1)), "an ice field is fine")
	t.ok(not c.can_hold_object(Vector2i(-1, 0)), "off the map is not")

func test_a_building_blocks_a_landing(t: Object) -> void:
	var defs := {"shed": {
		"name": "Shed", "size": 1, "cost": {}, "power": 0,
		"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
	}}
	var c := Colony.new(_flat_map(), defs, {}, _balance())
	c.place("shed", Vector2i(5, 5))
	t.ok(not c.can_hold_object(Vector2i(5, 5)), "rocks don't land inside buildings")

func test_building_over_a_rock_clears_it(t: Object) -> void:
	var defs := {"shed": {
		"name": "Shed", "size": 2, "cost": {}, "power": 0,
		"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
	}}
	var c := Colony.new(_flat_map(), defs, {}, _balance())
	c.map.set_object(Vector2i(6, 7), {"kind": Asteroids.ICE})
	c.place("shed", Vector2i(6, 6))   # 2x2, so it covers (6,7)
	t.ok(not c.map.has_object(Vector2i(6, 7)),
		"construction clears the site rather than burying a rock under it")

func test_ground_cap_stops_the_pile_up(t: Object) -> void:
	var b := _balance()
	b.asteroid_max_on_ground = 2
	var c := _colony(b)
	for i in 300:
		c.tick()
	t.eq(c.map.objects().size(), 2, "the cap holds once nothing collects them")

func test_skyfall_can_be_switched_off(t: Object) -> void:
	var b := _balance()
	b.asteroids_enabled = false
	var c := _colony(b)
	for i in 300:
		c.tick()
	t.eq(c.map.objects().size(), 0, "a quiet sky drops nothing")
	t.ok(c.asteroids.falling.is_empty(), "and nothing is ever in the air")

func test_schedule_is_deterministic(t: Object) -> void:
	var b := _balance()
	b.asteroid_interval_jitter = 9
	var seen := []
	for run in 2:
		var c := Colony.new(_flat_map(), {}, {}, b)
		c.map.seed = 4242
		c.asteroids = Asteroids.new(b, 4242)
		var cells := []
		for i in 200:
			c.tick()
			for e in c.asteroid_events:
				if str(e.type) == "impact":
					cells.append(e.cell)
		seen.append(cells)
	t.eq(seen[0], seen[1], "same seed, same rocks in the same places")
	t.ok(not seen[0].is_empty(), "and it actually dropped some")

func test_progress_runs_zero_to_one(t: Object) -> void:
	var c := _colony()
	while c.asteroids.falling.is_empty():
		c.tick()
	var a: Dictionary = c.asteroids.falling[0]
	var p := c.asteroids.progress(a)
	t.ok(p >= 0.0 and p < 1.0, "a rock just released has barely started (%f)" % p)
	var last := p
	for i in 3:
		c.tick()
		if c.asteroids.falling.is_empty():
			break
		last = c.asteroids.progress(c.asteroids.falling[0])
	t.ok(last > p, "and the fall progresses")

func test_flight_survives_save_load(t: Object) -> void:
	var c := _colony()
	while c.asteroids.falling.is_empty():
		c.tick()
	c.tick()
	var a: Dictionary = c.asteroids.falling[0]
	var round_trip := Colony.from_dict(c.map, c.defs,
		JSON.parse_string(JSON.stringify(c.to_dict())), c.balance)
	t.eq(round_trip.asteroids.falling.size(), 1, "the rock is still in the air")
	var b: Dictionary = round_trip.asteroids.falling[0]
	t.eq(b.cell, a.cell, "aimed at the same tile")
	t.eq(int(b.ticks_left), int(a.ticks_left), "with the same time to impact")
	# ...and it still lands.
	for i in 10:
		round_trip.tick()
	t.ok(round_trip.map.has_object(a.cell), "and it comes down where it was aimed")

func test_old_saves_load_with_an_empty_sky(t: Object) -> void:
	var c := _colony()
	var d := c.to_dict()
	d.erase("asteroids")   # a save written before skyfall existed
	var loaded := Colony.from_dict(c.map, c.defs, d, c.balance)
	t.ok(loaded.asteroids.falling.is_empty(), "loads with a clear sky")

func test_impact_is_announced(t: Object) -> void:
	var c := _colony()
	var mon := AlertMonitor.new()
	var texts := []
	for i in 40:
		c.tick()
		for a in mon.check(c):
			texts.append(str(a.text))
	t.ok(" | ".join(texts).contains("Ice asteroid down"), "the landing is announced")
