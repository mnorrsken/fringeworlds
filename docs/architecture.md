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
  `set_terrain` accessors. It does not know a `TileMapLayer` exists.
- `render/terrain_view.gd` (`TerrainView`) is a `TileMapLayer` subclass with
  one method that matters, `render_map(map: ColonyMap)`, which walks the map
  and paints matching tiles. It reads `ColonyMap`; `ColonyMap` never touches
  it.

This split is why the sim can be tested headlessly (see `tests/`) without
booting any rendering — `test_map.gd` instantiates `ColonyMap` directly and
never touches a scene.

## The three autoloads

Registered in `project.godot` under `[autoload]`, in load order:

1. **`Events`** (`sim/events.gd`) — a global signal bus. Currently defines
   `ticked(tick: int)` and `stockpile_changed(stockpile: Dictionary)`. The
   sim emits; UI/render layers connect. UI is meant to never poke `Sim`
   internals directly — it calls `Sim` methods and listens on `Events`
   signals instead. (`stockpile_changed` isn't emitted by anything yet;
   it's declared ahead of the stockpile landing in Milestone 3.)
2. **`Defs`** (`sim/defs.gd`) — loads read-only content definitions from
   `data/*.json` at startup into `resources: Dictionary` (id → definition
   dict). `_load_json` expects a JSON array of objects each with an `id`
   field and keys the resulting dictionary by that id. Engine code is meant
   to read `Defs.resources` rather than hard-code content; adding a resource
   means editing `data/resources.json`, not this script.
3. **`Sim`** (`sim/sim.gd`) — game state and the fixed tick loop. Runs at
   `TICKS_PER_SECOND = 4.0`, accumulator-driven inside `_process` so ticks
   stay decoupled from frame rate. `speed` is a multiplier (`0.0` = paused,
   `1.0` = normal; `set_paused()` toggles between them). Each tick currently
   just increments a counter and emits `Events.ticked` — stockpile,
   buildings, power, and prospecting logic land in later milestones per the
   comment at the top of the file.

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
(implicitly, via `TileMapLayer`'s own matching math) and `main.gd`, which
calls `IsoGrid.screen_to_grid(get_global_mouse_position())` every frame to
drive the hover highlight, and `IsoGrid.grid_to_screen` to center the camera
and to draw the highlight outline in `_draw()`.

## Data-driven content

Per the plan's architecture principles, building/resource/recipe content is
meant to live in JSON under `data/`, not in engine code. So far only
`data/resources.json` exists — an array of 9 objects
(`id`, `name`, `category`, `unit`), loaded by `Defs` as described above.
`data/buildings.json` and `data/recipes.json` arrive with Milestone 2 and 3.

## Rendering and camera

- `render/terrain_view.gd` (`TerrainView`) builds its own placeholder iso
  tileset in code (`_build_tileset` / `_build_atlas` / `_draw_diamond`) —
  one shaded diamond per `ColonyMap.Terrain` enum value, drawn into an
  `ImageTexture` at runtime. No external art files are committed yet; this
  is explicitly a Milestone-8 replacement target.
- `render/iso_camera.gd` (`IsoCamera`, extends `Camera2D`) handles
  WASD/arrow-key panning in `_process`, middle-mouse-drag panning and
  mouse-wheel zoom in `_unhandled_input`. Zoom is stepped through
  `ZOOM_STEPS = [1.0, 2.0, 3.0, 4.0]` to keep pixel scaling crisp — no
  free/continuous zoom.

## Game root

`main.gd` (on `main.tscn`, the project's `run/main_scene`) is the current
top-level scene: on `_ready()` it builds a `ColonyMap`, generates it with a
fixed seed (`DEFAULT_SEED = 1337`), hands it to the `TerrainView` child to
render, and centers the `IsoCamera` child on the map. Each frame it converts
the mouse position to a grid cell via `IsoGrid` to drive a hover outline
(`_draw()`) and an F1-toggleable debug label (`$Debug/Label`) showing cell
coordinates, terrain name, zoom level, seed, and FPS. This debug overlay is
intentionally meant to stay available for the life of the project — the plan
calls out coordinate conversion as the first thing to suspect when
on-screen visuals look wrong.

## Folder layout

```
data/       JSON content definitions (data/resources.json so far)
sim/        Pure sim logic and state: sim.gd, defs.gd, events.gd, map.gd, iso_grid.gd
render/     Views of sim state: terrain_view.gd, iso_camera.gd
tests/      Headless tests: run_tests.gd (runner) + test_*.gd files
main.gd / main.tscn   Current game root (Milestone 1)
```

`ui/` and `assets/` from the plan's suggested layout don't exist yet — they
arrive with Milestone 2 (build menu) and Milestone 8 (custom art/audio)
respectively.

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
`TileMapLayer` math). 701 assertions, 0 failures as of Milestone 1.
