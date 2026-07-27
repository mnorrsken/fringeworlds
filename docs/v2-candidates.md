# v2 candidates — designed, not built

Milestone 9 asks for the next round of features to be *written down* rather than
built. This is that list: five candidates from the plan (§ Milestone 9), each
sketched far enough to be costed and argued about, with the parts of the current
architecture they would disturb named explicitly.

Nothing here is committed to. The point is that when v2 starts, the arguments
have already happened.

## What v1 leaves us with

Three facts from the M9 balance pass shape everything below:

- **Metal is the universal currency and it is tight.** Every building costs
  metal; only the smelter makes it. The pacing harness found that a single parts
  factory can eat the entire output of two smelters (see
  [architecture.md](architecture.md), pacing harness). Any v2 feature that adds a
  metal sink, or interrupts metal income, lands on an economy with very little
  slack.
- **The global stockpile is load-bearing.** `Colony.stockpile` is one dictionary
  read by placement costs, recipes, life support, the HUD, alerts and save/load.
  It is the single biggest assumption in the sim.
- **Pacing is measured, not guessed.** `ColonyBot` plays the real sim headlessly
  and `tests/test_pacing.gd` fails if a session drifts outside 15–50 bot-minutes.
  **Every feature below has to update the bot**, or it silently stops being a
  reference player and the pacing guard rots. That cost is real and is included
  in each estimate.

## 1. Deposit depletion

**Sketch.** A deposit holds a finite quantity, not an infinite rate. Extracting
draws it down; richness falls as the node is worked out; an exhausted extractor
goes idle with a clear reason and can be demolished for its refund. Prospecting
stops being a one-time land-grab and becomes the thing you keep doing.

**Sim.** `ColonyMap` gains a per-cell `reserve` array alongside richness, seeded
at generation from richness × a balance multiplier. `Colony._run_mine()`
decrements it and idles the extractor at zero (`idle_reason = "Deposit
exhausted"`). Save/load carries the reserves. New balance keys: reserve per
richness point, and whether depletion also decays the yield curve.

**View/UI.** The inspector shows remaining reserve; the prospect overlay wants a
"worked out" state distinct from confirmed. Both are additive.

**Risks.** This is the change most likely to break the win condition: xenite must
stay reachable for the whole session, and the hub's *guaranteed* iron deposit
becomes a guarantee with an expiry date. The harness will catch a colony that
starves, but only if the bot learns to re-prospect and relocate extractors — the
bulk of the work here is in the bot, not the sim.

**Size.** Small sim change, medium bot change, small UI. Good first v2 feature —
it deepens the signature mechanic without touching the stockpile.

## 2. Depot / logistics radius

**Sketch.** Replace the global stockpile with depots that hold inventory and
serve buildings within a radius. Placement stops being "anywhere legal" and
becomes a layout problem: ore has to reach a smelter, metal has to reach a
construction site.

**Sim.** The largest change in this document. `Colony.stockpile` splits into
per-depot inventories plus a lookup ("which depot serves this cell"). Everything
that reads the stockpile changes: `_can_afford`/`place` (pay from depots near the
site), `_run_production` (inputs from in-range depots, outputs to them),
`_run_life_support`, `rates()`, `to_dict`/`from_dict`. Save version bumps.

**View/UI.** The resource bar becomes an aggregate; the sidebar needs a per-depot
view; the map wants a coverage overlay in the same family as the prospect
overlay. Placement previews need to show which depot would serve a site.

**Risks.** It invalidates the balance pass — the bot's build order assumes
resources are fungible across the map, so its ordering, its metal reserve logic
and its "build near the hub" placement all stop meaning what they meant. Expect
to re-derive pacing from scratch. It also interacts badly with depletion (§1):
together they mean relocating an entire production cluster, which may be more
logistics than this game wants.

**Size.** Large, and it is a one-way door. If v2 does this, do it first, alone,
and re-run the pacing harness before adding anything else.

## 3. Hostile events (dust storms)

**Sketch.** Periodic weather that degrades the colony for a while: a dust storm
cuts solar output, buries prospecting readings, or halts surface extraction.
Announced in advance so the player can bank power or pause a factory.

**Sim.** A pure `EventScheduler` (RefCounted, injected like `Balance` and
`AlertMonitor`) that `Sim` ticks. It emits typed modifiers the Colony applies
during `_balance_power()` and `_run_production()`. Frequency, duration and
severity are balance keys. `Events.alert` already exists for the warning, and the
alert tiers already have sounds.

**View/UI.** A screen-space particle/tint pass — the `BuildingFX` work already
established how to layer effects without touching the sim. An alert ticker entry
and a countdown in the sidebar.

**Risks.** With no way to switch a building off, a storm that cuts power just
sheds the newest buildings — which the M9 findings show can silently stop the
smelter. Either add an on/off toggle first, or make sure the power-shedding
order is something the player can predict and control. Also: pure downside
mechanics need a counterplay (batteries? storm shutters?) or they read as
arbitrary punishment.

**Size.** Small-to-medium, well isolated, and the highest drama-per-line in this
list. Best candidate to ship first if v2 wants a visible headline.

## 4. Terrain elevation

**Sketch.** Tiles gain a height level. Highlands actually sit above regolith,
buildings need level ground, and deeper deposits sit under higher terrain.

**Sim.** A height array on `ColonyMap`; placement requires a uniform height
across the footprint; prospecting cost scales with depth.

**View.** This is where the cost is. `IsoGrid` owns the one true grid↔screen
conversion and the project's standing advice is to suspect coordinate maths
first when something looks wrong — elevation means a Z offset in that
conversion, in picking (`screen_to_grid` becomes ambiguous: two tiles at
different heights can cover one pixel), in y-sorting, and in every overlay that
assumes flat tiles. The building art would need cliff/ramp edge tiles.

**Risks.** High visual payoff, but it destabilises the one subsystem the project
deliberately kept simple and heavily tested. Picking ambiguity in particular has
no clean answer at this projection.

**Size.** Large, mostly in `render/`. Recommend only alongside an art pass that
wants it.

## 5. Second colonist tier

**Sketch.** Specialists — engineers, say — unlocked by a training building. They
staff advanced buildings that ordinary colonists can't, and they demand more
than oxygen/water/food (medical supplies, or a comfort resource).

**Sim.** `Colony.population` becomes a per-tier table; `_balance_workforce()`
matches building requirements against tiers; `_run_life_support()` takes per-tier
demands from `Balance`; buildings gain a `requires_workers: {tier: n}` field in
`buildings.json`. Growth rules per tier.

**View/UI.** The sidebar's colonist block and the building inspector both need to
show tiers; the "no workers" idle reason needs to say *which* workers.

**Risks.** The workforce is already the quiet gate on the mid-game — the M9 runs
only reach the parts factory once housing has grown the population to seven. A
second tier tightens the same bottleneck, so it needs a matching increase in
housing throughput or the mid-game stalls. The bot needs to understand tiers or
it will stop being able to finish a run.

**Size.** Medium, concentrated in `Colony` + `Balance` + sidebar. Adds
strategic depth without new subsystems.

## Suggested order

1. **Hostile events** — isolated, visible, exercises the existing alert and FX
   layers. Ship an on/off toggle for buildings alongside it.
2. **Deposit depletion** — deepens prospecting, small sim surface, forces the
   bot to become a smarter reference player (worth doing on its own merits).
3. **Second colonist tier** — depth on top of a stable economy.
4. **Depot / logistics radius** — only with intent to re-derive pacing; treat as
   the start of a v2 branch rather than an increment.
5. **Terrain elevation** — pair with an art pass, or leave it.

## Non-goals for v2

Worth writing down so they don't creep in: multiplayer, procedural quests, a
research tree separate from the build-order tech gating, and any change that
makes the sim depend on rendering. The sim/render split and the pure injectable
classes are what make the pacing harness possible; every feature above is
affordable *because* of that split, and none of them is worth spending it.
