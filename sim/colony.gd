class_name Colony
extends RefCounted
## Pure colony state: the map, the global stockpile, and placed buildings with
## an occupancy index. No autoload/Events/rendering dependencies — building defs
## are injected — so all placement rules are headlessly testable. The Sim
## autoload wraps this and adds signal emission.

enum Status { PLAYING, WON, LOST }

const STARTING_POPULATION := 4
const BASE_CAPACITY := 4               # the colony ship houses the starters
const STARVE_TICKS := 24               # ticks of unmet needs before a death (~6s)
const GROWTH_TICKS := 80               # ticks of met needs before a birth (~20s)
const VICTORY_XENITE := 50             # xenite needed to "launch the beacon"

# Life support consumed per colonist per tick (kept gentle — the early base runs
# on robots, so colonists are a slow-burning pressure, not an immediate crisis).
const LIFE_SUPPORT := {"oxygen": 0.02, "water": 0.02, "food": 0.015}

var map: ColonyMap
var defs: Dictionary                  # building id -> def (needs size, cost, allowed_terrain_ids)
var stockpile: Dictionary = {}        # resource id -> amount

var population := STARTING_POPULATION
var status: int = Status.PLAYING

# Fractional life-support carryover, and streak counters for growth/starvation.
var _life_accum := {"oxygen": 0.0, "water": 0.0, "food": 0.0}
var _starve_ticks := 0
var _growth_ticks := 0

var buildings: Dictionary = {}        # building instance id (int) -> instance dict
var _occupancy: Dictionary = {}       # Vector2i cell -> building instance id
var _next_id := 1

# Building types ever built — drives tech unlocks (a prerequisite stays unlocked
# even if you later demolish the building that unlocked it).
var built_types: Dictionary = {}

# Power figures from the most recent tick (for HUD display).
var power_produced := 0
var power_consumed := 0

# Cells whose scan state changed during the most recent tick (for the overlay).
var scan_changes: Array = []

func _init(p_map: ColonyMap, p_defs: Dictionary, p_stockpile: Dictionary = {}) -> void:
	map = p_map
	defs = p_defs
	stockpile = p_stockpile.duplicate()

## Cells a building of `type_id` anchored at `origin` (its min corner) covers.
func footprint(type_id: String, origin: Vector2i) -> Array:
	var s: int = defs[type_id].size
	var cells := []
	for dy in s:
		for dx in s:
			cells.append(origin + Vector2i(dx, dy))
	return cells

## True once all of a building's prerequisite types have been built.
func is_unlocked(type_id: String) -> bool:
	return missing_prereqs(type_id).is_empty()

## Prerequisite building type ids not yet built (empty == unlocked).
func missing_prereqs(type_id: String) -> Array:
	var missing := []
	for req in defs[type_id].get("requires_built", []):
		if not built_types.has(req):
			missing.append(req)
	return missing

## { "ok": bool, "reason": String } — why a placement is or isn't allowed.
func can_place(type_id: String, origin: Vector2i) -> Dictionary:
	if not defs.has(type_id):
		return {"ok": false, "reason": "Unknown building"}
	if not is_unlocked(type_id):
		return {"ok": false, "reason": "Locked — prerequisite not built"}
	var def: Dictionary = defs[type_id]
	for c in footprint(type_id, origin):
		if not map.in_bounds(c):
			return {"ok": false, "reason": "Off the map"}
		if not (map.get_terrain(c) in def.allowed_terrain_ids):
			return {"ok": false, "reason": "Terrain not allowed"}
		if _occupancy.has(c):
			return {"ok": false, "reason": "Tile occupied"}
	if def.has("requires_deposit_ids"):
		# Extractors (all 1x1) need a confirmed matching deposit under them.
		if map.get_scan(origin) != ColonyMap.Scan.CONFIRMED:
			return {"ok": false, "reason": "Deposit not confirmed"}
		if not (map.get_deposit(origin) in def.requires_deposit_ids):
			return {"ok": false, "reason": "No matching deposit"}
	if not _can_afford(def.cost):
		return {"ok": false, "reason": "Cannot afford"}
	return {"ok": true, "reason": ""}

func _can_afford(cost: Dictionary) -> bool:
	for r in cost:
		if int(stockpile.get(r, 0)) < int(cost[r]):
			return false
	return true

## Places a building, deducting cost. Returns the instance dict, or null if the
## placement is invalid.
func place(type_id: String, origin: Vector2i) -> Variant:
	if not can_place(type_id, origin).ok:
		return null
	var def: Dictionary = defs[type_id]
	for r in def.cost:
		stockpile[r] = int(stockpile.get(r, 0)) - int(def.cost[r])
	var cells := footprint(type_id, origin)
	var id := _next_id
	_next_id += 1
	# `active` = powered/running (set each tick by power balance); `progress`
	# counts ticks toward the next recipe completion.
	# `active` = powered/staffed/running (set each tick by the balance passes);
	# `progress` counts ticks toward the next recipe completion; `idle_reason` is
	# the human-readable "why am I not running" string the inspector shows ("" ==
	# running fine), rewritten every tick by the phase that last touched it.
	var inst := {
		"id": id, "type": type_id, "origin": origin, "cells": cells,
		"active": true, "progress": 0, "idle_reason": "",
	}
	if def.has("scan"):
		inst["scan_ring"] = 0
		inst["scan_progress"] = 0
	if def.has("mine"):
		# Latch the deposit under the extractor at placement time.
		inst["deposit_type"] = map.get_deposit(origin)
		inst["richness"] = map.get_richness(origin)
		inst["mine_accum"] = 0.0
	buildings[id] = inst
	for c in cells:
		_occupancy[c] = id
	built_types[type_id] = true
	return inst

## The building instance covering `cell`, or {} if none.
func building_at(cell: Vector2i) -> Dictionary:
	if _occupancy.has(cell):
		return buildings[_occupancy[cell]]
	return {}

# --- Simulation tick ---------------------------------------------------------

## Housing capacity: the colony ship base plus every habitat.
func capacity() -> int:
	var c := BASE_CAPACITY
	for id in buildings:
		c += int(defs[buildings[id].type].get("capacity", 0))
	return c

## Workers currently employed by running (active) buildings.
func workers_used() -> int:
	var n := 0
	for id in buildings:
		if buildings[id].active:
			n += int(defs[buildings[id].type].get("workers", 0))
	return n

## Advances one tick: power, workforce, prospecting, life support, production,
## then win/lose evaluation.
func tick() -> void:
	scan_changes = []
	_balance_power()
	_balance_workforce()
	_run_prospecting()
	_run_production()
	_run_life_support()  # after production, so a just-in-time supply counts
	_check_status()

# Among powered buildings, staff oldest-first; idle the newest when the workforce
# demand exceeds the population.
func _balance_workforce() -> void:
	var available := population
	for id in _ids_oldest_first():
		var inst: Dictionary = buildings[id]
		if not inst.active:
			continue
		var w := int(defs[inst.type].get("workers", 0))
		if w <= 0:
			continue
		if available >= w:
			available -= w
		else:
			inst.active = false
			inst.idle_reason = "No workers"

# Consume O2/water/food for the population; sustained shortage kills colonists,
# sustained surplus grows them (up to capacity).
func _run_life_support() -> void:
	if population <= 0:
		return
	var met := true
	for res in LIFE_SUPPORT:
		_life_accum[res] = float(_life_accum[res]) + population * float(LIFE_SUPPORT[res])
		var whole := int(_life_accum[res])
		var have := int(stockpile.get(res, 0))
		if whole > 0:
			var take: int = min(whole, have)
			stockpile[res] = have - take
			_life_accum[res] = float(_life_accum[res]) - take
			if take < whole:
				met = false
		# No reserve of a life-support resource at all is a shortage.
		if int(stockpile.get(res, 0)) <= 0:
			met = false
	if not met:
		_growth_ticks = 0
		_starve_ticks += 1
		if _starve_ticks >= STARVE_TICKS:
			_starve_ticks = 0
			population -= 1
	else:
		_starve_ticks = 0
		if population < capacity():
			_growth_ticks += 1
			if _growth_ticks >= GROWTH_TICKS:
				_growth_ticks = 0
				population += 1

func _check_status() -> void:
	if status != Status.PLAYING:
		return
	if population <= 0:
		status = Status.LOST
	elif int(stockpile.get("xenite", 0)) >= VICTORY_XENITE:
		status = Status.WON

# Generators always run. Consumers are switched on oldest-first (by id) while
# there's power budget; the newest ones shut down when demand exceeds supply.
func _balance_power() -> void:
	power_produced = 0
	var consumers := []  # instance ids of buildings that draw power
	for id in _ids_oldest_first():
		var inst: Dictionary = buildings[id]
		var p := int(defs[inst.type].get("power", 0))
		if p > 0:
			power_produced += p
			inst.active = true
			inst.idle_reason = ""
		elif p < 0:
			consumers.append(id)
		else:
			inst.active = true
			inst.idle_reason = ""

	power_consumed = 0
	var available := power_produced
	for id in consumers:  # already oldest-first
		var inst: Dictionary = buildings[id]
		var need := -int(defs[inst.type].power)
		if available >= need:
			inst.active = true
			inst.idle_reason = ""
			available -= need
			power_consumed += need
		else:
			inst.active = false
			inst.idle_reason = "No power"

# Survey stations sweep an expanding circular ring outward; each visit advances
# a tile's scan state one step (unscanned -> coarse -> confirmed). After the
# outer ring, the sweep restarts from the center, so a second pass confirms.
func _run_prospecting() -> void:
	for id in _ids_oldest_first():
		var inst: Dictionary = buildings[id]
		if not inst.active or not defs[inst.type].has("scan"):
			continue
		var scan: Dictionary = defs[inst.type].scan
		inst.scan_progress = int(inst.scan_progress) + 1
		if int(inst.scan_progress) < int(scan.ticks_per_ring):
			continue
		inst.scan_progress = 0
		_scan_ring(inst, int(inst.scan_ring))
		var next_ring := int(inst.scan_ring) + 1
		inst.scan_ring = 0 if next_ring > int(scan.max_radius) else next_ring

func _scan_ring(inst: Dictionary, ring: int) -> void:
	var s: int = defs[inst.type].size
	var center: Vector2i = inst.origin + Vector2i(s / 2, s / 2)
	for dy in range(-ring, ring + 1):
		for dx in range(-ring, ring + 1):
			if int(round(sqrt(dx * dx + dy * dy))) != ring:
				continue
			var c := center + Vector2i(dx, dy)
			if not map.in_bounds(c):
				continue
			var st := map.get_scan(c)
			if st < ColonyMap.Scan.CONFIRMED:
				map.set_scan(c, st + 1)
				scan_changes.append(c)

func _run_production() -> void:
	for id in _ids_oldest_first():
		var inst: Dictionary = buildings[id]
		if not inst.active:
			continue
		var def: Dictionary = defs[inst.type]
		if def.has("mine"):
			_run_mine(inst, def)
			continue
		if not def.has("recipe"):
			continue
		var recipe: Dictionary = def.recipe
		inst.progress = int(inst.progress) + 1
		if int(inst.progress) < int(recipe.ticks):
			continue
		if _has(recipe.get("inputs", {})):
			_spend(recipe.get("inputs", {}))
			_gain(recipe.get("outputs", {}))
			inst.progress = 0
		else:
			# Stalled on missing inputs: hold at the completion threshold and
			# name what's short so the inspector can explain the idle.
			inst.progress = int(recipe.ticks)
			inst.idle_reason = "Needs " + ", ".join(_short_inputs(recipe.get("inputs", {})))

# Extractors yield their deposit's resource at base_rate x richness per tick,
# accumulating fractional output so rich tiles produce visibly faster.
func _run_mine(inst: Dictionary, def: Dictionary) -> void:
	var res: String = ColonyMap.DEPOSIT_RESOURCE.get(int(inst.deposit_type), "")
	if res == "":
		return
	inst.mine_accum = float(inst.mine_accum) + _mine_per_tick(inst, def)
	var whole := int(inst.mine_accum)
	if whole > 0:
		stockpile[res] = int(stockpile.get(res, 0)) + whole
		inst.mine_accum = float(inst.mine_accum) - whole

func _mine_per_tick(inst: Dictionary, def: Dictionary) -> float:
	return float(def.mine.base_per_tick) * float(inst.richness)

## Net stockpile change per tick from currently-active buildings (for the HUD).
func rates() -> Dictionary:
	var r := {}
	for id in buildings:
		var inst: Dictionary = buildings[id]
		if not inst.active:
			continue
		var def: Dictionary = defs[inst.type]
		if def.has("mine"):
			var res: String = ColonyMap.DEPOSIT_RESOURCE.get(int(inst.deposit_type), "")
			if res != "":
				r[res] = float(r.get(res, 0.0)) + _mine_per_tick(inst, def)
			continue
		if not def.has("recipe"):
			continue
		var recipe: Dictionary = def.recipe
		var per_tick := 1.0 / float(recipe.ticks)
		for res in recipe.get("outputs", {}):
			r[res] = float(r.get(res, 0.0)) + float(recipe.outputs[res]) * per_tick
		for res in recipe.get("inputs", {}):
			r[res] = float(r.get(res, 0.0)) - float(recipe.inputs[res]) * per_tick
	# Life support drains O2/water/food.
	if population > 0:
		for res in LIFE_SUPPORT:
			r[res] = float(r.get(res, 0.0)) - population * float(LIFE_SUPPORT[res])
	return r

func _ids_oldest_first() -> Array:
	var ids := buildings.keys()
	ids.sort()
	return ids

func _has(cost: Dictionary) -> bool:
	for r in cost:
		if int(stockpile.get(r, 0)) < int(cost[r]):
			return false
	return true

# The input resources a recipe can't currently afford (for the idle reason).
func _short_inputs(inputs: Dictionary) -> Array:
	var short := []
	for r in inputs:
		if int(stockpile.get(r, 0)) < int(inputs[r]):
			short.append(r)
	return short

## Display data for the building inspector — live instance state merged with its
## def. Returns {} if `id` isn't a placed building. Pure (no formatting): the UI
## turns this into text.
func building_report(id: int) -> Dictionary:
	if not buildings.has(id):
		return {}
	var inst: Dictionary = buildings[id]
	var def: Dictionary = defs[inst.type]
	var rep := {
		"id": id,
		"type": inst.type,
		"name": str(def.get("name", inst.type)),
		"active": bool(inst.active),
		"idle_reason": str(inst.get("idle_reason", "")),
		"power": int(def.get("power", 0)),
		"workers": int(def.get("workers", 0)),
		"capacity": int(def.get("capacity", 0)),
		"scans": def.has("scan"),
	}
	if def.has("recipe"):
		rep["recipe"] = def.recipe
		rep["progress"] = int(inst.get("progress", 0))
	if def.has("mine"):
		var dep := int(inst.get("deposit_type", ColonyMap.Deposit.NONE))
		rep["mine"] = {
			"resource": ColonyMap.DEPOSIT_RESOURCE.get(dep, ""),
			"richness": float(inst.get("richness", 0.0)),
			"per_tick": _mine_per_tick(inst, def),
		}
	return rep

func _spend(cost: Dictionary) -> void:
	for r in cost:
		stockpile[r] = int(stockpile.get(r, 0)) - int(cost[r])

func _gain(gain: Dictionary) -> void:
	for r in gain:
		stockpile[r] = int(stockpile.get(r, 0)) + int(gain[r])

# --- Serialization -----------------------------------------------------------

## A JSON-safe snapshot of colony state (everything except `map`, which is
## serialized separately). Vector2i fields are flattened to [x, y]. `from_dict()`
## is the inverse; the occupancy index is rebuilt from the buildings on load.
func to_dict() -> Dictionary:
	var blds := []
	for id in _ids_oldest_first():
		blds.append(_inst_to_dict(buildings[id]))
	return {
		"stockpile": stockpile.duplicate(),
		"population": population,
		"status": status,
		"next_id": _next_id,
		"starve_ticks": _starve_ticks,
		"growth_ticks": _growth_ticks,
		"life_accum": _life_accum.duplicate(),
		"built_types": built_types.duplicate(),
		"buildings": blds,
	}

func _inst_to_dict(inst: Dictionary) -> Dictionary:
	var o: Vector2i = inst.origin
	var cells := []
	for c in inst.cells:
		cells.append([c.x, c.y])
	var d := {
		"id": int(inst.id), "type": str(inst.type),
		"origin": [o.x, o.y], "cells": cells,
		"active": bool(inst.active), "progress": int(inst.progress),
		"idle_reason": str(inst.get("idle_reason", "")),
	}
	if inst.has("scan_ring"):
		d["scan_ring"] = int(inst.scan_ring)
		d["scan_progress"] = int(inst.scan_progress)
	if inst.has("deposit_type"):
		d["deposit_type"] = int(inst.deposit_type)
		d["richness"] = float(inst.richness)
		d["mine_accum"] = float(inst.mine_accum)
	return d

## Rebuilds a Colony from a to_dict() snapshot, injecting the (already
## deserialized) map and the live building defs.
static func from_dict(p_map: ColonyMap, p_defs: Dictionary, d: Dictionary) -> Colony:
	var c := Colony.new(p_map, p_defs, {})
	var stock := {}
	for r in d.get("stockpile", {}):
		stock[r] = int(d.stockpile[r])
	c.stockpile = stock
	c.population = int(d.get("population", STARTING_POPULATION))
	c.status = int(d.get("status", Status.PLAYING))
	c._next_id = int(d.get("next_id", 1))
	c._starve_ticks = int(d.get("starve_ticks", 0))
	c._growth_ticks = int(d.get("growth_ticks", 0))
	var la: Dictionary = d.get("life_accum", {})
	for k in c._life_accum:
		c._life_accum[k] = float(la.get(k, 0.0))
	var bt := {}
	for k in d.get("built_types", {}):
		bt[k] = true
	c.built_types = bt
	for bd in d.get("buildings", []):
		var inst := _inst_from_dict(bd)
		var id: int = inst.id
		c.buildings[id] = inst
		for cell in inst.cells:
			c._occupancy[cell] = id
	return c

static func _inst_from_dict(bd: Dictionary) -> Dictionary:
	var cells := []
	for pair in bd.cells:
		cells.append(Vector2i(int(pair[0]), int(pair[1])))
	var inst := {
		"id": int(bd.id), "type": str(bd.type),
		"origin": Vector2i(int(bd.origin[0]), int(bd.origin[1])),
		"cells": cells,
		"active": bool(bd.get("active", true)),
		"progress": int(bd.get("progress", 0)),
		"idle_reason": str(bd.get("idle_reason", "")),
	}
	if bd.has("scan_ring"):
		inst["scan_ring"] = int(bd.scan_ring)
		inst["scan_progress"] = int(bd.scan_progress)
	if bd.has("deposit_type"):
		inst["deposit_type"] = int(bd.deposit_type)
		inst["richness"] = float(bd.richness)
		inst["mine_accum"] = float(bd.mine_accum)
	return inst

## Removes the building covering `cell` (any of its footprint cells works).
## Returns the removed instance, or null if the cell was empty.
func demolish_at(cell: Vector2i) -> Variant:
	if not _occupancy.has(cell):
		return null
	var id: int = _occupancy[cell]
	var inst: Dictionary = buildings[id]
	for c in inst.cells:
		_occupancy.erase(c)
	buildings.erase(id)
	return inst
