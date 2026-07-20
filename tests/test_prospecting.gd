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

func test_richer_tiles_produce_faster(t: Object) -> void:
	# Two colonies, same mine, different richness -> more output on the richer tile.
	var lean := _mine_output(0.2, 40)
	var rich := _mine_output(1.0, 40)
	t.ok(rich > lean, "richer deposit yields more ore over the same ticks (%d vs %d)" % [rich, lean])

func _mine_output(richness: float, ticks: int) -> int:
	var m := ColonyMap.new(8, 8)
	# hand-craft a confirmed iron tile of the given richness
	var cell := Vector2i(4, 4)
	m._deposit[cell.y * m.width + cell.x] = ColonyMap.Deposit.IRON
	m._richness[cell.y * m.width + cell.x] = richness
	m.set_scan(cell, ColonyMap.Scan.CONFIRMED)
	var c := Colony.new(m, _defs(), {})
	c.place("mine", cell)
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
