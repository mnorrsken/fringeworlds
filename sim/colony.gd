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
	var inst := {"id": id, "type": type_id, "origin": origin, "cells": cells}
	buildings[id] = inst
	for c in cells:
		_occupancy[c] = id
	return inst

## The building instance covering `cell`, or {} if none.
func building_at(cell: Vector2i) -> Dictionary:
	if _occupancy.has(cell):
		return buildings[_occupancy[cell]]
	return {}

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
