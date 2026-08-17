# v2 candidates — designed, not built

Milestone 9 asks for the next round of features to be *written down* rather than
built. This is that list: five candidates from the plan (§ Milestone 9), each
sketched far enough to be costed and argued about, with the parts of the current
architecture they would disturb named explicitly. Two (deposit depletion,
hostile events) have since shipped — their entries below are kept as a record
of what was planned vs. what was built, rather than deleted.

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

## 1. Deposit depletion — shipped

**Shipped, not a candidate anymore.** `ColonyMap` gained a per-cell `_amount`
array (extractable units left), seeded at `set_deposit()` from richness ×
`Balance.deposit_units` (per deposit type — IRON 600, COPPER 260, XENITE 30).
Extraction runs at a flat rate and draws the reserve down; a tile that hits zero
idles its extractor with `idle_reason = "Deposit worked out"` and can be
demolished for the refund. Richness now sizes the reserve rather than the rate.
Xenite generation moved off a hidden noise field onto visible CRYSTAL terrain
(every crystal tile holds it, nowhere else does), so a formation is visible but
its size still has to be prospected — the endgame is a prospect → work-out →
relocate cycle across several formations, not a sit at one deposit. Save/load
carries reserves, with a migration that refills them from richness for
pre-existing saves. `ColonyBot` was reworked to match: it clears worked-out
extractors for the refund, keeps a standing metal reserve for the next mine, and
never re-sites onto a tile it has already emptied — this is exactly the "bulk of
the work is in the bot, not the sim" risk called out below, and it landed.
See `docs/architecture.md`'s "Deposits and prospecting" and "Pacing harness" for
the full mechanics and the resulting rebalance (`victory.xenite` 150 → 260,
mine/extractor rates down).

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

## 3. Hostile events (dust storms) — shipped

**Shipped, not a candidate anymore.** New `Weather` (`sim/weather.gd`), a pure
scheduler owned by `Colony` (not `Sim`, so `ColonyBot` and headless tests see
the same weather a real game does), cycling CLEAR → WARNING → STORM → CLEAR.
The schedule is a hash of a storm counter and the map seed rather than an RNG
object, so it's deterministic per seed and resumes correctly from a save with
nothing extra to serialize. Deliberately narrow scope, matching the risk noted
below: a storm dims `exposed` power production (Solar Panel, to 35% via
`Colony.power_of()`) and halts prospecting (survey stations idle "Dust storm",
holding sweep progress) — mining and life support are untouched, so the damage
always arrives through the power balance, where **the on/off toggle that
shipped first** (`Colony.set_enabled`/`toggle_at`, key `T`) is the actual
counterplay: the `WARNING` phase's lead time is when the player banks
resources and switches off whatever they'd rather lose. View: a screen-space
ochre veil with wind-blown streaks (`render/dust_storm.gd`), a sidebar
countdown, and three `AlertMonitor` announcements. `ColonyBot` needed no
changes — it plans against nominal power and eats the full storm cost, making
it a lower bound as intended (`make playtest`: 5/5 seeds win, avg 32.2 min, up
from 29.1). See `docs/architecture.md`'s "Weather / dust storms".

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

1. ~~**Deposit depletion**~~ — shipped; see § 1 above.
2. ~~**Hostile events**~~ — shipped; see § 3 above.
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
