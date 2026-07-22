extends Node
## Defs — loaded, read-only content definitions.
##
## All game content (resources, buildings, recipes) lives in data/*.json and is
## loaded here at startup. Engine code reads these dictionaries; it never
## hard-codes content. Adding content = editing JSON, not touching this file.

const DATA_DIR := "res://data/"

## resource id (String) -> definition (Dictionary)
var resources: Dictionary = {}

## building id (String) -> definition (Dictionary). Each def is augmented at load
## with `allowed_terrain_ids` (Array[int]) and `color_value` (Color) so game code
## never re-parses terrain names or hex strings.
var buildings: Dictionary = {}

func _ready() -> void:
	resources = _load_json(DATA_DIR + "resources.json")
	print("[Defs] loaded %d resource definitions" % resources.size())
	buildings = _load_buildings(DATA_DIR + "buildings.json")
	print("[Defs] loaded %d building definitions" % buildings.size())

## Loads buildings.json and pre-processes each entry for fast use at runtime.
func _load_buildings(path: String) -> Dictionary:
	var raw := _load_json(path)
	for id in raw:
		var def: Dictionary = raw[id]
		var ids: Array[int] = []
		for name in def.get("allowed_terrain", []):
			if ColonyMap.Terrain.has(name):
				ids.append(ColonyMap.Terrain[name])
			else:
				push_warning("[Defs] building '%s' unknown terrain '%s'" % [id, name])
		def["allowed_terrain_ids"] = ids
		def["color_value"] = Color.html(str(def.get("color", "ffffff")))
		if def.has("requires_deposit"):
			var deps: Array[int] = []
			for name in def.requires_deposit:
				if ColonyMap.Deposit.has(name):
					deps.append(ColonyMap.Deposit[name])
				else:
					push_warning("[Defs] building '%s' unknown deposit '%s'" % [id, name])
			def["requires_deposit_ids"] = deps
		if def.has("guarantees_deposit"):
			var g := str(def.guarantees_deposit)
			if ColonyMap.Deposit.has(g):
				def["guarantees_deposit_id"] = ColonyMap.Deposit[g]
			else:
				push_warning("[Defs] building '%s' unknown deposit '%s'" % [id, g])
	return raw

## Loads a JSON file expected to contain an array of objects each with an "id"
## field, and returns a dictionary keyed by that id. Returns {} on any failure.
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("[Defs] missing data file: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("[Defs] failed to parse JSON: %s" % path)
		return {}
	if not (parsed is Array):
		push_error("[Defs] expected a JSON array at top level: %s" % path)
		return {}
	var out: Dictionary = {}
	for entry in parsed:
		if entry is Dictionary and entry.has("id"):
			out[entry["id"]] = entry
		else:
			push_warning("[Defs] skipping entry without 'id' in %s" % path)
	return out
