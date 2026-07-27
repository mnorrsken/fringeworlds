# Architecture

A map of the codebase as it exists today. For the design/milestone plan, see
[`colony-game-plan.md`](../colony-game-plan.md); for what's done vs. pending,
see [`progress.md`](progress.md). This file describes real files and real
APIs — if it and the code disagree, trust the code and fix this file.

## The core rule: sim and render are separate

The simulation is plain data and logic — arrays, dictionaries, `RefCounted`
classes with no scene tree dependency. It has no idea anything is being drawn
on screen, and it never reaches into a node to change what's rendered.
Rendering is a one-way read of sim state: it draws what the sim says is true
and never writes game rules back into it.

Concretely today:

- `sim/map.gd` (`ColonyMap`) holds the 64×64 terrain grid as a
  `PackedByteArray`. It has a `generate(seed)` method and `get_terrain` /
  `set_terrain` accessors. It does not know a `TileMapLayer` exists. As of
  Milestone 4 it also owns the hidden deposit/scan layers — see "Deposits
  and prospecting" below.
- `render/terrain_view.gd` (`TerrainView`) is a `TileMapLayer` subclass with
  one method that matters, `render_map(map: ColonyMap)`, which walks the map
  and paints matching tiles. It reads `ColonyMap`; `ColonyMap` never touches
  it.
- `sim/colony.gd` (`Colony`) is the same pattern applied to buildings: a
  plain `RefCounted` holding the map, the stockpile, and placed buildings
  with an occupancy index. It takes its building definitions as a
  constructor argument (`_init(map, defs, stockpile)`) rather than reading
  `Defs` itself, so it has zero autoload dependency and can be constructed
  and tested in complete isolation — see `tests/test_placement.gd`, which
  builds a `Colony` with a hand-rolled two-entry defs dictionary and never
  touches `Defs`, `Sim`, or a scene.
- `render/buildings_view.gd` (`BuildingsView`) mirrors `TerrainView`'s role
  for buildings, except it doesn't even read `Colony` directly in steady
  state — it spawns/frees `BuildingSprite`s purely by listening to
  `Events.building_placed` / `building_removed` (see below).

This split is why the sim can be tested headlessly (see `tests/`) without
booting any rendering — `test_map.gd` instantiates `ColonyMap` directly and
never touches a scene, and `test_placement.gd` does the same for `Colony`.

## The autoloads

Registered in `project.godot` under `[autoload]`, in load order. Three are
the sim/signal-bus trio described in the plan; a fourth, `Audio` (Milestone
8), is view-layer-only — it listens on `Events` and never touches sim
state, and is a singleton solely so the ambient music survives the menu↔
game scene switch (see "Audio" below). Don't add a fifth without a similarly
good reason.

1. **`Events`** (`sim/events.gd`) — a global signal bus. Defines
   `ticked(tick: int)`, `stockpile_changed(stockpile: Dictionary)`,
   `building_placed(instance: Dictionary)`,
   `building_removed(instance: Dictionary)`, (Milestone 4)
   `scan_changed(cells: Array)`, (Milestone 5) `game_over(won: bool)`, and
   (Milestone 6) `alert(text: String, level: int)`. The sim emits; UI/render
   layers connect. UI is meant to never poke `Sim` internals directly — it
   calls `Sim` methods and listens on `Events` signals instead. The
   `building_placed`/`building_removed` payload is the same instance
   dictionary `Colony.place()`/`demolish_at()` returns: `{id, type, origin,
   cells}`. `scan_changed`'s payload is the list of grid cells whose
   prospecting scan state changed on the tick just processed;
   `ProspectOverlay` is the only current listener, using it to repaint
   incrementally instead of rebuilding the whole overlay every tick.
   `game_over` fires exactly once when the colony reaches a terminal state;
   `main.gd` is the only listener, and shows the win/loss overlay from it.
   `alert`'s `level` is an `AlertMonitor.Level` value (`INFO`/`WARN`/`CRIT`,
   0/1/2); `Sim` emits one per entry `AlertMonitor.check()` returns each
   tick (see "Alerts" below), and `ui/alert_ticker.gd` is the only
   listener.
2. **`Defs`** (`sim/defs.gd`) — loads read-only content definitions from
   `data/*.json` at startup into three dictionaries: `resources` (id →
   definition, unchanged since Milestone 0), `buildings` (id →
   definition), and (Milestone 8) `audio` (cue id → sound definition,
   loaded straight from `data/audio.json` with no preprocessing — see
   "Audio" below). `_load_buildings` post-processes each building entry after
   the generic `_load_json` pass, adding two derived fields so downstream
   code never re-parses raw JSON: `allowed_terrain_ids` (an
   `Array[int]`, the entry's `allowed_terrain` name strings resolved
   through `ColonyMap.Terrain`) and `color_value` (a `Color`, parsed from
   the entry's `color` hex string via `Color.html`). As of Milestone 4, a
   building declaring `requires_deposit` (a list of deposit names, for
   extractors) also gets `requires_deposit_ids` resolved through
   `ColonyMap.Deposit`, the same pattern as `allowed_terrain_ids`. Engine
   code is meant to read `Defs.resources` / `Defs.buildings` rather than
   hard-code content; adding a building means editing
   `data/buildings.json`, not this script. As of the Colony Hub rework, a
   building declaring `guarantees_deposit` (a single deposit name, for the
   Hub) similarly gets `guarantees_deposit_id` resolved through
   `ColonyMap.Deposit` — see "Colony Hub and guaranteed deposits" below.
3. **`Sim`** (`sim/sim.gd`) — game state and the fixed tick loop, plus the
   live `Colony` (since Milestone 2). `new_game(seed, size)` calls
   `_apply_balance(map)` (Milestone 9 — pushes `Defs.balance` into the
   pieces that don't take it as a constructor arg, currently just
   `map.reading_jitter`) then constructs `colony := Colony.new(map,
   Defs.buildings, Defs.balance.starting_stockpile, Defs.balance)`, and
   resets the tick counter. The starting stockpile is currently `{metal:
   120, oxygen: 60, water: 60, food: 60}` (metal peaked at 200 in the pre-M6
   metal-cliff fix, then dropped to 120 in the Colony Hub rework once the
   Hub started sustaining the base 4 colonists for free — see "Colony Hub
   and guaranteed deposits" below and the balance notes in
   `docs/progress.md`) — the buffer only needs to cover metal for the
   hub+mine+smelter bootstrap and life support for the time until the Hub is
   placed, since the Hub then covers the base 4 at no stockpile cost — and
   `new_game()` also resets `_ended`, the tick accumulator, and `speed` back
   to `1.0`, so restarting after a game-over isn't left
   paused or fast-forwarded. `colony` is `null` until `new_game()` is
   called. `Sim` exposes thin wrapper methods over `Colony`'s placement
   API — `can_place`, `place_building`, `demolish_at`, `building_at` —
   that delegate to `colony` and then emit the matching `Events` signal
   (`building_placed`/`building_removed`/`stockpile_changed`) on success,
   so `Colony` itself stays free of any signal-bus dependency.
   `building_report(id)` (Milestone 6) is the same pattern without a
   signal — a plain pass-through to `colony.building_report(id)`, since the
   inspector is pulled every frame by `main.gd` rather than pushed on an
   event. `Sim` also owns an `AlertMonitor` (`_alerts`, Milestone 6,
   constructed `AlertMonitor.new(Defs.balance)` since Milestone 9), reset
   alongside `colony` in `new_game()`. The tick loop runs at
   `ticks_per_second` (a var, default `4.0`, set from `Defs.balance` by
   `_apply_balance` — see "Tuning" below), accumulator-driven inside
   `_process` so ticks stay decoupled from frame rate; `_process` now also checks
   `colony.status` both before and inside the accumulator loop (Milestone
   5) so once the colony reaches a terminal state, no further ticks run in
   that frame or any later one. `_advance_tick()` calls `colony.tick()`
   (see below), then emits `Events.stockpile_changed` and `Events.ticked`,
   and (Milestone 6) calls `_alerts.check(colony)` and emits
   `Events.alert(entry.text, entry.level)` for each returned entry.
   `_end_game()` emits `Events.game_over(won)` the
   first time `colony.status != PLAYING` is observed, guarded by an
   `_ended` flag so it never fires twice for the same game. Speed control:
   `speed: float` is a multiplier (`0.0` = paused, `1.0` = normal, `3.0` =
   fast); `set_speed(mult)` sets it directly and remembers non-zero values
   in `_last_run_speed`; `toggle_pause()` flips between `0.0` and
   `_last_run_speed` (so unpausing restores whatever speed — 1× or 3× —
   was running before the pause, not always 1×); `is_paused()` reads
   `speed <= 0.0`; `set_paused(bool)` remains as a thin wrapper over
   `set_speed` for callers that prefer a boolean.

## Grid math lives in one place: `IsoGrid`

`sim/iso_grid.gd` (`IsoGrid`) is a static-method-only class (`TILE_W = 64`,
`TILE_H = 32`) that owns all grid↔screen conversion:

- `IsoGrid.grid_to_screen(cell: Vector2i) -> Vector2` — a cell's center in
  screen/world space. Matches Godot's own
  `TileMapLayer.map_to_local(cell)` exactly (dimetric 2:1, diamond-down
  layout) — pinned by `tests/test_iso_grid.gd`, which builds a real
  isometric `TileMapLayer` and asserts equality cell-by-cell.
- `IsoGrid.screen_to_grid(pos: Vector2) -> Vector2i` — inverse: which cell's
  diamond contains a screen/world point. Round-trip-tested against
  `grid_to_screen` for a range of cells.

Everything that needs to place or pick a tile is expected to go through
`IsoGrid` rather than re-deriving the formula. Today that's `TerrainView`
(implicitly, via `TileMapLayer`'s own matching math), `main.gd` (converts
mouse position to a cell every frame to drive `TileCursor` and the ghost),
and `BuildingSprite`, which uses `IsoGrid.grid_to_screen` to place itself at
a building's front tile and to compute its footprint diamond's corners in
`_draw()`.

## Data-driven content

Per the plan's architecture principles, building/resource/recipe content is
meant to live in JSON under `data/`, not in engine code. `data/audio.json`
(the sound cue manifest, loaded into `Defs.audio`) follows the same pattern
— see "Audio" below — but is described there rather than here since it's
consumed by the view layer, not `Colony`. Building/resource content:

- `data/resources.json` — an array of 9 objects (`id`, `name`, `category`,
  `unit`), loaded into `Defs.resources`.
- `data/buildings.json` — an array of 12 building objects (up from 10 with
  the Colony Hub rework, up from 6 as of Milestone 5): `hub` (2×2, the tech
  root, `requires_built` empty), `solar_panel` and `ice_harvester` (1×1),
  `habitat` and `survey_station` (2×2), `mine` and `crystal_extractor`
  (1×1), plus four production-chain buildings — `electrolysis_plant` (1×1,
  water→oxygen), `hydroponics_farm` (2×2, water→food), `smelter` (2×2,
  iron_ore→metal), `parts_factory` (2×2, metal+copper_ore→parts), all four
  built entirely on the existing `recipe` mechanism — no engine changes
  were needed to add a production chain, only JSON. Fields: `id`, `name`,
  `size`, `cost`, `allowed_terrain`, `color`, `desc`, `power` (int;
  positive = generator, negative = consumer, every building declares one),
  optionally `recipe` (`{inputs: {...}, outputs: {...}, ticks: int}`),
  `scan` (survey buildings), `mine`/`requires_deposit` (extractors — see
  "Deposits and prospecting" below). Milestone 5 added two more fields:
  `workers` (int; every building declares one) and `capacity` (int,
  housing added by the building — `habitat` at `6`, and (Colony Hub
  rework) `hub` at `4`). The Colony Hub rework added `life_support` (int,
  colonists sustained for free while the building is active — only `hub`,
  at `4`) and `guarantees_deposit` (a deposit name, resolved by `Defs` to
  `guarantees_deposit_id` — only `hub`, `"IRON"`; see "Colony Hub and
  guaranteed deposits" below).
  `crystal_extractor`'s `cost` also requires `parts: 8`, so it needs the
  full chain (mine → smelter → parts factory) to reach, not just raw
  metal. As of the pre-M6 balance pass, `workers` is rebalanced so the
  entire starter loop (Solar Panel, Habitat, Ice Harvester, Electrolysis
  Plant, Hydroponics Farm, Survey Station, Mine) is `workers: 0` — only
  the processing/advanced tier (Smelter 2, Parts Factory 3, Crystal
  Extractor 2) needs colonists. The same pass added `requires_built`
  (`Array[String]` of building ids — see "Tech unlocks" below) to most
  buildings; the Colony Hub rework re-rooted the tree at `hub` — it is now
  the only building with no `requires_built`, and Solar Panel, Habitat,
  Ice Harvester, Survey Station, and Mine all gained `requires_built:
  ["hub"]` (Mine's prerequisite changed from Survey Station to Hub, since
  the Hub itself prospects and guarantees iron). Loaded into
  `Defs.buildings` and augmented with
  `allowed_terrain_ids`/`color_value`/`requires_deposit_ids`/
  `guarantees_deposit_id` as described above
  (`workers`/`capacity`/`life_support`/`requires_built` need no
  preprocessing — `Colony` reads them as plain ints/arrays). The
  Milestone 8 art pass added `smoke` (bool, purely cosmetic — read only
  by `BuildingsView`, not `Colony`; procedural buildings only — cleared
  from any building that later gained real art) for the exhaust-puff
  animation described under "Rendering and camera" below. The Milestone 8
  asset-integration step added `sprite` (a `res://assets/*.png` path,
  optional — read only by `BuildingsView`; unset means the procedural
  block is used): `hub`, `mine`, `smelter`, `electrolysis_plant`, and
  `hydroponics_farm` have art so far, the other six buildings don't yet.
  `smelter`'s `size` also shrank 2→1 to match its 1×1 art
  (cost/workers/power/recipe unchanged). A second wave wired the
  remaining six (`solar_panel`, `survey_station`, `crystal_extractor`,
  `habitat`, `parts_factory`, `ice_harvester`), so **all 11 buildings now
  have `sprite`** — `survey_station`'s `size` shrank 2→1 the same way as
  `smelter`'s did, so `hub`, `habitat`, and `hydroponics_farm` are now the
  only 2×2 buildings left. The last `smoke: true` flag (`parts_factory`)
  was removed once its art shipped its own smokestacks — no building
  declares `smoke` anymore. The building-FX pass added an optional `fx`
  array (see "`BuildingFX` — decorative overlays" below): each entry is
  `{type, at, ...}` where `type` is one of `BuildingFX.TYPES` and `at` is a
  `[x, y]` pixel offset from the sprite's anchor; `Defs` only preprocesses
  an entry's `color` hex into `color_value` (mirroring the top-level
  `color`/`color_value` pattern) and does not validate `type` — the
  renderer owns that. All 11 buildings now declare `fx`. Adding a
  building, or a recipe/scan/mine/requires_built/fx block to an existing
  one, is a matter of editing JSON — no script changes needed, since
  `Colony.tick()`, `BuildingsView`, and the sidebar's build menu all read
  generically off the def dictionary. The finite-deposits/required-hub
  rework (see "Deposits and prospecting" and "Colony Hub and guaranteed
  deposits" below) added four more fields, all still generic — no new
  preprocessing in `Defs`: `unique` (bool, one-per-colony — only `hub`),
  `colony_controller` (bool, the colony shuts down without one active —
  only `hub`), `requires_coverage` (bool, must be placed inside an
  existing scanning building's range — only `survey_station`), and
  `scan.confirm_ticks` (int, only `survey_station`'s `scan` block — see
  below). `hub`'s `cost` is now `{}` (it's free) and `mine`/
  `crystal_extractor`'s `mine.base_per_tick` dropped to `0.30`/`0.022`
  (from `0.35`/`0.15`) as part of the same rebalance;
  `crystal_extractor`'s `allowed_terrain` narrowed to `["CRYSTAL"]` (from
  `["REGOLITH", "HIGHLANDS"]`), since xenite now only generates there. The
  storage/warehouse feature added `storage` (`Dictionary[String, int]`, a
  resource→capacity map — see "Storage limits" below): `hub` gained one
  (400 water/oxygen/food, 75 metal, 50 of each ore and parts, no xenite),
  and a new twelfth building, `warehouse` (2×2, 45 metal + 6 parts, −2
  power, `requires_built: ["parts_factory"]`), declares a much larger one
  (100 metal/ore, 60 parts, 90 xenite, 150 of each life-support resource) —
  the only building that can hold xenite at all. `warehouse` currently
  reuses `hub`'s neighbour `assets/partsfactory.png` as placeholder
  `sprite` (it renders identically to the Parts Factory in-game) pending
  its own art. `starting_stockpile.metal` in `data/balance.json` dropped
  120 → 50 to match the smaller hub yard (a colony can't land with more
  metal than its own storage can hold).

There is no separate `data/recipes.json` — recipes live inline on the
building that runs them, one recipe per building, which is enough for the
single-tier production so far. A dedicated recipes file may still arrive if
buildings need to switch between multiple recipes later.

## Tuning (`Balance`, Milestone 9)

`data/buildings.json` is content (what exists); `data/balance.json` is
pacing (how hard it presses) — starting population/capacity,
starve/growth tick counts, the xenite victory target, the hub's
guaranteed-deposit richness, the demolition refund fraction, life-support
draw per colonist, the starting stockpile, sim tick rate, autosave
interval, the low-stock alert floor, prospecting reading jitter, and (the
finite-deposits rework) `deposit_units` — extractable units per deposit
type at full richness (`IRON: 600, COPPER: 260, XENITE: 30`), read by
`ColonyMap.set_deposit()` to size a tile's reserve. Tuning the game means
editing that file, not engine code.

`sim/balance.gd` (`Balance`, `class_name`, `RefCounted`) holds every one of
those numbers as a field with the shipped value as its default, plus
`static func from_dict(d)` which applies a parsed `balance.json` over those
defaults — a section/key absent from the JSON keeps its default, so a
partial or missing file degrades to sane numbers rather than zeroes.
`Defs._load_balance()` loads `data/balance.json` (a single JSON object, not
a list of id'd entries like the other data files) into `Defs.balance` at
startup, falling back to `Balance.new()` if the file is missing or
malformed.

`Balance` is injected the same way `defs` is: `Colony._init()` takes an
optional fourth `Balance` argument (`null` defaults to `Balance.new()`,
i.e. the shipped numbers), exposed as `colony.balance`, and
`Colony.from_dict()` takes one too. `ColonyMap.reading_jitter` and
`AlertMonitor.low_stock` are plain fields defaulting to `Balance.new()`'s
values, set from the real `Balance` by `Sim._apply_balance()`/
`AlertMonitor.new(balance)`. `Sim.ticks_per_second`/`Sim.autosave_seconds`
are vars (no longer consts) read from `Defs.balance` the same way. Because
every default matches the shipped JSON, a bare `Colony.new(map, defs,
stockpile)` — the pattern every existing headless test already uses — still
behaves exactly like the real game; nothing needed to change to keep the
old tests passing.

`tests/test_tuning.gd` covers the layer itself: the shipped file parses; an
empty override reproduces every default; a partial override touches only
the key it names; JSON numbers keep their int/float type (stock amounts are
whole, life-support rates aren't); a tuned `Balance` actually reaches a
`Colony` (custom population and victory threshold take effect); and sanity
guards on the shipped values (`growth_ticks > starve_ticks`, so a failing
colony can't grow out of trouble; every life-support resource is stocked at
game start).

**Demolition refund (balance pass).** `Colony.demolish_at()` credits
`floor(cost[res] * balance.demolish_refund)` per resource back to the
stockpile (`demolish_refund` default `0.5`, clamped `0.0`–`1.0` in
`Balance.from_dict`). This is the colony's only way to turn a building back
into resources — without it, over-committing to a building with no way to
power it down is a dead end (see the parts-factory finding below, which is
what surfaced the gap). Flooring the refund means a build/demolish cycle on
the same building is always a net resource loss, so it can't be farmed;
`ui/sidebar.gd`'s Demolish button tooltip states the live percentage from
`Defs.balance`. Covered by `tests/test_tuning.gd` (refund amount, can't be
farmed, `0.0` disables it, out-of-range values clamp).

## Pacing harness (`ColonyBot`, Milestone 9)

Tuning numbers only matter if someone plays the game long enough to feel
them, and a human playtest isn't repeatable or CI-guardable. `tools/colony_bot.gd`
(`class_name ColonyBot`) is a scripted reference player driving the real
`Colony`/`ColonyMap` classes directly — no autoloads, no rendering, fully
deterministic per seed — so "is the game completable, and how long does it
take" is a headless, automatable question instead of a manual one.

The bot follows the intended build order (widen the metal loop → power →
life support → housing → prospect outward → parts chain → crystal
extractor) and buys the instant it can afford to; that makes its times a
**floor** on session length, not a prediction of how a person actually
plays. It acts once per game-second (`ACT_EVERY` ticks) and records a
timeline of when each tracked resource (`ColonyBot.TRACKED`) first appears
plus the full build order with timestamps. `ColonyBot.load_defs()`
preprocesses `data/buildings.json` the same way `Defs._load_buildings`
does, so a headless script with no autoloads can still construct a real
`Colony`.

**Reworked for finite deposits.** With deposits finite (see "Deposits and
prospecting" below), the bot had to stop treating a mine or extractor as a
permanent fixture: it now demolishes any extractor idled with "Deposit
worked out" for the refund (`_clear_worked_out`), keeps a standing metal
reserve for the *next* mine before spending on anything else — deposits
tend to run out in clusters, so the whole extraction fleet can collapse at
once (`_metal_reserve`, `MINE_RESERVE`) — aims survey stations at the
nearest unconfirmed *visible* crystal formation and otherwise pushes the
coverage frontier outward, since stations must now stand inside existing
coverage (`_nearest_unconfirmed_crystal`, `_farthest_placeable`), never
re-sites an extractor onto a tile it has already emptied (`_find_deposit`
drops worked-out cells from its index), and tears down the parts factory
once `PARTS_BANKED` (40) parts are banked, since a permanently-running
factory's metal drain is the difference between finishing and slowly
starving once ore is finite.

- **`tools/playtest.gd`** (`make playtest`) runs several seeds, prints each
  one's outcome/ticks/minutes/timeline/build order plus a summary, and
  exits non-zero if any seed fails to win — a manual/CI pacing report.
- **`tests/test_pacing.gd`** is the automated acceptance check: every seed
  wins, no seed starves the colony, the full ore→metal→parts→xenite chain
  is exercised (not just the win condition), and a session isn't trivially
  short. This is the kind of regression no single-building unit test would
  ever catch — a balance change can leave every building individually
  correct while making the colony as a whole unwinnable.

`tests/test_pacing.gd::test_sessions_land_in_the_intended_window` pins the
result to a 15–50 minute band so a future tuning change that drifts outside
it fails loudly, rather than quietly turning the game into a five-minute
clicker or an hour of waiting.

Measured result after the Milestone 9 balance pass: 5/5 seeds win,
20.3–41.4 minutes of game time, average 29.9 (previously 11.1–19.4 minutes,
average 15.8, against the plan's 45–90 minute target — since the bot buys
the instant it can afford to, its time is a floor, so ~30 bot-minutes was
chosen to put a human session in the plan's window).

**After the finite-deposits rework and its rebalance** (below): 5/5 seeds
win, 24.2–24.6 minutes, average 24.4 — the bot rework above (working tiles
out, relocating extractors, banking then shutting down the parts factory)
kept the session inside `test_pacing.gd`'s 15–50 minute band without
needing to widen it, so the endgame is now a prospect → work-out →
relocate cycle across several crystal formations rather than one sit at a
single deposit, at roughly the same real-world length as before.

Building the bot surfaced real balance findings, not just infrastructure:

- **The metal loop must widen *before* the parts factory turns on.** A
  running Parts Factory consumes 2 metal per 4 ticks — roughly the entire
  output of two smelters — so a colony that switches one on too early pins
  metal at ~0 forever and can never afford the Crystal Extractor's 20
  metal. Buildings can't be switched off, and (before the balance pass)
  demolition refunded nothing, so there was no way back short of a
  soft-lock; this is what motivated the demolition refund above. Three of
  five seeds failed this way before the bot was taught to expand first (4
  iron mines + 3 smelters, `IRON_MINES_BEFORE_FACTORY`/
  `SMELTERS_BEFORE_FACTORY`) before building the factory.
- **One Ice Harvester doesn't cover both an Electrolysis Plant and a
  Hydroponics Farm** — 0.25 water/tick produced vs. 0.67 consumed by the
  two together — so the water chain has to widen as the colony grows or it
  starves.
- **Xenite is common** and often sits within a few tiles of the hub, so a
  careless base can literally pave over its own win condition before ever
  surveying for it.
- **Don't build before you've prospected.** The Hub's guaranteed iron (see
  "Colony Hub and guaranteed deposits" below) is injected into the tiles
  right beside the Hub — exactly where an eager colony builds first — and an
  unconfirmed deposit is invisible, so it's possible to bury the colony's
  only guaranteed iron under a building before the first survey sweep
  confirms it, with no way to recover it. The bot now waits for the Hub's
  first survey sweep (a confirmed iron tile) before building anything else,
  which is also good practice for a human player: check the prospect
  overlay (`P`) before placing near the Hub.
- **A colony can go bankrupt with confirmed ore sitting unused**, because
  opening a deposit costs metal it no longer has once the metal loop is
  running and reserves have run low — demolition refunds are the way out
  (`_metal_reserve`'s mine/survey-station holdback exists because of this).
- **The parts factory's metal drain is much sharper now that ore is
  finite.** A permanently-running factory can outpace what a finite set of
  mines can ever replace, not just what an early, still-growing metal loop
  can — this is why the bot now tears the factory down once enough parts
  are banked instead of only delaying when it turns on.

**Balance pass (Milestone 9).** Tuned from `data/balance.json`/
`data/buildings.json` to move the bot's win time from ~16 to ~30 minutes:
`victory.xenite` 50 → 150, `colony.growth_ticks` 80 → 110, mine
`base_per_tick` 0.5 → 0.35, crystal extractor `base_per_tick` 0.25 → 0.15,
and `ticks_per_ring` 2 → 3 for both the hub's and the survey station's
`scan` blocks (prospecting is the dominant term in the ramp, so slowing it
lifted the fast seeds without over-inflating the slow ones).

This completed Milestone 9, and with it all nine milestones of the plan.

**Balance pass (finite deposits).** Deposits becoming finite (below)
needed its own retune, since a target sized for an infinite tap doesn't
carry over to one that runs dry: `victory.xenite` 150 → 260, crystal
extractor `base_per_tick` 0.15 → 0.022, mine `base_per_tick` 0.35 → 0.30,
and `growth_ticks`'s default in `sim/balance.gd` synced to the shipped
`110` (it had drifted to `80`). A typical iron tile now carries a colony
for a long while (deposit base 600 units), but a crystal formation holds
only ~18 units against a 260-unit beacon target, so finishing the game
means working through many formations, not sitting at one.

**After the storage/warehouse feature** (see "Storage limits" above): the
bot now builds Warehouses (`_needs_storage()`), holds only a 1-mine metal
reserve instead of 2 (`MINE_RESERVE` — storage caps mean metal can't be
hoarded anyway, so a deeper reserve just makes expensive buildings
permanently unaffordable), and rebuilds the parts factory only once its
bank drops under `PARTS_LOW` (12) rather than the instant it's demolished,
which stopped a bank→demolish→rebuild oscillation the tighter economy
otherwise fell into. `_metal_reserve()` also now exempts zero-cost
buildings (i.e. the hub) from ever being gated by a reserve — with the hub
free, an unconditional reserve could block the very first building and
starve the colony before it began. 5/5 seeds win, 25.4–26.4 minutes,
average 25.9 — close to the finite-deposits figure above, since the tuning
goal was a tighter opening and mandatory warehouses, not a longer session.

The findings above — the metal loop, the water chain, the stockpile as the
single biggest sim assumption — shaped the v2 candidates written up in
[`docs/v2-candidates.md`](v2-candidates.md); deposit depletion (candidate
#1 there) has since shipped and is described under "Deposits and
prospecting" below.

## The tick economy (`Colony.tick()`)

As of Milestone 3, `Colony` (in `sim/colony.gd`) does more than hold
placement state — it also owns the fixed-tick production economy, called
once per simulation tick from `Sim._advance_tick()`. As of Milestone 5,
`tick()` runs six phases in this order:

```gdscript
func tick() -> void:
    scan_changes = []
    _balance_power()
    _balance_workforce()
    _run_prospecting()
    _run_production()
    _run_life_support()  # after production, so a just-in-time supply counts
    _check_status()
```

Production deliberately runs *before* life support: a resource a building
produces this tick (e.g. an Electrolysis Plant finishing an oxygen batch)
is available to be consumed by life support in that same tick, so
colonists aren't falsely flagged as short on something the colony in fact
supplied in time.

**Power balance (`_balance_power`)**: iterates buildings **oldest-first**
(`_ids_oldest_first()`, i.e. sorted by instance id — ids are assigned
sequentially by `place()`, so this is placement order). Every building with
`power > 0` is a generator: it always runs (`active = true`) and adds to
`power_produced`. Buildings with `power < 0` are consumers, collected in
placement order and then switched on **while supply lasts**: since the
loop processes them oldest-first and stops granting power once the running
total would exceed `power_produced`, the practical effect is that the
**newest** consumers are the ones left `active = false` on a deficit —
older buildings keep priority. `power_produced`/`power_consumed` are
recomputed from scratch every tick and exposed as `Colony` members for the
HUD.

**Workforce balance (`_balance_workforce`, Milestone 5)**: the same
oldest-first/newest-shed pattern as power, applied to labor. Iterates
buildings oldest-first; any building that's still `active` (i.e. it
survived the power pass) and declares `workers > 0` is staffed from a
running `available := population` pool if there's enough left, otherwise
it's set `active = false` — so understaffing, like a power deficit, shuts
the newest offending buildings down first. `workers_used()` (a public
method, not part of the tick) sums `workers` across currently-active
buildings, for the HUD.

**Production (`_run_production`)**: for every *active* building with a
`recipe`, increments a per-instance `progress` counter (a field on the
building instance dict, alongside `active`, both initialized in `place()`).
Once `progress >= recipe.ticks`, it first checks whether `recipe.outputs`
would fit in the stockpile (`_fits()` — see "Storage limits" below): if
not, it **stalls for room**, holding `progress` at the threshold with
`idle_reason = "Storage full"` without touching the inputs at all, so a
full store never quietly eats the ore that would have become metal.
Otherwise it checks whether `recipe.inputs` are affordable: if so, it
spends the inputs, adds the outputs, and resets `progress` to `0`; if not,
it **stalls for inputs** the same way. Inactive (unpowered) buildings don't
advance `progress` at all, so a power outage doesn't cause a burst of
production the instant power returns.

Since Milestone 4, `_run_production` special-cases buildings with a `mine`
def block (extractors — see below) before the recipe branch, calling
`_run_mine(inst, def)` and skipping the recipe logic entirely for them.

**`rates()`** returns the net stockpile change **per tick** (not per
second) summed across only currently-active buildings — `{resource_id:
float}`, positive for net production, negative for net consumption. It
covers recipe-based production, (Milestone 4) extractor output
(`_mine_per_tick`, the same formula `_run_mine` uses), and (Milestone 5)
life-support consumption (`population * balance.life_support[res]`,
subtracted for oxygen/water/food whenever `population > 0`) — so the HUD's
per-resource rate is the true net figure, not just what buildings are doing.
Callers that want a per-second figure for display multiply by
`Sim.ticks_per_second` themselves (see `main.gd` below); `Colony` has no
concept of real time, only ticks.

## Storage limits (`Colony`, storage/warehouse feature)

The colony's stockpile is capped, not infinite: `Colony.storage_for(res)`
sums the `storage` block (see "Data-driven content" above) of every
*standing* building — active or not, since storage is physical, an
unpowered Warehouse still holds its contents. `space_for(res)` is
`storage_for(res) - stockpile.get(res, 0)`, clamped at `0`; `_fits(flow)`
checks a whole `{res: amount}` dict against `space_for()` at once and is
what `_run_production()`/`_run_mine()` call before spending anything (see
above and below). `_gain()` clamps every gain to `storage_for()`, as a
backstop for demolition refunds and partial draws rather than the primary
mechanism — production and extraction are meant to stall before they ever
overflow.

`_init()` sets a private `_storage_limited` flag if *any* def in the
passed-in `defs` dictionary declares a non-empty `storage` — the same
opt-in pattern as `_needs_controller` (see "The hub is free, unique, and
required" below). Content that declares no storage at all (every
hand-rolled test-defs dictionary except `tests/test_storage.gd`'s) gets
`UNLIMITED` (`1 << 30`) back from `storage_for()` instead of `0`, so the
rule can't retroactively cap unit-test colonies that never opted into it.

**Mines idle the same way as production.** `_run_mine()` checks
`space_for(res) <= 0` before accumulating any output; if the store is
full it sets `idle_reason = "Storage full"` and returns without touching
`map` at all, leaving the ore in the ground rather than discarding it.

**Demolition spills the excess.** `demolish_at()` refunds part of the
build cost as usual, then reclamps every stockpiled resource to the new
(now smaller) `storage_for()` — tearing down a Warehouse that's holding
more than what's left can stand loses whatever no longer fits.

**The shipped numbers are deliberately tight.** The Hub's yard (400
water/oxygen/food, 75 metal, 50 of each ore and parts, **no xenite**) is
sized so the colony can bootstrap but not coast, and can't hold any of the
beacon's win condition at all — the Warehouse (100 metal/ore, 60 parts, 90
xenite, 150 of each life-support resource) is the only place xenite can
go, and at 90 per warehouse against a 260-unit `victory.xenite` target,
three are mandatory (two hold only 180). `starting_stockpile.metal` (50)
was dropped from 120 so a new colony lands within its own hub yard rather
than starting over capacity. `tests/test_storage.gd` guards all of this:
capacity summing, the hub holding no xenite, clamped gains, stalling
without consuming inputs, resuming when room appears, extractors idling
with ore left in the ground, spillage on demolition, the
unlimited-when-unmodelled rule, and three guards on the shipped numbers —
three warehouses required for the beacon, the starting stockpile fits the
hub yard, and the hub yard can afford the single costliest building (a
regression guard: `tests/test_balance.gd`'s bootstrap-headroom check was
relaxed from a 20-metal cushion to 5, since the opening is now meant to be
tight).

**`ColonyBot`** (see "Pacing harness" below) learned to build Warehouses:
when the colony's xenite capacity is short of the beacon target, or when a
line is genuinely stalled ("Storage full") — capped at 4, since reacting
to every full store instead just paves the map with them.

## Colonists, life support, and win/lose (`Colony`, Milestone 5)

`Colony` tracks `population: int` (starts at `balance.starting_population`,
default `4`) and `status: int` (`enum Status { PLAYING, WON, LOST }`). The
tuning numbers below moved off `Colony` and onto the injected `Balance` in
Milestone 9 (see "Tuning" above) — the values are unchanged, only where they
live: `balance.base_capacity` (`0` — the Colony Hub rework dropped this from
`4`; housing no longer comes from an implicit colony ship, only from placed
buildings' `capacity` fields, of which the Hub is now one),
`balance.starve_ticks` (`24`, ~6s of real time at 1× speed — raised from
`16` in the pre-M6 balance pass, for a more forgiving grace period),
`balance.growth_ticks` (`110`, ~27.5s — raised from `80` in the Milestone 9
balance pass), `balance.victory_xenite` (`260` — `50` at launch, `150`
after the Milestone 9 balance pass, `260` after the finite-deposits
rebalance, since a crystal formation now only holds a fraction of the
target), and
`balance.life_support` (`{oxygen: 0.02, water: 0.02, food: 0.015}`,
consumption per colonist per tick — also reduced from `{0.03, 0.03, 0.02}`
in the pre-M6 pass).

- **`capacity()`** — `balance.base_capacity` plus every placed building's
  `capacity` field (`habitat` at `6`, and — Colony Hub rework — `hub` at
  `4`, so a fresh colony reaches its starting population of 4 as soon as
  the Hub is placed). Not cached; recomputed on call by summing over
  `buildings`.
- **`life_support_covered()`** (Colony Hub rework) — sums the `life_support`
  field across currently-*active* buildings (only `hub`, at `4`). This is
  how many colonists have their O2/water/food needs met for free, without
  touching the stockpile, as long as a building providing that coverage
  stays powered.
- **`_run_life_support()`** — computes `effective := max(0, population -
  life_support_covered())` (Colony Hub rework) and, for each of
  oxygen/water/food, adds `effective * balance.life_support[res]` (not
  `population * balance.life_support[res]` — the covered colonists draw
  nothing) to a per-resource fractional accumulator (`_life_accum`,
  mirroring the pattern `_run_mine` uses for fractional ore output), then
  withdraws whatever whole units it can afford from the stockpile (never
  going negative — it takes `min(whole, have)`). If it couldn't take the
  full amount, the tick counts as unmet; an empty stockpile for a resource
  only counts as an unmet shortage when `effective > 0` (uncovered
  colonists actually need it) — so with `effective == 0` (e.g. the Hub
  covering all 4 starting colonists) an empty reserve is not a crisis. A
  fully-met tick resets `_starve_ticks` to `0` and, if `population <
  capacity()`, increments `_growth_ticks` — reaching `balance.growth_ticks`
  resets it and adds one colonist. An unmet tick resets `_growth_ticks` to
  `0` and increments `_starve_ticks` — reaching `balance.starve_ticks`
  resets it and removes one colonist. Both are streak counters, not
  cumulative totals: a single good/bad tick doesn't immediately grow or
  kill anyone, but breaks the *other* streak.
- **`_check_status()`** — a no-op once `status` has already left
  `PLAYING`. Otherwise: `population <= 0` → `Status.LOST`; stockpiled
  `xenite >= balance.victory_xenite` → `Status.WON`. Checked last in
  `tick()`, after production and life support have both run for that tick.
- **`rates()`** (Colony Hub rework) — the same `effective` figure gates
  the life-support subtraction in `rates()` too, so the HUD's per-second
  rate for oxygen/water/food shows zero drain while the Hub covers every
  colonist, and only shows drain once growth pushes population past what's
  covered.

## Tech unlocks (`Colony`, pre-M6 balance pass)

Buildings can declare `requires_built: [building_id, ...]` in
`data/buildings.json` (see "Data-driven content" above); a building with
any unmet prerequisite can't be placed. This is deliberately pedagogical —
it walks a new player through the intended build order. As of the Colony
Hub rework, `hub` is the tree's root (the only building with no
`requires_built`, and the only one unlocked at game start): hub → solar
panel / habitat / ice harvester / survey station / mine → smelter → parts
→ crystal, with ice harvester → electrolysis/hydroponics on the side.

- **`built_types: Dictionary`** — a set (keys used as a `Dictionary` with
  unused `true` values) of every building type id ever placed. `place()`
  writes `built_types[type_id] = true` unconditionally on a successful
  placement. Crucially this is *ever built*, not *currently built*:
  demolishing the building that satisfied a prerequisite does not
  re-lock anything downstream — the colony "knows how" to build a mine
  once it's built one, even if that particular mine is later removed.
  `tests/test_tech.gd`'s `test_unlock_survives_demolish` pins this.
- **`missing_prereqs(type_id) -> Array`** — the subset of
  `defs[type_id].get("requires_built", [])` not yet in `built_types`, in
  declared order. Empty means unlocked.
- **`is_unlocked(type_id) -> bool`** — `missing_prereqs(type_id).is_empty()`.
- **`can_place()`** checks `is_unlocked(type_id)` immediately after the
  "does this building exist" check and before the terrain/occupancy/cost
  checks, returning `{"ok": false, "reason": "Locked — prerequisite not
  built"}` if not. So a locked building is rejected before any
  footprint-level validation even runs.

On the render/UI side: `ui/sidebar.gd` keeps its build buttons in a
`_build_buttons: Dictionary` (id → `Button`, populated alongside
`_build_list`'s children in `populate()`). `set_locks(locks: Dictionary)`
(id → reason string, `""` meaning unlocked) disables each locked button,
appends `"  🔒"` to its label, and swaps its tooltip from the building's
`desc` to the lock reason. `main.gd`'s `_refresh_locks()` builds that
`locks` dictionary by calling `Sim.colony.missing_prereqs(id)` for every
building in `Defs.buildings` and formatting a `"Requires: <name>, ..."`
string from the missing ids' display names; it's called once in `_ready()`
and again on every `Events.building_placed` (a new building can unlock
others further down the chain, so the whole menu is recomputed rather than
patched incrementally).

## Deposits and prospecting (`ColonyMap` + `Colony`, Milestone 4)

This is the game's signature mechanic: subsurface resources are hidden
until surveyed, and extraction is gated on a confirmed reading.

**Hidden layers on `ColonyMap`** (`sim/map.gd`), parallel to the terrain
`PackedByteArray` and indexed the same way:

- `_deposit` (`PackedByteArray`) — one of `enum Deposit { NONE, IRON,
  COPPER, XENITE }` per cell. Hidden; `get_deposit(cell)` reads it, but
  nothing renders it directly until a scan confirms it. `set_deposit(cell,
  dep, richness)` (Colony Hub rework) writes this, `_richness` (below),
  and — finite-deposits rework — `_amount` for one cell: the only way a
  deposit is ever placed outside of map generation; see "Colony Hub and
  guaranteed deposits" below.
- `_richness` (`PackedFloat32Array`) — `0.0`–`1.0` per cell. Originally how
  fast a matching extractor produced there; since the finite-deposits
  rework it instead sizes the tile's reserve (see `_amount` below) — a
  richer tile lasts longer, not faster. Hidden the same way.
- `_amount` (`PackedFloat32Array`, finite-deposits rework) — extractable
  units still in the ground at this cell. `set_deposit()` seeds it as
  `richness * Balance.deposit_units[deposit name]` (`deposit_units`: IRON
  600, COPPER 260, XENITE 30 — see "Tuning" above); `get_amount(cell)`/
  `set_amount(cell, v)` read/write it (the setter clamps at `0.0`).
  Extraction draws it down (see "Extractor gating and output" below) and
  it is the only layer that changes for a reason other than scanning.
  Serialized (`amount` key in `to_dict`/`from_dict`); a save from before
  this rework has no `amount` key, so `from_dict` refills every deposit's
  reserve from its richness on load, so an old save reads as an
  untouched map rather than a dead one.
- `_reading_noise` (`PackedFloat32Array`) — a fixed per-cell random value
  in `-1.0..1.0`, generated once at map creation from a seeded
  `RandomNumberGenerator`. `coarse_richness(cell)` adds
  `noise * reading_jitter` (a field, default `0.25`, set from
  `data/balance.json` since Milestone 9 — see "Tuning" above) to the true
  richness and clamps to
  `0.05..1.0`, so a coarse scan reports a plausible-but-imprecise number
  that's deterministic (not re-rolled) for a given cell and seed.
- `_scan` (`PackedByteArray`) — one of `enum Scan { UNSCANNED, COARSE,
  CONFIRMED }` per cell. This is the *revealed* layer — the only one that
  changes during play, via `set_scan(cell, state)`.

**Deposit generation** (`_generate_deposits`, called from `generate()`
after terrain): IRON and COPPER each get a low-frequency `FastNoiseLite`
field (seeded `p_seed + dep * 101` so they're independent), each with its
own threshold, eligible only on REGOLITH/HIGHLANDS cells. For each
eligible cell, the winning deposit is whichever field's value clears its
threshold by the largest margin (ties/no-clears → `Deposit.NONE`);
richness is derived from that margin (`clampf(0.2 + margin * 1.6, 0.1,
1.0)`). This produces naturally blob-shaped deposits without an explicit
blob/flood-fill algorithm, and is fully deterministic per seed — pinned by
`tests/test_prospecting.gd`'s `test_generation_is_deterministic`.

XENITE (finite-deposits rework) no longer goes through that noise-field/
threshold scheme at all: **every CRYSTAL terrain cell holds xenite, and no
xenite generates anywhere else** — `tests/test_prospecting.gd`'s
`test_xenite_sits_in_visible_crystal` pins both halves of that. A
formation is visible terrain from the start; only its richness (and so its
reserve) is hidden until prospected, seeded from a separate noise field
(`clampf(0.25 + v * 0.75, 0.2, 1.0)`) so richness still varies formation to
formation. `generate()`'s highlands→CRYSTAL feature threshold loosened
`-0.60 → -0.40` in the same rework (roughly 1–9 crystal formations per map
before, ~28–33 after) — at the old rarity a seed could hold less total
xenite than the victory target and be unwinnable outright.

**Survey scanning** (`Colony._run_prospecting` / `_scan_ring`, in
`sim/colony.gd`): a survey building (any def with a `scan` block —
`survey_station` at `max_radius: 7, ticks_per_ring: 3`, and — Colony Hub
rework — `hub` at `max_radius: 6, ticks_per_ring: 3` — both raised from `2`
in the Milestone 9 balance pass) sweeps an expanding
ring outward from its footprint center. Each active
survey building's `scan_progress` (a per-instance counter, alongside
`scan_ring`, both initialized in `place()`) advances one per tick; once it
hits `ticks_per_ring`, `_scan_ring` processes the current ring — every
cell whose rounded distance from center equals `scan_ring` — and advances
each such cell's scan state one step (`UNSCANNED→COARSE` or
`COARSE→CONFIRMED`; a cell already `CONFIRMED` is left alone). Every cell
actually advanced is appended to `Colony.scan_changes` (reset to `[]` at
the top of every `tick()`). Once `scan_ring` exceeds `max_radius`, what
happens next depends on the building (finite-deposits rework): a def with
no `scan.confirm_ticks` (just `hub`) resets `scan_ring` to `0` and
restarts from the center, so a tile visited by the first sweep (coarse)
gets upgraded to confirmed on the second sweep — the original "progressively
reveals coarse then confirmed" mechanism, unchanged for the hub. A def
*with* `scan.confirm_ticks` (`survey_station`, `6`) instead sets
`inst.resampling = true` and switches to `_run_resample` on every later
tick for that instance:

- One probe every `confirm_ticks` ticks (via the same `scan_progress`
  counter, now counting toward `confirm_ticks` instead of
  `ticks_per_ring`), incrementing a per-instance `scan_probes` counter.
- The probed cell is picked from the station's full radius by
  `_probe_hash(building_id, probe_number)` — an integer hash, not
  `RandomNumberGenerator` — so the sequence is deterministic and a save
  reloads mid-sequence (`resampling`/`scan_probes` are both serialized,
  alongside `scan_ring`/`scan_progress`).
- If the hashed cell is off the map, outside the radius, or not currently
  `COARSE`, the probe does nothing — it frequently lands on ground
  already confirmed, or on bare rock. If it *is* `COARSE`, it's promoted
  to `CONFIRMED` and appended to `scan_changes`.

So discovery (the ring sweep, `COARSE`) is comparatively quick; pinning
down richness away from the hub is a patient, scattershot process —
`tests/test_prospecting.gd`'s `test_confirming_is_much_slower_than_discovering`
asserts confirming takes more than 4× as long as first finding a tile, and
`test_resampling_is_deterministic` asserts a replayed colony confirms the
same tiles in the same order.

**Survey coverage requirement** (finite-deposits rework): a def can
declare `requires_coverage: true` (only `survey_station`); `can_place()`
then also requires `Colony.in_survey_coverage(origin)` — true if any
currently-placed building with a `scan` block has `origin` within its
`scan.max_radius` of its footprint center (`in_survey_coverage` loops
every building; there is no spatial index, since a colony has at most a
handful of scanning buildings at once). Practically this means a survey
station can only be planted somewhere the hub or an earlier station
already reaches, so coverage grows outward in overlapping steps instead of
leapfrogging into open dark.

**Extractor gating and output**: any building def with `requires_deposit_ids`
(resolved by `Defs` from `requires_deposit`, see above) can only be placed
where `Colony.can_place()` finds `map.get_scan(origin) ==
ColonyMap.Scan.CONFIRMED` *and* `map.get_deposit(origin)` is one of the
required types (`allowed_terrain_ids` is checked separately, the same way
as for every building — this is how `crystal_extractor` additionally
requires CRYSTAL terrain) — all extractors are 1×1, so `origin` is the
only cell to check. On placement, `place()` latches `deposit_type`,
`richness`, and a `mine_accum` float onto the instance — the deposit is
fixed at build time, not re-read every tick.

Since the finite-deposits rework, `_run_mine` (called from
`_run_production` for any `active` building with a `mine` def block) no
longer scales its rate by richness: it adds a flat `base_per_tick` to
`mine_accum` every tick and pays out whole units, capped at
`map.get_amount(origin)`, drawing that reserve down by the same amount
(`map.set_amount`). Once the reserve hits `0.0`, `_run_mine` idles the
building (`active = false`, `idle_reason = "Deposit worked out"`) instead
of accumulating further — the extractor has to be demolished (for the
refund) and rebuilt elsewhere. `rates()` mirrors this: a worked-out tile
contributes nothing to the projected per-tick figure, not just to actual
output. Richness now determines how much ore a tile ever holds, not how
fast it comes up — see `_amount`/`deposit_units` above.
`ColonyMap.reading_text()` reports units-left ("IRON · 240 units left") on
a confirmed tile instead of a richness percentage, and "worked out" at
zero; `ui/hover_panel.gd`'s mine line does the same via
`building_report()`'s new `remaining` field.

`Sim._advance_tick()` emits `Events.scan_changed(colony.scan_changes)`
after `colony.tick()`, but only when the list is non-empty, so idle ticks
(no active survey buildings, or a survey mid-ring/mid-resample with
nothing revealed this tick) don't spam the signal.

### Colony Hub and guaranteed deposits (Colony Hub rework)

A building def can declare `guarantees_deposit` (a deposit name, e.g.
`"IRON"` — only `hub`); `Defs` resolves it to `guarantees_deposit_id`, the
same pattern as `requires_deposit_ids`. `Colony.place()` checks, right
after placement, whether the new instance's def has both
`guarantees_deposit_id` and a `scan` block; if so it calls
`_ensure_deposit_in_range(center, def.scan.max_radius,
def.guarantees_deposit_id, balance.guaranteed_richness)`
(`balance.guaranteed_richness`, default `0.6`, from `data/balance.json`
since Milestone 9). That method first scans every cell within `radius` of
`center` for
an existing deposit of that type that isn't sitting under a building (a
buried-under-a-building deposit can't be mined, so it doesn't count as
reachable); if one exists, it does nothing. Otherwise it scans outward
ring-by-ring from `radius = 2` and calls `ColonyMap.set_deposit()` on the
first buildable (REGOLITH/HIGHLANDS), unoccupied, currently-empty
(`Deposit.NONE`) tile it finds, injecting a fresh richness-0.6 deposit
there — deterministic, since it always picks the first qualifying tile in
a fixed scan order. In practice this means placing the Hub always leaves
at least one mineable iron tile within its survey radius, so a new colony
can never be stranded without buildable ore.

`life_support` (int, per-instance in the def — only `hub`, at `4`) is the
other half of the Hub's forgiveness: see `life_support_covered()` and
`_run_life_support()` in "Colonists, life support, and win/lose" above.

### The hub is free, unique, and required (finite-deposits rework)

Three more def flags, all only ever set on `hub`:

- **`cost: {}`** — the hub is free. Landing the first one no longer
  depends on the starting stockpile at all.
- **`unique: true`** — `Colony.count_of(type_id)` counts placed instances
  of a type; `can_place()` refuses a second `unique` building
  (`{"ok": false, "reason": "Only one allowed"}`), and
  `Colony.lock_reason(type_id)` — the general-purpose "why is this greyed
  out in the build menu" query, covering both this and the existing
  `missing_prereqs()` check — returns `"Already built"` for it.
  `main.gd._refresh_locks()` now calls `lock_reason()` instead of
  re-deriving the prerequisite-only rule itself.
- **`colony_controller: true`** — `Colony._init()` sets a private
  `_needs_controller` flag if *any* def in the passed-in `defs` dictionary
  declares `colony_controller`; content that doesn't (every hand-rolled
  test-defs dictionary in the suite except `tests/test_hub.gd`'s) never
  triggers the rule below, so it's opt-in per content set, not a hardcoded
  hub special-case. `tick()` calls `_require_hub()` right after
  `_balance_power()`: if `_needs_controller` and no placed building with
  `colony_controller` is currently `active`, every building — including
  ones with `life_support` — is forced `active = false` with
  `idle_reason = "No colony hub"`, overriding whatever the power pass just
  decided. Losing the hub is recoverable, not fatal: placing a new one
  (anywhere) satisfies the check again on the very next tick.
  `main.gd` now also refreshes the build-menu locks on
  `Events.building_removed`, not just `building_placed`, so demolishing a
  `unique` building puts it back in the menu immediately.

`tests/test_hub.gd` covers all three: the hub can be placed from an empty
stockpile, a second one is refused and greyed out, demolishing and
rebuilding recovers the colony, and (the negative case) a defs dictionary
with no `colony_controller` declared is unaffected by the rule at all.

## Building inspector (`Colony`/`Sim`/sidebar, Milestone 6)

Every building instance dict carries `idle_reason: String` (initialized `""`
in `place()`), rewritten each tick by whichever balance/production phase last
touched that building's `active` flag: `_balance_power()` sets `"No power"`
on a shed consumer (and clears it to `""` for anything that stays/becomes
active), `_balance_workforce()` sets `"No workers"` on an understaffed
building, and `_run_production()`'s recipe branch sets `"Needs <res, ...>"`
(via `_short_inputs()`) when a recipe is stalled on missing inputs. `""`
always means "running fine" — the inspector's running/idle line is just
`rep.active and idle_reason == ""`.

`Colony.building_report(id) -> Dictionary` (pure, no formatting) merges an
instance's live state with its def into a display-ready dict: `name`,
`active`, `idle_reason`, `storage` (the storage/warehouse feature — the
def's `storage` dict verbatim, `{}` for non-storage buildings), `power`,
`workers`, `capacity`, `life_support`
(Colony Hub rework — the def's `life_support` field, `0` unless it's the
Hub), `scans` (bool), plus `recipe` (with the instance's `progress`) or
`mine` (resource/richness/per-tick rate, plus — finite-deposits rework —
`remaining`, the tile's live `map.get_amount(origin)`) when applicable.
Returns `{}` if
`id` is no longer a placed building — the caller's cue to deselect.
`Sim.building_report(id)` is a bare pass-through (no signal, since it's
polled, not pushed).

On the render/UI side, this is no longer surfaced by clicking to select —
see "UI layer" below for `ui/hover_panel.gd`, which renders the same
`building_report()` dict as a cursor-following readout instead of a sidebar
section, and shows a "sustains N colonists" line whenever `life_support > 0`.

## Alerts (`AlertMonitor`, Milestone 6)

`sim/alerts.gd` (`AlertMonitor`, `class_name`, `RefCounted`) is an
edge-triggered detector, following the same pure/testable pattern as
`Colony`/`ColonyMap` — no autoload or `Events` dependency. `check(col:
Colony) -> Array` returns `[{text, level}]` for conditions that just became
true this tick (rising edges only), so a sustained problem announces once,
not every tick, by keeping its own `_power_deficit`/`_low` state between
calls:

- **Power deficit** (`col.power_consumed > col.power_produced`) — `CRIT`.
- **Any net-drained resource running low** — a `low_stock` floor (field,
  default `8`, from `data/balance.json` since Milestone 9 — `AlertMonitor`
  takes an optional `Balance` in `_init`), checked against every id in
  `col.rates()` whose rate is negative (i.e.
  something is actively consuming it faster than it's produced), not just
  oxygen/water/food — so ore/metal/parts drawn down by the production chain
  warn too, the same as life support. `WARN`; text uses `String.capitalize()`
  so multi-word ids read naturally ("Iron Ore", "Copper Ore"). `_low` is a
  dynamic id→bool map (was a fixed 3-key dict for oxygen/water/food); a
  resource re-arms (can fire again) once its rate goes non-negative or it
  drops out of `rates()` and then goes low again later. The old
  `population > 0` gate is gone — it's subsumed, since a resource only shows
  a negative rate when something is actually consuming it.
- **Deposit confirmed** — any deposit kind newly `CONFIRMED` in
  `col.scan_changes` this tick — `INFO`, one entry per kind (not per cell).

`Sim` owns one `AlertMonitor`, resets it in `new_game()`, and calls
`check(colony)` at the end of `_advance_tick()`, emitting `Events.alert`
once per returned entry. `ui/alert_ticker.gd` is the sole listener: a
`VBoxContainer` on the UI `CanvasLayer`, bottom-left, that pushes a new
color-coded (by level), dark-outlined label onto a stack (capped at 4,
newest on top), fading and freeing each after ~5s.

## Status overlay (`render/status_overlay.gd`, Milestone 6)

Power in this game is a global capacity balance, not a spatial network (see
the power-balance section above), so there's no coverage radius to draw.
`StatusOverlay` (`Node2D`, `z_index = 6`, hidden by default) instead marks
every placed building with a dot at its front cell (`IsoGrid.grid_to_screen`
of the max-`x+y` cell, matching `BuildingSprite`'s anchor) — green
(`inst.active`) or red (idle, any reason). Toggled by `O` via
`main.gd` calling `_status.toggle()`; redraws every frame while visible so
it tracks the tick loop live.

## Save / load and menus (`ColonyMap`/`Colony`/`Sim`/menu, Milestone 7)

Full sim state serializes to a JSON-safe dict and back, following the same
pure/testable pattern as everything else in `sim/`:

- **`ColonyMap.to_dict()` / static `from_dict(d)`** (`sim/map.gd`): width,
  height, seed, plus the byte layers (`_cells`, `_deposit`, `_scan`) and
  float layers (`_richness`, `_amount` — finite-deposits rework —,
  `_reading_noise`), each base64-encoded via `Marshalls.raw_to_base64`
  (float arrays go through `to_byte_array()`/`to_float32_array()` first,
  since `Marshalls` only handles raw bytes). `from_dict` refills `_amount`
  from richness when a save predates it (see `_amount` above).
- **`Colony.to_dict()` / static `from_dict(map, defs, d)`** (`sim/colony.gd`):
  everything except the map (saved separately) — stockpile, population,
  status, `_next_id`, starve/growth streak counters, `_life_accum`,
  `built_types`, and every building instance. `_inst_to_dict`/
  `_inst_from_dict` flatten `origin`/`cells` `Vector2i`s to `[x, y]` pairs
  and carry the optional `scan_ring`/`scan_progress`/`resampling`/
  `scan_probes` (finite-deposits rework — see "Deposits and prospecting"
  above) and `deposit_type`/`richness`/`mine_accum` fields. `from_dict`
  rebuilds the cell-occupancy index from the restored buildings rather
  than serializing it directly. Both classes stay free of any
  autoload/rendering dependency.

**`Sim`** (`sim/sim.gd`) exposes the save API: `SAVE_DIR = "user://saves/"`,
`SAVE_VERSION = 1`, `AUTOSAVE_NAME = "autosave"`, `autosave_seconds` (a var,
default `180.0`, from `data/balance.json` since Milestone 9).
`save_game(name)` writes `{version, saved_at, tick, speed, last_run_speed,
map, colony}` as JSON under `SAVE_DIR`; `load_game(name)` reconstructs the
map and colony via the `from_dict` methods (injecting `Defs.buildings`),
restores tick/speed, and resets the transient bits (`_accumulator`,
`_autosave_accum`, `_alerts`). `list_saves()` (newest-first by file mtime),
`latest_save()`, `has_saves()`, and `delete_save(name)` round out the API.
A new `active: bool` gates the tick loop and autosave — `new_game()`/
`load_game()` set it `true`; the main menu sets it `false` so nothing
simulates while at the menu. `_process()` checks `active` first, drives
autosave on real elapsed time (even while paused, as long as
`status == PLAYING`), then runs the existing tick loop.

**Main menu** (`menu.gd`/`menu.tscn`) is now `project.godot`'s
`run/main_scene` (was `main.tscn`). It offers New Game (a seed field — blank
random, numeric as-is, other text hashed — and a map-size picker), Continue
(loads `Sim.latest_save()`), Load (an `ItemList` of saves with Load/Delete),
and Quit; Continue/Load disable themselves when `Sim.has_saves()` is false.
Selecting New/Continue/Load sets up `Sim` state, then
`change_scene_to_file("res://main.tscn")`.

**In-game system menu** (`SystemMenuLayer` in `main.tscn`): opened from
`main.gd` when Escape is pressed with nothing else to dismiss — the Escape
handling now cascades minimap → build/demolish mode → system menu. Opening
it pauses the sim (remembering the prior pause state to restore on Resume)
and offers Resume / Save Game (`Sim.save_game("quicksave")`) / Main Menu
(sets `Sim.active = false`, returns to `menu.tscn`) / Quit; it swallows
gameplay keys/clicks while visible.

`main.gd`'s boot changed accordingly: `_ready()` only calls
`Sim.new_game()` as a fallback when `Sim.colony == null` (the menu normally
sets one up first), sets `Sim.active = true`, and centers the camera on the
loaded map's actual `width`/`height` rather than a fixed constant, so a
loaded non-default-size map centers correctly. The game-over restart path
now calls `Sim.new_game(_map.seed, _map.width)` before
`reload_current_scene()`, since the reloaded scene reuses the existing
colony object — a fresh one must be created first for a true restart on the
same map.

## Audio (`audio/`, Milestone 8)

Sound follows the same one-way-read discipline as rendering: the `Audio`
autoload (`audio/audio.gd`) only listens on `Events` and reads `Defs.audio`;
it never reaches into `Sim`/`Colony`, so muting or removing it changes
nothing about the simulation.

- **Cue vocabulary** (`audio/audio_cues.gd`, `class_name AudioCues`) is a
  pure, dependency-free class listing every cue name and the event→cue
  mapping (`for_alert(level)`, clamped so an out-of-range alert level still
  gets a sound rather than falling silent; `for_game_over(won)`). Headlessly
  tested (`tests/test_audio.gd`) the same way `AlertMonitor` is.
- **Manifest** (`data/audio.json`, loaded into `Defs.audio`): one entry per
  cue — `file`, `bus` (`Music` or `SFX`), `volume_db`, optional
  `pitch_min`/`pitch_max` jitter, and `loop`. Adding a sound is a WAV file
  plus a manifest entry, no script changes — the same data-driven pattern as
  buildings/resources.
- **Playback** (`audio/audio.gd`): two audio buses (`Music`, `SFX`) created
  at runtime rather than via a binary bus-layout resource; an 8-voice
  one-shot `AudioStreamPlayer` pool with voice stealing for SFX, a separate
  looping player for the ambient bed, a same-cue repeat guard (40ms) so a
  cue fired twice in one frame doesn't double up, and mute + music/SFX
  volume persisted to `user://settings.cfg`. `shutdown()` stops everything
  before quit so a still-playing stream isn't reported as a leaked resource.
  In headless runs (`DisplayServer.get_name() == "headless"` — tests,
  `make import`) it validates the manifest but loads and plays nothing, since
  there's no audio device.
- **Event hooks**: `building_placed`/`building_removed`/`alert`/`game_over`
  each play their matching cue (see `AudioCues`); `main.gd` plays `denied`
  on a refused placement/demolition; every sidebar/menu button calls
  `Audio.ui_click()`. A pause-menu "Sound: On/Off" button calls
  `Audio.toggle_mute()`.
- **Assets**: `assets/audio/*.wav` (plus Godot `.import` sidecars, committed
  — looping is set as an asset property, `edit/loop_mode`, on `ambient.wav`
  rather than patched in code). None are hand-recorded or downloaded —
  `tools/gen_audio.py` (stdlib-only Python, run via `make audio`)
  synthesizes all of them: nine short chiptune-ish SFX plus a 32-second
  ambient bed (drone, pad, filtered wind, bell motes) built to loop
  seamlessly by quantizing every oscillator to a whole number of cycles
  over the bed's length. Changing an `.import` parameter needs
  `godot --headless --import` — `make import` alone won't re-run it.

## Rendering and camera

- `render/palette.gd` (`Palette`, `class_name`, static colour constants
  only, Milestone 8) is the one shared colour source for the whole
  procedural art pass: a warm dusty-brown/ochre "regolith" family with
  amber highlights, plus cool cyan (ice) and violet (crystal) accents for
  the special terrains, and building-detail tones (`LIGHT_ON`/`LIGHT_OFF`
  lamp colours, `SMOKE`, `EDGE`/`RIM_LIGHT`). `TerrainView` and
  `BuildingSprite` both pull from it so the whole screen reads as one
  palette; never instantiated. Shared visual convention: everything is
  lit from the upper left, so raised or dished detail (buildings, craters,
  stones) always shadows on its lower-right and catches light on its
  upper-left — one consistent light source across terrain and buildings.
- `render/terrain_view.gd` (`TerrainView`) builds a procedural iso tileset
  in code, no external art files committed. A `SPEC` dict declares, per
  `ColonyMap.Terrain`, how many static plain **variants** and animation
  **frames** to generate (regolith/highlands: 5 variants, 1 frame; ice/
  crystal: 2 variants, 3 frames each), plus how many **clutter** variants
  and what percentage of tiles should use one. `VOID` is not in `SPEC` —
  it's autotiled instead (see below).
  Each plain variant is drawn (`_draw_terrain`) as a near-flat 4x4 ordered
  (Bayer) dither between a light and dark tone (`MASK_LIMIT` relaxes the
  diamond mask slightly past the true edge so neighbours overlap a pixel
  at the corners), with per-variant mottling and sparse seeded flecks for
  grain. The tile boundary carries no rim or bevel — only a faint darken
  toward a per-terrain `seam` tone (a darker relative of that terrain,
  not shared black) past `SEAM_START`, so same-terrain neighbours read as
  continuous ground and the grid is a hint rather than an outline;
  legibility of the current tile comes from the hover cursor and overlays
  instead. Clutter variants (`_draw_clutter`) add terrain-specific incident
  — stones on regolith, craters and rubble on highlands, pressure cracks
  in ice — each following the shared top-lit convention (e.g. `_draw_crater`
  shadows its near/upper wall and lights its far rim); `render_map()`
  picks plain vs. clutter per cell via one hash (`_cell_hash` salted for
  clutter) and the specific variant via another (`_cell_variant`), kept
  independent so texture and clutter don't correlate into visible
  banding. All variants (plain then clutter, and each one's animation
  frames) are packed into successive columns of one atlas image;
  `_variant_coords`/`_clutter_coords` record each terrain's base coords,
  and ice/crystal frames get
  `TileSetAtlasSource.set_tile_animation_frames_count`/
  `set_tile_animation_frame_duration` (~0.4s/frame) so their sparkle
  pixels shift and the tiles shimmer. `TERRAIN_COLORS` (still used by the
  minimap) maps to `Palette`'s base tones instead of inline `Color`
  literals.
- **`VOID` (canyon) tiles are a bottomless rift, not dark ground**, and are
  autotiled rather than randomly varianted. Since the camera always looks
  down over a rift's near rim at the far wall, only the two edges facing
  the camera can ever be visible (the near edges face away); `_void_mask()`
  encodes which of those two neighbours — `x-1` and `y-1` — are solid
  ground into a 3-bit mask (off-map counts as open, so a canyon runs off
  the world edge instead of dead-ending in a wall). The third bit,
  `VOID_N` (`x-1, y-1`), exists because grid diagonals are screen
  cardinals in this projection: that cell is the tile directly *north* on
  screen, and when it's solid ground but both edge neighbours are rift,
  the cliff's vertical corner column still has to project down into this
  tile (the two flanking walls meet above it). Without it, a lone mesa
  bit a black notch out from under its south corner. `_draw_void` folds
  the bit in as the max of the two edge depth measures — both hit zero at
  the shared top corner, so their max is a wedge radiating from it,
  matching how the corner column reads — and it's a no-op wherever an
  edge wall already covers the same area. `_build_tileset()` pre-renders
  all 8 masks × `VOID_VARIANTS` into the atlas. `_draw_void`
  shades each pixel by its distance below whichever lit rim(s) apply,
  through a dark-to-light ramp (`_wall_ramp`, `Palette.VOID_RIM` at the lip
  down to `Palette.VOID_ABYSS`) picked via `_ramp_color`'s Bayer dither so
  the gradient stays pixel-art; a faster-than-linear falloff keeps the lit
  band hugging the lip, and per-column jitter/grain break the wall into
  ragged strata instead of a clean bevel. Below the wall nothing is drawn
  but flat `VOID_ABYSS` — there's no floor to draw, and adjacent rift tiles
  are identical black inside so a multi-tile canyon reads as one continuous
  void with no seams.
- `render/prospect_overlay.gd` (`ProspectOverlay`, extends `TileMapLayer`,
  Milestone 4) is a toggleable overlay of semi-transparent iso diamonds
  tinting each tile by prospecting knowledge: `enum Cat { UNSCANNED,
  COARSE_EMPTY, COARSE_DEP, CONFIRMED_EMPTY, IRON, COPPER, XENITE }`, each
  with its own `Color` (including alpha, so terrain shows through) in a
  `COLORS` dict, painted into a procedurally-built tileset the same way
  `TerrainView` builds its. `setup(map)` builds the tileset and connects
  `Events.scan_changed`. `rebuild()` repaints every cell from current scan
  state — called when the overlay is toggled on, since it doesn't track
  state while hidden. While `visible`, `_on_scan_changed(cells)` repaints
  only the cells in the signal's payload, so an active survey doesn't
  force a full-map repaint every tick. `_category(cell)` picks the `Cat`
  from `map.get_scan(cell)`/`map.get_deposit(cell)`: `COARSE` shows only
  whether *something* is there (`COARSE_DEP`) or not (`COARSE_EMPTY`), not
  which resource — matching the "coarse readings are imprecise" design;
  only `CONFIRMED` reveals the specific ore/crystal color.
- `render/building_sprite.gd` (`BuildingSprite`, extends `Node2D`) — 
  **rewritten in the pre-M6 fixes pass**. It used to draw one whole
  building's footprint (any size) as a single node, but that meant a
  multi-tile building y-sorted at one depth value, which is wrong for a
  2×2+ footprint — it could draw in front of or behind a neighboring
  building incorrectly on tiles where a single depth can't be correct for
  all 4 (or more) of its cells at once. It now draws a *list of cells*,
  each a separate flat-shaded 1×1 iso block (lit top face plus two
  darkened side walls, `WALL_H = 14.0` px). `configure(color, cells,
  ghost)` and `set_cells(cells)` take a plain `Color` (not a def
  dictionary — callers pass `def.color_value` themselves now) and an
  `Array` of `Vector2i` cells; the node `position` anchors at whichever
  cell has the largest `x + y` (the front-most, matching the old
  max-corner-tile logic) via `IsoGrid.grid_to_screen`, and `_draw()`
  renders all cells in the list back-to-front relative to that anchor.
  `set_valid()` and `set_dimmed()` are unchanged in behavior (ghost
  green/red tint; grey modulate for a shut-down placed building, no-op on
  a ghost). As of the Milestone 8 art pass, placed blocks also carry a
  recessed roof panel and warm `Palette`-coloured edge lines, plus idle
  animation: two indicator lamps that blink out of phase (phase derived
  from cell position, via `sin` on an animation clock `_t`), and, when
  `configure()`'s new `smoke: bool` parameter is set, rising/fading
  exhaust smoke puffs. `_process` (only running on placed sprites, not
  ghosts — `set_process(not ghost)`) advances `_t` every frame but
  throttles `queue_redraw()` to ~12fps. `set_dimmed(true)` also darkens
  the lamps and stops the smoke, so a shut-down building reads as
  visibly "off". The ghost stays flat and static (no `_process`, no
  lamps/smoke) since it never carries `smoke: true`.

  **Textured path (Milestone 8 asset integration)**: `configure()` takes a
  5th optional arg, `texture: Texture2D`. When set, `_draw()` calls
  `_draw_texture_sprite()` instead of the procedural block path entirely —
  no roof panel, edge lines, lamps, or smoke; `set_process(false)` so it
  never redraw-animates. The art is anchored so its **bottom-centre sits
  on the front cell's bottom vertex**: `offset = -(width/2, height -
  IsoGrid.TILE_H/2)`. This one formula works for any footprint size
  because a footprint diamond's bottom vertex is shared with its front
  (max `x+y`) cell's bottom vertex, so both a 1×1 (64×64 art) and a 2×2
  (128×128 art) building seat correctly with no per-size branching.
- `render/buildings_view.gd` (`BuildingsView`, extends `Node2D`) — also
  updated in the same pass: `_on_placed(inst)` now spawns **one
  `BuildingSprite` per footprint cell** (`spr.configure(color, [cell],
  false)` for each `cell in inst.cells`), rather than one sprite for the
  whole building. This is what actually fixes the depth-sorting bug —
  with `Buildings` still `y_sort_enabled = true`, each individual tile of
  a multi-tile building now sorts against its neighbors independently,
  the same way single-tile buildings always did. `_sprites: Dictionary`
  changed shape accordingly: instance id → `Array[BuildingSprite]`
  (previously → a single sprite). `_on_removed` frees every sprite in the
  array; `_on_ticked`'s dimming loop iterates the array too, so all of a
  building's tiles dim/undim together. `bind()`'s responsibilities
  (connecting `Events.building_placed`/`building_removed`/`ticked`,
  backfilling for buildings already in `Sim.colony.buildings`) are
  unchanged. As of the Milestone 8 art pass, `_on_placed` also reads the
  building def's `smoke: bool` (see "Data-driven content" above) and
  passes it to `configure()` only for the sprite at the footprint's
  front-most cell (`_front_cell`, largest `x + y`), so a multi-tile
  building emits a single smoke plume rather than one per tile.

  **Textured path (Milestone 8 asset integration)**: `_on_placed` also
  reads the def's `sprite` field through a cached `_load_texture(path)`
  (`_textures: Dictionary`, path → `Texture2D`; returns `null` — the
  procedural-fallback signal — for an empty path or a missing file, via
  `ResourceLoader.exists`). When a texture is found, `_on_placed` spawns a
  **single** `BuildingSprite` for the whole footprint (`configure(color,
  inst.cells, false, false, tex)`) instead of one sprite per cell;
  occlusion against neighboring buildings still comes for free from the
  `Buildings` layer's y-sort, same as the procedural path. `smoke` is
  irrelevant for a textured sprite (see `BuildingSprite` above) so it's
  passed `false`.

  Since the second Milestone 8 asset-integration wave gave every one of
  the 11 shipped buildings a `sprite`, the **procedural block path**
  described above (dithered blocks, roof panel, blinking lamps, smoke
  puffs, and `BuildingsView`'s per-footprint-cell spawning) is no longer
  exercised by any shipped building — it remains only as a fallback for
  robustness, or for any future building added without art. Terrain
  rendering is unaffected: `TerrainView`'s dithered/animated atlas and
  `Palette` are still fully procedural and very much live.

### `BuildingFX` — decorative overlays on art-backed buildings

`render/building_fx.gd` (`BuildingFX`, `Node2D`) is how a static, textured
building sprite still reads as alive: smokestack plumes, vent steam,
ground dust, ember sparks, crystal shimmer, blinking warning lamps, and
soft pulsing glows, all driven by a building def's optional `fx` array
(see "Data-driven content" above) rather than hand-authored per building.

- **`configure(specs: Array, phase := 0.0)`** builds one node per spec.
  `smoke`/`steam`/`dust`/`sparks`/`shimmer` become `CPUParticles2D`
  emitters (`_make_emitter`), each a tuned preset (direction, spread,
  velocity, gravity, scale-over-life curve, color) that every entry's
  optional `color`/`rate`/`scale`/`alpha`/`life_scale` overrides; all five
  share one 8×8 procedurally-drawn soft-disc puff texture (`_puff()`,
  built once, cached in a `static var`) rather than an asset file. `lamp`
  and `glow` aren't particles — cheap enough to just draw directly in
  `_draw()` each frame — and are stored as plain dictionaries in `_lamps`/
  `_glows` instead. `phase` (seconds) offsets every emitter/lamp/glow's
  cycle so identical buildings in a row don't blink or puff in lockstep;
  `BuildingsView` derives it from the building's instance id.
- **Anchoring**: a `BuildingFX` is parented directly onto the building's
  `BuildingSprite` (see `attach_fx()` below), which already sits at the
  sprite's own anchor — the bottom-centre of its front footprint cell (see
  the textured-path anchoring formula above). So an `fx` entry's `at` is
  simply a pixel position measured in the source PNG minus that same
  anchor offset: `at = pixel_in_png - (tex_w/2, tex_h - IsoGrid.TILE_H/2)`.
  `tests/test_building_fx.gd` checks every shipped `at` lands within the
  sprite's declared `size` in pixels, catching a mis-measured offset.
- **`lamp_intensity(t, period, duty)`** (`static`) is the blink curve: a
  `smoothstep`-shaped bump that peaks at the middle of the `duty` fraction
  of each `period` and is fully dark for the rest of the cycle — reads as
  a ramping beacon flash rather than a hard on/off toggle. `_draw_lamp`
  layers a soft halo under the bulb when lit; `_draw_glow` layers three
  nested discs pulsing on a `sin` cycle for a furnace-mouth/crystal-hopper
  bloom.
- **`set_active(active: bool)`** stops/resumes emitter `emitting` and
  darkens/relights lamps and glows (glows simply don't draw while
  inactive). `render/building_sprite.gd`'s `attach_fx(fx)` parents a
  `BuildingFX` as a child (so it shares the sprite's y-sort depth), and
  `set_dimmed(dimmed)` now also calls `fx.set_active(not dimmed)` — the
  same shut-down signal that greys out the sprite also stops its vents and
  darkens its lights.
- **`render/buildings_view.gd`**'s `_attach_fx(spr, def, id)` reads the
  def's `fx` array and, if non-empty, builds one `BuildingFX`,
  `spr.attach_fx()`s it, then `configure()`s it with `phase = id * 0.37`.
  It's only called on the textured (art-backed) path — the procedural
  block fallback keeps its own built-in lamps/smoke instead, so a building
  never gets both.

The placement ghost is the one place still using a single multi-cell
`BuildingSprite`: `main.gd`'s `_ghost` is configured with the *entire*
`Sim.colony.footprint(type_id, origin)` array in one `configure()`/
`set_cells()` call. This is safe because the ghost always renders at
`z_index = 50`, above every real building regardless of y-sort depth, so
per-tile interleaving with other buildings was never needed for it —
only placed buildings needed the fix.
- `render/tile_cursor.gd` (`TileCursor`, extends `Node2D`) is the hover
  highlight, replacing the Milestone-1 version. It exposes `cell` and
  `demolish` as setter-observed properties that trigger `queue_redraw()`,
  and draws a two-pass polyline diamond (a dark backing line under a bright
  one) so the border reads on any terrain color; the bright color switches
  amber→red when `demolish` is true.
- `render/iso_camera.gd` (`IsoCamera`, extends `Camera2D`) handles
  WASD/arrow-key panning in `_process` (`PAN_SPEED = 420.0` world px/sec at
  1× zoom) and middle-mouse-drag panning in `_unhandled_input`. Zoom is
  stepped through `ZOOM_STEPS = [1.0, 2.0, 3.0, 4.0]` to keep pixel scaling
  crisp — no free/continuous zoom. As of the second UI/UX refinement pass,
  zoom input is:
  - **`Z` is the primary control**: `toggle_zoom()` toggles 1×↔2×; called
    from any *higher* zoom (3×/4×), it snaps straight back to 1× rather
    than stepping down one level at a time.
  - **Pinch** (`InputEventMagnifyGesture`) is secondary fine zoom:
    `factor - 1.0` accumulates in `_magnify_accum`; every
    `MAGNIFY_PER_STEP` (0.18) of accumulated pinch steps zoom once
    (fingers apart = zoom in) via the shared `zoom_by(steps: int)` helper
    (clamps `_zoom_index`, reapplies `zoom`).
  - **Keyboard `+`/`-`** (`KEY_EQUAL`/`KEY_KP_ADD` and `KEY_MINUS`/
    `KEY_KP_SUBTRACT`) also call `zoom_by()` directly, one step per press.
  - **Mouse wheel and trackpad two-finger scroll (`InputEventPanGesture`)
    do NOT zoom** — this is a deliberate reversal of an earlier pass. That
    first pass (see `docs/progress.md`'s "UI/UX refinements" → Pass 1)
    added wheel/pan-gesture zoom specifically to fix zoom being unusable
    on macOS trackpads (which never emit wheel events); in practice
    scroll-to-zoom felt twitchy on a trackpad, so it was removed entirely
    in favor of the explicit `Z` toggle, keeping only pinch and keyboard
    as secondary paths. `tests/test_camera.gd` was rewritten accordingly —
    it now asserts a `InputEventPanGesture` leaves zoom unchanged, and
    covers the `Z` toggle/snap-back behavior with synthetic key events.

### Z-order / y-sort scheme

Draw order is controlled two ways, set on the nodes in `main.tscn`:

- `ProspectOverlay` sits at `z_index = 2` — above the base `TerrainView`
  (implicit `z_index = 0`) so its tints show, but below `Buildings` so
  building sprites remain visible over it.
- `Buildings` (`BuildingsView`) has `y_sort_enabled = true` and
  `z_index = 5`, so buildings sort against each other by their front-tile
  screen Y (via `BuildingSprite`'s position), and sit above the terrain
  and the prospecting overlay.
- `StatusOverlay` sits at `z_index = 6`, just above `Buildings`, so its
  running/idle dots draw on top of building sprites.
- `Ghost` (`BuildingSprite`, the placement preview) sits at `z_index = 50`.
- `TileCursor` sits at `z_index = 100`, the highest in the scene, so the
  hover border always draws on top of terrain and buildings. This fixed a
  Milestone-1 bug where the highlight was a plain `_draw()` on the game
  root and rendered *underneath* the `TileMapLayer`, making it invisible —
  see `docs/progress.md`'s Milestone 2 section and the class doc-comment at
  the top of `tile_cursor.gd`.

## Overhead map (`Minimap`)

`render/minimap.gd` (`Minimap`, extends `Control`) is a top-down view of
`ColonyMap`, toggled with `M`. It's purely a view — no game logic — and
follows the same one-way-read pattern as everything else in `render/`:

- `setup(map, camera)` (called once, from `main.gd._ready()`) builds a
  static `ImageTexture` with one pixel per map cell, colored from
  `TerrainView.TERRAIN_COLORS`, and sizes the control to
  `map.width/height * CELL_PX` (`CELL_PX = 4`). This terrain image is
  cached — it never changes after generation — while `_process` calls
  `queue_redraw()` every frame only while `visible`, since buildings and
  the camera view move.
- `_draw()` blits the cached terrain texture, then draws one colored rect
  per building (`Sim.colony.buildings`, sized/positioned from its
  footprint and tinted with its `Defs.buildings` `color_value` — the same
  field `BuildingSprite` uses), then the camera's current view as a
  polyline quad in grid space (`_draw_view_rect`, using a local unrounded
  inverse of `IsoGrid.grid_to_screen` since `IsoGrid.screen_to_grid`
  rounds to whole cells).
- `_gui_input` supports click-to-jump: a left click converts the click
  position to a grid cell (`position / CELL_PX`, floored) and sets
  `_camera.position` via `IsoGrid.grid_to_screen`, recentering the main
  view there.

In `main.tscn` it's the `Minimap` node under
`MinimapLayer/Root/Center/Panel/Margin/VBox`, where `MinimapLayer` is a
`CanvasLayer` and `Root` is a `Control` (`visible = false` by default)
containing a dim `ColorRect` backdrop plus a centered panel with a title
label and the `Minimap` itself. `main.gd` toggles `_minimap_root.visible`
on `M`; `Esc` closes the minimap first if it's open, only falling through
to canceling build mode when it's already closed.

## UI layer

As of a post-M9 UI restructure, three concerns that used to live in the
sidebar have moved out to where they're more naturally read: colony-wide
numbers to the top bar, help to a popup, and building/tile info to a
cursor-following hover panel. The sidebar is left as a pure command
surface — what mode you're in and what you can build — not a dashboard.
Click-to-select is gone entirely: hovering now shows the same facts a click
used to select, so there's no separate "select" state to maintain.

`ui/sidebar.gd` (on `ui/sidebar.tscn`, a `PanelContainer`) is a "Dune
II"-style fixed right-hand command panel, instanced under a `CanvasLayer`
(`UI`) in `main.tscn` so it draws in screen space above the game world. It
is 240px wide. `_ready()` assigns the Sidebar a `Theme` with
`default_font_size = 14` (down from the engine default 16); since a
Theme's default size propagates to every descendant, this shrinks every
sidebar label and build button in one place, except the Title, which keeps
its own explicit 18px `font_size` override. It holds no game logic — it
only displays state pushed into it and emits signals for user intent:

- Only the **build list** scrolls, not the whole sidebar. `Margin/VBox`
  holds Title, ModeLabel, SpeedLabel, and BuildHeader as static children,
  plus a `ScrollContainer` (`Margin/VBox/Scroll`, `size_flags_vertical = 3`
  so it fills the remaining height, horizontal scrolling disabled) wrapping
  just `BuildList`, with the Demolish button pinned static above it. The UI
  restructure removed the TILE/POWER/COLONISTS/SELECTED sections and the
  static controls-hint paragraph that used to sit here (moved to the top
  bar / hover panel / help popup respectively), so the sidebar's
  `@onready` set is now just `_title`, `_mode`, `_speed`, `_build_header`,
  `_build_list`, `_demolish`.
- `populate(buildings: Dictionary)` builds one `Button` per entry in
  `Defs.buildings`, each emitting `build_requested(type_id)` when pressed.
  Buttons are single-line (`"%s  ·  %s" % [name, cost]`) with
  `clip_text = true` so a long name/cost combination truncates instead of
  wrapping or overflowing the narrower scrollable column. As of the pre-M6
  balance pass, each button is also kept in `_build_buttons: Dictionary`
  (id → `Button`), and its label/desc text is cached on the button itself
  via `set_meta("label", ...)`/`set_meta("desc", ...)` rather than set
  directly, so `set_locks` (below) can rewrite the visible text/tooltip
  without needing to recompute the base strings.
- `set_locks(locks: Dictionary)` (pre-M6 balance pass; id → reason string,
  `""` = unlocked) disables (`Button.disabled = true`) every button whose
  id has a non-empty reason, appends `"  🔒"` to its label, and sets its
  tooltip to the reason (an unlocked button's tooltip reverts to the
  building's `desc`). Called by `main.gd`'s `_refresh_locks()`.
- `set_mode_label(text)` is pushed by `main.gd` every frame.
- `set_speed(speed)` (formerly `set_economy`, before power/colonist stats
  moved to `ResourceBar`) is pushed every frame by `main.gd`; renders the
  speed label as `❚❚ PAUSED` or `▶ Nx`.
- A Demolish button emits `demolish_requested()`.

`main.gd` connects `build_requested`/`demolish_requested` to switch its own
`Mode` enum (`NONE`/`PLACE`/`DEMOLISH`) and never reaches into the
sidebar's internals beyond those signals and setters.

### Top status bar (`ResourceBar`)

`ui/resource_bar.gd` (a `PanelContainer` under `UI/ResourceBar` in
`main.tscn`) spans the top of the screen, anchored from the left edge to
the sidebar (`offset_right = -240`). It now holds three groups inside
`Margin/HBox`: `Resources` (the original stockpile glyphs), a flexible
`Spacer`, and `Stats` (colony-wide numbers + help button), right-aligned.
Like the sidebar it holds no game logic:

- `populate(resources: Dictionary)` builds one hidden `Label` per entry in
  `Defs.resources` into the `Resources` box (skipping `power`, which is a
  capacity balance rather than a stockpiled good and is covered by
  `set_stats()` instead), tinted from the `color` field in
  `data/resources.json` (parsed with `Color.html`) and remembering its
  `glyph` as node metadata. Each label's `tooltip_text` is set to
  `"<name>\n<desc>"` from `data/resources.json`'s `desc` field, with
  `mouse_filter = Control.MOUSE_FILTER_STOP` so hovering a glyph pops up
  its name and a one-line description.
- `set_resources(stock, rates, caps)`, pushed every frame by `main.gd`
  (`caps` built from `Colony.storage_for()` per resource id), shows each
  label as `"<glyph> <amount>"`, switching to `"<glyph> <amount>/<cap>"`
  once `amount` is within 80% of `cap`, plus a `"  %+.1f"` rate suffix
  when the rate is non-negligible (e.g. `⬢ 185`, `≈ 100/100 -0.3`), and
  hides a resource entirely while the colony has none of it and no
  meaningful rate — so ore/parts/xenite stay hidden until the production
  chain that makes them comes online. The label's font color (stashed as
  `tint` metadata in `populate()`) switches to `AMBER` at `amount >= cap`,
  the same "full" signal a stalled building's `idle_reason` gives, so a
  line jammed for want of room is visible without hovering it.
- `set_stats(power_produced, power_consumed, population, capacity,
  workers_used)` — the colony's two standing numbers, formerly the
  sidebar's POWER and COLONISTS sections. Pushed every frame by `main.gd`.
  Renders `"⚡ <consumed>/<produced>"` (red when consumption exceeds
  production, same as before) and `"☻ <population>/<capacity>  ⚒
  <workers>"` (amber at/over capacity).
- A `help_requested()` signal, emitted by the `?` button (`_help.pressed`);
  `main.gd` connects it to `_toggle_help()` (see below).

### Help popup (`HelpLayer`, `main.gd`)

The sidebar's permanently-wrapped hint paragraph — read once, then a
standing cost in panel height — is gone, replaced by a popup behind the
top bar's `?` button or the `H` key. `HelpLayer` in `main.tscn` follows the
same backdrop-plus-centered-panel pattern as the minimap and system menu
(`HelpLayer/Root`: a dim `ColorRect` backdrop, a `CenterContainer` holding
a titled `PanelContainer` with a `Body` label and a Close button).
`main.gd` holds the copy as a single `HELP_TEXT` constant (MOUSE / CAMERA
/ OVERLAYS / TIME sections, ending with the "prospect before you build"
advice) assigned to the body label in `_ready()`. `_toggle_help()` flips
`_help_root.visible`; `H` toggles it, `Esc`/the Close button close it
(checked before the normal input `match`, same pattern as the system
menu). While it's open the hover panel is hidden (see below) so nothing
chases the cursor behind a modal.

### Hover panel (`ui/hover_panel.gd`)

`HoverPanel`, a `PanelContainer` under `UI` in `main.tscn`, is the
replacement for the sidebar's old TILE and INSPECT sections and for
click-to-select: it follows the cursor and shows whatever tile is under
it — terrain, `ColonyMap.reading_text()`, and, if a building sits there,
`Colony.building_report()` rendered the same way the old sidebar inspector
did (running/idle line first, then power/workers/capacity/life
support/scans, a "stores <res> <n>, ..." line for any building with a
non-empty `storage` block, then recipe or mine progress, then the terrain
line).
Screen-space and stateless like the other UI panels: `main.gd` pushes the
hovered tile's report each frame via `show_tile(terrain, reading, report)`;
it never reads `Colony` itself.

`top_level = true` positions it in screen space regardless of its parent's
layout, and every node in it has `mouse_filter = MOUSE_FILTER_IGNORE` so it
can sit directly under the cursor without swallowing clicks meant for the
map beneath it. `place_at(cursor)` calls `reset_size()` before
repositioning — without that a Godot `Control` keeps the largest size it
has ever needed, so moving from a building's multi-line readout onto bare
ground would otherwise leave a stale, mostly-empty box hanging off the
cursor — then flips to the cursor's left/above when the panel would run
off the right/bottom edge (`EDGE_MARGIN = 8px`), and clamps into the
viewport as a last resort.

`main.gd`'s `_update_hover_panel(terrain, reading)`, called from
`_update_info()` every frame, hides the panel (`hide_info()`) whenever the
cursor is over UI, off the map, or a modal overlay (minimap, system menu,
help, game-over) is showing — a panel chasing the mouse across a full-
screen backdrop would just be noise — otherwise looks up
`Sim.building_at(_hover)` and calls `show_tile()`. Because this replaces
selection, `main.gd` no longer has a `_selected_id` field, and a left
click in `Mode.NONE` (no build/demolish mode active) does nothing.

## Game root

`main.gd` (on `main.tscn`, the project's `run/main_scene`) is the current
top-level scene and game controller. On `_ready()` it calls
`Sim.new_game(DEFAULT_SEED, MAP_SIZE)` (seed `1337`, 64×64), hands the
resulting map to `TerrainView` to render, calls `_prospect.setup(_map)`
(Milestone 4), calls `BuildingsView.bind()`, centers the `IsoCamera`, wires
up the sidebar (`populate`, `build_requested` → enter place mode,
`demolish_requested` → enter demolish mode), calls
`_minimap.setup(_map, _camera)`, connects `Events.game_over` to
`_on_game_over` (Milestone 5), connects `Events.building_placed` to a
lambda that calls `_refresh_locks()` (pre-M6 balance pass — a newly placed
building can unlock others further down the tech tree, so the whole build
menu's lock state is recomputed), calls `_refresh_locks()` once up front,
and enters `Mode.NONE`. `_refresh_locks()` itself builds an id → reason
`Dictionary` from `Sim.colony.missing_prereqs(id)` for every entry in
`Defs.buildings` (an empty reason for an unlocked building) and hands it
to `sidebar.set_locks()`.

Each frame (`_process`) it converts the mouse position to a grid cell via
`IsoGrid.screen_to_grid`, updates `TileCursor.cell`, hides the cursor when
the mouse is over a UI control (`get_viewport().gui_get_hovered_control()`),
updates the placement ghost (visible + repositioned + validity-tinted only
in `Mode.PLACE` and only over the map — as of the pre-M6 fixes pass, via
`_ghost.set_cells(Sim.colony.footprint(_place_type, _hover))` rather than a
single-cell/single-origin call, so a multi-tile ghost previews its whole
footprint, not just its origin tile), and calls `_update_hover_panel(terrain,
reading)` (see "Hover panel" above) with `_map.reading_text(_hover)`, the
prospecting reading for the hovered cell. It also (as of Milestone 3) reads
`Sim.colony.rates()` — per-tick — and multiplies each value by
`Sim.ticks_per_second` to get a per-second figure before calling
`_resource_bar.set_resources(stockpile, per_sec)` and (post-M9 UI
restructure) `_resource_bar.set_stats(power_produced, power_consumed,
population, capacity, workers_used)`; this conversion happens here, in the
render/UI layer, precisely so `Colony` itself never needs to know about real
time or the UI. It also calls `sidebar.set_speed(Sim.speed)` every frame.
Finally it refreshes the F1 debug label.

**Game over (Milestone 5)**: `_on_game_over(won: bool)`, connected to
`Events.game_over`, sets the game-over panel's title to "BEACON LAUNCHED"
(win) or "COLONY LOST" (loss), a matching subtitle plus "Press Enter to
start a new colony.", and shows `_gameover_root`. `_unhandled_input`
checks `_gameover_root.visible` first, before the normal input `match`: while
it's visible, `Enter`/numpad-`Enter` calls `get_tree().reload_current_scene()`
(a full scene reload — simplest possible restart, no partial-state
cleanup needed since `_ready()` re-does all setup including a fresh
`Sim.new_game()`) and every other key is swallowed; mouse clicks aren't
separately blocked here, but since `Sim._process` has already frozen the
tick loop once the colony reaches a terminal state, clicking around behind
the overlay can't mutate a live game.

Input (`_unhandled_input`) is skipped for mouse clicks that landed on UI.
Left-click places (in `PLACE` mode) or demolishes (in `DEMOLISH` mode) at
the hovered cell via `Sim`; in `Mode.NONE` it does nothing (see "Hover
panel" above — there is no click-to-select anymore). Right-click cancels
the current mode if one is active, otherwise demolishes at the hovered
cell directly; F1 toggles the debug overlay (`$Debug/Label` — cell coords,
terrain name, zoom level, seed, FPS); `H` toggles the help popup
(`_toggle_help()`); `M` toggles `_minimap_root.visible`; `P` calls
`_toggle_prospect()` (Milestone 4 — flips `_prospect.visible` and calls
`_prospect.rebuild()` when turning it on, so the overlay reflects the
latest scan state even if it missed incremental `scan_changed` updates
while hidden); Escape closes the help popup first if it's open, then the
minimap, otherwise cancels the current mode to `Mode.NONE`; Space calls
`Sim.toggle_pause()`;
`1` and `3` call `Sim.set_speed(1.0)` / `Sim.set_speed(3.0)` directly. Zoom
(`Z`, pinch, `+`/`-`) is handled entirely inside `IsoCamera` itself, not
here. The debug overlay is intentionally meant to stay available for the
life of the project — the plan calls out coordinate conversion as the
first thing to suspect when on-screen visuals look wrong.

## Folder layout

```
data/       JSON content definitions: resources.json, buildings.json, audio.json, balance.json
sim/        Pure sim logic and state: sim.gd, defs.gd, events.gd, map.gd, iso_grid.gd, colony.gd, alerts.gd, balance.gd
render/     Views of sim state: terrain_view.gd, prospect_overlay.gd, building_sprite.gd, buildings_view.gd, tile_cursor.gd, iso_camera.gd, minimap.gd, status_overlay.gd, palette.gd
ui/         Screen-space UI: sidebar.gd / sidebar.tscn, resource_bar.gd, hover_panel.gd, alert_ticker.gd
audio/      View-layer sound: audio.gd (Audio autoload), audio_cues.gd (AudioCues)
tools/      Asset generators: gen_audio.py (run via `make audio`)
assets/     Committed art (PNG + Godot .import sidecars) and audio/ (WAV + .import sidecars)
tests/      Headless tests: run_tests.gd (runner) + test_*.gd files
dist/       Player-facing READ-ME-FIRST-{macos,windows,linux}.txt, bundled into each export zip
main.gd / main.tscn   In-game scene and controller
menu.gd / menu.tscn   Main menu (project's run/main_scene): new/continue/load/quit
```

`assets/` (Milestone 8 asset-integration step) holds the project's
committed art: PixelLab-made PNGs for **all 11 buildings** — `hub`,
`mine`, `smelter`, `electrolysisplant`, `hydroponics` (first wave) plus
`solar`, `prospector`, `crystalextractor`, `habitat`, `partsfactory`,
`iceharvester` (second wave) — plus their Godot `.png.import` sidecars;
the sidecars aren't gitignored (only `.godot/` is) since Godot needs them
to know how to import each texture. Authoring convention: the footprint
diamond sits at the **bottom** of the canvas, horizontally centred, with
the structure rising into transparent space above (matches
`BuildingSprite`'s bottom-vertex anchoring — see "Rendering and camera"
below); RGBA PNG at the tile's native pixel size (64×64 for a 1×1
footprint, 128×128 for 2×2), since the project runs nearest-neighbor
filtering with pixel snap.

## Running and testing

- `make run` — runs the game (`godot --path .`).
- `make editor` — opens the project in the Godot editor.
- `make build` / `make import` — headless import: builds the `.godot` cache
  and fails on script/asset errors (`godot --headless --editor --quit`).
- `make test` — runs the headless test suite
  (`godot --headless --path . --script res://tests/run_tests.gd`) and exits
  non-zero on any failure, so it's CI-friendly.
- `make audio` — regenerates every WAV under `assets/audio/`
  (`python3 tools/gen_audio.py`, stdlib-only, no downloaded assets).
- `make export` / `make release` — builds the distributable zips (macOS/
  Windows/Linux); `release` runs `make test` first. See `DISTRIBUTING.md`
  for what ships and how players get past the unsigned first-run warning.
  Export config lives in `export_presets.cfg` (committed) and player-facing
  text in `dist/`; build output goes to `build/` (gitignored).
- `make clean` — removes the `.godot` generated cache and `build/`.

All targets wrap the `godot` binary; override the binary path with
`make run GODOT=/path/to/godot` if it isn't on `PATH`.

### How the test harness works

`tests/run_tests.gd` is a `SceneTree`-based headless runner. It scans
`tests/` for every file named `test_*.gd`, instantiates it, and calls every
method on it named `test_*`, passing a `Tester` helper (`t.ok(cond, msg)`,
`t.eq(a, b, msg)`) that tests use for assertions. It prints a summary line
(`== N assertions across M tests, K failures ==`) and exits with status 1 if
any assertion failed, 0 otherwise. Test files are plain `RefCounted` scripts
with no special base class or registration step — dropping a new
`tests/test_whatever.gd` file with `test_*` methods is enough for it to be
picked up automatically.

Current suite: `tests/test_defs.gd` (resources.json shape/uniqueness),
`tests/test_map.gd` (`ColonyMap` dimensions, terrain id validity,
determinism, variety), `tests/test_iso_grid.gd` (`IsoGrid` vs. Godot's real
`TileMapLayer` math), `tests/test_placement.gd` (`Colony` placement,
occupancy, and demolish rules), `tests/test_economy.gd` (`Colony.tick()`:
production accrual, power-deficit shutdown, newest-first shedding, recipe
stalling on missing inputs, active-only `rates()` — its `_colony()` helper
sets `population = 0` on the returned `Colony` so life support doesn't
interfere with these building-economics-only tests), `tests/test_camera.gd`
(`IsoCamera` zoom: `Z` toggles 1×↔2× and snaps back from higher zoom, a
`KEY_Z` event toggles it, pinch still fine-zooms, and a trackpad
pan-gesture no longer changes zoom), `tests/test_prospecting.gd`
(deposit generation determinism/coverage, fresh-map unscanned state, a
survey station's coarse-then-confirmed two-sweep revelation, outward ring
expansion, `scan_changes` reporting, mine placement gating on confirmed
matching deposits; finite-deposits rework additions: richness sizes the
reserve rather than the rate, a worked-out tile idles with the right
reason and never yields more than its reserve held, survey stations must
stand in existing coverage, confirming a deposit is far slower than first
finding it and the resampling sequence is deterministic across a replay,
every crystal tile holds xenite and nowhere else does, and a formation's
reserve is hidden until confirmed), `tests/test_colonists.gd`
(life support is consumed, sustained starvation kills a colonist, growth
happens when fed/housed/under capacity, no growth once at capacity,
workforce idles the newest understaffed building on a labor deficit,
victory triggers at the xenite target, defeat triggers at population
zero), `tests/test_tech.gd` (a building with no prerequisites is unlocked
from the start; one with a prerequisite is locked until it's built and
`can_place()` rejects it while locked; `missing_prereqs()` reports
correctly before/after; an unlock survives demolishing the prerequisite;
a two-step prerequisite chain unlocks in order), `tests/test_balance.gd`
(a regression guard for the metal-cliff fix — sums the metal cost of a
minimal self-sustaining bootstrap build order and asserts it fits inside
the real `data/balance.json`'s starting metal with headroom to spare; see
"Balance regression testing" below), `tests/test_alerts.gd` (`AlertMonitor`: power
deficit fires once on the edge and doesn't repeat while sustained, a low
life-support resource warns and re-arms after recovery, a confirmed
deposit announces once per kind), `tests/test_inspector.gd`
(`Colony.building_report()`: idle reasons for no-power/no-workers/stalled
recipe, running state and recipe progress, mine resource/richness/rate,
and `{}` for a demolished/unknown id) — the
placement/economy/camera/prospecting/colonist/tech/balance/alerts/inspector
files are built with hand-rolled defs dictionaries or constructed
nodes/maps, independent of `Defs`/`Sim`/a running scene. `test_alerts.gd`
also covers the broadened low-stock rule (a metal-draining building on a
non-life-support resource triggers a warning). `tests/test_save.gd`
(Milestone 7) covers `ColonyMap`/`Colony` `to_dict`/`from_dict` round-trips
(every cell's terrain/deposit/scan/richness, and a JSON-text round-trip on
top of that; population/stockpile/buildings/next_id/occupancy/mine-deposit
all restored) plus a determinism check that a `from_dict`'d colony ticks
identically to the original. `tests/test_hub.gd` (Colony Hub rework) covers
the Hub's forgiveness mechanics: it sustains the base 4 colonists with an
empty stockpile, colonists beyond that coverage still consume normally,
covered colonists show no drain in `rates()`, placing the Hub injects an
iron deposit when none is reachable within its scan radius, and an
already-reachable deposit isn't duplicated; finite-deposits rework
additions cover the hub being free/unique/required — placeable with an
empty stockpile, a second refused and greyed out in the build menu,
demolishing and rebuilding it recovers a colony that went idle without
one, and a defs dictionary with no `colony_controller` declared is
unaffected by the whole rule. `tests/test_balance.gd` was updated for the
new bootstrap (Hub + Mine + Smelter now fits the reduced 120 starting
metal with headroom) and gained a check that every non-`hub` building's
`requires_built` chain roots at `hub`.
`tests/test_building_fx.gd` (Milestone 8 art) covers the `fx` JSON contract
and the lamp blink curve. `tests/test_audio.gd` (Milestone 8 audio) covers
the cue manifest contract (every required cue defined, files exist, valid
bus/volume/pitch ranges, only the ambient bed loops) and the alert/
game-over cue mapping, including out-of-range level clamping.
`tests/test_tuning.gd` (Milestone 9, see "Tuning" above) covers the
`Balance`/`balance.json` contract: the shipped file parses; an empty
override reproduces the defaults; a partial override touches only what it
names; JSON numbers keep their int/float type; a tuned `Balance` reaches a
`Colony`; and sanity guards on the shipped values. 1182 assertions across
111 tests, 0 failures.

### Balance regression testing

`tests/test_balance.gd` is a different shape from the other test files:
instead of constructing a `Colony`/`ColonyMap` with hand-rolled defs, it
reads the *real* `data/buildings.json` (via `FileAccess` + `JSON.parse_string`,
the same way `Defs._load_json` does) and the *real* `data/balance.json`
(parsed the same way, through `Balance.from_dict`), then asserts a fact
about actual shipped balance numbers (a specific bootstrap build order's
total metal cost fits inside the actual starting metal, with headroom).
Before Milestone 9 this had to scrape the starting-metal figure out of
`sim.gd`'s source text with a regex, since `STARTING_STOCKPILE` lived in an
autoload script that can't be `load()`-ed standalone in a headless test
(it references other autoloads that don't resolve outside the autoload
environment `run_tests.gd` runs in); now that the number lives in a plain
JSON file, the test reads it directly with no such workaround needed.
