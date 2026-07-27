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

# The intended session length (Milestone 9). The bot buys the instant it can
# afford to, so it runs faster than a person: the target is a bot win around
# half an hour, which puts a human session in the plan's 45-90 minute window.
# Tuning that drifts outside this band should fail loudly rather than quietly
# turn the game into a five-minute clicker or an hour of waiting.
const BOT_MINUTES_MIN := 15.0
const BOT_MINUTES_MAX := 50.0

func test_sessions_land_in_the_intended_window(t: Object) -> void:
	for seed in SEEDS:
		var r := _run(seed)
		t.ok(r.minutes >= BOT_MINUTES_MIN,
			"seed %d isn't over too fast (%.1f min, floor %.0f)" % [
				seed, r.minutes, BOT_MINUTES_MIN])
		t.ok(r.minutes <= BOT_MINUTES_MAX,
			"seed %d doesn't drag (%.1f min, ceiling %.0f)" % [
				seed, r.minutes, BOT_MINUTES_MAX])
