extends RefCounted
## Milestone 9 acceptance: a session must be completable, on every seed, without
## dead-ends. ColonyBot (tools/colony_bot.gd) plays the real sim headlessly, so
## this catches a balance change that makes the game unwinnable — the kind of
## regression no unit test on an individual building would ever notice.
##
## The bot buys the moment it can afford to, so its times are a floor, not a
## prediction of how long a person takes. `make playtest` prints the detail.

const SEEDS := [1337, 4242, 90210]
const MAP_SIZE := 64
const TICK_CAP := 60 * 60 * 4      # an hour of game time; well past any win

func _run(seed: int) -> Dictionary:
	var balance := Balance.from_dict(JSON.parse_string(
		FileAccess.get_file_as_string("res://data/balance.json")))
	var map := ColonyMap.new(MAP_SIZE, MAP_SIZE)
	map.generate(seed)
	map.reading_jitter = balance.reading_jitter
	var colony := Colony.new(map, ColonyBot.load_defs(), balance.starting_stockpile, balance)
	return ColonyBot.new(colony).run(TICK_CAP)

func test_every_seed_is_completable(t: Object) -> void:
	for seed in SEEDS:
		var r := _run(seed)
		t.ok(r.won, "seed %d reaches the beacon (got %s after %.1f min)" % [
			seed, "a loss" if r.lost else "a timeout", r.minutes])

func test_no_seed_starves_the_colony(t: Object) -> void:
	for seed in SEEDS:
		var r := _run(seed)
		t.ok(not r.lost, "seed %d never loses the colony" % seed)
		t.ok(r.population > 0, "seed %d still has colonists at the end" % seed)

# The whole chain has to be reachable, not just the win: if a seed could win
# without ever making parts, something in the tech gating has come loose.
func test_the_full_chain_is_exercised(t: Object) -> void:
	var r := _run(SEEDS[0])
	for res in ["iron_ore", "metal", "copper_ore", "parts", "xenite"]:
		t.ok(r.timeline.has(res), "seed %d produces %s" % [SEEDS[0], res])

# A floor on session length: if a tuning change ever makes the beacon reachable
# in a couple of minutes, the prospect-then-build loop has stopped mattering.
func test_a_session_is_not_trivially_short(t: Object) -> void:
	for seed in SEEDS:
		var r := _run(seed)
		t.ok(r.minutes > 5.0,
			"seed %d takes more than five minutes (took %.1f)" % [seed, r.minutes])
