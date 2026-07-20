# Progress log

Status of each milestone from [`colony-game-plan.md`](../colony-game-plan.md).
That file defines the acceptance criteria referenced below — this log tracks
whether they've been met, not what they are.

Current automated test count: **718 assertions across 17 tests, 0 failures**
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

## Milestone 3 — Simulation core: tick, stockpile, power — pending

Not started. `Sim`'s fixed 4-tick/second loop already exists
(`sim/sim.gd`), and Milestone 2 gave it a `Colony`-backed stockpile
(currently just a starting balance debited by building cost) — but there
is still no producer/consumer recipe logic or power balance; each tick
only advances a counter and emits `Events.ticked`. See plan section
"Milestone 3".

## Milestone 4 — Deposits and prospecting — pending

Not started. This is the game's signature mechanic. See plan section
"Milestone 4".

## Milestone 5 — Full production chains and colonists — pending

Not started. See plan section "Milestone 5".

## Milestone 6 — Real UI — pending

Not started as a milestone, though Milestone 2's Dune II–style sidebar
(`ui/sidebar.gd`/`.tscn`) already covers some of its ground (a persistent
resource/build panel). Still missing: rates (+/- per second), an alert
ticker over `Events`, a building inspection panel, and overlay toggles.
See plan section "Milestone 6".

## Milestone 7 — Save/load and main menu — pending

Not started. See plan section "Milestone 7".

## Milestone 8 — Retro art pass and audio — pending

Not started. All visuals are procedurally-drawn placeholders
(`TerrainView._build_atlas`). See plan section "Milestone 8".

## Milestone 9 — Balance, polish, v2 hooks — pending

Not started. See plan section "Milestone 9".
