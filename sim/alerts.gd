class_name AlertMonitor
extends RefCounted
## Edge-triggered alert detector — pure sim, no autoload/Events dependency so it
## is headlessly testable. Given a Colony after a tick, `check()` returns the
## alerts that just *became* true (rising edges only), so a sustained condition
## fires once, not every tick. Sim owns one of these and emits Events.alert for
## each returned entry; UI (the alert ticker) renders them.

enum Level { INFO, WARN, CRIT }

# A resource at or below this stock, while being net-drained, counts as "running
# low" — early enough to warn before it hits zero (for life support, before
# starvation, since STARVE_TICKS only starts after zero).
const LOW_STOCK := 8

var _power_deficit := false
var _low := {}  # resource id -> was-low last tick (edge-trigger state)

## Returns [{text: String, level: int}] for conditions newly true this tick.
func check(col: Colony) -> Array:
	var out := []

	# Power: consumers get shed when demand outstrips supply.
	var deficit := col.power_consumed > col.power_produced
	if deficit and not _power_deficit:
		out.append({"text": "⚡ Power deficit — buildings shutting down", "level": Level.CRIT})
	_power_deficit = deficit

	# Any resource that's being net-drained and has dipped low warns once (this
	# covers life support consumed by colonists, but also metal/parts/ore drawn
	# down by the production chain). Rearms once it recovers.
	var rates := col.rates()
	for res in rates:
		var low: bool = float(rates[res]) < -0.0001 and int(col.stockpile.get(res, 0)) <= LOW_STOCK
		if low and not bool(_low.get(res, false)):
			out.append({"text": "⚠ %s running low" % _cap(res), "level": Level.WARN})
		_low[res] = low
	# A resource no longer draining rearms so it can warn again later.
	for res in _low:
		if not rates.has(res):
			_low[res] = false

	# Prospecting: announce each deposit kind confirmed on this tick.
	var kinds := {}
	for c in col.scan_changes:
		if col.map.get_scan(c) == ColonyMap.Scan.CONFIRMED:
			var dep := col.map.get_deposit(c)
			if dep != ColonyMap.Deposit.NONE:
				kinds[dep] = true
	for dep in kinds:
		out.append({
			"text": "◆ Deposit confirmed: %s" % ColonyMap.DEPOSIT_NAMES[dep],
			"level": Level.INFO,
		})

	return out

# "iron_ore" -> "Iron Ore" (Godot's capitalize() splits underscores into words).
func _cap(s: String) -> String:
	return s.capitalize()
