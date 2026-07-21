extends RefCounted
## Guards against the early-game "metal cliff": you must be able to afford a
## viable path to self-sustaining metal from the starting stockpile.

func _buildings() -> Dictionary:
	var arr: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/buildings.json"))
	var out := {}
	for e in arr:
		out[e.id] = e
	return out

# Read the constant from source text — loading sim.gd here would recompile it
# without the autoload identifiers it references, which fails headlessly.
func _starting_metal() -> int:
	var text := FileAccess.get_file_as_string("res://sim/sim.gd")
	for line in text.split("\n"):
		if line.contains("STARTING_STOCKPILE"):
			var rx := RegEx.new()
			rx.compile('"metal"\\s*:\\s*(\\d+)')
			var m := rx.search(line)
			if m != null:
				return int(m.get_string(1))
	return 0

func test_metal_chain_affordable_from_start(t: Object) -> void:
	var defs := _buildings()
	# Power + life support + prospect + one mine + one smelter = a self-sustaining
	# metal loop. It must fit inside the starting metal, with room to spare.
	var plan := {
		"solar_panel": 2, "ice_harvester": 1, "electrolysis_plant": 1,
		"hydroponics_farm": 1, "survey_station": 1, "mine": 1, "smelter": 1,
	}
	var total := 0
	for id in plan:
		total += int(defs[id].cost.get("metal", 0)) * int(plan[id])
	var start := _starting_metal()
	t.ok(total <= start, "bootstrap costs %d metal, start is %d" % [total, start])
	# ...and a little headroom left over (not down to the last credit).
	t.ok(start - total >= 20, "at least 20 metal headroom after the bootstrap")
