# Progress log

Status of each milestone from [`colony-game-plan.md`](../colony-game-plan.md).
That file defines the acceptance criteria referenced below — this log tracks
whether they've been met, not what they are.

Current automated test count: **730 assertions across 22 tests, 0 failures**
(`make test`).

---

## Milestone 0 — Project skeleton — done

Deliverables:

- Folder structure in place: `data/ sim/ render/ tests/` (`ui/` and `assets/`
  from the plan's suggested layout didn't exist yet at this point — `ui/`
  arrives with Milestone 2's sidebar; `assets/` is still pending, for
  Milestone 8's art).
- `project.godot` configured for pixel art: 640×360 internal viewport,
  1280×720 window, `stretch/mode=viewport`, nearest-neighbor texture filter,
  2D pixel snap, GL Compatibility renderer.
- Three autoload singletons registered: `Events` (`sim/events.gd`), `Defs`
  (`sim/defs.gd`), `Sim` (`sim/sim.gd`).
- `data/resources.json` — 9 resource definitions, loaded by `Defs` at startup
  and printed to the console as the data-pipeline proof.
- `.gitignore` (ignores `.godot/`), placeholder `icon.svg`.
- `Makefile` with `run`, `editor`, `build`/`import`, `test`, `clean`.
- Headless test harness (`tests/run_tests.gd`) and first test file
  (`tests/test_defs.gd`).

Acceptance criteria from the plan: project opens and runs an empty scene at
the correct pixel scale; `Defs` prints loaded resource definitions.

**Status: met.** `make run` launches at the configured resolution; `Defs`
logs all 9 resources on startup (see the `make test` output above, which
exercises the same `Defs` load path).

---

## Milestone 1 — Isometric terrain rendering and camera — done

Deliverables:

- `sim/map.gd` (`ColonyMap`): 64×64 terrain grid, generated from two
  `FastNoiseLite` fields (elevation carves VOID/HIGHLANDS, a feature field
  scatters ICE into flats and CRYSTAL into highlands). Deterministic per
  seed. Terrain is pure sim data — a `PackedByteArray`, no scene nodes.
- `sim/iso_grid.gd` (`IsoGrid`): the single source of truth for grid↔screen
  conversion. 64×32 tiles, diamond-down. Verified to match Godot's own
  `TileMapLayer.map_to_local` exactly, in both directions.
- `render/terrain_view.gd` (`TerrainView`): a `TileMapLayer` subclass that
  builds a placeholder iso tileset procedurally (shaded diamonds drawn into
  an `ImageTexture`, no external art files) and paints `ColonyMap` onto it.
- `render/iso_camera.gd` (`IsoCamera`): WASD/arrow-key and middle-mouse-drag
  panning, stepped integer zoom (1×/2×/3×/4×) on the mouse wheel.
- `main.gd` / `main.tscn`: generates the map (seed 1337), centers the camera,
  hover-highlights the tile under the cursor via `IsoGrid.screen_to_grid`,
  and shows an F1-toggleable debug overlay (cell coords, terrain name, zoom,
  seed, FPS).
- Tests: `tests/test_iso_grid.gd` (grid↔screen matches Godot's real
  `TileMapLayer` in both directions, plus round-trip identity) and
  `tests/test_map.gd` (dimensions, terrain ids in range, determinism for a
  given seed, terrain variety).

Acceptance criteria from the plan: a varied alien landscape renders; panning
and zoom feel right; the hovered tile is always correctly identified,
including after pan/zoom.

**Status: mechanically met, visually unverified.** The coordinate-conversion
half of the acceptance criteria is proven by test — `test_iso_grid.gd` pins
`IsoGrid` against Godot's actual `TileMapLayer` math in both directions, so
hover picking is correct by construction, at any pan or zoom, without needing
a human to eyeball it tile-by-tile. What tests *cannot* confirm is the
subjective part: whether the placeholder-tile landscape actually reads as
"a varied alien landscape" and whether panning/zoom "feel right" on screen.
**Nobody has run `make run` and looked at it yet.** That's the next thing to
do before calling Milestone 1 fully closed in spirit, even though its
testable acceptance criteria pass.

---

## Milestone 2 — Building placement — done

Deliverables:

- `sim/colony.gd` (`Colony`): new pure `RefCounted` class — no autoload
  dependencies — holding the map, the global stockpile, placed buildings,
  and a cell→building occupancy index. `can_place()` returns
  `{ok, reason}` after checking in-bounds, allowed terrain, unoccupied
  cells, and affordability; `place()` deducts cost and records the
  instance; `demolish_at()` frees a building's full footprint from any one
  of its cells; `building_at()` and `footprint()` round out the API. This
  is the testable core — no rendering or Events involved.
- `sim/sim.gd`: now owns a `Colony`, created by `new_game(seed, size)`
  with a starting stockpile of `{metal: 100}`. Wraps `Colony`'s placement
  API (`can_place`, `place_building`, `demolish_at`, `building_at`),
  emitting `Events.building_placed` / `building_removed` /
  `stockpile_changed` after each mutation.
- `sim/events.gd`: added `building_placed(instance)` and
  `building_removed(instance)` signals.
- `sim/defs.gd`: now also loads `data/buildings.json`, pre-processing each
  definition with `allowed_terrain_ids` (terrain name strings resolved to
  `ColonyMap.Terrain` enum values) and `color_value` (hex string parsed to
  `Color`) so game/render code never re-parses either.
- `data/buildings.json`: 4 buildings — Solar Panel (1×1), Ice Harvester
  (1×1), Habitat (2×2), Survey Station (2×2) — each with cost, allowed
  terrain, color, and description. Covers the plan's requirement of at
  least one 1×1 and one 2×2 footprint.
- `render/building_sprite.gd` (`BuildingSprite`): draws a lightweight iso
  block (lit top face, two shaded side walls) for either a placed building
  or the placement ghost; ghosts are tinted green/red by placement
  validity. Positioned at the building's front (max-corner) tile so a
  y-sorted parent orders overlapping footprints correctly.
- `render/buildings_view.gd` (`BuildingsView`): spawns/frees
  `BuildingSprite`s purely by listening to `Events.building_placed` /
  `building_removed`, keyed by instance id. Holds no game state itself.
- `tests/test_placement.gd`: 8 new tests over `Colony` directly (valid
  placement + cost deduction, 2×2 occupies all 4 cells, overlap rejected,
  off-map rejected, disallowed terrain rejected, unaffordable rejected,
  demolish frees cells and allows rebuilding, demolishing an empty tile is
  a no-op).
- `main.gd` / `main.tscn`: game controller extended with build/demolish
  interaction modes (left-click places or demolishes depending on mode,
  right-click demolishes or cancels, Escape cancels), a ghost preview that
  follows the cursor and reflects live placement validity, and wiring for
  the new sidebar (build menu, tile info, stockpile display).

Acceptance criteria from the plan: buildings of at least two different
footprint sizes (1×1 and 2×2) can be placed and demolished with correct
validation and no visual sorting glitches.

**Status: met.** `tests/test_placement.gd` proves the validation and
occupancy rules (including the 2×2 case and rebuild-after-demolish) against
`Colony` directly. Visual y-sorting and no-glitch placement/demolish were
confirmed by screenshot review in addition to the automated tests.

### UX changes alongside Milestone 2

A few interface changes landed in the same pass, not called for by the
plan's Milestone 2 text but implemented in response to user feedback:

- **Bigger viewport.** `project.godot` internal resolution went from
  640×360 to **800×450** and the window from 1280×720 to **1600×900**,
  still integer 2× scaled with the pixel-art settings (nearest-neighbor
  filtering, 2D pixel snap) unchanged.
- **Dune II–style sidebar.** New `ui/sidebar.gd` + `ui/sidebar.tscn`: a
  fixed right-hand command panel (dark background, amber/sand accent
  colors) showing the game title, current interaction mode, the hovered
  tile's coordinates/terrain/occupant, the live stockpile, and a build
  menu generated from `Defs.buildings` plus a Demolish button. This is the
  first content under `ui/`.
- **Tile-highlight fix.** The Milestone-1 hover highlight was a `_draw()`
  call on the game root, which rendered *underneath* the `TileMapLayer`
  and was invisible in practice. It's now `render/tile_cursor.gd`
  (`TileCursor`), a dedicated node at `z_index = 100` (above `Buildings`
  at `z_index = 5` and the `Ghost` at `z_index = 50`) that draws a
  dark-backed bright diamond border on top of terrain and buildings, and
  turns red while in demolish mode.

Verified: `make import` clean, headless run clean (no script errors),
`make test` green, and the visuals (highlight on top, sidebar layout,
building blocks) were confirmed by screenshot.

## Milestone 3 — Simulation core: tick, stockpile, power — done

Deliverables:

- `sim/colony.gd`: added the tick economy on top of the Milestone-2
  placement core. `tick()` runs `_balance_power()` then
  `_run_production()`. Power balance: buildings with `power > 0` always
  run and add to `power_produced`; buildings with `power < 0` are switched
  on oldest-first (by instance id) while supply lasts, and the **newest**
  consumers are the ones shut off (`active = false`) once demand exceeds
  supply. Production: each *active* building with a `recipe` advances a
  per-instance `progress` counter every tick; on reaching `recipe.ticks` it
  consumes `recipe.inputs` and produces `recipe.outputs` if the inputs are
  available, otherwise it stalls (holds at the threshold, doesn't consume
  or reset). Building instances gained `active` (bool) and `progress`
  (int) fields, initialized in `place()`. `rates()` returns the net
  stockpile change **per tick** across active buildings, for the HUD.
  `power_produced`/`power_consumed` are recomputed each tick for display.
- `sim/sim.gd`: `_advance_tick()` now calls `colony.tick()` and emits both
  `Events.stockpile_changed` and `Events.ticked`. Added speed controls:
  `set_speed(mult)`, `toggle_pause()`, `is_paused()`, with a
  `_last_run_speed` member so unpausing restores whatever speed (1× or 3×)
  was active before pausing rather than always resuming at 1×.
- `data/buildings.json`: every building now declares `power` (Solar Panel
  +10, Ice Harvester −5, Habitat −2, Survey Station −3) and Ice Harvester
  gained a `recipe` (`{inputs: {}, outputs: {water: 1}, ticks: 4}` — no
  inputs, so it always produces once powered).
- `render/building_sprite.gd`: added `set_dimmed(dimmed)`, applying a
  grey modulate to a shut-down building (no-op on ghosts).
- `render/buildings_view.gd`: `bind()` now also connects `Events.ticked`
  and dims/undims each tracked sprite from the corresponding instance's
  `active` flag every tick.
- `ui/sidebar.gd` / `ui/sidebar.tscn`: added a `SpeedLabel` and a POWER
  section. `set_economy(stock, rates, power_produced, power_consumed,
  speed)` renders the stockpile with a per-second rate suffix where
  nonzero (e.g. `water 4  +1.0/s`), power as `used / produced` (turns red
  on deficit), and speed as `❚❚ PAUSED` or `▶ Nx`.
- `main.gd`: Space toggles pause, `1`/`3` set speed directly. Each frame it
  converts `Colony.rates()` (per-tick) to per-second by multiplying by
  `Sim.TICKS_PER_SECOND` before pushing to the sidebar, alongside power
  figures and `Sim.speed`.
- `tests/test_economy.gd`: 5 new tests — production accrues correctly over
  ticks; a power deficit stops a consumer and halts its production
  entirely; the newest consumer is the one shed when demand exceeds supply
  (with `power_produced`/`power_consumed` assertions); a recipe with
  missing inputs stalls and then produces exactly once inputs arrive;
  `rates()` reflects only currently-active buildings.

Acceptance criteria from the plan: placing a Solar Panel and an Ice
Harvester makes Water tick upward; removing the panel stops the harvester;
the resource HUD updates live; pause works.

**Status: met.** `tests/test_economy.gd` proves the mechanics directly
against `Colony` (production accrual, power-deficit shutdown, newest-first
shedding, input stalling, active-only rates). The plan's acceptance
criteria were additionally confirmed by screenshot: Solar Panel + Ice
Harvester ticks Water upward with power showing `5 / 10` used; removing the
Solar Panel dims the harvester and halts Water; the sidebar's stockpile,
rate, and power figures update live; Space/1/3 pause and change speed as
expected.

## Milestone 4 — Deposits and prospecting — pending

Not started. This is the game's signature mechanic. See plan section
"Milestone 4".

## Milestone 5 — Full production chains and colonists — pending

Not started. See plan section "Milestone 5".

## Milestone 6 — Real UI — pending

Not started as a milestone, though the sidebar built across Milestones 2–3
(`ui/sidebar.gd`/`.tscn`) already covers a fair amount of its ground: a
persistent resource/build panel, per-second stockpile rates, and a
power used/produced readout. Still missing: an alert ticker over `Events`,
a building inspection panel with an idle-reason explanation, and overlay
toggles (prospecting, power coverage). See plan section "Milestone 6".

## Milestone 7 — Save/load and main menu — pending

Not started. See plan section "Milestone 7".

## Milestone 8 — Retro art pass and audio — pending

Not started. All visuals are procedurally-drawn placeholders
(`TerrainView._build_atlas`). See plan section "Milestone 8".

## Milestone 9 — Balance, polish, v2 hooks — pending

Not started. See plan section "Milestone 9".
