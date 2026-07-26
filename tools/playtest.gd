extends SceneTree
## Headless pacing harness (Milestone 9):
##   godot --headless --script res://tools/playtest.gd
## Plays several seeds with ColonyBot and prints how long each takes and where
## the time goes. See tools/colony_bot.gd for what the bot does.

const SEEDS := [1337, 4242, 90210, 7, 55555]
const MAP_SIZE := 64
const MAX_TICKS := 60 * 60 * 4      # one hour of game time at 4 ticks/s

func _init() -> void:
	var defs := ColonyBot.load_defs()
	var balance := Balance.from_dict(JSON.parse_string(
		FileAccess.get_file_as_string("res://data/balance.json")))
	print("Playtest: %d seeds, %dx%d map, cap %d ticks (%.0f min)\n" % [
		SEEDS.size(), MAP_SIZE, MAP_SIZE, MAX_TICKS,
		MAX_TICKS / balance.ticks_per_second / 60.0])

	var total := 0.0
	var wins := 0
	for seed in SEEDS:
		var map := ColonyMap.new(MAP_SIZE, MAP_SIZE)
		map.generate(seed)
		map.reading_jitter = balance.reading_jitter
		var colony := Colony.new(map, defs, balance.starting_stockpile, balance)
		var bot := ColonyBot.new(colony)
		var r := bot.run(MAX_TICKS)
		_print_run(seed, r, balance)
		if r.won:
			wins += 1
			total += r.minutes
	print("\n%d/%d seeds won%s" % [wins, SEEDS.size(),
		"" if wins == 0 else ", average %.1f min" % (total / wins)])
	quit(0 if wins == SEEDS.size() else 1)

func _print_run(seed: int, r: Dictionary, balance: Balance) -> void:
	var outcome := "WON" if r.won else ("LOST" if r.lost else "TIMED OUT")
	print("seed %-6d %-9s %6d ticks  %5.1f min   pop %d  xenite %d/%d" % [
		seed, outcome, r.ticks, r.minutes, r.population,
		int(r.stockpile.get("xenite", 0)), balance.victory_xenite])
	var marks := []
	for res in ColonyBot.TRACKED:
		if r.timeline.has(res):
			marks.append("%s@%.1fm" % [res, r.timeline[res] / balance.ticks_per_second / 60.0])
		else:
			marks.append("%s@never" % res)
	print("            first: %s" % "  ".join(marks))
	var order := []
	for entry in r.built:
		order.append("%s(%.0fm)" % [entry[1], entry[0] / balance.ticks_per_second / 60.0])
	print("            built: %s" % "  ".join(order))
