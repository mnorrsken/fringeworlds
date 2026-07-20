# Progress log

Status of each milestone from [`colony-game-plan.md`](../colony-game-plan.md).
That file defines the acceptance criteria referenced below — this log tracks
whether they've been met, not what they are.

Current automated test count: **701 assertions across 9 tests, 0 failures**
(`make test`).

---

## Milestone 0 — Project skeleton — done

Deliverables:

- Folder structure in place: `data/ sim/ render/ tests/` (`ui/` and `assets/`
  from the plan's suggested layout don't exist yet — nothing has needed them
  so far; they'll show up with Milestone 2's build menu and Milestone 8's art).
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

## Milestone 2 — Building placement — pending

Not started. See plan section "Milestone 2" for scope (buildings.json,
ghost preview, placement/demolish, footprint-aware y-sorting).

## Milestone 3 — Simulation core: tick, stockpile, power — pending

Not started. `Sim`'s fixed 4-tick/second loop already exists
(`sim/sim.gd`) but only advances a counter and emits `Events.ticked`; no
stockpile, producers/consumers, or power balance yet. See plan section
"Milestone 3".

## Milestone 4 — Deposits and prospecting — pending

Not started. This is the game's signature mechanic. See plan section
"Milestone 4".

## Milestone 5 — Full production chains and colonists — pending

Not started. See plan section "Milestone 5".

## Milestone 6 — Real UI — pending

Not started. Current UI is the Milestone-1 debug overlay only. See plan
section "Milestone 6".

## Milestone 7 — Save/load and main menu — pending

Not started. See plan section "Milestone 7".

## Milestone 8 — Retro art pass and audio — pending

Not started. All visuals are procedurally-drawn placeholders
(`TerrainView._build_atlas`). See plan section "Milestone 8".

## Milestone 9 — Balance, polish, v2 hooks — pending

Not started. See plan section "Milestone 9".
