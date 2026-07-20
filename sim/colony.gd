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

## Advances the economy by one tick: balance power, then run production.
func tick() -> void:
	_balance_power()
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

func _run_production() -> void:
	for id in _ids_oldest_first():
		var inst: Dictionary = buildings[id]
		if not inst.active:
			continue
		var def: Dictionary = defs[inst.type]
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

## Net stockpile change per tick from currently-active buildings (for the HUD).
func rates() -> Dictionary:
	var r := {}
	for id in buildings:
		var inst: Dictionary = buildings[id]
		if not inst.active or not defs[inst.type].has("recipe"):
			continue
		var recipe: Dictionary = defs[inst.type].recipe
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
