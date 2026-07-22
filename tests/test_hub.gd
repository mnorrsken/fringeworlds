extends RefCounted
## The Colony Hub: free life support for its base colonists, and a guaranteed
## reachable iron deposit in its survey range.

func _defs() -> Dictionary:
	return {
		"hub": {
			"name": "Colony Hub", "size": 2, "cost": {}, "power": 15, "workers": 0,
			"capacity": 4, "life_support": 4,
			"scan": {"max_radius": 4, "ticks_per_ring": 1},
			"guarantees_deposit_id": ColonyMap.Deposit.IRON,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"hab": {
			"name": "Hab", "size": 1, "cost": {}, "power": 0, "workers": 0, "capacity": 6,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

func _flat_map(n := 24) -> ColonyMap:
	var m := ColonyMap.new(n, n)
	for y in n:
		for x in n:
			m.set_terrain(Vector2i(x, y), ColonyMap.Terrain.REGOLITH)
	return m

func _count_iron(m: ColonyMap) -> int:
	var n := 0
	for y in m.height:
		for x in m.width:
			if m.get_deposit(Vector2i(x, y)) == ColonyMap.Deposit.IRON:
				n += 1
	return n

func test_hub_sustains_base_colonists(t: Object) -> void:
	# Empty stockpile: without the hub the base 4 would starve; with it they live.
	var c := Colony.new(_flat_map(), _defs(), {})
	c.population = 4
	c.place("hub", Vector2i(6, 6))
	for i in 200:
		c.tick()
	t.eq(c.population, 4, "hub keeps the base 4 alive with no stockpiled life support")
	t.eq(c.status, Colony.Status.PLAYING, "colony survives on the hub alone")

func test_uncovered_colonists_still_consume(t: Object) -> void:
	# Colonists beyond the hub's coverage of 4 must draw from the stockpile.
	var c := Colony.new(_flat_map(), _defs(), {"oxygen": 100, "water": 100, "food": 100})
	c.place("hub", Vector2i(6, 6))
	c.population = 6  # 2 uncovered
	for i in 120:
		c.tick()
	t.ok(int(c.stockpile["oxygen"]) < 100, "colonists beyond coverage consume oxygen")

func test_covered_colonists_show_no_drain(t: Object) -> void:
	var c := Colony.new(_flat_map(), _defs(), {})
	c.population = 4
	c.place("hub", Vector2i(6, 6))
	c.tick()
	t.ok(absf(float(c.rates().get("oxygen", 0.0))) < 0.0001, "no oxygen drain while the hub covers everyone")

func test_hub_guarantees_iron_when_absent(t: Object) -> void:
	var m := _flat_map()  # a flat map has no deposits at all
	var c := Colony.new(m, _defs(), {})
	t.eq(_count_iron(m), 0, "the flat map starts with no iron")
	c.place("hub", Vector2i(10, 10))
	t.ok(_count_iron(m) >= 1, "the hub injects an iron node into its survey area")
	# ...and it's mineable (buildable terrain, not under the hub footprint).
	var found := Vector2i(-1, -1)
	for y in m.height:
		for x in m.width:
			if m.get_deposit(Vector2i(x, y)) == ColonyMap.Deposit.IRON:
				found = Vector2i(x, y)
	t.ok(c.building_at(found).is_empty(), "the guaranteed iron is on an open, mineable tile")

func test_hub_does_not_duplicate_existing_iron(t: Object) -> void:
	var m := _flat_map()
	m.set_deposit(Vector2i(13, 11), ColonyMap.Deposit.IRON, 0.5)  # already reachable near the hub
	var c := Colony.new(m, _defs(), {})
	c.place("hub", Vector2i(10, 10))  # center (11,11); (13,11) is distance 2, in range
	t.eq(_count_iron(m), 1, "existing reachable iron isn't duplicated")
