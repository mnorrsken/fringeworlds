extends RefCounted
## Tick economy: production, power balance (newest-first shutdown), input stalls.

func _defs() -> Dictionary:
	return {
		"gen": {  # generator
			"name": "Gen", "size": 1, "cost": {}, "power": 10,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"harv": {  # consumes 5 power, makes 1 water every 2 ticks, no inputs
			"name": "Harv", "size": 1, "cost": {}, "power": -5,
			"recipe": {"inputs": {}, "outputs": {"water": 1}, "ticks": 2},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"drain": {  # consumes 8 power, does nothing else
			"name": "Drain", "size": 1, "cost": {}, "power": -8,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"smelt": {  # needs 2 ore -> 1 metal every 2 ticks, no power
			"name": "Smelt", "size": 1, "cost": {}, "power": 0,
			"recipe": {"inputs": {"ore": 2}, "outputs": {"metal": 1}, "ticks": 2},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

func _colony(stock := {}) -> Colony:
	return Colony.new(ColonyMap.new(16, 16), _defs(), stock)

func test_production_accrues(t: Object) -> void:
	var c := _colony()
	c.place("gen", Vector2i(1, 1))
	c.place("harv", Vector2i(2, 1))
	for i in 4:
		c.tick()
	t.eq(int(c.stockpile.get("water", 0)), 2, "1 water / 2 ticks -> 2 water after 4 ticks")

func test_power_deficit_stops_consumer(t: Object) -> void:
	var c := _colony()
	var gen = c.place("gen", Vector2i(1, 1))
	var harv = c.place("harv", Vector2i(2, 1))
	c.tick()
	t.ok(harv.active, "harvester runs while powered")
	c.demolish_at(gen.origin)  # remove the only generator
	c.tick()
	t.ok(not harv.active, "harvester shuts down with no power")
	var water_after := int(c.stockpile.get("water", 0))
	for i in 6:
		c.tick()
	t.eq(int(c.stockpile.get("water", 0)), water_after, "no production while unpowered")

func test_newest_consumer_shut_first(t: Object) -> void:
	var c := _colony()
	c.place("gen", Vector2i(1, 1))          # +10, oldest
	var harv = c.place("harv", Vector2i(2, 1))   # -5, older consumer
	var drain = c.place("drain", Vector2i(3, 1)) # -8, newest consumer
	c.tick()
	t.ok(harv.active, "older consumer keeps power")
	t.ok(not drain.active, "newest consumer is shed on deficit")
	t.eq(c.power_produced, 10, "production reported")
	t.eq(c.power_consumed, 5, "only the powered consumer counts")

func test_recipe_stalls_without_inputs(t: Object) -> void:
	var c := _colony()  # no ore in stock
	c.place("smelt", Vector2i(1, 1))
	for i in 4:
		c.tick()
	t.eq(int(c.stockpile.get("metal", 0)), 0, "no metal without ore")
	c.stockpile["ore"] = 10
	for i in 2:
		c.tick()
	t.eq(int(c.stockpile.get("metal", 0)), 1, "produces once ore is available")
	t.eq(int(c.stockpile.get("ore", 0)), 8, "consumed 2 ore")

func test_rates_reflect_active_only(t: Object) -> void:
	var c := _colony()
	c.place("gen", Vector2i(1, 1))
	c.place("harv", Vector2i(2, 1))
	c.tick()
	t.ok(absf(float(c.rates().get("water", 0.0)) - 0.5) < 0.001, "water rate = 0.5/tick")
