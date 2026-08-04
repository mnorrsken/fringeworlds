class_name ColonistCrowd
extends RefCounted
## The colony's visible crowd: little people who walk the open ground between
## the buildings, step in through their doors, and come back out.
##
## **This is cosmetic, and deliberately so.** It reads `Colony` — how many
## colonists there are, which buildings are staffed and running, where their
## doors are — and never writes a thing back. No game rule depends on where a
## colonist is standing, nothing here is saved (a loaded game just repopulates
## the crowd from the colony it loaded), and the pacing harness is untouched by
## it. The plan scoped colonists as "a number, not simulated individuals walking
## around"; that is still true of the *simulation*. This is the view's reading of
## that number.
##
## It is still a pure `RefCounted` with no autoload, Events or node dependency,
## stepped in real seconds by `ColonistsView`, so it is tested headlessly like
## the rest of the sim classes.

enum State {
	WALKING,  ## crossing the ground toward `target`
	PAUSED,   ## standing still for a moment before picking somewhere new
	INSIDE,   ## through a door and out of sight, on shift
}

## Ground a colonist will cross. Crystal formations and canyons are impassable
## (the plan's terrain rules), and a building's footprint is solid — you go in
## through the door or not at all.
const WALKABLE := [
	ColonyMap.Terrain.REGOLITH, ColonyMap.Terrain.HIGHLANDS, ColonyMap.Terrain.ICE,
]

## Tuning, overridable from data/colonists.json. Anything the file leaves out
## keeps the value here, so a missing or partial file still walks.
const DEFAULTS := {
	"speed": 1.05,             # tiles per second
	"speed_jitter": 0.22,      # ± fraction, per colonist, so a crowd isn't a drill squad
	"max_visible": 20,         # crowd size ceiling, whatever the population
	"shift_seconds": [6.0, 14.0],
	"pause_seconds": [0.4, 2.0],
	"work_chance": 0.75,       # odds an employed colonist heads back in vs. strolls
	"stroll_radius": 4,        # how far a stroll wanders from its anchor
}

## The walkers, read by the view each frame. Each is a Dictionary:
## `{ id, pos (fractional grid), facing (0..7), state, timer, path, speed,
##    enter (building id to step into on arrival, or -1), inside (building id),
##    door_of (the building whose doorway it may stand in, or -1) }`
##
## `door_of` is the one licence to be off open ground: the last step in and the
## first step out cross the building's own footprint, which is what makes a
## colonist look like they are using the door rather than dissolving beside it.
var walkers: Array = []

var _colony: Colony
var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _astar := AStarGrid2D.new()
var _jobs: Dictionary = {}   # walker id -> building instance id it staffs
var _next_id := 1
var _stamp := -1             # what the buildings looked like when the ground was last mapped

func _init(colony: Colony, cfg: Dictionary = {}, seed: int = 20260804) -> void:
	_colony = colony
	_cfg = DEFAULTS.duplicate(true)
	for k in cfg:
		if DEFAULTS.has(k):
			_cfg[k] = cfg[k]
	_rng.seed = seed
	_astar.region = Rect2i(0, 0, colony.map.width, colony.map.height)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	refresh()

## Re-reads the colony: which ground is walkable, who works where, and how many
## colonists there are. The live game calls this every tick, so it only rebuilds
## the pathfinding grid when the buildings have actually changed — the rest is a
## pass over a dozen walkers.
func refresh() -> void:
	var stamp := _ground_stamp()
	if stamp != _stamp:
		_stamp = stamp
		_update_solid()
	_sync_population()
	_assign_jobs()
	_evict_stranded()

# Cheap fingerprint of "which cells are built on". Instance ids are never
# reused, so their sum moves whenever anything is placed or demolished.
func _ground_stamp() -> int:
	var n := 0
	for id in _colony.buildings:
		n += int(id) * 31 + 1
	return n

## Advances every colonist by `delta` real seconds.
func step(delta: float) -> void:
	for w in walkers:
		match int(w.state):
			State.INSIDE:
				w.timer = float(w.timer) - delta
				if float(w.timer) <= 0.0:
					_leave(w)
			State.PAUSED:
				w.timer = float(w.timer) - delta
				if float(w.timer) <= 0.0:
					_choose_destination(w)
			State.WALKING:
				_advance(w, delta)

## How many colonists are out on the ground rather than inside a building.
func visible_count() -> int:
	var n := 0
	for w in walkers:
		if int(w.state) != State.INSIDE:
			n += 1
	return n

# --- Population ---------------------------------------------------------------

# The crowd matches the colony's population, capped so a big colony doesn't turn
# into a swarm. Before anything is built there is nobody outside to see: the
# colonists are still aboard the lander, and four figures standing on bare
# regolith would read as a bug rather than a colony.
func _sync_population() -> void:
	var target := 0
	if not _colony.buildings.is_empty():
		target = mini(_colony.population, int(_cfg.max_visible))
	while walkers.size() > target:
		walkers.pop_back()
	while walkers.size() < target:
		var spawn := _spawn_cell()
		if spawn.x < 0:
			return  # nowhere to stand yet; try again next refresh
		walkers.append(_new_walker(spawn))

func _new_walker(cell: Vector2i) -> Dictionary:
	var jitter := float(_cfg.speed_jitter)
	var w := {
		"id": _next_id,
		"pos": Vector2(cell),
		"facing": 0,
		"state": State.PAUSED,
		"timer": _rng.randf_range(0.0, 1.5),
		"path": [],
		"speed": float(_cfg.speed) * _rng.randf_range(1.0 - jitter, 1.0 + jitter),
		"enter": -1,
		"inside": -1,
		"door_of": -1,
		# A fixed personal offset from the exact line they walk, so two colonists
		# heading for the same door stand shoulder to shoulder instead of merging
		# into one sprite. Cosmetic: the view adds it, pathing ignores it.
		"offset": Vector2(_rng.randf_range(-0.22, 0.22), _rng.randf_range(-0.22, 0.22)),
	}
	_next_id += 1
	return w

# New arrivals step out of a home building (hub or habitat) if there is one, so
# they appear from a door rather than materialising in the open.
func _spawn_cell() -> Vector2i:
	for id in _home_ids():
		var out: Vector2i = _door(_colony.buildings[id]).outside
		if out.x >= 0:
			return out
	for id in _colony.buildings:
		var out: Vector2i = _door(_colony.buildings[id]).outside
		if out.x >= 0:
			return out
	return Vector2i(-1, -1)

# --- Jobs ---------------------------------------------------------------------

# One slot per worker a running building asks for, oldest building first, handed
# out to colonists in the order they arrived. A building that shuts down stops
# offering slots, so its crew walks out and joins the strollers — which is the
# whole point of driving this from sim state instead of inventing it.
func _assign_jobs() -> void:
	var slots := []
	var ids := _colony.buildings.keys()
	ids.sort()
	for id in ids:
		var inst: Dictionary = _colony.buildings[id]
		if not inst.active:
			continue
		var n := int(_colony.defs[inst.type].get("workers", 0))
		for i in n:
			slots.append(id)
	_jobs.clear()
	for i in walkers.size():
		if i < slots.size():
			_jobs[int(walkers[i].id)] = slots[i]

func _home_ids() -> Array:
	var out := []
	var ids := _colony.buildings.keys()
	ids.sort()
	for id in ids:
		var def: Dictionary = _colony.defs[_colony.buildings[id].type]
		if int(def.get("capacity", 0)) > 0 or int(def.get("life_support", 0)) > 0:
			out.append(id)
	return out

# A colonist whose workplace was demolished (or who was standing where something
# has just been built) is put back on solid open ground rather than left inside a
# building that no longer exists.
func _evict_stranded() -> void:
	for w in walkers:
		var inside := int(w.inside)
		if inside != -1 and not _colony.buildings.has(inside):
			w.inside = -1
			w.enter = -1
			_place_outside(w, Vector2i(w.pos.round()))
		if int(w.state) == State.INSIDE:
			continue
		var cell := Vector2i(w.pos.round())
		if _is_open(cell):
			continue
		# Standing on a building is fine if it's the doorway they're walking
		# through — this runs every tick, so treating that as "stranded" would
		# bounce them off the threshold and nobody would ever get inside.
		var under: Dictionary = _colony.building_at(cell)
		if not under.is_empty() and int(w.door_of) == int(under.id):
			continue
		# Someone mid-stride is only passing over the tile: let them walk out of
		# it rather than snapping them somewhere else, which is far more visible
		# than a colonist clipping a corner for a fraction of a second. Only
		# impassable ground is worth teleporting off.
		if int(w.state) == State.WALKING and not under.is_empty():
			continue
		_place_outside(w, cell)

func _place_outside(w: Dictionary, near: Vector2i) -> void:
	var cell := _nearest_open(near)
	w.pos = Vector2(cell)
	w.path = []
	w.enter = -1
	w.door_of = -1
	w.state = State.PAUSED
	w.timer = _rng.randf_range(0.2, 1.0)

# --- Movement -----------------------------------------------------------------

func _advance(w: Dictionary, delta: float) -> void:
	var budget := float(w.speed) * delta
	while budget > 0.0 and not w.path.is_empty():
		var target: Vector2 = w.path[0]
		var to: Vector2 = target - w.pos
		var dist := to.length()
		if dist > 0.0001:
			w.facing = facing_for(to)
		if dist <= budget:
			w.pos = target
			w.path.pop_front()
			budget -= dist
		else:
			w.pos = w.pos + to / dist * budget
			budget = 0.0
	if w.path.is_empty():
		_arrive(w)

func _arrive(w: Dictionary) -> void:
	if int(w.enter) != -1 and _colony.buildings.has(int(w.enter)):
		w.inside = int(w.enter)
		w.enter = -1
		w.door_of = -1
		w.state = State.INSIDE
		w.timer = _rand_range(_cfg.shift_seconds)
		return
	w.enter = -1
	w.door_of = -1   # back on open ground; the doorway licence lapses
	w.state = State.PAUSED
	w.timer = _rand_range(_cfg.pause_seconds)

# Back out of the door onto the ground in front of it, then decide what's next.
func _leave(w: Dictionary) -> void:
	var id := int(w.inside)
	w.inside = -1
	if _colony.buildings.has(id):
		var door := _door(_colony.buildings[id])
		if door.outside.x >= 0:
			w.pos = door.point
			w.path = [Vector2(door.outside)]
			w.state = State.WALKING
			w.enter = -1
			w.door_of = id   # stepping out through its doorway
			return
	_place_outside(w, Vector2i(w.pos.round()))

# Either back to work or a wander across the open ground. An employed colonist
# who has just finished a shift usually strolls first — a base where everyone
# walks door-to-door looks like a queue, not a colony.
func _choose_destination(w: Dictionary) -> void:
	var job := int(_jobs.get(int(w.id), -1))
	if job != -1 and _colony.buildings.has(job) \
			and _rng.randf() < float(_cfg.work_chance):
		if _walk_to_door(w, job):
			return
	_stroll(w, job)

func _walk_to_door(w: Dictionary, id: int) -> bool:
	var door := _door(_colony.buildings[id])
	if door.outside.x < 0:
		return false
	var path := _path_to(w, door.outside)
	if path.is_empty():
		return false
	path.append(door.point)   # the last step is through the door itself
	w.path = path
	w.enter = id
	w.door_of = id
	w.state = State.WALKING
	return true

func _stroll(w: Dictionary, job: int) -> void:
	var anchor := Vector2i(w.pos.round())
	if job != -1 and _colony.buildings.has(job):
		anchor = _colony.buildings[job].origin
	var radius := int(_cfg.stroll_radius)
	for attempt in 8:
		var cell := anchor + Vector2i(
			_rng.randi_range(-radius, radius), _rng.randi_range(-radius, radius))
		if not _is_open(cell):
			continue
		var path := _path_to(w, cell)
		if path.is_empty():
			continue
		w.path = path
		w.enter = -1
		w.state = State.WALKING
		return
	# Boxed in (or nowhere to go): wait and try again shortly.
	w.state = State.PAUSED
	w.timer = _rand_range(_cfg.pause_seconds)

# A* across open ground, as fractional waypoints. Empty when there's no route —
# callers treat that as "pick something else".
func _path_to(w: Dictionary, to: Vector2i) -> Array:
	var from := Vector2i(w.pos.round())
	if not _is_open(from):
		from = _nearest_open(from)
	if not _is_open(from) or not _is_open(to):
		return []
	var out := []
	for cell in _astar.get_id_path(from, to):
		if Vector2(cell) != w.pos:
			out.append(Vector2(cell))
	return out

# --- Doors --------------------------------------------------------------------

## Where a building is entered: `{ cell, point, outside }` — the footprint cell
## holding the door, the exact spot on it a colonist vanishes into (from the
## def's pixel-measured `door.offset`, so it can be lined up with the art), and
## the open cell in front to approach from (`outside.x < 0` if it's walled in).
##
## With no `door` block a building is entered at the front of its footprint,
## which is where an isometric building's face is anyway.
func _door(inst: Dictionary) -> Dictionary:
	var def: Dictionary = _colony.defs[inst.type]
	var spec: Dictionary = def.get("door", {})
	var cell := _front_cell(inst.cells)
	if spec.has("cell"):
		cell = inst.origin + Vector2i(int(spec.cell[0]), int(spec.cell[1]))
	var point := Vector2(cell)
	if spec.has("offset"):
		point += IsoGrid.screen_offset_to_grid(
			Vector2(float(spec.offset[0]), float(spec.offset[1])))
	return {"cell": cell, "point": point, "outside": _approach(cell)}

# The cell a colonist waits on before stepping inside. Front-most first (the
# camera-facing side, where the art's door is), then anything open.
func _approach(door: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_rank := -99
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c := door + Vector2i(dx, dy)
			if not _is_open(c):
				continue
			var rank := c.x + c.y
			if rank > best_rank:
				best_rank = rank
				best = c
	return best

func _front_cell(cells: Array) -> Vector2i:
	var front: Vector2i = cells[0]
	for c in cells:
		if c.x + c.y > front.x + front.y:
			front = c
	return front

# --- Ground -------------------------------------------------------------------

func _update_solid() -> void:
	var map: ColonyMap = _colony.map
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			_astar.set_point_solid(cell, not _is_open(cell))

func _is_open(cell: Vector2i) -> bool:
	if not _colony.map.in_bounds(cell):
		return false
	if not (_colony.map.get_terrain(cell) in WALKABLE):
		return false
	return _colony.building_at(cell).is_empty()

func _nearest_open(from: Vector2i) -> Vector2i:
	if _is_open(from):
		return from
	for r in range(1, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := from + Vector2i(dx, dy)
				if _is_open(c):
					return c
	return from

func _rand_range(pair: Variant) -> float:
	return _rng.randf_range(float(pair[0]), float(pair[1]))

# --- Facing -------------------------------------------------------------------

## Which of the eight sprite-sheet rows faces along a grid-space direction.
## Rows run S, SE, E, NE, N, NW, W, SW — screen directions, not grid ones, since
## that is what the art is drawn to: "south" is toward the camera.
static func facing_for(dir: Vector2) -> int:
	if dir == Vector2.ZERO:
		return 0
	# Project the grid-space heading into screen space before measuring its angle:
	# equal steps in x and y are 2:1 apart on screen, and the art is drawn to what
	# the player sees, not to the grid.
	var screen := Vector2((dir.x - dir.y) * (IsoGrid.TILE_W / 2.0),
		(dir.x + dir.y) * (IsoGrid.TILE_H / 2.0))
	var angle := atan2(screen.y, screen.x)
	var index := int(round((PI / 2.0 - angle) / (PI / 4.0)))
	return posmod(index, 8)
