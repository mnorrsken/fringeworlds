class_name AudioCues
extends RefCounted
## The cue vocabulary shared by the game and the `Audio` autoload.
##
## Pure names and mapping logic, with no engine or audio-server dependency, so
## the "which sound does this event make" rules stay headlessly testable (the
## same split as the sim classes). Every cue listed in `required()` must have an
## entry in data/audio.json. Never instantiated — static members only.

const AMBIENT := "ambient"
const UI_CLICK := "ui_click"
const PLACE := "place"
const DENIED := "denied"
const DEMOLISH := "demolish"
const WIN := "win"
const LOSE := "lose"

## Indexed by AlertMonitor.Level (INFO, WARN, CRIT).
const ALERT := ["alert_info", "alert_warn", "alert_crit"]

## Every cue the game can ask for — the contract data/audio.json must satisfy.
static func required() -> Array:
	return [AMBIENT, UI_CLICK, PLACE, DENIED, DEMOLISH, WIN, LOSE] + ALERT

## Cue for an Events.alert level. Unknown levels fall back to the nearest tier,
## so a new AlertMonitor.Level can never silence an alert.
static func for_alert(level: int) -> String:
	return ALERT[clampi(level, 0, ALERT.size() - 1)]

## Cue for Events.game_over.
static func for_game_over(won: bool) -> String:
	return WIN if won else LOSE
