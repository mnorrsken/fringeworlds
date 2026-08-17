class_name Weather
extends RefCounted
## Dust storms — the planet pushing back.
##
## A pure scheduler, injected into Colony like Balance: no autoloads, no
## rendering, no RNG object. The schedule is derived by hashing a storm counter,
## so a colony's weather is deterministic for its map seed, identical in the
## pacing harness and the real game, and resumes correctly from a save without
## having to serialize an RNG.
##
## The cycle is CLEAR → WARNING → STORM → CLEAR. The warning phase is the whole
## point: a storm that simply happened to you would be arbitrary, but one that is
## announced is a decision — bank what you can, and switch off (key T) whatever
## you would rather lose than your life support.
##
## What a storm does is deliberately narrow: it dims exposed power (solar panels)
## and blinds prospecting. It does *not* touch mining or life support directly,
## so the colony is squeezed rather than spiralled — the damage arrives through
## the power balance, where the player has a lever.

enum Phase { CLEAR, WARNING, STORM }

## Phase change to announce, returned by advance(): "" most ticks.
const NONE := ""
const WARNING := "warning"
const STORM := "storm"
const CLEAR := "clear"

var phase: int = Phase.CLEAR
## Ticks left in the current phase.
var ticks_left := 0
## Storms completed — the salt for the schedule hash.
var index := 0

var _balance: Balance
var _seed := 0

func _init(p_balance: Balance = null, p_seed := 0) -> void:
	_balance = p_balance if p_balance != null else Balance.new()
	_seed = p_seed
	ticks_left = _balance.storm_grace_ticks

## Advances one tick. Returns the phase change to announce (WARNING/STORM/CLEAR),
## or NONE. Colony calls this at the top of its tick, so a storm applies on the
## same tick it is announced.
func advance() -> String:
	if not _balance.storms_enabled:
		return NONE
	ticks_left -= 1
	if ticks_left > 0:
		return NONE
	match phase:
		Phase.CLEAR:
			phase = Phase.WARNING
			ticks_left = maxi(1, _balance.storm_warning_ticks)
			return WARNING
		Phase.WARNING:
			phase = Phase.STORM
			ticks_left = _roll(_balance.storm_duration_ticks,
				_balance.storm_duration_jitter, 1)
			return STORM
		_:
			phase = Phase.CLEAR
			index += 1
			ticks_left = _roll(_balance.storm_interval_ticks,
				_balance.storm_interval_jitter, 2)
			return CLEAR

func is_storming() -> bool:
	return phase == Phase.STORM

## True once a storm is announced but hasn't landed — the window to prepare.
func is_warning() -> bool:
	return phase == Phase.WARNING

## What exposed power production is multiplied by right now (1.0 = clear skies).
func power_factor() -> float:
	return _balance.storm_power_factor if is_storming() else 1.0

## Airborne dust blinds the survey gear; scanners make no progress in a storm.
func blocks_prospecting() -> bool:
	return is_storming()

# base ± jitter, drawn deterministically from the seed, the storm index and a
# per-field salt (so duration and interval don't move in lockstep).
func _roll(base: int, jitter: int, salt: int) -> int:
	if jitter <= 0:
		return maxi(1, base)
	var h := _hash(_seed, index * 4 + salt)
	return maxi(1, base + h % (jitter * 2 + 1) - jitter)

static func _hash(a: int, b: int) -> int:
	var h := (a * 374761393) ^ ((b + 1) * 668265263)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))

# --- Serialization -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {"phase": phase, "ticks_left": ticks_left, "index": index}

func from_dict(d: Dictionary) -> void:
	phase = int(d.get("phase", Phase.CLEAR))
	ticks_left = int(d.get("ticks_left", ticks_left))
	index = int(d.get("index", 0))
