# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Overhead map (toggle on `M`) with building markers, camera-view
  rectangle, and click-to-jump. New `render/minimap.gd` (`Minimap`)
  renders `ColonyMap` top-down as a cached one-pixel-per-cell image,
  overlays a colored rect per placed building and the camera's current
  view as a rotated quad in grid space, and jumps the camera to a clicked
  cell. Shown in a dim-backdrop popup (`MinimapLayer` in `main.tscn`);
  `Esc` closes it before falling back to canceling build mode.

- **Milestone 3 — Simulation core: tick, stockpile, power** (2026-07-20)
  - `sim/colony.gd`: fixed-tick economy. `tick()` runs `_balance_power()`
    then `_run_production()`. Power balance: generators (`power > 0`)
    always run; consumers (`power < 0`) are switched on oldest-placed-first
    while supply lasts, so the newest consumers are shed first on a
    deficit. Production: each active building with a `recipe` advances a
    per-instance `progress` counter and, on reaching `recipe.ticks`,
    consumes `inputs` and produces `outputs` if affordable, otherwise
    stalls without losing progress. Added `rates()` (net per-tick
    stockpile change from active buildings, for the HUD) and
    `power_produced`/`power_consumed` members. Building instances gained
    `active` and `progress` fields.
  - `sim/sim.gd`: `_advance_tick()` now calls `colony.tick()` and emits
    `stockpile_changed` alongside `ticked`. Speed controls:
    `set_speed(mult)`, `toggle_pause()`, `is_paused()` (pause / 1× / 3×),
    remembering the last running speed so unpausing restores it instead of
    always resuming at 1×.
  - `data/buildings.json`: every building now declares `power` (Solar
    Panel +10, Ice Harvester −5, Habitat −2, Survey Station −3); Ice
    Harvester gained a `recipe` (no inputs → 1 water every 4 ticks).
  - `render/building_sprite.gd`: `set_dimmed()` greys out a shut-down
    building.
  - `render/buildings_view.gd`: connects `Events.ticked` and dims/undims
    each tracked sprite from the building's `active` flag every tick.
  - `ui/sidebar.gd` / `ui/sidebar.tscn`: added a speed label and a POWER
    section; `set_economy(stock, rates, power_produced, power_consumed,
    speed)` shows the stockpile with per-second rates (e.g.
    `water 4  +1.0/s`), power as `used / produced` (red on deficit), and
    speed (`❚❚ PAUSED` / `▶ Nx`).
  - `main.gd`: Space toggles pause, `1`/`3` set speed; pushes the economy
    to the sidebar every frame, converting `Colony.rates()` from per-tick
    to per-second via `Sim.TICKS_PER_SECOND`.
  - Tests: `tests/test_economy.gd` (5 tests — production accrual, power
    deficit halting a consumer, newest-consumer-shed-first, recipe stall
    and recovery on missing inputs, active-only `rates()`).
  - Full suite: 730 assertions across 22 tests, 0 failures (`make test`).

- **Milestone 2 — Building placement** (2026-07-20)
  - `sim/colony.gd` (`Colony`): pure sim class holding the map, stockpile,
    placed buildings, and a cell occupancy index; `can_place`/`place`/
    `demolish_at`/`building_at`/`footprint` form the testable placement
    core, independent of autoloads or rendering.
  - `sim/sim.gd`: `new_game(seed, size)` builds a map and a `Colony` seeded
    with a starting stockpile of `{metal: 100}`; thin wrapper methods
    (`can_place`, `place_building`, `demolish_at`, `building_at`) delegate
    to `Colony` and emit `Events` signals after mutating state.
  - `sim/events.gd`: new `building_placed(instance)` and
    `building_removed(instance)` signals.
  - `data/buildings.json` + `sim/defs.gd` loading it: 4 data-driven
    buildings (Solar Panel, Ice Harvester — 1×1; Habitat, Survey Station —
    2×2), each with cost, allowed terrain, and color, pre-processed into
    `allowed_terrain_ids` and `color_value`.
  - `render/building_sprite.gd` (`BuildingSprite`): procedurally-drawn iso
    block per placed building or placement ghost, tinted green/red for
    ghost validity.
  - `render/buildings_view.gd` (`BuildingsView`): spawns/frees building
    sprites purely from the `Events` bus.
  - `main.gd` / `main.tscn`: build/demolish interaction modes (left-click
    place/demolish, right-click demolish/cancel, Esc cancel), a live ghost
    preview, and sidebar wiring.
  - `ui/sidebar.gd` / `ui/sidebar.tscn`: new Dune II–style right-hand
    command panel — title, current mode, hovered-tile info (coords,
    terrain, occupant), stockpile, and a build menu generated from
    `Defs.buildings` plus a Demolish button.
  - Bigger viewport: internal resolution 640×360 → 800×450, window
    1280×720 → 1600×900 (still integer 2× scaled; pixel-art settings
    unchanged).
  - Tests: `tests/test_placement.gd` (8 tests covering placement, cost
    deduction, footprint occupancy, overlap/off-map/bad-terrain/
    unaffordable rejection, and demolish/rebuild).
  - Full suite: 718 assertions across 17 tests, 0 failures (`make test`).

- **Milestone 1 — Isometric terrain rendering and camera** (2026-07-20)
  - `sim/map.gd` (`ColonyMap`): 64×64 terrain grid generated from
    `FastNoiseLite` fields (REGOLITH, HIGHLANDS, ICE, CRYSTAL, VOID),
    deterministic per seed.
  - `sim/iso_grid.gd` (`IsoGrid`): grid↔screen coordinate conversion,
    verified against Godot's own isometric `TileMapLayer` math.
  - `render/terrain_view.gd` (`TerrainView`): procedurally-built placeholder
    tileset rendering `ColonyMap` onto a `TileMapLayer`.
  - `render/iso_camera.gd` (`IsoCamera`): WASD/arrow/middle-mouse panning,
    stepped integer zoom (1×–4×).
  - `main.gd` / `main.tscn`: game root wiring map generation, camera
    centering, cursor hover highlighting, and an F1-toggleable debug
    overlay.
  - Tests: `tests/test_iso_grid.gd`, `tests/test_map.gd`.
  - Full suite: 701 assertions across 9 tests, 0 failures (`make test`).

- **Milestone 0 — Project skeleton** (2026-07-20)
  - Folder structure: `data/ sim/ render/ tests/`.
  - `project.godot` configured for pixel art: 640×360 internal viewport,
    1280×720 window, viewport stretch mode, nearest-neighbor filtering,
    2D pixel snap, GL Compatibility renderer.
  - Autoload singletons: `Events` (`sim/events.gd`), `Defs`
    (`sim/defs.gd`), `Sim` (`sim/sim.gd`).
  - `data/resources.json`: 9 resource definitions, loaded by `Defs` at
    startup.
  - `.gitignore`, placeholder `icon.svg`.
  - `Makefile`: `run`, `editor`, `build`/`import`, `test`, `clean`.
  - Headless test harness: `tests/run_tests.gd`, `tests/test_defs.gd`.

### Changed

- Zoom is now toggled 1×/2× on `Z` (scroll/wheel no longer zoom). Trackpad
  scroll-to-zoom, added in the previous pass to fix macOS zoom, felt
  twitchy in practice, so mouse-wheel and trackpad two-finger-scroll zoom
  were removed entirely in favor of an explicit `Z` toggle
  (`IsoCamera.toggle_zoom()`: 1×↔2×, snapping straight to 1× from any
  higher zoom). Pinch and keyboard `+`/`-` remain as secondary fine-zoom
  controls. `tests/test_camera.gd` was rewritten for the new scheme.
- Faster map panning: `PAN_SPEED` in `render/iso_camera.gd` raised from
  260 to 420 world px/sec at 1× zoom.
- Sidebar build menu is now scrollable: content wrapped in a
  `ScrollContainer` (horizontal scroll disabled) so every building is
  reachable regardless of list length, not just the ones that fit in
  450px. Sidebar widened 216→240px so the scrollbar doesn't clip button
  text; build buttons are now single-line (`Name  ·  cost`) with
  `clip_text` to fit.

### Fixed

- Zoom now works on macOS trackpad / Magic Mouse. Those devices never emit
  mouse-wheel events, only `InputEventPanGesture` (two-finger scroll) and
  `InputEventMagnifyGesture` (pinch), which `render/iso_camera.gd`
  previously ignored entirely. The camera now zooms from wheel, pan
  gesture (accumulated to a threshold), pinch (accumulated), and keyboard
  `+`/`-`, all through a shared `zoom_by(steps)` helper. Covered by 4 new
  synthetic-event tests in `tests/test_camera.gd`.

- Tile hover highlight now renders on top of terrain and buildings.
  Previously it was drawn via `_draw()` on the game root, which rendered
  underneath the `TileMapLayer` and made it effectively invisible. Replaced
  with `render/tile_cursor.gd` (`TileCursor`), a dedicated node at
  `z_index = 100`, above both the `Buildings` view (`z_index = 5`) and the
  placement ghost (`z_index = 50`); it also turns red while in demolish
  mode.
