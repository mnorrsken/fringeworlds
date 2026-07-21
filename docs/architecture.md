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

## The three autoloads

Registered in `project.godot` under `[autoload]`, in load order:

1. **`Events`** (`sim/events.gd`) — a global signal bus. Defines
   `ticked(tick: int)`, `stockpile_changed(stockpile: Dictionary)`,
   `building_placed(instance: Dictionary)`,
   `building_removed(instance: Dictionary)`, (Milestone 4)
   `scan_changed(cells: Array)`, and (Milestone 5) `game_over(won: bool)`.
   The sim emits; UI/render layers connect. UI is meant to never poke
   `Sim` internals directly — it calls `Sim` methods and listens on
   `Events` signals instead. The `building_placed`/`building_removed`
   payload is the same instance dictionary `Colony.place()`/
   `demolish_at()` returns: `{id, type, origin, cells}`. `scan_changed`'s
   payload is the list of grid cells whose prospecting scan state changed
   on the tick just processed; `ProspectOverlay` is the only current
   listener, using it to repaint incrementally instead of rebuilding the
   whole overlay every tick. `game_over` fires exactly once when the
   colony reaches a terminal state; `main.gd` is the only listener, and
   shows the win/loss overlay from it.
2. **`Defs`** (`sim/defs.gd`) — loads read-only content definitions from
   `data/*.json` at startup into two dictionaries: `resources` (id →
   definition, unchanged since Milestone 0) and `buildings` (id →
   definition). `_load_buildings` post-processes each building entry after
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
   `data/buildings.json`, not this script.
3. **`Sim`** (`sim/sim.gd`) — game state and the fixed tick loop, plus the
   live `Colony` (since Milestone 2). `new_game(seed, size)` generates a
   `ColonyMap`, constructs `colony := Colony.new(map, Defs.buildings,
   STARTING_STOCKPILE)`, and resets the tick counter. As of Milestone 5,
   `STARTING_STOCKPILE` is `{metal: 100, oxygen: 60, water: 60, food: 60}`
   — the life-support buffer exists so a new colony survives long enough
   to get its first O2/water/food buildings running before colonists
   starve — and `new_game()` also resets `_ended`, the tick accumulator,
   and `speed` back to `1.0`, so restarting after a game-over isn't left
   paused or fast-forwarded. `colony` is `null` until `new_game()` is
   called. `Sim` exposes thin wrapper methods over `Colony`'s placement
   API — `can_place`, `place_building`, `demolish_at`, `building_at` —
   that delegate to `colony` and then emit the matching `Events` signal
   (`building_placed`/`building_removed`/`stockpile_changed`) on success,
   so `Colony` itself stays free of any signal-bus dependency. The tick
   loop runs at `TICKS_PER_SECOND = 4.0`, accumulator-driven inside
   `_process` so ticks stay decoupled from frame rate; `_process` now also
   checks `colony.status` both before and inside the accumulator loop
   (Milestone 5) so once the colony reaches a terminal state, no further
   ticks run in that frame or any later one. `_advance_tick()` calls
   `colony.tick()` (see below) before emitting `Events.stockpile_changed`
   and `Events.ticked`. `_end_game()` emits `Events.game_over(won)` the
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
meant to live in JSON under `data/`, not in engine code. Two files exist so
far:

- `data/resources.json` — an array of 9 objects (`id`, `name`, `category`,
  `unit`), loaded into `Defs.resources`.
- `data/buildings.json` — an array of 10 building objects (up from 6 as of
  Milestone 5): `solar_panel` and `ice_harvester` (1×1), `habitat` and
  `survey_station` (2×2), `mine` and `crystal_extractor` (1×1), plus four
  new production-chain buildings — `electrolysis_plant` (1×1,
  water→oxygen), `hydroponics_farm` (2×2, water→food), `smelter` (2×2,
  iron_ore→metal), `parts_factory` (2×2, metal+copper_ore→parts). All four
  are built entirely on the existing `recipe` mechanism — no engine
  changes were needed to add a production chain, only JSON. Fields: `id`,
  `name`, `size`, `cost`, `allowed_terrain`, `color`, `desc`, `power` (int;
  positive = generator, negative = consumer, every building declares one),
  optionally `recipe` (`{inputs: {...}, outputs: {...}, ticks: int}`),
  `scan` (survey buildings), `mine`/`requires_deposit` (extractors — see
  "Deposits and prospecting" below). Milestone 5 added two more fields:
  `workers` (int; every building now declares one, `0` for unstaffed
  buildings like Solar Panel and Habitat) and `capacity` (int, housing
  added by the building — only `habitat`, at `6`). `crystal_extractor`'s
  `cost` now also requires `parts: 8`, so it needs the full chain (mine →
  smelter → parts factory) to reach, not just raw metal. Loaded into
  `Defs.buildings` and augmented with
  `allowed_terrain_ids`/`color_value`/`requires_deposit_ids` as described
  above (`workers`/`capacity` need no preprocessing — `Colony` reads them
  as plain ints). Adding a building, or a recipe/scan/mine block to an
  existing one, is a matter of editing JSON — no script changes needed,
  since `Colony.tick()`, `BuildingSprite`, and the sidebar's build menu all
  read generically off the def dictionary.

There is no separate `data/recipes.json` — recipes live inline on the
building that runs them, one recipe per building, which is enough for the
single-tier production so far. A dedicated recipes file may still arrive if
buildings need to switch between multiple recipes later.

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
Once `progress >= recipe.ticks`, it checks whether `recipe.inputs` are
affordable in the stockpile: if so, it spends the inputs, adds the outputs,
and resets `progress` to `0`; if not, it **stalls** — holds `progress` at
the threshold (doesn't consume, doesn't reset, doesn't lose the built-up
progress) until inputs become available on a later tick. Inactive
(unpowered) buildings don't advance `progress` at all, so a power outage
doesn't cause a burst of production the instant power returns.

Since Milestone 4, `_run_production` special-cases buildings with a `mine`
def block (extractors — see below) before the recipe branch, calling
`_run_mine(inst, def)` and skipping the recipe logic entirely for them.

**`rates()`** returns the net stockpile change **per tick** (not per
second) summed across only currently-active buildings — `{resource_id:
float}`, positive for net production, negative for net consumption. It
covers recipe-based production, (Milestone 4) extractor output
(`_mine_per_tick`, the same formula `_run_mine` uses), and (Milestone 5)
life-support consumption (`population * LIFE_SUPPORT[res]`, subtracted for
oxygen/water/food whenever `population > 0`) — so the HUD's per-resource
rate is the true net figure, not just what buildings are doing. Callers
that want a per-second figure for display multiply by
`Sim.TICKS_PER_SECOND` themselves (see `main.gd` below); `Colony` has no
concept of real time, only ticks.

## Colonists, life support, and win/lose (`Colony`, Milestone 5)

`Colony` tracks `population: int` (starts at `STARTING_POPULATION = 4`)
and `status: int` (`enum Status { PLAYING, WON, LOST }`). Related
constants: `BASE_CAPACITY = 4` (housing the colony ship itself provides,
before any habitat), `STARVE_TICKS = 16` (~4s of real time at 1× speed),
`GROWTH_TICKS = 80` (~20s), `VICTORY_XENITE = 50`, and `LIFE_SUPPORT =
{oxygen: 0.03, water: 0.03, food: 0.02}` (consumption per colonist per
tick).

- **`capacity()`** — `BASE_CAPACITY` plus every placed building's
  `capacity` field (only `habitat` declares one, at `6`). Not cached;
  recomputed on call by summing over `buildings`.
- **`_run_life_support()`** — for each of oxygen/water/food, adds
  `population * LIFE_SUPPORT[res]` to a per-resource fractional
  accumulator (`_life_accum`, mirroring the pattern `_run_mine` uses for
  fractional ore output), then withdraws whatever whole units it can
  afford from the stockpile (never going negative — it takes `min(whole,
  have)`). If it couldn't take the full amount, or the stockpile is
  already at zero for that resource (checked as an independent condition,
  so a resource that's been fully drained is an immediate shortage even
  before the accumulator would otherwise cross a whole unit), the tick
  counts as unmet. A fully-met tick resets `_starve_ticks` to `0` and, if
  `population < capacity()`, increments `_growth_ticks` — reaching
  `GROWTH_TICKS` resets it and adds one colonist. An unmet tick resets
  `_growth_ticks` to `0` and increments `_starve_ticks` — reaching
  `STARVE_TICKS` resets it and removes one colonist. Both are streak
  counters, not cumulative totals: a single good/bad tick doesn't
  immediately grow or kill anyone, but breaks the *other* streak.
- **`_check_status()`** — a no-op once `status` has already left
  `PLAYING`. Otherwise: `population <= 0` → `Status.LOST`; stockpiled
  `xenite >= VICTORY_XENITE` → `Status.WON`. Checked last in `tick()`,
  after production and life support have both run for that tick.

## Deposits and prospecting (`ColonyMap` + `Colony`, Milestone 4)

This is the game's signature mechanic: subsurface resources are hidden
until surveyed, and extraction is gated on a confirmed reading.

**Hidden layers on `ColonyMap`** (`sim/map.gd`), parallel to the terrain
`PackedByteArray` and indexed the same way:

- `_deposit` (`PackedByteArray`) — one of `enum Deposit { NONE, IRON,
  COPPER, XENITE }` per cell. Hidden; `get_deposit(cell)` reads it, but
  nothing renders it directly until a scan confirms it.
- `_richness` (`PackedFloat32Array`) — `0.0`–`1.0` per cell, how much a
  matching extractor produces there. Hidden the same way.
- `_reading_noise` (`PackedFloat32Array`) — a fixed per-cell random value
  in `-1.0..1.0`, generated once at map creation from a seeded
  `RandomNumberGenerator`. `coarse_richness(cell)` adds
  `noise * READING_JITTER` (`0.25`) to the true richness and clamps to
  `0.05..1.0`, so a coarse scan reports a plausible-but-imprecise number
  that's deterministic (not re-rolled) for a given cell and seed.
- `_scan` (`PackedByteArray`) — one of `enum Scan { UNSCANNED, COARSE,
  CONFIRMED }` per cell. This is the *revealed* layer — the only one that
  changes during play, via `set_scan(cell, state)`.

**Deposit generation** (`_generate_deposits`, called from `generate()`
after terrain): one low-frequency `FastNoiseLite` field per deposit type
(`IRON`/`COPPER`/`XENITE`, each seeded `p_seed + dep * 101` so they're
independent), each with its own threshold. Only cells already terrain
REGOLITH or HIGHLANDS are eligible. For each eligible cell, the winning
deposit is whichever field's value clears its threshold by the largest
margin (ties/no-clears → `Deposit.NONE`); richness is derived from that
margin (`clampf(0.2 + margin * 1.6, 0.1, 1.0)`). This produces
naturally blob-shaped deposits without an explicit blob/flood-fill
algorithm, and is fully deterministic per seed — pinned by
`tests/test_prospecting.gd`'s `test_generation_is_deterministic`.

**Survey scanning** (`Colony._run_prospecting` / `_scan_ring`, in
`sim/colony.gd`): a survey building (any def with a `scan` block —
currently only `survey_station`, with `max_radius: 7, ticks_per_ring: 2`)
sweeps an expanding ring outward from its footprint center. Each active
survey building's `scan_progress` (a per-instance counter, alongside
`scan_ring`, both initialized in `place()`) advances one per tick; once it
hits `ticks_per_ring`, `_scan_ring` processes the current ring — every
cell whose rounded distance from center equals `scan_ring` — and advances
each such cell's scan state one step (`UNSCANNED→COARSE` or
`COARSE→CONFIRMED`; a cell already `CONFIRMED` is left alone). Every cell
actually advanced is appended to `Colony.scan_changes` (reset to `[]` at
the top of every `tick()`). Once `scan_ring` exceeds `max_radius`, it
resets to `0` and the sweep restarts from the center — so a tile visited
by the first sweep (coarse) gets upgraded to confirmed on the second. This
is why the acceptance criteria's "progressively reveals coarse then
confirmed" holds: it's not two different mechanisms, just the same ring
sweep run twice.

**Extractor gating and output**: any building def with `requires_deposit_ids`
(resolved by `Defs` from `requires_deposit`, see above) can only be placed
where `Colony.can_place()` finds `map.get_scan(origin) ==
ColonyMap.Scan.CONFIRMED` *and* `map.get_deposit(origin)` is one of the
required types — all extractors are 1×1, so `origin` is the only cell to
check. On placement, `place()` latches `deposit_type`, `richness`, and a
`mine_accum` float onto the instance — the deposit is fixed at build time,
not re-read every tick. `_run_mine` (called from `_run_production` for any
`active` building with a `mine` def block) adds `base_per_tick * richness`
to `mine_accum` every tick and pays out whole units to the stockpile
resource (`ColonyMap.DEPOSIT_RESOURCE[deposit_type]`) once the accumulator
crosses `1.0`, carrying the fractional remainder forward — so a richness-1.0
deposit visibly produces roughly twice as fast as a richness-0.5 one over
many ticks, without ever paying out a fraction of a resource unit.

`Sim._advance_tick()` emits `Events.scan_changed(colony.scan_changes)`
after `colony.tick()`, but only when the list is non-empty, so idle ticks
(no active survey buildings, or a survey mid-ring with nothing left to
reveal) don't spam the signal.

## Rendering and camera

- `render/terrain_view.gd` (`TerrainView`) builds its own placeholder iso
  tileset in code (`_build_tileset` / `_build_atlas` / `_draw_diamond`) —
  one shaded diamond per `ColonyMap.Terrain` enum value, drawn into an
  `ImageTexture` at runtime. No external art files are committed yet; this
  is explicitly a Milestone-8 replacement target.
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
- `render/building_sprite.gd` (`BuildingSprite`, extends `Node2D`) draws one
  placed building or the placement ghost as a flat-shaded iso block: a lit
  top face plus two darkened side walls (`WALL_H = 16.0` px tall), sized to
  the building's footprint. `configure(def, origin, ghost)` sets it up from
  a `Defs.buildings` entry; `set_origin()` moves it (used every frame for
  the ghost following the cursor); `set_valid()` switches the ghost's
  green/red tint (`_ghost=true` also applies a semi-transparent modulate);
  `set_dimmed(dimmed)` (Milestone 3) applies a flat grey modulate to a
  placed (non-ghost) building that's currently shut down — a no-op if
  called on a ghost. Its node `position` is pinned to the footprint's front
  (max-corner) tile via `IsoGrid.grid_to_screen`, which is what makes
  y-sorting order multi-tile buildings correctly against each other.
- `render/buildings_view.gd` (`BuildingsView`, extends `Node2D`) has no
  `_process`/state of its own — `bind()` connects to
  `Events.building_placed`/`building_removed` and, as of Milestone 3,
  `Events.ticked`, and backfills sprites for any buildings already in
  `Sim.colony.buildings` (needed because it binds after `Sim.new_game()`
  has already placed nothing, but is defensive for future load-game
  flows). Sprites are tracked in a `Dictionary` keyed by building instance
  id so removal is O(1). Its `_on_ticked` handler walks every tracked
  sprite each tick and calls `set_dimmed(not inst.active)` against the
  live `Colony` instance, so power-driven shutdowns become visible without
  `BuildingsView` running any economy logic itself.
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

`ui/sidebar.gd` (on `ui/sidebar.tscn`, a `PanelContainer`) is a "Dune
II"-style fixed right-hand command panel, instanced under a `CanvasLayer`
(`UI`) in `main.tscn` so it draws in screen space above the game world. It
is 240px wide (widened from 216px in the post-Milestone-3 UI/UX pass so a
scrollbar doesn't clip button text). It holds no game logic — it only
displays state pushed into it and emits signals for user intent:

- Its content (`VBox`) is wrapped in a `ScrollContainer`
  (`Margin/Scroll/VBox`, horizontal scrolling disabled), added in the same
  pass, because the build list previously had no scrolling and buildings
  past the sidebar's ~450px visible height (already true of the 4th
  building) were unreachable. All the `@onready` node paths in
  `sidebar.gd` point through `Scroll` accordingly (e.g.
  `$Margin/Scroll/VBox/Title`).
- `populate(buildings: Dictionary)` builds one `Button` per entry in
  `Defs.buildings`, each emitting `build_requested(type_id)` when pressed.
  Buttons are single-line (`"%s  ·  %s" % [name, cost]`) with
  `clip_text = true` so a long name/cost combination truncates instead of
  wrapping or overflowing the narrower scrollable column.
- `set_mode_label(text)` and `set_tile_info(cell, terrain, occupant,
  reading = "")` are pushed by `main.gd` every frame. The optional
  `reading` parameter (Milestone 4) renders `ColonyMap.reading_text(cell)`
  between the terrain and occupant lines when non-empty — the prospecting
  readout ("coarse: metal traces (~40%)", "Iron Ore · richness 72%",
  etc.).
- `set_economy(stock, rates, power_produced, power_consumed, speed)`
  (replacing Milestone 2's `set_stockpile`) is also pushed every frame by
  `main.gd`, not event-driven — it renders the STOCKPILE section with a
  per-second rate suffix per resource where the rate is non-negligible
  (`%+.1f/s`), the POWER section as `"<consumed> / <produced> used"`
  (colored red when consumption exceeds production), and the speed label
  as `❚❚ PAUSED` or `▶ Nx`.
- `set_colony(population, cap, workers_used)` (Milestone 5, a new
  COLONISTS section) renders `"pop %d / %d"` and `"workers %d / %d"`
  (workers used vs. population, not capacity), turning amber when
  `population >= cap` to flag a crowded colony.
- A Demolish button emits `demolish_requested()`.

`main.gd` connects `build_requested`/`demolish_requested` to switch its own
`Mode` enum (`NONE`/`PLACE`/`DEMOLISH`) and never reaches into the
sidebar's internals beyond those signals and setters.

## Game root

`main.gd` (on `main.tscn`, the project's `run/main_scene`) is the current
top-level scene and game controller. On `_ready()` it calls
`Sim.new_game(DEFAULT_SEED, MAP_SIZE)` (seed `1337`, 64×64), hands the
resulting map to `TerrainView` to render, calls `_prospect.setup(_map)`
(Milestone 4), calls `BuildingsView.bind()`, centers the `IsoCamera`, wires
up the sidebar (`populate`, `build_requested` → enter place mode,
`demolish_requested` → enter demolish mode), calls
`_minimap.setup(_map, _camera)`, connects `Events.game_over` to
`_on_game_over` (Milestone 5), and enters `Mode.NONE`.

Each frame (`_process`) it converts the mouse position to a grid cell via
`IsoGrid.screen_to_grid`, updates `TileCursor.cell`, hides the cursor when
the mouse is over a UI control (`get_viewport().gui_get_hovered_control()`),
updates the placement ghost (visible + repositioned + validity-tinted only
in `Mode.PLACE` and only over the map), and refreshes the sidebar's tile
info — including (Milestone 4) `_map.reading_text(_hover)`, the
prospecting reading for the hovered cell, passed as `set_tile_info`'s new
`reading` argument. It also (as of Milestone 3) reads `Sim.colony.rates()`
— per-tick —
and multiplies each value by `Sim.TICKS_PER_SECOND` to get a per-second
figure before calling `sidebar.set_economy(stockpile, per_sec,
power_produced, power_consumed, Sim.speed)`; this conversion happens here,
in the render/UI layer, precisely so `Colony` itself never needs to know
about real time or the sidebar. As of Milestone 5 it also calls
`sidebar.set_colony(col.population, col.capacity(), col.workers_used())`
every frame. Finally it refreshes the F1 debug label.

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
the hovered cell via `Sim`; right-click cancels the current mode if one is
active, otherwise demolishes at the hovered cell directly; F1 toggles the
debug overlay (`$Debug/Label` — cell coords, terrain name, zoom level,
seed, FPS); `M` toggles `_minimap_root.visible`; `P` calls
`_toggle_prospect()` (Milestone 4 — flips `_prospect.visible` and calls
`_prospect.rebuild()` when turning it on, so the overlay reflects the
latest scan state even if it missed incremental `scan_changed` updates
while hidden); Escape closes the minimap first if it's open, otherwise
cancels the current mode to `Mode.NONE`; Space calls `Sim.toggle_pause()`;
`1` and `3` call `Sim.set_speed(1.0)` / `Sim.set_speed(3.0)` directly. Zoom
(`Z`, pinch, `+`/`-`) is handled entirely inside `IsoCamera` itself, not
here. The debug overlay is intentionally meant to stay available for the
life of the project — the plan calls out coordinate conversion as the
first thing to suspect when on-screen visuals look wrong.

## Folder layout

```
data/       JSON content definitions: resources.json, buildings.json
sim/        Pure sim logic and state: sim.gd, defs.gd, events.gd, map.gd, iso_grid.gd, colony.gd
render/     Views of sim state: terrain_view.gd, prospect_overlay.gd, building_sprite.gd, buildings_view.gd, tile_cursor.gd, iso_camera.gd, minimap.gd
ui/         Screen-space UI: sidebar.gd / sidebar.tscn
tests/      Headless tests: run_tests.gd (runner) + test_*.gd files
main.gd / main.tscn   Current game root and controller
```

`assets/` from the plan's suggested layout doesn't exist yet — it arrives
with Milestone 8 (custom art/audio); all art through Milestone 2 is drawn
procedurally in code.

## Running and testing

- `make run` — runs the game (`godot --path .`).
- `make editor` — opens the project in the Godot editor.
- `make build` / `make import` — headless import: builds the `.godot` cache
  and fails on script/asset errors (`godot --headless --editor --quit`).
- `make test` — runs the headless test suite
  (`godot --headless --path . --script res://tests/run_tests.gd`) and exits
  non-zero on any failure, so it's CI-friendly.
- `make clean` — removes the `.godot` generated cache.

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
matching deposits, and richness-scaled output), `tests/test_colonists.gd`
(life support is consumed, sustained starvation kills a colonist, growth
happens when fed/housed/under capacity, no growth once at capacity,
workforce idles the newest understaffed building on a labor deficit,
victory triggers at the xenite target, defeat triggers at population
zero) — the placement/economy/camera/prospecting/colonist files are built
with hand-rolled defs dictionaries or constructed nodes/maps, independent
of `Defs`/`Sim`/a running scene. 760 assertions across 43 tests, 0
failures as of Milestone 5.
