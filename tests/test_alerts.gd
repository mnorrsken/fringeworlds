extends RefCounted
## AlertMonitor: edge-triggered alerts (power deficit, life support low, deposit
## confirmed) fire once on the rising edge, not every tick.

func _colony(stock := {}) -> Colony:
	var c := Colony.new(ColonyMap.new(16, 16), {}, stock)
	c.population = 0  # isolate power/deposit alerts from life-support warnings
	return c

func test_power_deficit_fires_once(t: Object) -> void:
	var mon := AlertMonitor.new()
	var c := _colony()
	c.power_produced = 5
	c.power_consumed = 10  # deficit
	var first := mon.check(c)
	t.eq(first.size(), 1, "power deficit raises one alert")
	t.eq(int(first[0].level), AlertMonitor.Level.CRIT, "power deficit is critical")
	var second := mon.check(c)  # still in deficit
	t.eq(second.size(), 0, "sustained deficit does not re-alert")

func test_power_deficit_rearms(t: Object) -> void:
	var mon := AlertMonitor.new()
	var c := _colony()
	c.power_produced = 5
	c.power_consumed = 10
	mon.check(c)
	c.power_consumed = 3  # back in balance
	mon.check(c)
	c.power_consumed = 10  # deficit again
	t.eq(mon.check(c).size(), 1, "deficit re-alerts after recovering")

func test_life_support_low_warns(t: Object) -> void:
	var mon := AlertMonitor.new()
	var c := _colony({"oxygen": 5, "water": 100, "food": 100})
	c.population = 4
	var out := mon.check(c)
	t.eq(out.size(), 1, "only the low resource warns")
	t.eq(int(out[0].level), AlertMonitor.Level.WARN, "low stock is a warning")
	t.ok("Oxygen" in str(out[0].text), "the warning names oxygen")
	t.eq(mon.check(c).size(), 0, "still-low resource does not re-warn")

func test_non_life_support_resource_low_warns(t: Object) -> void:
	# A building that drains metal (recipe input, no output) pulls the stock down;
	# the low-stock alert covers any net-drained resource, not just life support.
	var defs := {
		"burner": {
			"name": "Burner", "size": 1, "cost": {}, "power": 0, "workers": 0,
			"recipe": {"inputs": {"metal": 1}, "outputs": {}, "ticks": 1},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}
	var c := Colony.new(ColonyMap.new(16, 16), defs, {"metal": 6})
	c.population = 0
	c.place("burner", Vector2i(1, 1))
	c.tick()  # burner consumes metal; rates() reports metal net-negative
	var out := AlertMonitor.new().check(c)
	t.eq(out.size(), 1, "a drained low resource warns")
	t.ok("Metal" in str(out[0].text), "the warning names metal")

func test_no_low_warning_without_colonists(t: Object) -> void:
	var mon := AlertMonitor.new()
	var c := _colony({"oxygen": 0, "water": 0, "food": 0})
	c.population = 0
	t.eq(mon.check(c).size(), 0, "no life-support alerts when nobody lives here")

func test_deposit_confirmed_alerts(t: Object) -> void:
	var map := ColonyMap.new(32, 32)
	map.generate(1337)
	# Find any deposit cell and mark it confirmed as if a survey just did so.
	var found := Vector2i(-1, -1)
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			if map.get_deposit(cell) != ColonyMap.Deposit.NONE:
				found = cell
				break
		if found.x != -1:
			break
	t.ok(found.x != -1, "the generated map has at least one deposit")
	map.set_scan(found, ColonyMap.Scan.CONFIRMED)
	var c := Colony.new(map, {}, {})
	c.population = 0  # avoid life-support warnings from the empty stockpile
	c.scan_changes = [found]
	var out := AlertMonitor.new().check(c)
	t.eq(out.size(), 1, "a confirmed deposit raises one alert")
	t.eq(int(out[0].level), AlertMonitor.Level.INFO, "deposit confirmation is info-level")
