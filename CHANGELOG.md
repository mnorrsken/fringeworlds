# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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
