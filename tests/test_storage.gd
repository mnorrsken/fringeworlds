extends RefCounted
## Storage limits: the colony can only hold what its buildings can contain, and
## a full store stalls the line feeding it rather than quietly destroying output.
##
## The rule that decides the endgame lives here too — the hub cannot hold xenite
## at all, so the beacon cannot be filled without warehouses.

const BUILDINGS := "res://data/buildings.json"
const BALANCE := "res://data/balance.json"

func _defs() -> Dictionary:
	return {
		"hub": {
			"name": "Hub", "size": 1, "cost": {}, "power": 10, "workers": 0,
			"storage": {"metal": 50, "iron_ore": 50, "water": 400},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"shed": {
			"name": "Shed", "size": 1, "cost": {}, "power": 0, "workers": 0,
			"storage": {"metal": 30, "xenite": 20},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"smelter": {
			"name": "Smelter", "size": 1, "cost": {}, "power": 0, "workers": 0,
			"recipe": {"inputs": {"iron_ore": 2}, "outputs": {"metal": 1}, "ticks": 1},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"mine": {
			"name": "Mine", "size": 1, "cost": {}, "power": 0, "workers": 0,
			"mine": {"base_per_tick": 1.0},
			"requires_deposit_ids": [ColonyMap.Deposit.IRON],
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

func _map(n := 12) -> ColonyMap:
	var m := ColonyMap.new(n, n)
	for y in n:
		for x in n:
			m.set_terrain(Vector2i(x, y), ColonyMap.Terrain.REGOLITH)
	return m

func _colony(stock := {}) -> Colony:
	return Colony.new(_map(), _defs(), stock)

func test_capacity_is_the_sum_of_what_is_standing(t: Object) -> void:
	var c := _colony()
	t.eq(c.storage_for("metal"), 0, "an empty site holds nothing")
	c.place("hub", Vector2i(2, 2))
	t.eq(c.storage_for("metal"), 50, "the hub's yard")
	c.place("shed", Vector2i(4, 4))
	t.eq(c.storage_for("metal"), 80, "sheds add to it")
	t.eq(c.storage_for("xenite"), 20, "and can hold things the hub cannot")

func test_the_hub_cannot_hold_xenite(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(2, 2))
	t.eq(c.storage_for("xenite"), 0, "no xenite containment in the hub at all")

func test_gains_are_capped(t: Object) -> void:
	var c := _colony({"metal": 45})
	c.place("hub", Vector2i(2, 2))
	c._gain({"metal": 20})
	t.eq(int(c.stockpile.metal), 50, "a gain past capacity is clipped, not carried")

# A building has a small internal hopper, so a full colony store doesn't stop it
# dead — it keeps working until that hopper backs up too, and only then stalls
# without eating any more input.
func test_a_full_store_backs_up_through_the_hopper(t: Object) -> void:
	var c := _colony({"metal": 50, "iron_ore": 40})
	c.place("hub", Vector2i(2, 2))
	var smelter: Dictionary = c.place("smelter", Vector2i(3, 3))
	for i in 20:
		c.tick()
	t.eq(int(c.stockpile.metal), 50, "the colony store stays at its ceiling")
	t.eq(int(smelter.buffer.get("metal", 0)), c.balance.building_buffer,
		"the smelter's hopper fills up")
	t.eq(str(smelter.idle_reason), "Storage full", "and then it stalls")
	var ore_left := int(c.stockpile.iron_ore)
	c.tick()
	t.eq(int(c.stockpile.iron_ore), ore_left, "a stalled line consumes nothing")

func test_the_hopper_is_only_a_moments_grace(t: Object) -> void:
	var c := _colony({"metal": 50, "iron_ore": 40})
	c.place("hub", Vector2i(2, 2))
	var smelter: Dictionary = c.place("smelter", Vector2i(3, 3))
	for i in 20:
		c.tick()
	t.ok(int(smelter.buffer.get("metal", 0)) <= 8,
		"a hopper is a pause, not a second warehouse")

# With room in the store the hopper is invisible: output arrives the same tick,
# exactly as it did before buffers existed.
func test_the_hopper_does_not_delay_normal_production(t: Object) -> void:
	var c := _colony({"iron_ore": 40})
	c.place("hub", Vector2i(2, 2))
	c.place("smelter", Vector2i(3, 3))
	c.tick()
	t.eq(int(c.stockpile.get("metal", 0)), 1, "the first batch lands immediately")

func test_production_resumes_when_room_appears(t: Object) -> void:
	var c := _colony({"metal": 50, "iron_ore": 40})
	c.place("hub", Vector2i(2, 2))
	var smelter: Dictionary = c.place("smelter", Vector2i(3, 3))
	for i in 20:
		c.tick()
	t.eq(str(smelter.idle_reason), "Storage full", "stalled to begin with")
	c.stockpile["metal"] = 10          # something spent the metal
	c.tick()
	t.ok(int(c.stockpile.metal) > 10, "the hopper empties into the store")
	t.eq(int(smelter.buffer.get("metal", 0)), 0, "leaving the hopper clear")

func test_an_extractor_stops_with_the_ore_left_in_the_ground(t: Object) -> void:
	var c := _colony({"iron_ore": 50})
	c.place("hub", Vector2i(2, 2))
	var cell := Vector2i(5, 5)
	c.map.set_deposit(cell, ColonyMap.Deposit.IRON, 1.0)
	c.map.set_scan(cell, ColonyMap.Scan.CONFIRMED)
	var mine: Dictionary = c.place("mine", cell)
	var before := c.map.get_amount(cell)
	for i in 20:
		c.tick()
	t.eq(str(mine.idle_reason), "Storage full", "the mine stops once its hopper backs up")
	t.eq(before - c.map.get_amount(cell), float(c.balance.building_buffer),
		"and no more than a hopper's worth ever left the ground")

func test_losing_storage_spills_the_excess(t: Object) -> void:
	var c := _colony({"metal": 70})
	c.place("hub", Vector2i(2, 2))
	c.place("shed", Vector2i(4, 4))
	t.eq(int(c.stockpile.metal), 70, "both buildings hold it")
	c.demolish_at(Vector2i(4, 4))
	t.eq(int(c.stockpile.metal), 50, "tearing the shed down spills what no longer fits")

# Content that models no storage isn't playing by these rules; unit test
# colonies built from a couple of synthetic defs must not be capped at zero.
func test_defs_without_storage_are_unlimited(t: Object) -> void:
	var defs := _defs()
	defs.hub.erase("storage")
	defs.shed.erase("storage")
	var c := Colony.new(_map(), defs, {"iron_ore": 40})
	c.place("smelter", Vector2i(3, 3))
	c.tick()
	t.eq(int(c.stockpile.get("metal", 0)), 1, "production runs uncapped")

# --- the shipped numbers -----------------------------------------------------

func _shipped() -> Dictionary:
	var out := {}
	for def in JSON.parse_string(FileAccess.get_file_as_string(BUILDINGS)):
		out[def.id] = def
	return out

func test_the_beacon_needs_about_three_warehouses(t: Object) -> void:
	var defs := _shipped()
	var balance := Balance.from_dict(JSON.parse_string(
		FileAccess.get_file_as_string(BALANCE)))
	var per_warehouse := int(defs.warehouse.storage.get("xenite", 0))
	t.eq(int(defs.hub.get("storage", {}).get("xenite", 0)), 0,
		"the hub holds no xenite, so warehouses are mandatory")
	t.ok(per_warehouse > 0, "a warehouse can hold xenite")
	var needed := ceili(float(balance.victory_xenite) / float(per_warehouse))
	t.eq(needed, 3, "three warehouses are required to hold the beacon (got %d)" % needed)
	t.ok(per_warehouse * 2 < balance.victory_xenite,
		"and two are genuinely not enough")

# Every material the colony can bank has somewhere to go from the start, or the
# opening deadlocks before the first warehouse is affordable.
func test_the_hub_can_hold_the_starting_stockpile(t: Object) -> void:
	var defs := _shipped()
	var balance := Balance.from_dict(JSON.parse_string(
		FileAccess.get_file_as_string(BALANCE)))
	var yard: Dictionary = defs.hub.storage
	for res in balance.starting_stockpile:
		t.ok(int(balance.starting_stockpile[res]) <= int(yard.get(res, 0)),
			"the colony lands with %d %s and can store %d" % [
				int(balance.starting_stockpile[res]), res, int(yard.get(res, 0))])

# The hub's yard has to be deep enough to save up for the priciest thing that
# can be built out of it, or that building is unreachable forever.
func test_the_hub_yard_can_afford_the_costliest_building(t: Object) -> void:
	var defs := _shipped()
	var dearest := 0
	var name := ""
	for id in defs:
		var metal := int(defs[id].get("cost", {}).get("metal", 0))
		if metal > dearest:
			dearest = metal
			name = str(defs[id].name)
	t.ok(dearest <= int(defs.hub.storage.get("metal", 0)),
		"%s costs %d metal and the hub yard holds %d" % [
			name, dearest, int(defs.hub.storage.get("metal", 0))])
