extends Node
## Defs — loaded, read-only content definitions.
##
## All game content (resources, buildings, recipes) lives in data/*.json and is
## loaded here at startup. Engine code reads these dictionaries; it never
## hard-codes content. Adding content = editing JSON, not touching this file.

const DATA_DIR := "res://data/"

## resource id (String) -> definition (Dictionary)
var resources: Dictionary = {}

func _ready() -> void:
	resources = _load_json(DATA_DIR + "resources.json")
	print("[Defs] loaded %d resource definitions:" % resources.size())
	for id in resources:
		var r: Dictionary = resources[id]
		print("  - %s: %s (%s)" % [id, r.get("name", "?"), r.get("category", "?")])

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
