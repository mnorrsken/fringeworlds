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
