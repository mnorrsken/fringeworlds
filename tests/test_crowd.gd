extends RefCounted
## The walking-colonist crowd (render/colonist_crowd.gd). It is cosmetic, but it
## is still pure logic, so it is pinned here like the rest: colonists stay on
## walkable ground, they come and go with the population, they staff the
## buildings the sim says are staffed, and they never end up stuck inside
## something that has been demolished.
##
## The one rule that outranks the others: **the crowd must not touch the sim.**
## test_the_crowd_never_writes_to_the_colony is what enforces it.

const STEP := 1.0 / 30.0

func _defs() -> Dictionary:
	return {
		"hub": {
			"name": "Hub", "size": 2, "cost": {}, "power": 20, "workers": 0,
			"capacity": 4, "life_support": 4,
			"door": {"offset": [0, -7]},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
		"works": {  # a workplace: two colonists staff it
			"name": "Works", "size": 1, "cost": {}, "power": -2, "workers": 2,
			"recipe": {"inputs": {}, "outputs": {"metal": 1}, "ticks": 2},
			"allowed_terrain_ids": [ColonyMap.Terrain.REGOLITH],
		},
	}

# Open regolith with a wall of impassable crystal down one side, so "stays on
# walkable ground" is a claim with something to fail against.
func _map(n := 20) -> ColonyMap:
	var m := ColonyMap.new(n, n)
	for y in n:
		for x in n:
			m.set_terrain(Vector2i(x, y), ColonyMap.Terrain.REGOLITH)
	for y in n:
		m.set_terrain(Vector2i(15, y), ColonyMap.Terrain.CRYSTAL)
		m.set_terrain(Vector2i(16, y), ColonyMap.Terrain.VOID)
	return m

func _colony() -> Colony:
	var c := Colony.new(_map(), _defs(), {})
	c.population = 6
	return c

func _crowd(c: Colony, seed := 7) -> ColonistCrowd:
	return ColonistCrowd.new(c, {}, seed)

func _run(crowd: ColonistCrowd, seconds: float) -> void:
	for i in int(seconds / STEP):
		crowd.step(STEP)

# --- Who is out there --------------------------------------------------------

# Before the hub lands, the colonists are still aboard: an empty site with a
# population of six should show nobody, or four figures stand on bare ground.
func test_nobody_is_outside_before_anything_is_built(t: Object) -> void:
	var c := _colony()
	var crowd := _crowd(c)
	t.eq(crowd.walkers.size(), 0, "an unbuilt site has no crowd")
	c.place("hub", Vector2i(4, 4))
	crowd.refresh()
	t.eq(crowd.walkers.size(), c.population, "the hub landing brings them out")

func test_the_crowd_tracks_the_population(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	var crowd := _crowd(c)
	t.eq(crowd.walkers.size(), 6, "one walker per colonist")
	c.population = 9
	crowd.refresh()
	t.eq(crowd.walkers.size(), 9, "growth puts more of them outside")
	c.population = 2
	crowd.refresh()
	t.eq(crowd.walkers.size(), 2, "and deaths take them away")

func test_the_crowd_is_capped(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	c.population = 400
	var crowd := ColonistCrowd.new(c, {"max_visible": 12}, 3)
	t.eq(crowd.walkers.size(), 12, "a big colony is a crowd, not a swarm")

# --- Where they can be -------------------------------------------------------

# The heart of it: whatever the pathing does, a colonist is never standing in a
# canyon, on a crystal formation, or inside a building's footprint — unless they
# have gone in through its door, which is the one legitimate way to be indoors.
func test_colonists_only_ever_stand_on_open_ground(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	c.place("works", Vector2i(8, 6))
	c.place("works", Vector2i(3, 9))
	var crowd := _crowd(c)
	# Sampled every step and totalled, rather than asserted per step: this walks
	# thousands of frames, and one assertion each would drown the suite.
	var samples := 0
	var off_map := 0
	var impassable := 0
	var indoors := 0
	for i in 3000:
		crowd.step(STEP)
		for w in crowd.walkers:
			if int(w.state) == ColonistCrowd.State.INSIDE:
				continue
			var cell := Vector2i(w.pos.round())
			samples += 1
			if not c.map.in_bounds(cell):
				off_map += 1
				continue
			var terrain := c.map.get_terrain(cell)
			if terrain == ColonyMap.Terrain.CRYSTAL or terrain == ColonyMap.Terrain.VOID:
				impassable += 1
			# Standing on a building's footprint is only legitimate in its own
			# doorway, on the way in or out.
			var under: Dictionary = c.building_at(cell)
			if not under.is_empty() and int(w.door_of) != int(under.id):
				indoors += 1
	t.ok(samples > 5000, "the walk actually ran (%d samples)" % samples)
	t.eq(off_map, 0, "nobody ever left the map")
	t.eq(impassable, 0, "nobody ever stood on crystal or in a canyon")
	t.eq(indoors, 0, "nobody ever walked through a wall instead of a door")

func test_colonists_do_not_cross_the_impassable_wall(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	var crowd := _crowd(c)
	_run(crowd, 120.0)
	for w in crowd.walkers:
		t.ok(w.pos.x < 15.0, "nobody crossed the crystal/void wall (x=%.1f)" % w.pos.x)

# --- Work --------------------------------------------------------------------

# The point of driving this from sim state: a staffed building actually gets
# people walking to it and stepping inside.
func test_colonists_go_to_work(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	c.place("works", Vector2i(9, 9))
	c.tick()                      # power/workforce pass marks the works active
	var crowd := _crowd(c)
	var works_id := _id_of(c, "works")
	var went_in := false
	for i in 6000:
		crowd.step(STEP)
		for w in crowd.walkers:
			if int(w.inside) == works_id:
				went_in = true
		if went_in:
			break
	t.ok(went_in, "somebody walked to the works and went in through the door")

# The live game calls refresh() every tick, which is four times a second — far
# more often than a colonist takes a step. Anything refresh() does has to survive
# happening mid-stride, and the first version of it did not: it treated a
# colonist standing in a doorway as stranded on a blocked tile and bounced them
# back outside, so in the real game nobody ever got through a door. Unit tests
# that only refreshed between phases never saw it.
func test_going_to_work_survives_a_refresh_every_step(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	c.place("works", Vector2i(9, 9))
	c.tick()
	var crowd := _crowd(c)
	var works_id := _id_of(c, "works")
	var went_in := false
	for i in 6000:
		crowd.step(STEP)
		crowd.refresh()          # as the tick does
		if _inside_count(crowd, works_id) > 0:
			went_in = true
			break
	t.ok(went_in, "colonists still reach the works when refresh runs constantly")

# A building that shuts down stops offering work, so its crew comes back out —
# that is the visible half of "no power" and it must not need a special case.
func test_a_shut_building_empties_out(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	c.place("works", Vector2i(9, 9))
	c.tick()
	var crowd := _crowd(c)
	var works_id := _id_of(c, "works")
	for i in 6000:
		crowd.step(STEP)
		if _inside_count(crowd, works_id) > 0:
			break
	t.ok(_inside_count(crowd, works_id) > 0, "somebody is on shift to begin with")

	c.buildings[works_id].active = false
	crowd.refresh()
	_run(crowd, 60.0)
	t.eq(_inside_count(crowd, works_id), 0, "a dead building has nobody in it")

func test_demolition_does_not_strand_anyone(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	c.place("works", Vector2i(9, 9))
	c.tick()
	var crowd := _crowd(c)
	var works_id := _id_of(c, "works")
	for i in 6000:
		crowd.step(STEP)
		if _inside_count(crowd, works_id) > 0:
			break
	c.demolish_at(Vector2i(9, 9))
	crowd.refresh()
	for w in crowd.walkers:
		t.ok(int(w.inside) != works_id, "nobody is inside a building that is gone")
	_run(crowd, 10.0)
	for w in crowd.walkers:
		var cell := Vector2i(w.pos.round())
		t.ok(c.map.in_bounds(cell), "and they are back on the map")

# Building on top of somebody puts them beside the new wall, not under it.
func test_building_on_a_colonist_moves_them_clear(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	var crowd := _crowd(c)
	_run(crowd, 5.0)
	var w: Dictionary = crowd.walkers[0]
	var cell := Vector2i(w.pos.round())
	w.state = ColonistCrowd.State.PAUSED
	w.timer = 99.0
	c.place("works", cell)
	crowd.refresh()
	t.ok(c.building_at(Vector2i(w.pos.round())).is_empty(),
		"the colonist was moved out from under the new building")

# --- Purity ------------------------------------------------------------------

# The crowd is a view. If it ever writes to the colony, the sim stops being the
# only thing that decides the game and the pacing harness stops meaning anything.
func test_the_crowd_never_writes_to_the_colony(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	c.place("works", Vector2i(9, 9))
	c.tick()
	var before := JSON.stringify(c.to_dict())
	var stock_before := c.stockpile.duplicate()
	var pop_before := c.population
	var crowd := _crowd(c)
	_run(crowd, 300.0)
	t.eq(JSON.stringify(c.to_dict()), before, "colony state is untouched by the crowd")
	t.eq(c.stockpile, stock_before, "the stockpile is untouched")
	t.eq(c.population, pop_before, "the population is untouched")

func test_the_same_seed_walks_the_same_route(t: Object) -> void:
	t.eq(_positions_after(11), _positions_after(11), "replaying a seed is identical")
	t.ok(_positions_after(11) != _positions_after(12), "a different seed walks differently")

func _positions_after(seed: int) -> String:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	c.place("works", Vector2i(9, 9))
	c.tick()
	var crowd := _crowd(c, seed)
	_run(crowd, 40.0)
	var out := []
	for w in crowd.walkers:
		out.append("%.3f,%.3f,%d" % [w.pos.x, w.pos.y, int(w.state)])
	return ";".join(out)

# --- Facing ------------------------------------------------------------------

# Sheet rows are screen directions: row 0 faces the camera. Grid +x+y is
# "toward the viewer" in this projection, so that is what row 0 has to mean.
func test_facing_rows_follow_screen_directions(t: Object) -> void:
	t.eq(ColonistCrowd.facing_for(Vector2(1, 1)), 0, "down-screen is S (row 0)")
	t.eq(ColonistCrowd.facing_for(Vector2(1, 0)), 1, "grid +x reads as SE")
	t.eq(ColonistCrowd.facing_for(Vector2(1, -1)), 2, "across to the right is E")
	t.eq(ColonistCrowd.facing_for(Vector2(0, -1)), 3, "grid -y reads as NE")
	t.eq(ColonistCrowd.facing_for(Vector2(-1, -1)), 4, "up-screen is N")
	t.eq(ColonistCrowd.facing_for(Vector2(-1, 0)), 5, "grid -x reads as NW")
	t.eq(ColonistCrowd.facing_for(Vector2(-1, 1)), 6, "across to the left is W")
	t.eq(ColonistCrowd.facing_for(Vector2(0, 1)), 7, "grid +y reads as SW")
	t.eq(ColonistCrowd.facing_for(Vector2.ZERO), 0, "standing still keeps a row")

func test_walkers_face_where_they_are_going(t: Object) -> void:
	var c := _colony()
	c.place("hub", Vector2i(4, 4))
	var crowd := _crowd(c)
	_run(crowd, 30.0)
	for w in crowd.walkers:
		t.ok(int(w.facing) >= 0 and int(w.facing) < 8,
			"facing stays a sheet row (got %d)" % int(w.facing))

# --- helpers -----------------------------------------------------------------

func _id_of(c: Colony, type_id: String) -> int:
	for id in c.buildings:
		if c.buildings[id].type == type_id:
			return int(id)
	return -1

func _inside_count(crowd: ColonistCrowd, building_id: int) -> int:
	var n := 0
	for w in crowd.walkers:
		if int(w.inside) == building_id:
			n += 1
	return n
