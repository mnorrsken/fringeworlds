class_name ColonyBot
extends RefCounted
## A scripted "reference player" for Milestone 9 pacing work.
##
## Playing a 45-90 minute session by hand isn't repeatable, and it can't be run
## in CI. This bot plays the pure sim instead — same Colony, same rules, no
## rendering — following the intended build order and buying whatever it can
## afford as soon as it can afford it. That makes it a *lower bound* on how long
## a session takes: a human is slower, never faster.
##
## What it is good for: proving a seed is completable (no dead-ends), and
## measuring where the time actually goes. What it is not: a fun-o-meter.
##
## It only touches Colony/ColonyMap, so it runs headlessly and deterministically.

## Milestones worth timing, in the order a session hits them.
const TRACKED := ["metal", "iron_ore", "copper_ore", "parts", "xenite"]

## Ticks between decisions (4 ticks = 1 second at the shipped tick rate).
const ACT_EVERY := 4
## How long to leave a fruitless site search alone.
const RETRY_TICKS := 600
## How far from a target formation the bot will look for a legal station site.
const SURVEY_REACH := 22
## Housing the bot builds toward — enough to staff the whole chain.
const MAX_POPULATION := 12
## Metal capacity to have in place before switching on the parts factory.
const IRON_MINES_BEFORE_FACTORY := 4
const SMELTERS_BEFORE_FACTORY := 3
## Extractors to keep running at once. Deposits are finite now, so these are
## concurrent counts, not lifetime totals — the bot works a tile out, tears the
## extractor down for the refund, and moves on to the next confirmed tile.
const IRON_MINES := 4
const COPPER_MINES := 2
const CRYSTAL_EXTRACTORS := 3
## Parts worth banking before the factory is shut down — enough for several more
## extractors and a warehouse or two. Rebuilding waits until the bank is nearly
## spent (PARTS_LOW), or the colony oscillates: bank 40, demolish, spend, rebuild.
const PARTS_BANKED := 40
const PARTS_LOW := 12
## Warehouses the bot is willing to build: the three the beacon requires, plus
## one for slack. Reacting to stalled lines without a ceiling paves the map —
## fresh capacity just fills up again, because the mines out-produce the
## smelters by design.
const MAX_WAREHOUSES := 4
## Mines the colony keeps enough metal in hand to (re)build at any moment.
## Only one: storage caps mean metal can't be hoarded, and a deeper reserve
## simply makes the expensive buildings unaffordable forever.
const MINE_RESERVE := 1
## Spare power kept in hand, so the next building has somewhere to plug in.
const POWER_MARGIN := 6

var colony: Colony
var timeline: Dictionary = {}   # label -> tick it first happened
var built: Array = []           # [tick, building id] in build order

var _tick := 0
var _survey_ring := 1           # how far out the next survey station reaches
# Confirmed deposits, kept incrementally from Colony.scan_changes: rescanning
# the whole map every tick is what made an hour-long run take minutes to
# simulate. deposit type -> Array[Vector2i], nearest-first.
var _confirmed: Dictionary = {}
# A site search that found nothing (no ice in range, nowhere to put a survey
# station) would otherwise re-scan the map every decision, forever.
var _retry_after: Dictionary = {}   # type id -> tick to try again

func _init(p_colony: Colony) -> void:
	colony = p_colony

## Plays until the colony wins, loses, or `max_ticks` elapses.
## Returns { won, lost, ticks, minutes, timeline, built, stockpile, population }.
func run(max_ticks: int) -> Dictionary:
	while _tick < max_ticks and colony.status == Colony.Status.PLAYING:
		# A player issues orders at human speed, not four times a second.
		if _tick % ACT_EVERY == 0:
			_act()
		colony.tick()
		_tick += 1
		_note_scans()
		_record()
	return report()

func report() -> Dictionary:
	return {
		"won": colony.status == Colony.Status.WON,
		"lost": colony.status == Colony.Status.LOST,
		"ticks": _tick,
		"minutes": _tick / colony.balance.ticks_per_second / 60.0,
		"timeline": timeline,
		"built": built,
		"population": colony.population,
		"stockpile": colony.stockpile.duplicate(),
	}

# Folds this tick's scan results into the confirmed-deposit index.
func _note_scans() -> void:
	for c in colony.scan_changes:
		if colony.map.get_scan(c) != ColonyMap.Scan.CONFIRMED:
			continue
		var dep := colony.map.get_deposit(c)
		if dep == ColonyMap.Deposit.NONE:
			continue
		if not _confirmed.has(dep):
			_confirmed[dep] = []
		_confirmed[dep].append(c)

# Notes the first tick each tracked resource appears, so a report shows which
# link in the chain the session actually waits on.
func _record() -> void:
	for res in TRACKED:
		if not timeline.has(res) and int(colony.stockpile.get(res, 0)) > 0:
			timeline[res] = _tick

# --- the build order ---------------------------------------------------------

# One placement attempt per decision, highest priority first.
#
# The order matters and is the intended path through the tech tree: the metal
# loop pays for everything else, so it comes first; life support only bites once
# the population outgrows the hub's free coverage; and copper/xenite sit outside
# the hub's survey range, so prospecting has to be pushed outward before the
# parts chain can start.
func _act() -> void:
	if not colony.built_types.has("hub"):
		_place_near("hub", colony.map.width / 2, func(_c): return true)
		return
	# 1. Wait for the hub's first survey before building anything else. Until a
	#    deposit is confirmed the bot can't see it, and the tiles next to the hub
	#    are exactly where the guaranteed iron sits — carpeting them with solar
	#    panels buries the colony's only metal source with no way to get it back.
	#    Watching the overlay before building is what a player does too.
	if not colony.built_types.has("mine") \
			and _find_deposit(ColonyMap.Deposit.IRON) == null:
		return
	# 2. Power headroom, so the next consumer can actually run.
	if _power_headroom() < POWER_MARGIN and _try("solar_panel"):
		return
	# 3. Clear out extractors standing on worked-out ground: the tile is spent,
	#    and the refund pays toward its replacement.
	if _clear_worked_out():
		return
	# 3b. Once enough parts are banked, the factory is pure metal drain — it eats
	#     2 metal every 4 ticks forever. With finite ore that is the difference
	#     between finishing and slowly starving, so tear it down and take the
	#     refund; it can be rebuilt if more parts are ever needed.
	if int(colony.stockpile.get("parts", 0)) >= PARTS_BANKED \
			and _demolish_one("parts_factory"):
		return
	# 4. Metal loop. Spending the starting stockpile on anything else first is
	#    the classic dead-end: no income, nothing affordable.
	if _try_mine("mine", ColonyMap.Deposit.IRON, 1):
		return
	if _count("smelter") < 1 and _try("smelter"):
		return

	# 4b. Storage. The hub's yard is small and holds no xenite at all, so the
	#     beacon simply cannot be filled without warehouses — and a capped store
	#     stalls every line feeding it.
	if _needs_storage() and _try("warehouse"):
		return
	# 5. Life support, before growth makes colonists draw on the stockpile.
	if _count("ice_harvester") < 1 \
			and _try_on_terrain("ice_harvester", ColonyMap.Terrain.ICE):
		return
	if _count("electrolysis_plant") < 1 and _try("electrolysis_plant"):
		return
	if _count("hydroponics_farm") < 1 and _try("hydroponics_farm"):
		return
	# ...and keep it in surplus. One ice harvester does not cover both an
	# electrolysis plant and a farm, so the chain has to be widened as it grows.
	var short := _draining_life_support()
	if short != "" and _build_producer(short):
		return
	# 6. Housing: the smelter, factory and extractor need 7 workers between them,
	#    and population only grows while there's room spare.
	if colony.capacity() - colony.population <= 1 and colony.population < MAX_POPULATION \
			and _try("habitat"):
		return
	# 7. Push prospecting out to find copper and xenite.
	if _needs_more_prospecting() and _try_survey():
		return
	# 8. Parts chain. Widen metal supply *first*: a running parts factory eats
	#    2 metal every 4 ticks, which is more than a couple of mines and one
	#    smelter can replace, and the colony then never affords the extractor.
	if _try_mine("mine", ColonyMap.Deposit.COPPER, COPPER_MINES):
		return
	if _count("mine") < IRON_MINES_BEFORE_FACTORY + 1 \
			and _try_mine("mine", ColonyMap.Deposit.IRON, IRON_MINES_BEFORE_FACTORY):
		return
	if _count("smelter") < SMELTERS_BEFORE_FACTORY and _try("smelter"):
		return
	if _count("parts_factory") < 1 \
			and int(colony.stockpile.get("parts", 0)) < PARTS_LOW \
			and _try("parts_factory"):
		return
	if _try_mine("crystal_extractor", ColonyMap.Deposit.XENITE, CRYSTAL_EXTRACTORS):
		return
	# 9. Nothing gating: widen the metal supply and the power margin.
	if _try_mine("mine", ColonyMap.Deposit.IRON, IRON_MINES):
		return
	if _count("smelter") < 2 and _try("smelter"):
		return
	if _count("solar_panel") < 8:
		_try("solar_panel")

## Which building makes each life-support resource.
const PRODUCER := {
	"water": "ice_harvester",
	"oxygen": "electrolysis_plant",
	"food": "hydroponics_farm",
}

# The life-support resource being drained fastest right now, or "" if all are
# in surplus. This is the same net-rate figure the HUD shows the player.
func _draining_life_support() -> String:
	var rates := colony.rates()
	var worst := ""
	var worst_rate := -0.0001
	for res in PRODUCER:
		var rate := float(rates.get(res, 0.0))
		if rate < worst_rate:
			worst = res
			worst_rate = rate
	return worst

func _build_producer(res: String) -> bool:
	var type_id: String = PRODUCER[res]
	if type_id == "ice_harvester":
		return _try_on_terrain(type_id, ColonyMap.Terrain.ICE)
	return _try(type_id)

# Spare power, treating every consumer as if it were running.
func _power_headroom() -> int:
	var produced := 0
	var demand := 0
	for id in colony.buildings:
		var p := int(colony.defs[colony.buildings[id].type].get("power", 0))
		if p > 0:
			produced += p
		else:
			demand += -p
	return produced - demand

# Keep pushing survey coverage out while the colony is short of somewhere to
# put its next extractor. One confirmed crystal formation is no longer enough:
# each holds only a fraction of the beacon, so the bot wants a queue of them.
func _needs_more_prospecting() -> bool:
	if _find_deposit(ColonyMap.Deposit.COPPER) == null:
		return true
	if _free_deposits(ColonyMap.Deposit.IRON) < 2:
		return true
	# Crystal hunting waits for the parts chain. Stations are expensive, and
	# early metal belongs in the metal loop, not in scouting for an endgame the
	# colony can't build toward yet.
	return colony.built_types.has("parts_factory") \
		and _free_deposits(ColonyMap.Deposit.XENITE) < CRYSTAL_EXTRACTORS + 1

# Warehouses are worth building for two different reasons: to unjam a line that
# has filled its store, and — the one that decides the game — to have somewhere
# to put the beacon's xenite, which the hub cannot hold at all.
func _needs_storage() -> bool:
	if _count("warehouse") >= MAX_WAREHOUSES:
		return false
	# Room for the whole beacon: xenite is never spent, so it all has to fit at
	# once, and the hub holds none of it.
	if colony.storage_for("xenite") < colony.balance.victory_xenite:
		return true
	# Otherwise only when a line is genuinely stalled for want of room. Reacting
	# to any full store instead has the colony paving the map with warehouses.
	for id in colony.buildings:
		if str(colony.buildings[id].get("idle_reason", "")) == "Storage full":
			return true
	return false

# Confirmed, unoccupied tiles of a deposit type that are still available to
# build on.
func _free_deposits(deposit: int) -> int:
	var n := 0
	for c in _confirmed.get(deposit, []):
		if colony.building_at(c).is_empty() and colony.map.get_amount(c) > 0.0:
			n += 1
	return n

# --- placement helpers -------------------------------------------------------

func _count(type_id: String) -> int:
	var n := 0
	for id in colony.buildings:
		if colony.buildings[id].type == type_id:
			n += 1
	return n

func _try(type_id: String) -> bool:
	return _place_near(type_id, 12, func(_c): return true)

func _try_on_terrain(type_id: String, terrain: int) -> bool:
	return _place_near(type_id, 20,
		func(c): return colony.map.get_terrain(c) == terrain)

# Site searches are the expensive part of a run, so never start one for a
# building we can't pay for or haven't unlocked.
func _available(type_id: String) -> bool:
	if _tick < int(_retry_after.get(type_id, 0)):
		return false
	if not colony.is_unlocked(type_id):
		return false
	var cost: Dictionary = colony.defs[type_id].get("cost", {})
	for res in cost:
		if int(colony.stockpile.get(res, 0)) < int(cost[res]):
			return false
	if int(colony.stockpile.get("metal", 0)) - int(cost.get("metal", 0)) \
			< _metal_reserve(type_id):
		return false
	# Don't switch on a consumer the grid can't carry: the power balance sheds
	# the *newest* buildings, so an over-committed grid silently stops the
	# smelter — and with no metal income and no demolition refund, that is
	# unrecoverable. Falling through here makes the bot build a solar panel first.
	var draw := -int(colony.defs[type_id].get("power", 0))
	return draw <= 0 or _power_headroom() >= draw

# Metal that must survive this purchase: whatever is still needed to finish the
# metal loop (mine, smelter, and a panel to actually run them), minus the part
# this purchase is itself paying for.
#
# Until that loop closes there is no metal income at all, and demolition doesn't
# refund — so a colony that spends down to nothing before its first smelter is
# unwinnable. Every purchase has to leave the rest of the bootstrap affordable.
func _metal_reserve(type_id: String) -> int:
	# A building that costs no metal can never be what the colony is saving up
	# for, so a reserve must never block it. The hub is free, and gating it
	# behind the bootstrap reserve leaves the colony with no hub at all — which
	# now means nothing runs and everyone starves.
	if _cost(type_id) == 0:
		return 0
	var need := 0
	if not colony.built_types.has("smelter"):
		var draw := _draw("smelter")
		if type_id != "smelter":
			need += _cost("smelter")
		if not colony.built_types.has("mine"):
			draw += _draw("mine")
			if type_id != "mine":
				need += _cost("mine")
		# Headroom *after* this purchase — a consumer bought now is exactly what
		# pushes the grid short of the smelter later.
		if _power_headroom() - _draw(type_id) < draw and type_id != "solar_panel":
			need += _cost("solar_panel")
	# Ore runs out. Once the metal loop exists, the colony must always be able to
	# afford the next mine *and* the survey station that finds somewhere to put
	# it — going broke with no ore income and no way to prospect for more is
	# unrecoverable, and with finite deposits it is the default outcome rather
	# than an edge case.
	if colony.built_types.has("smelter"):
		var mines := MINE_RESERVE
		if type_id == "mine":
			mines -= 1
		need += mines * _cost("mine")
		# Only hold metal back for a survey station when there is nowhere left
		# to mine. Reserving it while confirmed ore sits unused blocks the very
		# mine the reserve exists to protect, and the colony deadlocks with a
		# healthy bank balance and no income.
		if type_id != "survey_station" \
				and _free_deposits(ColonyMap.Deposit.IRON) < 1:
			need += _cost("survey_station")
	# The win condition outranks everything else. A running parts factory eats
	# 2 metal every 4 ticks forever, so metal income can sit at roughly zero
	# while parts pile up uselessly — hold back an extractor's worth the moment
	# one becomes buildable, or the colony can end up with 1000 parts, a free
	# xenite tile and no way to pay the 20 metal to mine it.
	if type_id != "crystal_extractor" and _wants_extractor():
		need += _cost("crystal_extractor")
	return need

# True while the colony can and should still plant an extractor on xenite.
func _wants_extractor() -> bool:
	return colony.is_unlocked("crystal_extractor") \
		and _extractors_on(ColonyMap.Deposit.XENITE) < CRYSTAL_EXTRACTORS \
		and _find_deposit(ColonyMap.Deposit.XENITE) != null

func _cost(type_id: String) -> int:
	return int(colony.defs[type_id].get("cost", {}).get("metal", 0))

func _draw(type_id: String) -> int:
	return maxi(0, -int(colony.defs[type_id].get("power", 0)))

# Puts an extractor on a confirmed deposit, up to `limit` of that type.
func _try_mine(type_id: String, deposit: int, limit: int) -> bool:
	if _extractors_on(deposit) >= limit:
		return false
	if not _available(type_id):
		return false
	var cell: Variant = _find_deposit(deposit)
	if cell == null:
		return false
	return _commit(type_id, cell)

func _extractors_on(deposit: int) -> int:
	var n := 0
	for id in colony.buildings:
		if int(colony.buildings[id].get("deposit_type", ColonyMap.Deposit.NONE)) == deposit:
			n += 1
	return n

# A confirmed deposit of a type that is free to build on and still has ore in
# it. Tiles that are occupied or worked out are dropped from the index as they
# turn up, so it stays short — and, critically, a tile the colony has already
# emptied never gets a second extractor built on it.
func _find_deposit(deposit: int) -> Variant:
	var cells: Array = _confirmed.get(deposit, [])
	while not cells.is_empty():
		var c: Vector2i = cells[0]
		if colony.map.get_amount(c) <= 0.0:
			cells.pop_front()
			continue
		if colony.building_at(c).is_empty():
			return c
		cells.pop_front()
	return null

# Survey stations have to stand inside existing coverage now, so they can no
# longer leapfrog into the dark — coverage grows outward in overlapping steps.
#
# Where to aim them isn't a guess, though: crystal formations are *visible*
# terrain, so the colony can see which ground is worth surveying long before it
# knows how rich it is. The bot heads for the nearest unconfirmed formation and
# plants the station as close to it as coverage allows, which is exactly the loop
# the design intends — see the crystal, go confirm it.
func _try_survey() -> bool:
	if not _available("survey_station"):
		return false
	# Crystal is visible and worth aiming at; iron isn't, so when the colony is
	# short of ore the station just goes to the frontier to open new ground.
	var goal: Variant = null
	if _free_deposits(ColonyMap.Deposit.IRON) >= 2:
		goal = _nearest_unconfirmed_crystal()
	var cell: Variant = null
	if goal != null:
		cell = _nearest_to(goal, SURVEY_REACH,
			func(c): return colony.can_place("survey_station", c).ok)
	if cell == null:
		# Nothing reachable to aim at: just push the frontier outward instead.
		cell = _farthest_placeable("survey_station", 10 + _survey_ring * 5)
	_survey_ring += 1   # widen the fallback search next time either way
	if cell == null:
		_retry_after["survey_station"] = _tick + RETRY_TICKS
		return false
	return _commit("survey_station", cell)

# The closest crystal formation whose richness hasn't been confirmed yet. Terrain
# is public knowledge; only the reserve underneath needs prospecting.
func _nearest_unconfirmed_crystal() -> Variant:
	var hub := _hub_center()
	var best: Variant = null
	var best_d := 1 << 30
	for y in colony.map.height:
		for x in colony.map.width:
			var c := Vector2i(x, y)
			if colony.map.get_terrain(c) != ColonyMap.Terrain.CRYSTAL:
				continue
			if colony.map.get_scan(c) == ColonyMap.Scan.CONFIRMED:
				continue
			var d := (c - hub).length_squared()
			if d < best_d:
				best_d = d
				best = c
	return best

# The legal build site furthest from the hub — the frontier of survey coverage.
func _farthest_placeable(type_id: String, reach: int) -> Variant:
	var hub := _hub_center()
	var best: Variant = null
	var best_d := -1
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var d := dx * dx + dy * dy
			if d <= best_d:
				continue
			var c := hub + Vector2i(dx, dy)
			if colony.map.in_bounds(c) and colony.can_place(type_id, c).ok:
				best = c
				best_d = d
	return best

# Tears down one building of a type, refunding half its cost.
func _demolish_one(type_id: String) -> bool:
	for id in colony.buildings:
		if colony.buildings[id].type == type_id:
			colony.demolish_at(colony.buildings[id].origin)
			return true
	return false

# Extractors whose tile has run dry: demolish them so the ground is free and
# half the cost comes back. Without this the bot sits on dead mines forever.
func _clear_worked_out() -> bool:
	for id in colony.buildings:
		var inst: Dictionary = colony.buildings[id]
		if str(inst.get("idle_reason", "")) == "Deposit worked out":
			colony.demolish_at(inst.origin)
			return true
	return false

# Places `type_id` on the closest valid tile to the hub (or to map center before
# the hub exists) that also satisfies `extra`.
func _place_near(type_id: String, max_radius: int, extra: Callable) -> bool:
	if not _available(type_id):
		return false
	var cell: Variant = _nearest_to(_hub_center(), max_radius, func(c):
		return colony.can_place(type_id, c).ok and not _is_reserved(c) \
			and extra.call(c))
	if cell == null:
		_retry_after[type_id] = _tick + RETRY_TICKS
		return false
	return _commit(type_id, cell)

# A confirmed deposit is a future extractor site — paving over it wastes the
# tile permanently, since demolition doesn't refund and the ore underneath stays
# buried. The bot builds around what it has found. (Xenite often sits within a
# few tiles of the hub, so without this the base swallows its own win condition.)
func _is_reserved(cell: Vector2i) -> bool:
	return colony.map.get_scan(cell) == ColonyMap.Scan.CONFIRMED \
		and colony.map.get_deposit(cell) != ColonyMap.Deposit.NONE

# Every placement goes through here so the report can show the build order.
func _commit(type_id: String, cell: Vector2i) -> bool:
	if colony.place(type_id, cell) == null:
		return false
	built.append([_tick, type_id])
	return true

# Closest cell to `origin` within `max_radius` satisfying `pred`, or null.
# One pass over the bounding square, skipping anything already further than the
# best match — ring-by-ring scanning re-walked the same cells O(r) times, which
# made a full run take minutes.
func _nearest_to(origin: Vector2i, max_radius: int, pred: Callable) -> Variant:
	var best: Variant = null
	var best_d := max_radius * max_radius + 1
	for dy in range(-max_radius, max_radius + 1):
		for dx in range(-max_radius, max_radius + 1):
			var d := dx * dx + dy * dy
			if d >= best_d:
				continue
			var c := origin + Vector2i(dx, dy)
			if colony.map.in_bounds(c) and pred.call(c):
				best = c
				best_d = d
	return best

func _hub_center() -> Vector2i:
	for id in colony.buildings:
		if colony.buildings[id].type == "hub":
			return colony.buildings[id].origin
	return Vector2i(colony.map.width / 2, colony.map.height / 2)

## The real building defs, preprocessed the way Defs does at startup. Headless
## runs have no autoloads, so they can't just read Defs.
static func load_defs() -> Dictionary:
	var arr: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/buildings.json"))
	var out := {}
	for def in arr:
		var ids: Array[int] = []
		for name in def.get("allowed_terrain", []):
			ids.append(ColonyMap.Terrain[name])
		def["allowed_terrain_ids"] = ids
		if def.has("requires_deposit"):
			var deps: Array[int] = []
			for name in def.requires_deposit:
				deps.append(ColonyMap.Deposit[name])
			def["requires_deposit_ids"] = deps
		if def.has("guarantees_deposit"):
			def["guarantees_deposit_id"] = ColonyMap.Deposit[def.guarantees_deposit]
		out[def.id] = def
	return out
