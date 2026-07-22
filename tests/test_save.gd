extends RefCounted
## Save/load serialization: ColonyMap and Colony survive a to_dict → JSON →
## from_dict → to_dict round-trip unchanged. This is the M7 acceptance check
## ("a re-serialized snapshot equals the saved file"), done at the data level so
## it needs no autoloads or files.

func _defs() -> Dictionary:
	return {
		"gen": {
			"name": "Gen", "size": 1, "cost": {}, "power": 10, "workers": 0,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"harv": {
			"name": "Harv", "size": 1, "cost": {}, "power": -2, "workers": 0,
			"recipe": {"inputs": {}, "outputs": {"water": 1}, "ticks": 2},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"survey": {
			"name": "Survey", "size": 2, "cost": {}, "power": 0, "workers": 0,
			"scan": {"max_radius": 3, "ticks_per_ring": 1},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"mine": {  # no requires_deposit so it can be placed on the flat test map
			"name": "Mine", "size": 1, "cost": {}, "power": 0, "workers": 0,
			"mine": {"base_per_tick": 0.5},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

func _flat_map(n := 16) -> ColonyMap:
	var m := ColonyMap.new(n, n)
	for y in n:
		for x in n:
			m.set_terrain(Vector2i(x, y), ColonyMap.Terrain.REGOLITH)
	return m

func test_map_roundtrip(t: Object) -> void:
	var m := ColonyMap.new(24, 24)
	m.generate(4242)
	# Reveal a few tiles so the scan layer isn't uniformly zero.
	m.set_scan(Vector2i(3, 3), ColonyMap.Scan.COARSE)
	m.set_scan(Vector2i(4, 4), ColonyMap.Scan.CONFIRMED)

	var text := JSON.stringify(m.to_dict())
	var m2 := ColonyMap.from_dict(JSON.parse_string(text))

	t.eq(m2.width, m.width, "width preserved")
	t.eq(m2.height, m.height, "height preserved")
	t.eq(m2.seed, m.seed, "seed preserved")
	var same := true
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if m2.get_terrain(c) != m.get_terrain(c) \
					or m2.get_deposit(c) != m.get_deposit(c) \
					or m2.get_scan(c) != m.get_scan(c) \
					or absf(m2.get_richness(c) - m.get_richness(c)) > 0.0001:
				same = false
	t.ok(same, "every cell's terrain/deposit/scan/richness survives the round-trip")
	t.eq(JSON.stringify(m2.to_dict()), text, "map re-serializes byte-for-byte identically")

func test_colony_roundtrip(t: Object) -> void:
	var map := _flat_map()
	var defs := _defs()
	var c := Colony.new(map, defs, {"metal": 40, "oxygen": 30, "water": 30, "food": 30})
	c.population = 3
	c.place("gen", Vector2i(1, 1))
	c.place("harv", Vector2i(3, 1))
	c.place("survey", Vector2i(5, 5))
	var m = c.place("mine", Vector2i(8, 8))
	# Give the mine a real deposit so mine_accum accrues (the flat map has none).
	m.deposit_type = ColonyMap.Deposit.IRON
	m.richness = 0.7
	for i in 12:
		c.tick()

	var text := JSON.stringify(c.to_dict())
	var c2 := Colony.from_dict(map, defs, JSON.parse_string(text))

	t.eq(JSON.stringify(c2.to_dict()), text, "colony re-serializes identically after a JSON round-trip")
	t.eq(c2.population, c.population, "population restored")
	t.eq(c2.stockpile, c.stockpile, "stockpile restored")
	t.eq(c2.buildings.size(), c.buildings.size(), "all buildings restored")
	t.eq(c2._next_id, c._next_id, "id counter restored")
	t.eq(str(c2.building_at(Vector2i(8, 8)).type), "mine", "occupancy index rebuilt from buildings")
	t.eq(int(c2.building_at(Vector2i(8, 8)).deposit_type), ColonyMap.Deposit.IRON, "mine deposit latched")

func test_loaded_colony_keeps_ticking(t: Object) -> void:
	# A restored colony must advance identically to one that never left memory.
	var defs := _defs()
	var a := Colony.new(_flat_map(), defs, {"metal": 40, "oxygen": 50, "water": 50, "food": 50})
	a.place("gen", Vector2i(1, 1))
	a.place("harv", Vector2i(3, 1))
	for i in 8:
		a.tick()
	var b := Colony.from_dict(_flat_map(), defs, JSON.parse_string(JSON.stringify(a.to_dict())))
	for i in 6:
		a.tick()
		b.tick()
	t.eq(b.stockpile, a.stockpile, "restored colony ticks identically to the original")
	t.eq(b.population, a.population, "population evolves identically after load")
