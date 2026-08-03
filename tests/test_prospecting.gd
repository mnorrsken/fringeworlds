extends RefCounted
## Deposits, survey scanning, and deposit-gated extractor placement/output.

func _defs() -> Dictionary:
	return {
		"survey": {
			"name": "Survey", "size": 1, "cost": {}, "power": 0,
			"scan": {"max_radius": 3, "ticks_per_ring": 1},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"mine": {
			"name": "Mine", "size": 1, "cost": {}, "power": 0,
			"mine": {"base_per_tick": 0.5},
			"requires_deposit_ids": [ColonyMap.Deposit.IRON, ColonyMap.Deposit.COPPER],
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH, ColonyMap.Terrain.HIGHLANDS],
		},
	}

func _colony() -> Colony:
	return Colony.new(ColonyMap.new(16, 16), _defs(), {})

# --- Deposit generation ---

func test_generation_is_deterministic(t: Object) -> void:
	var a := ColonyMap.new(48, 48)
	a.generate(2024)
	var b := ColonyMap.new(48, 48)
	b.generate(2024)
	var diffs := 0
	for y in 48:
		for x in 48:
			var c := Vector2i(x, y)
			if a.get_deposit(c) != b.get_deposit(c) or a.get_richness(c) != b.get_richness(c):
				diffs += 1
	t.eq(diffs, 0, "same seed -> identical deposits + richness")

func test_map_has_some_deposits(t: Object) -> void:
	var m := ColonyMap.new(64, 64)
	m.generate(1337)
	var count := 0
	for y in 64:
		for x in 64:
			if m.get_deposit(Vector2i(x, y)) != ColonyMap.Deposit.NONE:
				count += 1
	t.ok(count > 0, "map generates at least some deposits")

func test_fresh_map_is_all_unscanned(t: Object) -> void:
	var m := ColonyMap.new(32, 32)
	m.generate(7)
	var scanned := 0
	for y in 32:
		for x in 32:
			if m.get_scan(Vector2i(x, y)) != ColonyMap.Scan.UNSCANNED:
				scanned += 1
	t.eq(scanned, 0, "nothing is scanned on a fresh map")

# --- Survey scanning ---

func test_survey_reveals_coarse_then_confirmed(t: Object) -> void:
	var c := _colony()
	var survey = c.place("survey", Vector2i(8, 8))
	# First sweep: rings 0..3 over 4 ticks -> the station's own tile is coarse.
	for i in 4:
		c.tick()
	t.eq(c.map.get_scan(Vector2i(8, 8)), ColonyMap.Scan.COARSE, "own tile coarse after first sweep")
	# Second sweep confirms.
	for i in 4:
		c.tick()
	t.eq(c.map.get_scan(Vector2i(8, 8)), ColonyMap.Scan.CONFIRMED, "own tile confirmed after second sweep")

func test_scan_expands_outward(t: Object) -> void:
	var c := _colony()
	c.place("survey", Vector2i(8, 8))
	c.tick()  # processes ring 0 only
	t.eq(c.map.get_scan(Vector2i(8, 8)), ColonyMap.Scan.COARSE, "center scanned first")
	t.eq(c.map.get_scan(Vector2i(11, 8)), ColonyMap.Scan.UNSCANNED, "far tile not yet reached")

func test_scan_changes_reported(t: Object) -> void:
	var c := _colony()
	c.place("survey", Vector2i(8, 8))
	c.tick()
	t.ok(c.scan_changes.size() > 0, "tick reports scanned cells")

# --- Extractor gating + output ---

func _confirm(m: ColonyMap, cell: Vector2i) -> void:
	m.set_scan(cell, ColonyMap.Scan.CONFIRMED)

func _generated_colony() -> Colony:
	var m := ColonyMap.new(48, 48)
	m.generate(1337)
	return Colony.new(m, _defs(), {})

func test_mine_requires_confirmed_deposit(t: Object) -> void:
	var c := _generated_colony()
	var cell := _find_deposit(c.map, ColonyMap.Deposit.IRON)
	t.ok(cell.x >= 0, "test map has an iron deposit")
	t.ok(not c.can_place("mine", cell).ok, "mine rejected on unconfirmed deposit")
	_confirm(c.map, cell)
	t.ok(c.can_place("mine", cell).ok, "mine allowed once confirmed")

func test_mine_rejected_without_deposit(t: Object) -> void:
	var c := _generated_colony()
	var cell := _find_no_deposit(c.map)
	_confirm(c.map, cell)  # confirmed, but barren
	t.ok(not c.can_place("mine", cell).ok, "mine rejected where there is no ore")

# Richness sizes the reserve, not the rate: two tiles produce at the same speed,
# but the lean one runs dry first and the rich one keeps going.
func test_richness_sizes_the_reserve_not_the_rate(t: Object) -> void:
	var early := 20
	t.eq(_mine_output(0.2, early), _mine_output(1.0, early),
		"both tiles produce at the same rate while ore remains")
	var long := 400
	t.ok(_mine_output(1.0, long) > _mine_output(0.2, long),
		"over a long run the richer tile yields more, because it lasts longer")

func test_a_worked_out_tile_stops_and_says_so(t: Object) -> void:
	var c := _mine_colony(0.05)   # a nearly empty tile
	var inst: Dictionary = c.buildings[c.buildings.keys()[0]]
	for i in 400:
		c.tick()
	t.eq(c.map.get_amount(Vector2i(4, 4)), 0.0, "the reserve is drawn down to nothing")
	t.ok(not inst.active, "the extractor shuts down")
	t.eq(str(inst.idle_reason), "Deposit worked out", "and explains why")

# The stockpile can never gain more than the ground held.
func test_a_tile_yields_no_more_than_its_reserve(t: Object) -> void:
	var c := _mine_colony(0.5)
	var reserve := int(round(c.map.get_amount(Vector2i(4, 4))))
	for i in 4000:
		c.tick()
	t.eq(int(c.stockpile.get("iron_ore", 0)), reserve,
		"total ore mined equals the tile's reserve")

# The overlay shades by remaining_fraction, so it has to be a per-type scale:
# deposits differ by an order of magnitude in size, and a raw unit count would
# paint every crystal formation as good as exhausted.
func test_remaining_fraction_is_scaled_per_deposit_type(t: Object) -> void:
	var m := ColonyMap.new(8, 8)
	var iron := Vector2i(1, 1)
	var xenite := Vector2i(2, 2)
	m.set_deposit(iron, ColonyMap.Deposit.IRON, 1.0)
	m.set_deposit(xenite, ColonyMap.Deposit.XENITE, 1.0)
	t.eq(m.remaining_fraction(iron), 1.0, "a full-richness iron seam reads full")
	t.eq(m.remaining_fraction(xenite), 1.0, "so does a full crystal, on its own scale")

	# Half a crystal's worth of units left is exactly that — and next to nothing
	# in an iron seam, which holds an order of magnitude more.
	var half_a_crystal: float = m.deposit_units["XENITE"] * 0.5
	m.set_amount(iron, half_a_crystal)
	m.set_amount(xenite, half_a_crystal)
	t.ok(m.remaining_fraction(iron) < 0.1, "that many units of iron is nearly nothing")
	t.ok(absf(m.remaining_fraction(xenite) - 0.5) < 0.01,
		"but it is half a xenite deposit")

func test_remaining_fraction_of_barren_and_worked_out_ground(t: Object) -> void:
	var m := ColonyMap.new(8, 8)
	var cell := Vector2i(3, 3)
	t.eq(m.remaining_fraction(cell), 0.0, "barren ground has nothing left")
	m.set_deposit(cell, ColonyMap.Deposit.COPPER, 0.5)
	m.set_amount(cell, 0.0)
	t.eq(m.remaining_fraction(cell), 0.0, "neither does a worked-out deposit")

# The overlay repaints depleting tiles off this list, so mining has to report it.
func test_mining_reports_the_cells_it_drew_down(t: Object) -> void:
	var c := _mine_colony(1.0)
	var cell := Vector2i(4, 4)
	var drawn := false
	for i in 20:
		c.tick()
		if c.reserve_changes.has(cell):
			drawn = true
	t.ok(drawn, "the mined cell is reported while it still holds ore")

	# Long enough to scrape the tile out, taper and all.
	for i in 12000:
		c.tick()
	t.eq(c.map.get_amount(cell), 0.0, "the tile is worked out")
	c.tick()
	t.eq(c.reserve_changes.size(), 0, "a dead tile reports no further change")

# An extractor reaches sideways: it works every tile of its own ore in the 3×3
# around it, so a machine sited in the middle of a seam outlasts one on its edge.
func test_an_extractor_works_the_patch_around_it(t: Object) -> void:
	var m := ColonyMap.new(8, 8)
	var centre := Vector2i(4, 4)
	var per_tile := 0.1 * float(m.deposit_units["IRON"])
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			m.set_deposit(centre + Vector2i(dx, dy), ColonyMap.Deposit.IRON, 0.1)
	m.set_scan(centre, ColonyMap.Scan.CONFIRMED)
	var c := Colony.new(m, _defs(), {})
	var mine: Dictionary = c.place("mine", centre)
	t.eq(c.mine_cells(mine).size(), 9, "the whole 3×3 of iron feeds it")
	t.eq(float(mine.mine_initial), 9.0 * per_tile, "and all nine tiles count as its reserve")

	# 400 ticks at the def's 0.5/tick is 200 units: more than the tile it stands
	# on holds, so it has had to reach beyond it.
	for i in 400:
		c.tick()
	t.eq(m.get_amount(centre), 0.0, "the tile it stands on is drawn down first")
	t.eq(int(c.stockpile.get("iron_ore", 0)), 200, "and it keeps producing past that")

	for i in 8000:
		c.tick()
	t.eq(int(c.stockpile.get("iron_ore", 0)), int(9.0 * per_tile),
		"until every unit in the patch is up")
	t.ok(not mine.active, "and then it shuts down")

# The inspector reads the patch, not the tile underfoot — that's what the hover
# panel puts on screen, so it has to count every tile still feeding the machine.
func test_the_inspector_reports_the_whole_patch(t: Object) -> void:
	var m := ColonyMap.new(8, 8)
	var centre := Vector2i(4, 4)
	m.set_deposit(centre, ColonyMap.Deposit.IRON, 0.5)
	m.set_deposit(Vector2i(5, 4), ColonyMap.Deposit.IRON, 0.5)
	m.set_scan(centre, ColonyMap.Scan.CONFIRMED)
	var c := Colony.new(m, _defs(), {})
	var mine: Dictionary = c.place("mine", centre)
	var rep: Dictionary = c.building_report(int(mine.id)).mine
	t.eq(int(rep.tiles), 2, "two tiles are feeding it")
	t.eq(float(rep.remaining), m.get_amount(centre) + m.get_amount(Vector2i(5, 4)),
		"and the reserve is both of them together")

	m.set_amount(centre, 0.0)
	t.eq(int(c.building_report(int(mine.id)).mine.tiles), 1,
		"a worked-out tile stops counting")

# Only its own ore: a mine latched onto iron ignores the copper next door, or
# siting would stop mattering.
func test_an_extractor_only_draws_its_own_ore(t: Object) -> void:
	var m := ColonyMap.new(8, 8)
	var centre := Vector2i(4, 4)
	m.set_deposit(centre, ColonyMap.Deposit.IRON, 1.0)
	var copper := Vector2i(5, 4)
	m.set_deposit(copper, ColonyMap.Deposit.COPPER, 1.0)
	m.set_scan(centre, ColonyMap.Scan.CONFIRMED)
	var c := Colony.new(m, _defs(), {})
	var mine: Dictionary = c.place("mine", centre)
	t.eq(c.mine_cells(mine).size(), 1, "only the iron tile is worked")
	var before := m.get_amount(copper)
	for i in 4000:
		c.tick()
	t.eq(m.get_amount(copper), before, "the copper is untouched")
	t.eq(int(c.stockpile.get("copper_ore", 0)), 0, "and none of it is banked")

# Thin ground is slow ground: the rate holds while the patch is fresh and tapers
# off as it empties, so the tail of a seam takes far longer than the top of it.
func test_extraction_slows_as_the_patch_empties(t: Object) -> void:
	var c := _mine_colony(1.0)
	var mine: Dictionary = c.buildings[c.buildings.keys()[0]]
	var full: float = c.building_report(int(mine.id)).mine.per_tick
	t.ok(absf(full - 0.5) < 0.001, "a fresh patch runs at the def's rate")

	# Halfway down is still full speed; a nearly-spent patch crawls.
	c.map.set_amount(Vector2i(4, 4), float(mine.mine_initial) * 0.6)
	t.ok(absf(float(c.building_report(int(mine.id)).mine.per_tick) - full) < 0.001,
		"and holds it while the patch is better than half full")
	c.map.set_amount(Vector2i(4, 4), 0.0)
	t.ok(absf(float(c.building_report(int(mine.id)).mine.per_tick)
		- full * c.balance.mine_min_rate) < 0.001,
		"bottoming out at the floor rate, never at zero")

# The taper is measured against what the patch held when the machine was sited,
# not against a full-richness deposit — otherwise a lean tile would crawl from
# the first tick and richness would be back to setting the rate.
func test_a_lean_patch_still_starts_at_full_speed(t: Object) -> void:
	var lean := _mine_colony(0.1)
	var rich := _mine_colony(1.0)
	var lean_rate: float = lean.building_report(int(lean.buildings.keys()[0])).mine.per_tick
	var rich_rate: float = rich.building_report(int(rich.buildings.keys()[0])).mine.per_tick
	t.ok(absf(lean_rate - rich_rate) < 0.001, "a thin seam comes up as fast — there's just less of it")

func _mine_colony(richness: float) -> Colony:
	var m := ColonyMap.new(8, 8)
	var cell := Vector2i(4, 4)
	m.set_deposit(cell, ColonyMap.Deposit.IRON, richness)
	m.set_scan(cell, ColonyMap.Scan.CONFIRMED)
	var c := Colony.new(m, _defs(), {})
	c.place("mine", cell)
	return c

func _mine_output(richness: float, ticks: int) -> int:
	var c := _mine_colony(richness)
	for i in ticks:
		c.tick()
	return int(c.stockpile.get("iron_ore", 0))

func _find_deposit(m: ColonyMap, dep: int) -> Vector2i:
	for y in m.height:
		for x in m.width:
			if m.get_deposit(Vector2i(x, y)) == dep:
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func _find_no_deposit(m: ColonyMap) -> Vector2i:
	for y in m.height:
		for x in m.width:
			var cell := Vector2i(x, y)
			if m.get_deposit(cell) == ColonyMap.Deposit.NONE \
					and m.get_terrain(cell) == ColonyMap.Terrain.REGOLITH:
				return cell
	return Vector2i(0, 0)

# --- survey coverage, slow confirmation, crystal deposits --------------------

func _coverage_defs() -> Dictionary:
	var d := _defs()
	d.survey["requires_coverage"] = true
	d.survey.scan["confirm_ticks"] = 4
	d["beacon"] = {
		"name": "Beacon", "size": 1, "cost": {}, "power": 0,
		"scan": {"max_radius": 3, "ticks_per_ring": 1},
		"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
	}
	return d

func _flat(n := 24) -> ColonyMap:
	var m := ColonyMap.new(n, n)
	for y in n:
		for x in n:
			m.set_terrain(Vector2i(x, y), ColonyMap.Terrain.REGOLITH)
	return m

func test_survey_stations_must_stand_in_existing_coverage(t: Object) -> void:
	var c := Colony.new(_flat(), _coverage_defs(), {})
	var refused := c.can_place("survey", Vector2i(12, 12))
	t.ok(not refused.ok, "the first station has nothing to stand in")
	t.eq(str(refused.reason), "Outside survey coverage", "and says why")
	c.place("beacon", Vector2i(12, 12))          # something with a scan radius
	t.ok(c.can_place("survey", Vector2i(13, 13)).ok, "inside that radius is fine")
	t.ok(not c.can_place("survey", Vector2i(20, 20)).ok, "well outside it is not")

# The sweep finds deposits quickly; confirming richness afterwards is a slow,
# scattered resample that can waste a probe on ground it has already done.
func test_confirming_is_much_slower_than_discovering(t: Object) -> void:
	var c := Colony.new(_flat(), _coverage_defs(), {})
	var cell := Vector2i(15, 12)
	var station: Dictionary = _lone_station(c, cell)
	t.ok(not station.is_empty(), "the station was placed")
	var coarse_at := -1
	var confirmed_at := -1
	for i in 4000:
		c.tick()
		var state := c.map.get_scan(cell)
		if coarse_at < 0 and state >= ColonyMap.Scan.COARSE:
			coarse_at = i
		if confirmed_at < 0 and state == ColonyMap.Scan.CONFIRMED:
			confirmed_at = i
			break
	t.ok(coarse_at >= 0, "the sweep finds the tile")
	t.ok(confirmed_at > coarse_at * 4,
		"confirming takes far longer than finding (%d vs %d ticks)" % [confirmed_at, coarse_at])
	t.ok(bool(station.get("resampling", false)),
		"the station has dropped into resampling after its sweep")

func test_resampling_is_deterministic(t: Object) -> void:
	var a := _resample_probes()
	var b := _resample_probes()
	t.eq(a, b, "the same colony replayed confirms the same tiles in the same order")

# Stands a survey station at `cell`, using a temporary beacon purely to satisfy
# the coverage rule, then tears the beacon down so the station is the only thing
# scanning — otherwise the beacon's own systematic sweep confirms the ground
# before the resampler ever gets to it, and the test measures nothing.
func _lone_station(c: Colony, cell: Vector2i) -> Dictionary:
	c.place("beacon", Vector2i(12, 12))
	var station: Variant = c.place("survey", cell)
	c.demolish_at(Vector2i(12, 12))
	return station if station != null else {}

func _resample_probes() -> Array:
	var c := Colony.new(_flat(), _coverage_defs(), {})
	_lone_station(c, Vector2i(15, 12))
	var order := []
	for i in 600:
		c.tick()
		for cell in c.scan_changes:
			if c.map.get_scan(cell) == ColonyMap.Scan.CONFIRMED:
				order.append([cell.x, cell.y])
	return order

# Crystal formations are visible terrain, so you can see where xenite is —
# what you can't see is how much, which is what prospecting is for.
func test_xenite_sits_in_visible_crystal(t: Object) -> void:
	var m := ColonyMap.new(64, 64)
	m.generate(1337)
	var crystal := 0
	var xenite_off_crystal := 0
	for y in 64:
		for x in 64:
			var cell := Vector2i(x, y)
			var is_crystal := m.get_terrain(cell) == ColonyMap.Terrain.CRYSTAL
			var is_xenite := m.get_deposit(cell) == ColonyMap.Deposit.XENITE
			if is_crystal:
				crystal += 1
				t.ok(is_xenite, "every crystal formation holds xenite")
			elif is_xenite:
				xenite_off_crystal += 1
	t.ok(crystal > 0, "the map has crystal formations")
	t.eq(xenite_off_crystal, 0, "and no xenite hides anywhere else")

func test_a_formations_reserve_is_hidden_until_confirmed(t: Object) -> void:
	var m := ColonyMap.new(64, 64)
	m.generate(1337)
	var cell := Vector2i(-1, -1)
	for y in 64:
		for x in 64:
			if m.get_terrain(Vector2i(x, y)) == ColonyMap.Terrain.CRYSTAL:
				cell = Vector2i(x, y)
				break
	t.ok(cell.x >= 0, "found a crystal formation")
	t.eq(m.reading_text(cell), "", "unsurveyed, it reports nothing")
	m.set_scan(cell, ColonyMap.Scan.CONFIRMED)
	t.ok(m.reading_text(cell).contains("units left"),
		"confirmed, it reports the reserve: %s" % m.reading_text(cell))
