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
## Compass directions the survey stations rotate through as they push outward.
const DIRECTIONS := 8
## Housing the bot builds toward — enough to staff the whole chain.
const MAX_POPULATION := 12
## Metal capacity to have in place before switching on the parts factory.
const IRON_MINES_BEFORE_FACTORY := 4
const SMELTERS_BEFORE_FACTORY := 3
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
	# 1. Power headroom, so the next consumer can actually run.
	if _power_headroom() < POWER_MARGIN and _try("solar_panel"):
		return
	# 2. Metal loop. Spending the starting stockpile on anything else first is
	#    the classic dead-end: no income, nothing affordable.
	if _try_mine("mine", ColonyMap.Deposit.IRON, 1):
		return
	if _count("smelter") < 1 and _try("smelter"):
		return

	# 3. Life support, before growth makes colonists draw on the stockpile.
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
	# 4. Housing: the smelter, factory and extractor need 7 workers between them,
	#    and population only grows while there's room spare.
	if colony.capacity() - colony.population <= 1 and colony.population < MAX_POPULATION \
			and _try("habitat"):
		return
	# 5. Push prospecting out to find copper and xenite.
	if _needs_more_prospecting() and _try_survey():
		return
	# 6. Parts chain. Widen metal supply *first*: a running parts factory eats
	#    2 metal every 4 ticks, which is more than a couple of mines and one
	#    smelter can replace, and the colony then never affords the extractor.
	if _try_mine("mine", ColonyMap.Deposit.COPPER, 1):
		return
	if _count("mine") < IRON_MINES_BEFORE_FACTORY + 1 \
			and _try_mine("mine", ColonyMap.Deposit.IRON, IRON_MINES_BEFORE_FACTORY):
		return
	if _count("smelter") < SMELTERS_BEFORE_FACTORY and _try("smelter"):
		return
	if _count("parts_factory") < 1 and _try("parts_factory"):
		return
	if _try_mine("crystal_extractor", ColonyMap.Deposit.XENITE, 2):
		return
	# 7. Nothing gating: widen the metal supply and the power margin.
	if _try_mine("mine", ColonyMap.Deposit.IRON, 3):
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

# Prospect further out while a needed deposit type hasn't been confirmed yet.
func _needs_more_prospecting() -> bool:
	return _find_deposit(ColonyMap.Deposit.COPPER) == null \
		or _find_deposit(ColonyMap.Deposit.XENITE) == null

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
		and _extractors_on(ColonyMap.Deposit.XENITE) < 1 \
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

# A confirmed, still-free deposit of a type, or null. Occupied tiles are dropped
# as they're found, so the index stays short.
func _find_deposit(deposit: int) -> Variant:
	var cells: Array = _confirmed.get(deposit, [])
	while not cells.is_empty():
		var c: Vector2i = cells[0]
		if colony.building_at(c).is_empty():
			return c
		cells.pop_front()
	return null

# Survey stations leapfrog outward: each one is planted a scan radius further
# from the hub than the last, rotating through eight directions, so the
# confirmed area keeps growing instead of thickening around the hub.
func _try_survey() -> bool:
	if not _available("survey_station"):
		return false
	var radius: int = int(colony.defs["survey_station"].scan.max_radius)
	var step := _survey_ring
	var distance: float = radius * (1.0 + floor(step / DIRECTIONS))
	var angle: float = TAU * float(step % DIRECTIONS) / float(DIRECTIONS)
	var target := _hub_center() + Vector2i(
		int(round(cos(angle) * distance)), int(round(sin(angle) * distance)))
	_survey_ring += 1   # always move on, so a bad spot isn't retried forever
	var cell: Variant = _nearest_to(target, radius,
		func(c): return colony.can_place("survey_station", c).ok)
	if cell == null:
		return false
	return _commit("survey_station", cell)

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
