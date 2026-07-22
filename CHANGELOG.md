# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Milestone 7 — Save/load & main menu** (2026-07-22)
  - `ColonyMap.to_dict()`/static `from_dict(d)` and `Colony.to_dict()`/static
    `from_dict(map, defs, d)` snapshot full sim state to a JSON-safe dict
    (byte/float layers base64-encoded, buildings flattened, occupancy
    rebuilt on load) — pure, dependency-free, headlessly testable.
  - `Sim`: `save_game(name)`/`load_game(name)` (JSON files under
    `user://saves/`), `list_saves()`/`latest_save()`/`has_saves()`/
    `delete_save(name)`, autosave every ~3 minutes, and an `active` flag
    gating the tick loop/autosave so nothing simulates at the menu.
  - New main menu (`menu.gd`/`menu.tscn`, now `run/main_scene`): New Game
    (seed + map size), Continue, Load (with delete), Quit.
  - New in-game system menu (Escape, when nothing else to dismiss): Resume,
    Save Game, Main Menu, Quit; pauses the sim while open.
  - Tests: `tests/test_save.gd` (map/colony round-trip, tick-determinism
    after load). Full suite: 816 assertions across 64 tests, 0 failures
    (`make test`).

- **Milestone 6 — Real UI** (2026-07-22)
  - Building inspector: click a building in SELECT mode to inspect it in the
    sidebar (name, running/idle status with the reason — "No power", "No
    workers", "Needs <inputs>" — power, workers, housing, recipe progress,
    and for extractors the mined resource/richness/rate); click empty
    ground to deselect; a demolished selection auto-clears. `Colony` now
    tracks `idle_reason` per building instance and exposes
    `building_report(id) -> Dictionary`; `Sim.building_report()` wraps it.
    New sidebar INSPECT section in `ui/sidebar.gd`/`ui/sidebar.tscn`.
  - Alert ticker: a pure `AlertMonitor` (`sim/alerts.gd`) edge-detects power
    deficits, life-support resources running low, and newly confirmed
    deposits, firing once per rising edge. New `Events.alert(text, level)`
    signal, emitted from `Sim`'s tick loop. New `ui/alert_ticker.gd` renders
    a fading, color-coded stack (bottom-left, capped at 4).
  - Status overlay (`O` toggle): `render/status_overlay.gd` marks every
    building with a green/red dot (running/idle) at its front cell, since
    power here is a global balance rather than a spatial network.
  - Sidebar hint updated to "LMB place / inspect" / "P prospect · O status
    · M map".
  - Tests: `tests/test_alerts.gd`, `tests/test_inspector.gd`. Full suite:
    800 assertions across 60 tests, 0 failures (`make test`).

- Tech unlocks: buildings gated behind prerequisites (e.g. solar → survey
  → mine → smelter → parts → crystal; ice harvester → electrolysis/
  hydroponics), shown in the build menu. `Colony` tracks `built_types`
  (every building type ever placed, so an unlock persists even if the
  prerequisite is later demolished); `is_unlocked()`/`missing_prereqs()`
  drive a new `can_place()` rejection ("Locked — prerequisite not
  built"). The sidebar's build buttons disable, show a 🔒, and explain
  what's missing via `set_locks()`; the menu recomputes on every building
  placement since a new building can unlock others. 5 new tests in
  `tests/test_tech.gd`.

- **Milestone 5 — Full production chains and colonists** (2026-07-21)
  - `data/buildings.json`: expanded from 6 to 10 buildings. Every building
    now declares `workers`; Habitat gained `capacity: 6`. Four new
    production-chain buildings on the existing recipe system: Electrolysis
    Plant (water→oxygen), Hydroponics Farm (water→food), Smelter
    (iron_ore→metal), Parts Factory (metal+copper_ore→parts). Crystal
    Extractor's cost now also requires `parts: 8`. The design plan's
    Geothermal Plant is deferred — it needs a surface "vent" feature the
    map doesn't generate yet; Solar Panel remains the only power source.
  - `sim/colony.gd`: colonists, life support, workforce, and win/lose.
    `enum Status { PLAYING, WON, LOST }`; `population`; constants
    `STARTING_POPULATION 4`, `BASE_CAPACITY 4`, `STARVE_TICKS 16`,
    `GROWTH_TICKS 80`, `VICTORY_XENITE 50`, `LIFE_SUPPORT` (oxygen/water/
    food per colonist per tick). `capacity()`/`workers_used()`. `tick()`
    order: power → workforce → prospecting → production → life support →
    status. `_balance_workforce()` idles the newest understaffed buildings
    when labor demand exceeds population, mirroring the power-shedding
    rule. `_run_life_support()` consumes O2/water/food via a fractional
    accumulator; sustained shortage kills a colonist, sustained surplus
    under capacity grows one. `_check_status()` sets WON at the xenite
    threshold or LOST at population zero. `rates()` now nets out
    life-support consumption too.
  - `sim/sim.gd`: `STARTING_STOCKPILE` gained an oxygen/water/food buffer
    (60 each). The tick loop freezes once the colony reaches a terminal
    state; `_end_game()` emits `Events.game_over(won)` exactly once.
  - `sim/events.gd`: new `game_over(won: bool)` signal.
  - `ui/sidebar.gd`/`ui/sidebar.tscn`: new COLONISTS section —
    `set_colony(population, cap, workers_used)` shows pop/capacity and
    workers used/population, amber when at capacity.
  - `main.tscn`/`main.gd`: new `GameOverLayer` overlay — "BEACON LAUNCHED"
    on victory or "COLONY LOST" on defeat, with Enter-to-restart
    (`reload_current_scene()`).
  - Tests: `tests/test_colonists.gd` (7 tests — life support consumption,
    starvation deaths, growth when fed/housed, no growth past capacity,
    workforce idling the newest understaffed building, xenite victory,
    population-zero defeat).
  - Full suite: 760 assertions across 43 tests, 0 failures (`make test`).

- **Milestone 4 — Deposits and prospecting** (2026-07-20)
  - `sim/map.gd`: `ColonyMap` gained hidden per-cell deposit/richness
    layers (`enum Deposit { NONE, IRON, COPPER, XENITE }`, richness
    `0.0`–`1.0`, a fixed per-cell reading-noise field) and a revealed
    scan-state layer (`enum Scan { UNSCANNED, COARSE, CONFIRMED }`).
    `_generate_deposits()` places blob-shaped deposits from one
    low-frequency noise field per type under buildable ground, richness
    from the noise margin, deterministic per seed. New accessors
    `get_deposit`/`get_richness`/`get_scan`/`set_scan`,
    `coarse_richness()` (true value + deterministic jitter for imprecise
    coarse readings), and `reading_text()` (the sidebar reading string).
  - `sim/colony.gd`: `can_place()` gates buildings declaring
    `requires_deposit_ids` on a CONFIRMED matching deposit. `tick()` now
    runs `_run_prospecting()` (survey stations sweep an expanding circular
    ring outward, one ring per `ticks_per_ring` ticks, advancing each
    tile's scan state one step per visit — unscanned→coarse→confirmed —
    restarting from center after the outer ring so a second sweep
    confirms) before production. `_run_mine()`: extractors yield their
    deposit's resource at `base_per_tick × richness` per tick via a
    fractional accumulator, so richer tiles visibly produce faster.
    `rates()` now includes mine output.
  - `sim/events.gd`: new `scan_changed(cells: Array)` signal, emitted by
    `Sim` after any tick that changed scan state.
  - `data/buildings.json`: Survey Station gained a `scan` block
    (`max_radius: 7, ticks_per_ring: 2`); new Mine (1×1, requires
    confirmed Iron or Copper, `0.5 × richness`/tick) and Crystal Extractor
    (1×1, requires confirmed Xenite, `0.25 × richness`/tick).
  - `render/prospect_overlay.gd` (new `ProspectOverlay`): a `P`-toggleable
    overlay tinting each tile by scan state and, once confirmed, by
    deposit type (semi-transparent iso diamonds — unscanned veil, coarse
    trace, confirmed iron/copper/xenite/barren). Repaints fully when shown,
    then incrementally via `Events.scan_changed` while visible.
  - `main.tscn`/`main.gd`: `ProspectOverlay` added between terrain and
    buildings (`z_index = 2`); `P` toggles it; the sidebar's tile info now
    shows the prospecting reading for the hovered cell.
  - Tests: `tests/test_prospecting.gd` (9 tests — deterministic deposit
    generation, fresh-map unscanned state, coarse-then-confirmed
    revelation over two survey sweeps, outward ring expansion,
    `scan_changes` reporting, deposit-gated mine placement, and
    richness-scaled output).
  - Full suite: 749 assertions across 36 tests, 0 failures (`make test`).

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

- **Post-M6 UI/UX refinement pass** (2026-07-22)
  - Bigger window/UI room: internal viewport 800×450→1280×720, window
    1600×900→1920×1080 — genuine extra layout space, not just bigger
    pixels.
  - New top resource bar (`ui/resource_bar.gd`, data-driven from
    `data/resources.json`'s new `glyph`/`color` fields): each stockpiled
    resource shown as coloured glyph + amount + per-second rate (e.g.
    `⬢ 185`, `≈ 100 -0.3`), staying hidden until the colony has some of it.
    `power` is skipped here (a capacity balance, not a stockpiled good) —
    still shown in the sidebar.
  - Sidebar: only the build list scrolls now; mode/speed, a condensed
    one-line controls hint, TILE/POWER/COLONISTS/SELECTED are static. The
    STOCKPILE section moved to the new top bar and was removed from the
    sidebar; `set_economy()` dropped its stockpile/rates args
    (`set_economy(power_produced, power_consumed, speed)`).
  - Layout/presentation only — no sim logic changed. Full suite: 800
    assertions across 60 tests, 0 failures (`make test`).
  - Follow-up: smaller sidebar font (`ui/sidebar.gd` sets a `Theme` with
    `default_font_size = 14` in `_ready()`, so labels and build buttons
    shrink; the Title keeps its own 18px override). Resource glyphs in the
    top bar now show a tooltip (name + one-line description) on hover, from
    a new `desc` field per entry in `data/resources.json`. Low-resource
    alerts broadened: `AlertMonitor` now warns on *any* resource that's both
    net-drained (per `Colony.rates()`) and at/below the low-stock floor, not
    just oxygen/water/food — so a smelter/parts-factory chain running the
    colony out of ore or metal alerts too. New test:
    `tests/test_alerts.gd::test_non_life_support_resource_low_warns`. Full
    suite: 802 assertions across 61 tests, 0 failures (`make test`).
- Rebalanced early game: starting metal 120→200 and Solar Panel 10→15
  power, so the metal chain is reachable without a perfect build order
  (fixes an early-game dead-end). Even with the gentler-early-game numbers
  below, the starting metal couldn't fund power + life support +
  prospecting *and* leave enough for a Smelter — the building that
  replenishes metal — so a colony could paint itself into a corner with
  no way to bootstrap self-sustaining metal production. `sim/sim.gd`'s
  `STARTING_STOCKPILE` metal raised to 200; `data/buildings.json`'s Solar
  Panel power raised to 15 (roughly 2 panels power the early base instead
  of 3, freeing metal for the rest of the bootstrap). New
  `tests/test_balance.gd` regression-guards this: the metal cost of a
  minimal self-sustaining bootstrap (2 solar panels + ice harvester +
  electrolysis plant + hydroponics farm + survey station + mine + smelter
  = 145 metal) must fit inside the starting metal with at least 20 to
  spare.
- Gentler early game: automated (robot) early buildings, reduced
  life-support drain, larger starting buffer. `data/buildings.json`:
  Solar Panel, Habitat, Ice Harvester, Electrolysis Plant, Hydroponics
  Farm, Survey Station, and Mine are all `workers: 0`; only the
  processing/advanced tier (Smelter, Parts Factory, Crystal Extractor)
  needs colonists. `sim/colony.gd`: `LIFE_SUPPORT` reduced (oxygen/water
  0.03→0.02, food 0.02→0.015 per colonist per tick), `STARVE_TICKS`
  raised 16→24 (~6s grace). `sim/sim.gd`: `STARTING_STOCKPILE`'s
  oxygen/water/food raised to 100 each (was 60); its starting metal was
  raised too in this same pass, but see the metal-cliff entry above for
  the number that actually shipped. Colonist pressure now builds slowly
  over a game rather than hitting immediately.
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

- Multi-tile buildings render per-tile, fixing depth/occlusion overlap.
  Previously a multi-tile building was a single `BuildingSprite` y-sorted
  at one depth, so a 2×2+ footprint could draw in front of or behind a
  neighboring building incorrectly on some of its cells. `BuildingSprite`
  was rewritten to draw a list of cells as separate 1×1 blocks;
  `BuildingsView` now spawns one sprite per footprint cell, so each tile
  of a multi-tile building depth-sorts against its neighbors
  independently. The placement ghost still uses one multi-cell sprite
  (it always renders on top, so per-tile interleaving isn't needed there).

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
