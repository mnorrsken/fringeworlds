extends RefCounted
## Milestone 9: the tuning layer. data/balance.json must parse into a Balance,
## every key it sets must actually reach the sim, and anything it leaves out must
## fall back to the shipped defaults rather than to zero.

const PATH := "res://data/balance.json"

func _file() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))

func _defs() -> Dictionary:
	return {
		"hab": {"size": 1, "cost": {}, "power": 0, "workers": 0, "capacity": 6,
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH]},
	}

func _map() -> ColonyMap:
	var m := ColonyMap.new(8, 8)
	m.generate(7)
	for y in 8:
		for x in 8:
			m.set_terrain(Vector2i(x, y), ColonyMap.Terrain.REGOLITH)
	return m

func test_shipped_file_parses(t: Object) -> void:
	var raw: Variant = _file()
	t.ok(raw is Dictionary, "balance.json is a JSON object")
	var b := Balance.from_dict(raw)
	t.ok(b != null, "it builds a Balance")

# An empty override must reproduce the defaults exactly — that is what makes a
# missing or partial balance.json safe.
func test_empty_dict_keeps_defaults(t: Object) -> void:
	var d := Balance.new()
	var b := Balance.from_dict({})
	t.eq(b.starting_population, d.starting_population, "starting population")
	t.eq(b.starve_ticks, d.starve_ticks, "starve ticks")
	t.eq(b.growth_ticks, d.growth_ticks, "growth ticks")
	t.eq(b.victory_xenite, d.victory_xenite, "victory xenite")
	t.eq(b.ticks_per_second, d.ticks_per_second, "tick rate")
	t.eq(b.low_stock, d.low_stock, "low stock threshold")
	t.eq(b.reading_jitter, d.reading_jitter, "reading jitter")
	t.eq(b.life_support, d.life_support, "life support table")
	t.eq(b.starting_stockpile, d.starting_stockpile, "starting stockpile")

func test_partial_override_leaves_the_rest_alone(t: Object) -> void:
	var d := Balance.new()
	var b := Balance.from_dict({"colony": {"starve_ticks": 99}})
	t.eq(b.starve_ticks, 99, "the named key is overridden")
	t.eq(b.growth_ticks, d.growth_ticks, "its neighbour is untouched")
	t.eq(b.victory_xenite, d.victory_xenite, "other sections are untouched")

func test_json_numbers_keep_their_type(t: Object) -> void:
	var b := Balance.from_dict({
		"starting_stockpile": {"metal": 7},
		"life_support": {"oxygen": 0.5},
	})
	t.eq(typeof(b.starting_stockpile.metal), TYPE_INT, "stock amounts are whole")
	t.eq(typeof(b.life_support.oxygen), TYPE_FLOAT, "life support rates are not")

# The point of the file: changing a number changes the game. If injection ever
# breaks, this fails while every other test still passes.
func test_balance_reaches_the_colony(t: Object) -> void:
	var b := Balance.from_dict({
		"colony": {"starting_population": 9},
		"victory": {"xenite": 3},
	})
	var c := Colony.new(_map(), _defs(), {"xenite": 3}, b)
	t.eq(c.population, 9, "colony starts with the tuned population")
	c.tick()
	t.eq(c.status, Colony.Status.WON, "colony wins at the tuned xenite target")

func test_default_colony_uses_shipped_numbers(t: Object) -> void:
	var c := Colony.new(_map(), _defs(), {})
	var d := Balance.new()
	t.eq(c.population, d.starting_population, "bare Colony matches the defaults")
	t.eq(c.balance.victory_xenite, d.victory_xenite, "and carries a full Balance")

func test_shipped_values_are_sane(t: Object) -> void:
	var b := Balance.from_dict(_file())
	t.ok(b.starting_population > 0, "the colony starts with people")
	t.ok(b.starve_ticks > 0, "starvation takes time")
	t.ok(b.growth_ticks > b.starve_ticks,
		"growth is slower than starvation, so a failing colony can't grow out of it")
	t.ok(b.victory_xenite > 0, "the win condition is reachable and non-trivial")
	t.ok(b.ticks_per_second > 0.0, "the sim advances")
	t.ok(b.reading_jitter >= 0.0 and b.reading_jitter < 1.0,
		"prospecting noise leaves the reading meaningful")
	t.ok(b.low_stock > 0, "the low-stock warning can fire before zero")
	for res in b.life_support:
		t.ok(float(b.life_support[res]) >= 0.0, "%s draw is not negative" % res)
	for res in b.life_support:
		t.ok(int(b.starting_stockpile.get(res, 0)) > 0,
			"%s is stocked at the start, so the colony doesn't begin starving" % res)
