extends RefCounted
## Map generation: correct shape, valid terrain ids, deterministic per seed.

func test_dimensions(t: Object) -> void:
	var m := ColonyMap.new(32, 48)
	m.generate(7)
	t.eq(m.width, 32, "width")
	t.eq(m.height, 48, "height")

func test_values_in_enum_range(t: Object) -> void:
	var m := ColonyMap.new(40, 40)
	m.generate(99)
	var bad := 0
	for y in m.height:
		for x in m.width:
			var v := m.get_terrain(Vector2i(x, y))
			if v < 0 or v >= ColonyMap.Terrain.size():
				bad += 1
	t.eq(bad, 0, "all terrain ids within enum range")

func test_deterministic_for_seed(t: Object) -> void:
	var a := ColonyMap.new(24, 24)
	a.generate(1234)
	var b := ColonyMap.new(24, 24)
	b.generate(1234)
	var diffs := 0
	for y in 24:
		for x in 24:
			if a.get_terrain(Vector2i(x, y)) != b.get_terrain(Vector2i(x, y)):
				diffs += 1
	t.eq(diffs, 0, "same seed produces identical map")

func test_generation_is_varied(t: Object) -> void:
	var m := ColonyMap.new(64, 64)
	m.generate(1337)
	var seen := {}
	for y in 64:
		for x in 64:
			seen[m.get_terrain(Vector2i(x, y))] = true
	t.ok(seen.size() >= 3, "map contains at least 3 distinct terrain types")
