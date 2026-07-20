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
   `building_placed(instance: Dictionary)`, and
   `building_removed(instance: Dictionary)`. The sim emits; UI/render layers
   connect. UI is meant to never poke `Sim` internals directly — it calls
   `Sim` methods and listens on `Events` signals instead. The
   `building_placed`/`building_removed` payload is the same instance
   dictionary `Colony.place()`/`demolish_at()` returns:
   `{id, type, origin, cells}`.
2. **`Defs`** (`sim/defs.gd`) — loads read-only content definitions from
   `data/*.json` at startup into two dictionaries: `resources` (id →
   definition, unchanged since Milestone 0) and `buildings` (id →
   definition). `_load_buildings` post-processes each building entry after
   the generic `_load_json` pass, adding two derived fields so downstream
   code never re-parses raw JSON: `allowed_terrain_ids` (an
   `Array[int]`, the entry's `allowed_terrain` name strings resolved
   through `ColonyMap.Terrain`) and `color_value` (a `Color`, parsed from
   the entry's `color` hex string via `Color.html`). Engine code is meant
   to read `Defs.resources` / `Defs.buildings` rather than hard-code
   content; adding a building means editing `data/buildings.json`, not this
   script.
3. **`Sim`** (`sim/sim.gd`) — game state and the fixed tick loop, plus (as
   of Milestone 2) the live `Colony`. `new_game(seed, size)` generates a
   `ColonyMap`, constructs `colony := Colony.new(map, Defs.buildings,
   STARTING_STOCKPILE)` (`STARTING_STOCKPILE = {metal: 100}`), and resets
   the tick counter; `colony` is `null` until this is called. `Sim` exposes
   thin wrapper methods over `Colony`'s placement API —
   `can_place`, `place_building`, `demolish_at`, `building_at` — that
   delegate to `colony` and then emit the matching `Events` signal
   (`building_placed`/`building_removed`/`stockpile_changed`) on success,
   so `Colony` itself stays free of any signal-bus dependency. The tick
   loop is unchanged: runs at `TICKS_PER_SECOND = 4.0`, accumulator-driven
   inside `_process` so ticks stay decoupled from frame rate; `speed` is a
   multiplier (`0.0` = paused, `1.0` = normal; `set_paused()` toggles
   between them). Each tick still just increments a counter and emits
   `Events.ticked` — producer/consumer economy and power balance land in
   Milestone 3 per the comment at the top of the file.

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
- `data/buildings.json` — an array of 4 building objects (`id`, `name`,
  `size`, `cost`, `allowed_terrain`, `color`, `desc`): `solar_panel` and
  `ice_harvester` (1×1), `habitat` and `survey_station` (2×2). Loaded into
  `Defs.buildings` and augmented with `allowed_terrain_ids`/`color_value`
  as described above. Adding a fifth building is a matter of adding a JSON
  entry — no script changes needed, since `BuildingSprite`, `Colony`, and
  the sidebar's build menu all read generically off the def dictionary.

`data/recipes.json` arrives with Milestone 3 (production chains).

## Rendering and camera

- `render/terrain_view.gd` (`TerrainView`) builds its own placeholder iso
  tileset in code (`_build_tileset` / `_build_atlas` / `_draw_diamond`) —
  one shaded diamond per `ColonyMap.Terrain` enum value, drawn into an
  `ImageTexture` at runtime. No external art files are committed yet; this
  is explicitly a Milestone-8 replacement target.
- `render/building_sprite.gd` (`BuildingSprite`, extends `Node2D`) draws one
  placed building or the placement ghost as a flat-shaded iso block: a lit
  top face plus two darkened side walls (`WALL_H = 16.0` px tall), sized to
  the building's footprint. `configure(def, origin, ghost)` sets it up from
  a `Defs.buildings` entry; `set_origin()` moves it (used every frame for
  the ghost following the cursor); `set_valid()` switches the ghost's
  green/red tint (`_ghost=true` also applies a semi-transparent modulate).
  Its node `position` is pinned to the footprint's front (max-corner) tile
  via `IsoGrid.grid_to_screen`, which is what makes y-sorting order
  multi-tile buildings correctly against each other.
- `render/buildings_view.gd` (`BuildingsView`, extends `Node2D`) has no
  `_process`/state of its own — `bind()` connects to
  `Events.building_placed`/`building_removed` and backfills sprites for any
  buildings already in `Sim.colony.buildings` (needed because it binds
  after `Sim.new_game()` has already placed nothing, but is defensive for
  future load-game flows). Sprites are tracked in a `Dictionary` keyed by
  building instance id so removal is O(1).
- `render/tile_cursor.gd` (`TileCursor`, extends `Node2D`) is the hover
  highlight, replacing the Milestone-1 version. It exposes `cell` and
  `demolish` as setter-observed properties that trigger `queue_redraw()`,
  and draws a two-pass polyline diamond (a dark backing line under a bright
  one) so the border reads on any terrain color; the bright color switches
  amber→red when `demolish` is true.
- `render/iso_camera.gd` (`IsoCamera`, extends `Camera2D`) handles
  WASD/arrow-key panning in `_process`, middle-mouse-drag panning and
  mouse-wheel zoom in `_unhandled_input`. Zoom is stepped through
  `ZOOM_STEPS = [1.0, 2.0, 3.0, 4.0]` to keep pixel scaling crisp — no
  free/continuous zoom. Unchanged since Milestone 1.

### Z-order / y-sort scheme

Draw order is controlled two ways, set on the nodes in `main.tscn`:

- `Buildings` (`BuildingsView`) has `y_sort_enabled = true` and
  `z_index = 5`, so buildings sort against each other by their front-tile
  screen Y (via `BuildingSprite`'s position), and sit above the terrain.
- `Ghost` (`BuildingSprite`, the placement preview) sits at `z_index = 50`.
- `TileCursor` sits at `z_index = 100`, the highest in the scene, so the
  hover border always draws on top of terrain and buildings. This fixed a
  Milestone-1 bug where the highlight was a plain `_draw()` on the game
  root and rendered *underneath* the `TileMapLayer`, making it invisible —
  see `docs/progress.md`'s Milestone 2 section and the class doc-comment at
  the top of `tile_cursor.gd`.

## UI layer

`ui/sidebar.gd` (on `ui/sidebar.tscn`, a `PanelContainer`) is a "Dune
II"-style fixed right-hand command panel, instanced under a `CanvasLayer`
(`UI`) in `main.tscn` so it draws in screen space above the game world. It
holds no game logic — it only displays state pushed into it and emits
signals for user intent:

- `populate(buildings: Dictionary)` builds one `Button` per entry in
  `Defs.buildings`, each emitting `build_requested(type_id)` when pressed.
- `set_mode_label`, `set_tile_info`, `set_stockpile` are pushed to by
  `main.gd` (mode/tile info, every frame) and by `Events.stockpile_changed`
  (stockpile, event-driven — `main.gd` connects
  `Events.stockpile_changed.connect(_sidebar.set_stockpile)` and seeds the
  initial value once, since `new_game()` doesn't itself emit).
- A Demolish button emits `demolish_requested()`.

`main.gd` connects `build_requested`/`demolish_requested` to switch its own
`Mode` enum (`NONE`/`PLACE`/`DEMOLISH`) and never reaches into the
sidebar's internals beyond those signals and setters.

## Game root

`main.gd` (on `main.tscn`, the project's `run/main_scene`) is the current
top-level scene and game controller. On `_ready()` it calls
`Sim.new_game(DEFAULT_SEED, MAP_SIZE)` (seed `1337`, 64×64), hands the
resulting map to `TerrainView` to render, calls `BuildingsView.bind()`,
centers the `IsoCamera`, wires up the sidebar (`populate`, `build_requested`
→ enter place mode, `demolish_requested` → enter demolish mode,
`Events.stockpile_changed` → `sidebar.set_stockpile`), and enters
`Mode.NONE`.

Each frame (`_process`) it converts the mouse position to a grid cell via
`IsoGrid.screen_to_grid`, updates `TileCursor.cell`, hides the cursor when
the mouse is over a UI control (`get_viewport().gui_get_hovered_control()`),
updates the placement ghost (visible + repositioned + validity-tinted only
in `Mode.PLACE` and only over the map), and refreshes the sidebar's tile
info plus the F1 debug label.

Input (`_unhandled_input`) is skipped for mouse clicks that landed on UI.
Left-click places (in `PLACE` mode) or demolishes (in `DEMOLISH` mode) at
the hovered cell via `Sim`; right-click cancels the current mode if one is
active, otherwise demolishes at the hovered cell directly; Escape always
cancels to `Mode.NONE`; F1 toggles the debug overlay
(`$Debug/Label` — cell coords, terrain name, zoom level, seed, FPS). The
debug overlay is intentionally meant to stay available for the life of the
project — the plan calls out coordinate conversion as the first thing to
suspect when on-screen visuals look wrong.

## Folder layout

```
data/       JSON content definitions: resources.json, buildings.json
sim/        Pure sim logic and state: sim.gd, defs.gd, events.gd, map.gd, iso_grid.gd, colony.gd
render/     Views of sim state: terrain_view.gd, building_sprite.gd, buildings_view.gd, tile_cursor.gd, iso_camera.gd
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
occupancy, and demolish rules — built with a hand-rolled defs dictionary,
independent of `Defs`/`Sim`). 718 assertions across 17 tests, 0 failures as
of Milestone 2.
