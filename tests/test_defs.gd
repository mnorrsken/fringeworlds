extends RefCounted
## Milestone 0 smoke tests: the data pipeline that Defs depends on.
## Tests pure data/logic directly — no autoloads, no rendering — per the
## "simulation is testable headlessly" architecture principle.

const RESOURCES := "res://data/resources.json"

func _parse(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func test_resources_is_array_of_nine(t: Object) -> void:
	var data: Variant = _parse(RESOURCES)
	t.ok(data is Array, "resources.json parses to an Array")
	t.eq(data.size(), 9, "resource definition count")

func test_resources_have_required_fields(t: Object) -> void:
	var data: Variant = _parse(RESOURCES)
	for entry in data:
		for key in ["id", "name", "category", "unit"]:
			t.ok(entry is Dictionary and entry.has(key), "entry missing '%s'" % key)

func test_resource_ids_are_unique(t: Object) -> void:
	var data: Variant = _parse(RESOURCES)
	var ids := {}
	for entry in data:
		ids[entry["id"]] = true
	t.eq(ids.size(), data.size(), "resource ids are unique")
