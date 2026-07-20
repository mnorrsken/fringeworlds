class_name Colony
extends RefCounted
## Pure colony state: the map, the global stockpile, and placed buildings with
## an occupancy index. No autoload/Events/rendering dependencies — building defs
## are injected — so all placement rules are headlessly testable. The Sim
## autoload wraps this and adds signal emission.

var map: ColonyMap
var defs: Dictionary                  # building id -> def (needs size, cost, allowed_terrain_ids)
var stockpile: Dictionary = {}        # resource id -> amount

var buildings: Dictionary = {}        # building instance id (int) -> instance dict
var _occupancy: Dictionary = {}       # Vector2i cell -> building instance id
var _next_id := 1

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

## { "ok": bool, "reason": String } — why a placement is or isn't allowed.
func can_place(type_id: String, origin: Vector2i) -> Dictionary:
	if not defs.has(type_id):
		return {"ok": false, "reason": "Unknown building"}
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
	var inst := {
		"id": id, "type": type_id, "origin": origin, "cells": cells,
		"active": true, "progress": 0,
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
	return inst

## The building instance covering `cell`, or {} if none.
func building_at(cell: Vector2i) -> Dictionary:
	if _occupancy.has(cell):
		return buildings[_occupancy[cell]]
	return {}

# --- Simulation tick ---------------------------------------------------------

## Advances the economy by one tick: balance power, prospect, then produce.
func tick() -> void:
	scan_changes = []
	_balance_power()
	_run_prospecting()
	_run_production()

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
		elif p < 0:
			consumers.append(id)
		else:
			inst.active = true

	power_consumed = 0
	var available := power_produced
	for id in consumers:  # already oldest-first
		var inst: Dictionary = buildings[id]
		var need := -int(defs[inst.type].power)
		if available >= need:
			inst.active = true
			available -= need
			power_consumed += need
		else:
			inst.active = false

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
			# Stalled on missing inputs: hold at the completion threshold.
			inst.progress = int(recipe.ticks)

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

func _spend(cost: Dictionary) -> void:
	for r in cost:
		stockpile[r] = int(stockpile.get(r, 0)) - int(cost[r])

func _gain(gain: Dictionary) -> void:
	for r in gain:
		stockpile[r] = int(stockpile.get(r, 0)) + int(gain[r])

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
