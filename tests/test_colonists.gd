extends RefCounted
## Colonists: life support consumption, starvation deaths, growth, workforce
## idling, and win/lose status.

func _defs() -> Dictionary:
	return {
		"gen": {
			"name": "Gen", "size": 1, "cost": {}, "power": 20, "workers": 0,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"hab": {
			"name": "Hab", "size": 1, "cost": {}, "power": 0, "workers": 0, "capacity": 6,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"factory": {  # needs 3 workers, no power
			"name": "Factory", "size": 1, "cost": {}, "power": 0, "workers": 3,
			"recipe": {"inputs": {}, "outputs": {"parts": 1}, "ticks": 1},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

func _colony(stock := {}) -> Colony:
	return Colony.new(ColonyMap.new(16, 16), _defs(), stock)

func test_life_support_consumed(t: Object) -> void:
	var c := _colony({"oxygen": 100, "water": 100, "food": 100})
	for i in 40:
		c.tick()
	t.ok(int(c.stockpile["oxygen"]) < 100, "oxygen is consumed by colonists")
	t.ok(int(c.stockpile["food"]) < 100, "food is consumed by colonists")

func test_starvation_kills_colonists(t: Object) -> void:
	var c := _colony({})  # no life support at all
	var start := c.population
	for i in Colony.STARVE_TICKS + 2:
		c.tick()
	t.ok(c.population < start, "colonists die when starved")

func test_growth_when_fed_and_housed(t: Object) -> void:
	var c := _colony({"oxygen": 100000, "water": 100000, "food": 100000})
	c.place("hab", Vector2i(1, 1))  # capacity now 4 + 6 = 10
	var start := c.population
	for i in Colony.GROWTH_TICKS + 4:
		c.tick()
	t.ok(c.population > start, "colonists grow when all needs are met and housed")

func test_no_growth_past_capacity(t: Object) -> void:
	# No habitat: capacity == BASE_CAPACITY == starting population, so no growth.
	var c := _colony({"oxygen": 100000, "water": 100000, "food": 100000})
	var start := c.population
	for i in Colony.GROWTH_TICKS * 2:
		c.tick()
	t.eq(c.population, start, "no growth when already at capacity")

func test_workforce_idles_understaffed(t: Object) -> void:
	var c := _colony({"oxygen": 100000, "water": 100000, "food": 100000})
	# population 4; two factories need 3 workers each = 6 > 4, so one idles.
	var a = c.place("factory", Vector2i(1, 1))
	var b = c.place("factory", Vector2i(2, 1))
	c.tick()
	t.ok(a.active, "oldest factory staffed")
	t.ok(not b.active, "newest factory idled when workforce is short")
	t.eq(c.workers_used(), 3, "only the staffed factory's workers count")

func test_victory_on_xenite(t: Object) -> void:
	var c := _colony({"oxygen": 100000, "water": 100000, "food": 100000, "xenite": Colony.VICTORY_XENITE})
	c.tick()
	t.eq(c.status, Colony.Status.WON, "reaching the xenite target wins")

func test_defeat_on_zero_population(t: Object) -> void:
	var c := _colony({})  # starve to death
	for i in Colony.STARVE_TICKS * (Colony.STARTING_POPULATION + 1):
		c.tick()
	t.eq(c.population, 0, "population reaches zero")
	t.eq(c.status, Colony.Status.LOST, "empty colony is a loss")
