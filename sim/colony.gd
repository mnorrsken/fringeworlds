class_name Colony
extends RefCounted
## Pure colony state: the map, the global stockpile, and placed buildings with
## an occupancy index. No autoload/Events/rendering dependencies — building defs
## are injected — so all placement rules are headlessly testable. The Sim
## autoload wraps this and adds signal emission.

enum Status { PLAYING, WON, LOST }

var map: ColonyMap
var defs: Dictionary                  # building id -> def (needs size, cost, allowed_terrain_ids)
## Tunable numbers (data/balance.json). Injected like defs; defaults to the
## shipped values so a Colony can be built bare in tests.
var balance: Balance
var stockpile: Dictionary = {}        # resource id -> amount

var population := 0
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

## Stand-in for "no limit" when the content models no storage at all.
const UNLIMITED := 1 << 30

# Whether the content models storage limits at all.
var _storage_limited := false

# Whether these defs declare a controller building at all. Test colonies built
# from a handful of synthetic defs have no hub, and requiring one there would be
# meaningless — the rule belongs to the content, not the engine.
var _needs_controller := false

# Cells whose scan state changed during the most recent tick (for the overlay).
var scan_changes: Array = []

# Cells an extractor drew ore out of during the most recent tick. The overlay
# shades confirmed tiles by what's left, so it has to repaint as they deplete —
# not just when a scan lands.
var reserve_changes: Array = []

func _init(p_map: ColonyMap, p_defs: Dictionary, p_stockpile: Dictionary = {},
		p_balance: Balance = null) -> void:
	map = p_map
	defs = p_defs
	balance = p_balance if p_balance != null else Balance.new()
	for id in defs:
		if defs[id].get("colony_controller", false):
			_needs_controller = true
		if not defs[id].get("storage", {}).is_empty():
			_storage_limited = true
	stockpile = p_stockpile.duplicate()
	population = balance.starting_population

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

## How much of a resource the colony can hold, summed over everything standing.
## Storage is physical: an unpowered warehouse still holds what's in it, so this
## counts buildings whether or not they're running.
##
## Content that declares no storage anywhere isn't playing by these rules at all
## (the unit tests build colonies from two or three synthetic defs), so capacity
## is unlimited in that case rather than zero.
func storage_for(res: String) -> int:
	if not _storage_limited:
		return UNLIMITED
	var n := 0
	for id in buildings:
		n += int(defs[buildings[id].type].get("storage", {}).get(res, 0))
	return n

## Room left for a resource right now.
func space_for(res: String) -> int:
	return maxi(0, storage_for(res) - int(stockpile.get(res, 0)))

## True when everything in `flow` would fit. Producers check this before
## consuming their inputs — a full store stalls a building rather than quietly
## destroying its output.
func _fits(flow: Dictionary) -> bool:
	for res in flow:
		if int(flow[res]) > space_for(res):
			return false
	return true

## How many of a building type currently stand.
func count_of(type_id: String) -> int:
	var n := 0
	for id in buildings:
		if buildings[id].type == type_id:
			n += 1
	return n

## True while a scanning building's range covers `cell`. Survey stations have to
## be planted inside existing coverage, so prospecting spreads outward from the
## hub in overlapping steps instead of leapfrogging into the dark.
func in_survey_coverage(cell: Vector2i) -> bool:
	for id in buildings:
		var inst: Dictionary = buildings[id]
		var def: Dictionary = defs[inst.type]
		if not def.has("scan"):
			continue
		var s: int = int(def.size)
		var center: Vector2i = inst.origin + Vector2i(s / 2, s / 2)
		if Vector2(cell - center).length() <= float(def.scan.max_radius):
			return true
	return false

## Why the build menu should grey this building out, or "" if it's offerable.
## Covers both tech prerequisites and one-per-colony limits; affordability and
## terrain are per-tile and belong to can_place() instead.
func lock_reason(type_id: String) -> String:
	if bool(defs[type_id].get("unique", false)) and count_of(type_id) > 0:
		return "Already built"
	var missing := missing_prereqs(type_id)
	if missing.is_empty():
		return ""
	var names := []
	for r in missing:
		names.append(str(defs[r].get("name", r)))
	return "Requires: " + ", ".join(names)

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
	if bool(def.get("unique", false)) and count_of(type_id) > 0:
		return {"ok": false, "reason": "Only one allowed"}
	if bool(def.get("requires_coverage", false)) and not in_survey_coverage(origin):
		return {"ok": false, "reason": "Outside survey coverage"}
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
		inst["resampling"] = false
		inst["scan_probes"] = 0
	if def.has("recipe") or def.has("mine"):
		# A small internal hopper. Output lands here first and drains into the
		# colony store as room allows; when both are full the building stops.
		inst["buffer"] = {}
	if def.has("mine"):
		# Latch the deposit under the extractor at placement time.
		inst["deposit_type"] = map.get_deposit(origin)
		inst["richness"] = map.get_richness(origin)
		inst["mine_accum"] = 0.0
		# What the patch it works held when it was sited. Extraction slows as
		# this is drawn down, and it is measured against the patch's own opening
		# reserve so a lean tile still starts at full speed (richness sizes the
		# reserve, never the rate).
		inst["mine_initial"] = _mine_remaining(inst)
	buildings[id] = inst
	for c in cells:
		_occupancy[c] = id
	built_types[type_id] = true
	# A prospecting building that "guarantees" a deposit (the hub) ensures a
	# reachable node of that type exists in its survey range, so the player can
	# always reach metal.
	if def.has("guarantees_deposit_id") and def.has("scan"):
		var center: Vector2i = origin + Vector2i(int(def.size) / 2, int(def.size) / 2)
		_ensure_deposit_in_range(center, int(def.scan.max_radius),
			int(def.guarantees_deposit_id), balance.guaranteed_richness)
	return inst

# Ensures at least one *mineable* deposit of `dep` sits within `radius` of
# `center`. A deposit already under a building doesn't count (it can't be mined),
# so this always leaves the player a reachable node. Deterministic: scans rings
# outward and injects into the first buildable, empty, unoccupied tile it finds.
func _ensure_deposit_in_range(center: Vector2i, radius: int, dep: int, richness: float) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if int(round(sqrt(dx * dx + dy * dy))) > radius:
				continue
			var c := center + Vector2i(dx, dy)
			if map.in_bounds(c) and map.get_deposit(c) == dep and not _occupancy.has(c):
				return  # a reachable one already exists
	for r in range(2, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if int(round(sqrt(dx * dx + dy * dy))) != r:
					continue
				var c := center + Vector2i(dx, dy)
				if not map.in_bounds(c) or _occupancy.has(c):
					continue
				var t := map.get_terrain(c)
				if t != ColonyMap.Terrain.REGOLITH and t != ColonyMap.Terrain.HIGHLANDS:
					continue
				if map.get_deposit(c) != ColonyMap.Deposit.NONE:
					continue
				map.set_deposit(c, dep, richness)
				return

## The building instance covering `cell`, or {} if none.
func building_at(cell: Vector2i) -> Dictionary:
	if _occupancy.has(cell):
		return buildings[_occupancy[cell]]
	return {}

# --- Simulation tick ---------------------------------------------------------

## Housing capacity: the colony ship base plus every habitat.
func capacity() -> int:
	var c := balance.base_capacity
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

## Colonists whose life support is provided for free by running buildings (the
## hub). Consumption from the stockpile only applies to colonists beyond this.
func life_support_covered() -> int:
	var n := 0
	for id in buildings:
		if buildings[id].active:
			n += int(defs[buildings[id].type].get("life_support", 0))
	return n

## Advances one tick: power, workforce, prospecting, life support, production,
## then win/lose evaluation.
func tick() -> void:
	scan_changes = []
	reserve_changes = []
	_balance_power()
	_require_hub()
	_balance_workforce()
	_run_prospecting()
	_run_production()
	_run_life_support()  # after production, so a just-in-time supply counts
	_check_status()

# The hub is the colony's controller as well as its heart: without one standing,
# nothing else runs. Losing it is survivable — build another — but the colony
# holds its breath until then, including life support.
func _require_hub() -> void:
	if not _needs_controller:
		return
	for id in buildings:
		if defs[buildings[id].type].get("colony_controller", false) \
				and buildings[id].active:
			return
	for id in buildings:
		buildings[id].active = false
		buildings[id].idle_reason = "No colony hub"

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
	# The hub covers the first N colonists for free; only the rest draw stock.
	var effective: int = max(0, population - life_support_covered())
	var met := true
	for res in balance.life_support:
		_life_accum[res] = float(_life_accum[res]) \
			+ effective * float(balance.life_support[res])
		var whole := int(_life_accum[res])
		var have := int(stockpile.get(res, 0))
		if whole > 0:
			var take: int = min(whole, have)
			stockpile[res] = have - take
			_life_accum[res] = float(_life_accum[res]) - take
			if take < whole:
				met = false
		# An empty reserve is only a shortage if uncovered colonists actually need it.
		if effective > 0 and int(stockpile.get(res, 0)) <= 0:
			met = false
	if not met:
		_growth_ticks = 0
		_starve_ticks += 1
		if _starve_ticks >= balance.starve_ticks:
			_starve_ticks = 0
			population -= 1
	else:
		_starve_ticks = 0
		if population < capacity():
			_growth_ticks += 1
			if _growth_ticks >= balance.growth_ticks:
				_growth_ticks = 0
				population += 1

func _check_status() -> void:
	if status != Status.PLAYING:
		return
	if population <= 0:
		status = Status.LOST
	elif int(stockpile.get("xenite", 0)) >= balance.victory_xenite:
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

# Scanners sweep an expanding circular ring outward; each visit advances a
# tile's scan state one step (unscanned -> coarse -> confirmed).
#
# What happens after the sweep reaches the outer ring depends on the building.
# The hub simply starts over, so a second systematic pass confirms everything it
# found. A def with `scan.confirm_ticks` instead drops into resampling — slow,
# scattered probes (see _run_resample). Finding a deposit is quick; pinning down
# how rich it is is the patient part.
func _run_prospecting() -> void:
	for id in _ids_oldest_first():
		var inst: Dictionary = buildings[id]
		if not inst.active or not defs[inst.type].has("scan"):
			continue
		var scan: Dictionary = defs[inst.type].scan
		if bool(inst.get("resampling", false)):
			_run_resample(inst, scan)
			continue
		inst.scan_progress = int(inst.scan_progress) + 1
		if int(inst.scan_progress) < int(scan.ticks_per_ring):
			continue
		inst.scan_progress = 0
		_scan_ring(inst, int(inst.scan_ring))
		var next_ring := int(inst.scan_ring) + 1
		inst.scan_ring = 0 if next_ring > int(scan.max_radius) else next_ring
		if next_ring > int(scan.max_radius) and scan.has("confirm_ticks"):
			inst["resampling"] = true

# One probe every `confirm_ticks` at a tile picked pseudo-randomly from the
# station's range. It often lands on ground it has already confirmed, or on bare
# rock, and achieves nothing — that scatter is the cost of confirming richness
# away from the hub.
#
# The pick is hashed from the building id and its probe count rather than drawn
# from an RNG, so the sim stays deterministic and a save reloads mid-sequence.
func _run_resample(inst: Dictionary, scan: Dictionary) -> void:
	inst.scan_progress = int(inst.scan_progress) + 1
	if int(inst.scan_progress) < int(scan.confirm_ticks):
		return
	inst.scan_progress = 0
	var probe := int(inst.get("scan_probes", 0))
	inst["scan_probes"] = probe + 1

	var radius := int(scan.max_radius)
	var size: int = int(defs[inst.type].size)
	var center: Vector2i = inst.origin + Vector2i(size / 2, size / 2)
	var span := radius * 2 + 1
	var h := _probe_hash(int(inst.id), probe)
	var cell := center + Vector2i(h % span - radius, (h / span) % span - radius)
	if not map.in_bounds(cell) or Vector2(cell - center).length() > float(radius):
		return
	if map.get_scan(cell) == ColonyMap.Scan.COARSE:
		map.set_scan(cell, ColonyMap.Scan.CONFIRMED)
		scan_changes.append(cell)

static func _probe_hash(id: int, n: int) -> int:
	var h := (id * 73856093) ^ ((n + 1) * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

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
		_flush(inst)
		inst.progress = int(inst.progress) + 1
		if int(inst.progress) < int(recipe.ticks):
			continue
		if not _buffer_fits(inst, recipe.get("outputs", {})):
			# Hold at the completion threshold rather than burning the inputs:
			# a full colony store backs the hopper up and pauses the line, it
			# doesn't waste what goes in.
			inst.progress = int(recipe.ticks)
			inst.idle_reason = "Storage full"
		elif _has(recipe.get("inputs", {})):
			_spend(recipe.get("inputs", {}))
			_buffer_gain(inst, recipe.get("outputs", {}))
			_flush(inst)   # straight through when there's room; the hopper only
			inst.progress = 0   # holds output the colony currently can't take
		else:
			# Stalled on missing inputs: hold at the completion threshold and
			# name what's short so the inspector can explain the idle.
			inst.progress = int(recipe.ticks)
			inst.idle_reason = "Needs " + ", ".join(_short_inputs(recipe.get("inputs", {})))

# Moves whatever a building is holding internally into the colony store, as far
# as there is room for it. Runs before the building produces, so a line restarts
# the moment space appears somewhere.
func _flush(inst: Dictionary) -> void:
	var buffer: Dictionary = inst.get("buffer", {})
	for res in buffer.keys():
		var held := int(buffer[res])
		if held <= 0:
			buffer.erase(res)
			continue
		var moved: int = mini(held, space_for(res))
		if moved <= 0:
			continue
		stockpile[res] = int(stockpile.get(res, 0)) + moved
		if held - moved > 0:
			buffer[res] = held - moved
		else:
			buffer.erase(res)

## Room left in a building's internal hopper for one resource.
func _buffer_space(inst: Dictionary, res: String) -> int:
	return maxi(0, balance.building_buffer - int(inst.get("buffer", {}).get(res, 0)))

# True when a whole batch of outputs would fit in the hopper.
func _buffer_fits(inst: Dictionary, flow: Dictionary) -> bool:
	for res in flow:
		if int(flow[res]) > _buffer_space(inst, res):
			return false
	return true

func _buffer_gain(inst: Dictionary, flow: Dictionary) -> void:
	var buffer: Dictionary = inst.buffer
	for res in flow:
		buffer[res] = int(buffer.get(res, 0)) + int(flow[res])

## The cells an extractor works: every tile within its `mine.radius` (1 == a 3×3
## patch) that holds the same deposit it was sited on. A machine drills sideways
## as well as down, so one is worth siting where the seam is thickest — but it
## still only draws the one ore, so an iron mine ignores the copper next door.
##
## Derived from the map each time rather than latched at placement, so the patch
## survives a save/load without being stored.
func mine_cells(inst: Dictionary) -> Array:
	var dep := int(inst.get("deposit_type", ColonyMap.Deposit.NONE))
	if dep == ColonyMap.Deposit.NONE:
		return []
	var origin: Vector2i = inst.origin
	var r := int(defs[inst.type].mine.get("radius", 1))
	# Centre first: an extractor eats the ground it stands on before it reaches.
	var cells := [origin]
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)
			if c == origin or not map.in_bounds(c):
				continue
			if map.get_deposit(c) == dep:
				cells.append(c)
	return cells

## Units still in the ground across the whole patch an extractor works.
func _mine_remaining(inst: Dictionary) -> float:
	var total := 0.0
	for c in mine_cells(inst):
		total += map.get_amount(c)
	return total

# Extractors draw their patch down until it's gone, slowing as it empties (see
# _mine_per_tick). Richness sizes the reserve rather than the rate, so a rich
# patch lasts longer instead of pumping faster — and every extractor eventually
# stands on dead ground and has to be moved.
func _run_mine(inst: Dictionary, def: Dictionary) -> void:
	var res: String = ColonyMap.DEPOSIT_RESOURCE.get(int(inst.deposit_type), "")
	if res == "":
		return
	_flush(inst)
	var cells := mine_cells(inst)
	var remaining := 0.0
	for c in cells:
		remaining += map.get_amount(c)
	if remaining <= 0.0:
		inst.active = false
		inst.idle_reason = "Deposit worked out"
		return
	var room := _buffer_space(inst, res)
	if room <= 0:
		# Nowhere to put it: the ore stays in the ground rather than being
		# pumped into a colony that cannot hold it.
		inst.idle_reason = "Storage full"
		return
	inst.mine_accum = float(inst.mine_accum) + _mine_per_tick(inst, def)
	var whole := minf(minf(float(int(inst.mine_accum)), remaining), float(room))
	if whole <= 0.0:
		return
	_buffer_gain(inst, {res: int(whole)})
	_flush(inst)
	inst.mine_accum = float(inst.mine_accum) - whole
	# Take it out of the ground nearest-first, so the tile under the machine is
	# the one the overlay watches go dark first.
	var left := whole
	for c in cells:
		if left <= 0.0:
			break
		var have := map.get_amount(c)
		if have <= 0.0:
			continue
		var take := minf(have, left)
		map.set_amount(c, have - take)
		left -= take
		reserve_changes.append(c)

# The thinner the ground gets, the harder it is to work: extraction runs at the
# def's flat rate while the patch is still better than `mine_full_rate_above` of
# what it started with, then tapers linearly to `mine_min_rate` of it as the
# patch empties. It never reaches zero, so a patch does finish — it just takes
# far longer to scrape out the last of a seam than to skim the top off it.
func _mine_per_tick(inst: Dictionary, def: Dictionary) -> float:
	var base := float(def.mine.base_per_tick)
	var initial := float(inst.get("mine_initial", 0.0))
	var full_above := balance.mine_full_rate_above
	if initial <= 0.0 or full_above <= 0.0:
		return base
	var left := _mine_remaining(inst) / initial
	return base * lerpf(balance.mine_min_rate, 1.0, minf(left / full_above, 1.0))

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
			if res != "" and _mine_remaining(inst) > 0.0:
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
	# Life support drains O2/water/food — but only for colonists the hub doesn't cover.
	var effective: int = max(0, population - life_support_covered())
	if effective > 0:
		for res in balance.life_support:
			r[res] = float(r.get(res, 0.0)) \
				- effective * float(balance.life_support[res])
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
		"storage": def.get("storage", {}),
		"buffer": inst.get("buffer", {}),
		"power": int(def.get("power", 0)),
		"workers": int(def.get("workers", 0)),
		"capacity": int(def.get("capacity", 0)),
		"life_support": int(def.get("life_support", 0)),
		"scans": def.has("scan"),
	}
	if def.has("recipe"):
		rep["recipe"] = def.recipe
		rep["progress"] = int(inst.get("progress", 0))
	if def.has("mine"):
		var dep := int(inst.get("deposit_type", ColonyMap.Deposit.NONE))
		var live := 0
		for c in mine_cells(inst):
			if map.get_amount(c) > 0.0:
				live += 1
		rep["mine"] = {
			"resource": ColonyMap.DEPOSIT_RESOURCE.get(dep, ""),
			"richness": float(inst.get("richness", 0.0)),
			"per_tick": _mine_per_tick(inst, def),
			"remaining": _mine_remaining(inst),
			"tiles": live,
		}
	return rep

func _spend(cost: Dictionary) -> void:
	for r in cost:
		stockpile[r] = int(stockpile.get(r, 0)) - int(cost[r])

# Nothing can be stored beyond capacity. Producers call _fits() first so they
# stall instead of quietly destroying output; this clamp is the backstop for
# demolition refunds and partial draws.
func _gain(gain: Dictionary) -> void:
	for r in gain:
		stockpile[r] = mini(int(stockpile.get(r, 0)) + int(gain[r]), storage_for(r))

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
		d["resampling"] = bool(inst.get("resampling", false))
		d["scan_probes"] = int(inst.get("scan_probes", 0))
	if inst.has("buffer"):
		d["buffer"] = inst.buffer.duplicate()
	if inst.has("deposit_type"):
		d["deposit_type"] = int(inst.deposit_type)
		d["richness"] = float(inst.richness)
		d["mine_accum"] = float(inst.mine_accum)
		d["mine_initial"] = float(inst.get("mine_initial", 0.0))
	return d

## Rebuilds a Colony from a to_dict() snapshot, injecting the (already
## deserialized) map and the live building defs.
static func from_dict(p_map: ColonyMap, p_defs: Dictionary, d: Dictionary,
		p_balance: Balance = null) -> Colony:
	var c := Colony.new(p_map, p_defs, {}, p_balance)
	var stock := {}
	for r in d.get("stockpile", {}):
		stock[r] = int(d.stockpile[r])
	c.stockpile = stock
	c.population = int(d.get("population", c.balance.starting_population))
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
		# Saves from before extraction slowed with depletion carry no opening
		# reserve; take what the patch holds now, so an old save resumes at full
		# rate rather than crawling.
		if inst.has("deposit_type") and not inst.has("mine_initial"):
			inst["mine_initial"] = c._mine_remaining(inst)
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
		inst["resampling"] = bool(bd.get("resampling", false))
		inst["scan_probes"] = int(bd.get("scan_probes", 0))
	if bd.has("buffer"):
		var buffer := {}
		for res in bd.buffer:
			buffer[res] = int(bd.buffer[res])
		inst["buffer"] = buffer
	if bd.has("deposit_type"):
		inst["deposit_type"] = int(bd.deposit_type)
		inst["richness"] = float(bd.richness)
		inst["mine_accum"] = float(bd.mine_accum)
		if bd.has("mine_initial"):
			inst["mine_initial"] = float(bd.mine_initial)
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
	_refund(str(inst.type))
	# Tearing down storage spills whatever no longer fits.
	for res in stockpile:
		stockpile[res] = mini(int(stockpile[res]), storage_for(res))
	return inst

# Demolition returns part of the build cost (balance.demolish_refund), rounded
# down per resource. Without it a colony that over-commits has no way back:
# switching a building off isn't possible, so a parts factory that eats the
# entire metal income would pin the stockpile at zero permanently.
func _refund(type_id: String) -> void:
	if balance.demolish_refund <= 0.0:
		return
	var cost: Dictionary = defs[type_id].get("cost", {})
	for res in cost:
		var amount := int(floor(float(cost[res]) * balance.demolish_refund))
		if amount > 0:
			stockpile[res] = int(stockpile.get(res, 0)) + amount
