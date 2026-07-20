# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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

### Fixed

- Tile hover highlight now renders on top of terrain and buildings.
  Previously it was drawn via `_draw()` on the game root, which rendered
  underneath the `TileMapLayer` and made it effectively invisible. Replaced
  with `render/tile_cursor.gd` (`TileCursor`), a dedicated node at
  `z_index = 100`, above both the `Buildings` view (`z_index = 5`) and the
  placement ghost (`z_index = 50`); it also turns red while in demolish
  mode.
