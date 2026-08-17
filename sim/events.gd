extends Node
## Events — global signal bus.
##
## Sim emits signals here; UI and render layers connect to them. UI must never
## poke Sim internals directly: it calls Sim methods and listens on this bus.
## Keep signals coarse and gameplay-meaningful; add them as milestones need them.

## Emitted once per simulation tick, after sim state has advanced.
signal ticked(tick: int)

## Emitted when the global stockpile changes (resource id -> amount).
signal stockpile_changed(stockpile: Dictionary)

## Emitted after a building is placed / removed. Payload is the instance dict
## ({ id, type, origin, cells }). The render layer spawns/frees sprites from these.
signal building_placed(instance: Dictionary)
signal building_removed(instance: Dictionary)

## Emitted when the player switches a building off or back on. The tick already
## refreshes every sprite, but a toggle has to land while paused too.
signal building_toggled(instance: Dictionary)

## Emitted after a tick if any tiles' prospecting scan state changed. Payload is
## the list of changed cells; the prospecting overlay updates just those.
signal scan_changed(cells: Array)

## Emitted after a tick if extractors drew down any tiles' reserves. Payload is
## the list of those cells; the prospecting overlay reshades them, since it shows
## how much of a deposit is left.
signal reserves_changed(cells: Array)

## Emitted when the weather changes phase (a Weather.Phase value). The storm
## overlay and the sidebar countdown read the live Weather off Sim.colony.
signal weather_changed(phase: int)

## Emitted once when the colony reaches a terminal state (won == true means the
## xenite beacon was launched; false means the population died out).
signal game_over(won: bool)

## Emitted for a critical event the player should be told about (power deficit,
## life support low, deposit confirmed). `level` is an AlertMonitor.Level
## (0 = info, 1 = warning, 2 = critical). The alert ticker renders these.
signal alert(text: String, level: int)
