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

## Emitted after a tick if any tiles' prospecting scan state changed. Payload is
## the list of changed cells; the prospecting overlay updates just those.
signal scan_changed(cells: Array)

## Emitted once when the colony reaches a terminal state (won == true means the
## xenite beacon was launched; false means the population died out).
signal game_over(won: bool)
