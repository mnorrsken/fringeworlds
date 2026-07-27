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
## Xenite that must be stockpiled to launch the beacon and win.
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
## Extractable units a deposit holds at full richness, keyed by deposit name. A
## tile's actual reserve is its richness times this, so richness now means "how
## much is down there", not "how fast it comes up" — extraction runs at a flat
## rate and a tile simply runs dry. Xenite is deliberately small against the
## victory target: one crystal formation can't finish the beacon.
var deposit_units := {"IRON": 600.0, "COPPER": 260.0, "XENITE": 30.0}
## Fraction of a building's cost returned when it is demolished. This is the
## colony's only way to turn a building back into resources, so it is what makes
## an over-committed base recoverable instead of a dead end.
var demolish_refund := 0.5

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

	var sim: Dictionary = d.get("sim", {})
	b.ticks_per_second = float(sim.get("ticks_per_second", b.ticks_per_second))
	b.autosave_seconds = float(sim.get("autosave_seconds", b.autosave_seconds))
	b.low_stock = int(sim.get("low_stock", b.low_stock))
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
