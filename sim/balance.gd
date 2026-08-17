class_name Balance
extends RefCounted
## Every tunable number the sim runs on, in one injectable object loaded from
## `data/balance.json` (Milestone 9). Tuning the game is editing that file — no
## engine code, no recompile, and nothing to hunt for across sim classes.
##
## The values here are the defaults, and they are the shipped balance: the JSON
## file only overrides what it names. That means a Colony built without a Balance
## (as the headless tests do) still behaves exactly like the real game, and a
## partial or missing balance.json degrades to sane numbers rather than zeroes.

## Colonists the colony starts with.
var starting_population := 4
## Housing before any building provides it — the hub is what shelters the first
## colonists, so this is deliberately 0.
var base_capacity := 0
## Consecutive ticks of unmet life support before a colonist dies.
var starve_ticks := 24
## Consecutive ticks of met needs (with housing spare) before one is born.
var growth_ticks := 110
## Xenite that must be banked to launch the beacon and complete phase 1. Xenite
## is an ordinary high-energy material otherwise — later technology will burn it
## — this is simply the quota the first phase of the colony is judged on.
var victory_xenite := 260
## Richness of the iron deposit the hub guarantees within its survey range.
var guaranteed_richness := 0.6
## Per colonist, per tick.
var life_support := {"oxygen": 0.02, "water": 0.02, "food": 0.015}
## What the colony starts with in the global stockpile.
var starting_stockpile := {"metal": 50, "oxygen": 60, "water": 60, "food": 60}
## Simulation rate. Recipe `ticks` and the rates above are all relative to this.
var ticks_per_second := 4.0
## Real seconds between autosaves.
var autosave_seconds := 180.0
## A draining resource at or below this stock raises the "running low" alert.
var low_stock := 8
## Spread of the noise on an unconfirmed prospecting reading (± this, roughly).
var reading_jitter := 0.25
## Units of each resource a building can hold internally before it has to stop.
## Small on purpose: it keeps a line from stalling the instant the colony store
## fills, and gives the player a moment to react, without becoming storage in
## its own right.
var building_buffer := 4
## Extractable units a deposit holds at full richness, keyed by deposit name. A
## tile's actual reserve is its richness times this, so richness means "how much
## is down there", not "how fast it comes up" — the rate depends only on how
## worked-out the patch is (below), and a tile eventually runs dry. Xenite is
## deliberately small against the phase-1 quota: one crystal formation can't
## fill it on its own.
var deposit_units := {"IRON": 1400.0, "COPPER": 620.0, "XENITE": 70.0}
## Extraction slows as the patch an extractor works empties out. It runs at the
## def's full rate while the patch still holds more than `mine_full_rate_above`
## of what it held when the machine was sited, then tapers linearly down to
## `mine_min_rate` of that rate as the patch approaches empty. The floor is what
## keeps a patch finite: scraping out the last of a seam is slow, not endless.
var mine_min_rate := 0.2
var mine_full_rate_above := 0.5
## Fraction of a building's cost returned when it is demolished. This is the
## colony's only way to turn a building back into resources, so it is what makes
## an over-committed base recoverable instead of a dead end.
var demolish_refund := 0.5

## Dust storms (see sim/weather.gd). Ticks, so 4 = one second at 1x.
## Storms can be switched off wholesale for a calm-weather game.
var storms_enabled := true
## Quiet ticks before the first storm is announced — long enough that the metal
## loop is standing before the weather starts interfering with it.
var storm_grace_ticks := 1600
## Between the end of one storm and the announcement of the next, ± jitter.
var storm_interval_ticks := 1500
var storm_interval_jitter := 400
## Lead time between the warning and the storm arriving. This is the player's
## window to bank resources and switch off what they can afford to lose.
var storm_warning_ticks := 48
## How long a storm blows for, ± jitter.
var storm_duration_ticks := 200
var storm_duration_jitter := 60
## What `exposed` power production (solar) is multiplied by during a storm.
## Not zero: a blacked-out grid would shed life support with no counterplay.
var storm_power_factor := 0.35

## Builds a Balance from parsed JSON. Unknown sections and keys are ignored;
## anything absent keeps its default above.
static func from_dict(d: Dictionary) -> Balance:
	var b := Balance.new()
	var colony: Dictionary = d.get("colony", {})
	b.starting_population = int(colony.get("starting_population", b.starting_population))
	b.base_capacity = int(colony.get("base_capacity", b.base_capacity))
	b.starve_ticks = int(colony.get("starve_ticks", b.starve_ticks))
	b.growth_ticks = int(colony.get("growth_ticks", b.growth_ticks))
	b.guaranteed_richness = float(colony.get("guaranteed_richness", b.guaranteed_richness))
	b.demolish_refund = clampf(
		float(colony.get("demolish_refund", b.demolish_refund)), 0.0, 1.0)

	var victory: Dictionary = d.get("victory", {})
	b.victory_xenite = int(victory.get("xenite", b.victory_xenite))

	var mining: Dictionary = d.get("mining", {})
	b.mine_min_rate = clampf(float(mining.get("min_rate", b.mine_min_rate)), 0.0, 1.0)
	b.mine_full_rate_above = clampf(
		float(mining.get("full_rate_above", b.mine_full_rate_above)), 0.0, 1.0)

	var weather: Dictionary = d.get("weather", {})
	b.storms_enabled = bool(weather.get("enabled", b.storms_enabled))
	b.storm_grace_ticks = int(weather.get("grace_ticks", b.storm_grace_ticks))
	b.storm_interval_ticks = int(weather.get("interval_ticks", b.storm_interval_ticks))
	b.storm_interval_jitter = int(weather.get("interval_jitter", b.storm_interval_jitter))
	b.storm_warning_ticks = int(weather.get("warning_ticks", b.storm_warning_ticks))
	b.storm_duration_ticks = int(weather.get("duration_ticks", b.storm_duration_ticks))
	b.storm_duration_jitter = int(weather.get("duration_jitter", b.storm_duration_jitter))
	b.storm_power_factor = clampf(
		float(weather.get("power_factor", b.storm_power_factor)), 0.0, 1.0)

	var sim: Dictionary = d.get("sim", {})
	b.ticks_per_second = float(sim.get("ticks_per_second", b.ticks_per_second))
	b.autosave_seconds = float(sim.get("autosave_seconds", b.autosave_seconds))
	b.low_stock = int(sim.get("low_stock", b.low_stock))
	b.building_buffer = int(sim.get("building_buffer", b.building_buffer))
	b.reading_jitter = float(sim.get("reading_jitter", b.reading_jitter))

	# Overriding either of these replaces the whole table rather than merging, so
	# a resource can be removed from the diet / starting kit by leaving it out.
	if d.has("life_support"):
		b.life_support = _merge(d.life_support, {}, false)
	if d.has("starting_stockpile"):
		b.starting_stockpile = _merge(d.starting_stockpile, {}, true)
	if d.has("deposit_units"):
		b.deposit_units = _merge(d.deposit_units, b.deposit_units, false)
	return b

# JSON numbers all parse as floats; stockpile amounts are whole units, life
# support rates aren't.
static func _merge(src: Dictionary, defaults: Dictionary, whole: bool) -> Dictionary:
	var out := defaults.duplicate()
	for k in src:
		out[k] = int(src[k]) if whole else float(src[k])
	return out
