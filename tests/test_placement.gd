extends RefCounted
## Building placement rules (Colony is pure — no autoloads needed here).

func _defs() -> Dictionary:
	return {
		"hut": {
			"name": "Hut", "size": 1, "cost": {"metal": 10},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"base": {
			"name": "Base", "size": 2, "cost": {"metal": 30},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

# A fresh ColonyMap is all-zero == all REGOLITH, so it's a blank buildable flat.
func _colony(metal := 100) -> Colony:
	return Colony.new(ColonyMap.new(16, 16), _defs(), {"metal": metal})

func test_place_on_valid_tile(t: Object) -> void:
	var c := _colony()
	var inst = c.place("hut", Vector2i(4, 4))
	t.ok(inst != null, "placement succeeds on flat regolith")
	t.eq(c.stockpile["metal"], 90, "cost deducted")
	t.eq(c.building_at(Vector2i(4, 4)).type, "hut", "building indexed at its cell")

func test_2x2_occupies_four_cells(t: Object) -> void:
	var c := _colony()
	c.place("base", Vector2i(2, 2))
	for cell in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 3)]:
		t.eq(c.building_at(cell).type, "base", "base occupies %s" % cell)

func test_reject_overlap(t: Object) -> void:
	var c := _colony()
	c.place("base", Vector2i(2, 2))
	t.ok(not c.can_place("hut", Vector2i(3, 3)).ok, "cannot place on occupied cell")
	t.ok(c.place("hut", Vector2i(3, 3)) == null, "overlapping place returns null")

func test_reject_off_map(t: Object) -> void:
	var c := _colony()
	t.ok(not c.can_place("base", Vector2i(15, 15)).ok, "2x2 off the edge is rejected")

func test_reject_bad_terrain(t: Object) -> void:
	var c := _colony()
	c.map.set_terrain(Vector2i(5, 5), ColonyMap.Terrain.ICE)
	t.ok(not c.can_place("hut", Vector2i(5, 5)).ok, "hut not allowed on ice")

func test_reject_unaffordable(t: Object) -> void:
	var c := _colony(5)
	var res := c.can_place("hut", Vector2i(1, 1))
	t.ok(not res.ok, "cannot afford with too little metal")
	t.eq(res.reason, "Cannot afford", "reason reported")

func test_demolish_frees_cells(t: Object) -> void:
	var c := _colony()
	c.place("base", Vector2i(2, 2))
	var removed = c.demolish_at(Vector2i(3, 3))  # any footprint cell works
	t.ok(removed != null, "demolish returns the instance")
	t.ok(c.building_at(Vector2i(2, 2)).is_empty(), "cells freed after demolish")
	t.ok(c.place("base", Vector2i(2, 2)) != null, "can rebuild on freed cells")

func test_demolish_empty_is_noop(t: Object) -> void:
	var c := _colony()
	t.ok(c.demolish_at(Vector2i(0, 0)) == null, "demolishing empty tile returns null")
