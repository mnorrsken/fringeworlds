class_name Asteroids
extends RefCounted
## Skyfall: rocks off the belt coming down on the colony.
##
## A pure scheduler in the same family as Weather — no autoloads, no rendering,
## no RNG object. Both the timing and the target tile are derived by hashing a
## drop counter with the map seed, so a colony's skyfall is deterministic for its
## seed, identical in the pacing harness and the real game, and resumes from a
## save mid-descent.
##
## A drop runs FALLING (the long approach) → CRASHING (the impact) → gone from
## this list, at which point the object is written onto the map's tile and stays
## there. That last step is the point: an asteroid is a delivery, not an event.
## What it is worth is in data/objects.json, and collecting it is a colonist job
## that doesn't exist yet — for now they simply accumulate.
##
## Nothing here damages the colony. These land on open ground the base isn't
## using, and a tile with a rock on it is refused to the next one, so the map
## can't silt up with ice on top of ice.

enum Phase { FALLING, CRASHING }

## The one kind of object that falls today. New kinds are a data entry plus a
## line here — the sim never reads what a kind is worth.
const ICE := "ice_asteroid"

## In-flight rocks: [{ id, kind, cell, phase, ticks_left }].
var falling: Array = []

## Drops scheduled so far — the salt for the hash, and the source of ids.
var index := 0
## Ticks until the next drop is released.
var ticks_left := 0

var _balance: Balance
var _seed := 0

func _init(p_balance: Balance = null, p_seed := 0) -> void:
	_balance = p_balance if p_balance != null else Balance.new()
	_seed = p_seed
	ticks_left = _balance.asteroid_grace_ticks

## Advances one tick. `is_free` is called with a Vector2i and must answer whether
## a rock may come to rest there — the map alone can't say, since it doesn't know
## what the colony has built. Returns the events of this tick:
## [{ type: "impact"|"launch", cell: Vector2i, kind: String }].
func advance(map: ColonyMap, is_free: Callable) -> Array:
	var out := []
	# Advance what's already in the air first, so a drop released this tick gets
	# its full fall rather than being aged on the same tick.
	var landed := []
	for a in falling:
		a.ticks_left = int(a.ticks_left) - 1
		if int(a.ticks_left) > 0:
			continue
		if int(a.phase) == Phase.FALLING:
			a.phase = Phase.CRASHING
			a.ticks_left = maxi(1, _balance.asteroid_crash_ticks)
		else:
			landed.append(a)
	for a in landed:
		falling.erase(a)
		# The ground may have been built on during the descent; if it has, the
		# rock is simply lost rather than landing inside a warehouse.
		if is_free.call(a.cell):
			map.set_object(a.cell, {"kind": str(a.kind)})
			out.append({"type": "impact", "cell": a.cell, "kind": str(a.kind)})

	if not _balance.asteroids_enabled:
		return out
	ticks_left -= 1
	if ticks_left > 0:
		return out
	ticks_left = _roll(_balance.asteroid_interval_ticks,
		_balance.asteroid_interval_jitter)
	index += 1
	# A cap on what's lying about, counted over the ground and the sky together,
	# so a colony that never collects anything doesn't end up under a glacier.
	if _count_on_ground(map) + falling.size() >= _balance.asteroid_max_on_ground:
		return out
	var cell: Variant = _pick_cell(map, is_free)
	if cell == null:
		return out
	falling.append({
		"id": index, "kind": ICE, "cell": cell,
		"phase": Phase.FALLING,
		"ticks_left": maxi(1, _balance.asteroid_fall_ticks),
	})
	out.append({"type": "launch", "cell": cell, "kind": ICE})
	return out

## How far through its current phase a rock is, 0..1 — what the view animates on.
func progress(a: Dictionary) -> float:
	var total: int = _balance.asteroid_fall_ticks if int(a.phase) == Phase.FALLING \
		else _balance.asteroid_crash_ticks
	if total <= 0:
		return 1.0
	return clampf(float(total - int(a.ticks_left)) / float(total), 0.0, 1.0)

func _count_on_ground(map: ColonyMap) -> int:
	return map.objects().size()

# A target tile, hunted deterministically: probe cells drawn from the seed and
# the drop index, and take the first free one. Bounded so a colony that has
# built over everything costs a few dozen checks, not a map sweep.
func _pick_cell(map: ColonyMap, is_free: Callable) -> Variant:
	for probe in 40:
		var h := _hash(_seed, index * 97 + probe)
		var cell := Vector2i(h % map.width, (h / map.width) % map.height)
		if is_free.call(cell):
			return cell
	return null

func _roll(base: int, jitter: int) -> int:
	if jitter <= 0:
		return maxi(1, base)
	return maxi(1, base + _hash(_seed, index * 7 + 3) % (jitter * 2 + 1) - jitter)

static func _hash(a: int, b: int) -> int:
	var h := (a * 2654435761) ^ ((b + 1) * 40503)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

# --- Serialization -----------------------------------------------------------

func to_dict() -> Dictionary:
	var air := []
	for a in falling:
		air.append({
			"id": int(a.id), "kind": str(a.kind),
			"x": a.cell.x, "y": a.cell.y,
			"phase": int(a.phase), "ticks_left": int(a.ticks_left),
		})
	return {"index": index, "ticks_left": ticks_left, "falling": air}

func from_dict(d: Dictionary) -> void:
	index = int(d.get("index", 0))
	ticks_left = int(d.get("ticks_left", ticks_left))
	falling = []
	for e in d.get("falling", []):
		falling.append({
			"id": int(e.get("id", 0)), "kind": str(e.get("kind", ICE)),
			"cell": Vector2i(int(e.x), int(e.y)),
			"phase": int(e.get("phase", Phase.FALLING)),
			"ticks_left": int(e.get("ticks_left", 1)),
		})
