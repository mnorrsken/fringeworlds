# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- Prospecting overlay now shades confirmed/coarse tiles by how much of the
  deposit is left, on a per-deposit-type scale (30 xenite units reads "full"
  the same as 600 iron units) — a worked-out tile fades to dim grey, a fat
  one is vivid. Shading updates live as extractors deplete a tile, not just
  when a scan lands.

## [1.1.0] - 2026-07-28

Regolith's first release since 1.0.0, and a lot has changed under the hood and
on screen. The interface got a rework: colony stats moved to a top bar with
hover readouts, and there's a proper in-game help popup. Terrain now flows
naturally with scattered ground clutter, and canyons read as real bottomless
drops instead of flat dark tiles. The colony hub is free to build but unique
and essential — lose it and everything else grinds to a halt. Ore and crystal
deposits are no longer bottomless: they run out, so prospecting new ground and
relocating extractors is now the core loop, and xenite is visible up front in
crystal formations rather than hidden anywhere underground. Storage is also
limited now, so building warehouses is required to stockpile enough xenite to
finish the beacon.

### Added

- **Warehouse art.** The Warehouse now renders its own `assets/warehouse.png`
  instead of borrowing the Parts Factory sprite, with matching `fx`: a
  rooftop steam vent and three blinking status lamps on its tanks and tower.

- **Internal building buffers.** Producers and extractors now hold a small
  hopper (`building_buffer` balance key, default 4 units per resource)
  instead of writing straight to the colony stockpile. Output lands in the
  hopper and flushes into the store as room allows, both before a building
  acts (so a stalled line restarts the moment space appears) and right
  after it produces (so normal play is unaffected when the store has
  room). A full colony store now backs up through the hopper before a line
  actually stalls with "Storage full"; a stalled extractor leaves the ore
  in the ground, pulling no more than one hopper's worth. The hopper is
  serialized and shown in the hover readout ("holding ...").
- **Limited storage and a Warehouse building.** Buildings can declare a
  `storage` block in `buildings.json`; `Colony.storage_for(res)` sums it
  over everything standing (storage is physical, so an unpowered warehouse
  still holds its contents), with `space_for()`/`_fits()` on top. Gains
  clamp to capacity, producers check `_fits()` before consuming inputs so a
  full store stalls a line ("Storage full") instead of destroying output,
  extractors idle the same way with the ore left in the ground, and
  demolishing storage spills whatever no longer fits. Content that
  declares no storage anywhere is unlimited, so unit-test colonies built
  from synthetic defs are unaffected. New 2×2 **Warehouse** (45 metal + 6
  parts, −2 power, requires Parts Factory) holds 100 metal/ore, 60 parts,
  90 xenite, 150 life support — the only place xenite can be kept, since
  the Hub's yard holds none at all, so three warehouses are required to
  hold the beacon's 260 xenite target. The top status bar shows
  `amount/cap` once a resource is near its ceiling (amber at capacity),
  and the hover readout lists what a storage building holds.
- **Deposits are now finite.** A tile's richness sizes its reserve
  (`deposit_units`: IRON 600, COPPER 260, XENITE 30) instead of its output
  rate; extractors run at a flat rate and idle with "Deposit worked out"
  once a reserve hits zero. Reserves are serialized, with a migration that
  refills them from richness for older saves. The hover readout and
  `reading_text()` now report units left instead of a richness percentage.
- **Xenite lives in visible crystal formations**: every CRYSTAL terrain
  tile holds xenite and no xenite generates anywhere else, so a formation
  is visible from the start even though its reserve still has to be
  prospected. Crystal generation loosened (highlands feature threshold
  -0.60 → -0.40, ~1–9 formations per map → ~28–33) since the old rarity
  could make a seed unwinnable outright.
- **The Colony Hub is now free (`cost: {}`), unique, and required.** New
  building-def flags `unique` (only one may stand; `can_place`/
  `Colony.lock_reason()` grey out a second) and `colony_controller`: with
  no active controller building, every other building — including life
  support — goes inactive with idle reason "No colony hub" until one is
  rebuilt. The rule is data-driven; defs with no declared controller (all
  existing unit tests) are unaffected.
- **Survey stations must be built inside existing survey coverage**
  (new `requires_coverage` flag, `Colony.in_survey_coverage()`), so
  prospecting spreads outward from the hub in overlapping steps instead of
  leapfrogging into the dark.
- **Slow, scattered richness confirmation.** A scan def can carry
  `confirm_ticks`: once a survey station's outward sweep finishes, it drops
  into resampling — one probe every `confirm_ticks` ticks at a
  pseudo-randomly picked tile in its radius (deterministically hashed from
  building id + probe count, not an RNG, so saves reload mid-sequence).
  The probe often lands on already-confirmed ground or bare rock and
  achieves nothing. The hub is unaffected — its sweep still just restarts.
- **Ground clutter**: regolith, highlands and ice tiles now generate extra
  "cluttered" atlas variants — stones, craters/rubble, pressure cracks —
  used by a percentage of tiles, independent of the base texture pick.

### Changed

- **Stronger furnace/hopper glow FX.** `_draw_glow` now builds from four
  nested discs (was three) with roughly double the alpha per ring; the old
  version read as too faint next to the buildings' baked-in art. Raised the
  per-building glow alpha/radius on the ice harvester's furnace, the
  smelter's grill, the crystal extractor's hopper, and the hydroponics
  grow-lights to match.
- **Stalled buildings now read differently from shut-down ones.**
  `BuildingSprite` splits "dimmed" (no power/workers/hub — greyed out) from
  a new "working" state (actually producing this tick): overlay FX
  (plumes, vents, dust, lamps, glows) now run only while working, so a
  building stalled on "Storage full" stays lit and staffed but visibly
  goes quiet, instead of looking identical to a powered-down one.
- **`ColonyBot` learned warehouses**: builds them when xenite capacity falls
  short of the beacon target or a line is genuinely stalled for want of
  room (capped at 4 — reacting to any full store instead paved the map,
  since fresh capacity just refills). Also: a reserve can no longer gate a
  *free* building (it was blocking the free hub, starving the colony), the
  parts factory now has rebuild hysteresis (bank 40, don't rebuild until
  under 12) to stop it oscillating, and the mine metal reserve dropped
  2 → 1 since storage caps mean metal can't be hoarded anyway. Starting
  metal 120 → 50 so the colony lands within its own (now much smaller)
  hub yard. `make playtest`: 5/5 seeds win, 25.4–26.4 minutes (avg 25.9).
- **Rebalance for finite deposits**: `victory.xenite` 150 → 260, crystal
  extractor rate 0.15 → 0.022, mine rate 0.35 → 0.30, `growth_ticks`
  default in `sim/balance.gd` synced to the shipped 110. The endgame is now
  a prospect → work-out → relocate cycle across several crystal formations
  rather than one sit at a single deposit.
- **`ColonyBot` reworked** for the finite-deposit economy: it clears
  worked-out extractors for the refund, keeps a standing metal reserve for
  the next mine (deposits deplete in clusters, so the whole fleet can
  collapse at once), aims survey stations at the nearest unconfirmed
  visible crystal formation, never re-sites onto a tile it has already
  emptied, and tears down the parts factory once 40 parts are banked.
  `make playtest`: 5/5 seeds win, 24.2–24.6 minutes (avg 24.4).

- **VOID terrain now renders as bottomless canyons instead of flat dark
  diamonds**: `TerrainView` autotiles rift walls per-cell from a 2-bit
  neighbour mask (only the two far edges are ever visible from this camera
  angle) and shades each one through a dithered dark-to-light ramp from a
  sunlit rim down to an unbroken abyss with no floor, so adjoining rift
  tiles merge into one continuous void. `Palette.VOID_HI`/`VOID_STAR`
  replaced by `VOID_RIM`/`VOID_ABYSS`.

- **Terrain rendering reworked to flow rather than tile as separate plates**:
  removed the black rim outline and lit/shadowed bevel from `TerrainView`,
  replaced with a faint per-terrain seam at tile boundaries and a flatter
  fill, so the grid reads as a hint (via hover cursor/overlays) instead of
  an outline around every diamond.

- **UI restructure: top-bar stats, popup help, hover readout** (2026-07-27)
  - `ui/resource_bar.gd` gained a right-aligned `set_stats()` showing
    power drawn/generated and colonists/capacity/workers (same
    red-on-deficit, amber-at-capacity colouring as before), plus a `?`
    button opening a new help popup (`HelpLayer` in `main.tscn`, also
    bound to the `H` key) with `main.gd`'s `HELP_TEXT`.
  - New `ui/hover_panel.gd` (`HoverPanel` in `main.tscn`): a cursor-following
    panel showing the hovered tile's terrain/survey reading and, when a
    building is there, its live state (running/idle, power, workers,
    capacity, life support, recipe or mining progress) — the same facts
    `Colony.building_report()` always provided, now read where you're
    already looking instead of a sidebar section.
  - Click-to-select a building is removed (superseded by hover); `main.gd`
    no longer tracks `_selected_id`.
  - `ui/sidebar.gd` is back to a command surface only: title, mode, speed,
    build list. Lost `set_tile_info`/`set_economy`/`set_colony`/
    `set_inspector`; `set_economy` became `set_speed`. The permanently-
    wrapped hint paragraph is gone (superseded by the help popup).
  - Full suite: 1127 assertions across 98 tests, 0 failures (`make test`).
- **CI release workflow** (2026-07-27)
  - New `.github/workflows/release.yml`: on a `vX.Y.Z` tag (also
    `workflow_dispatch` for a build-only dry run), tests, cross-builds all
    three platforms (macOS on a real Mac runner so its ad-hoc signature is
    produced and verified by real `codesign`, Linux/Windows cross-exported
    from Ubuntu), and publishes them to a GitHub release. Refuses to build if
    the tag doesn't match `config/version` in `project.godot`.
  - New `.github/actions/setup-godot/action.yml`: composite action that
    installs and caches the pinned Godot editor + matching export templates.
  - CI/docs only — no game code, no test-count change.
- **Distribution / export support** (2026-07-27)
  - New `export_presets.cfg` (committed): macOS (universal Intel + Apple
    Silicon, ad-hoc signed), Windows (x86_64, pck embedded), and Linux
    (x86_64, pck embedded) presets, all excluding `tests/*` and `tools/*`.
  - `Makefile`: new `make export`/`make export-macos`/`make export-windows`/
    `make export-linux` (build zips into `build/`, named from
    `project.godot`'s new `config/version`) and `make release` (tests, then
    all exports — a failing suite can't be packaged). `make clean` now also
    removes `build/`.
  - New `dist/READ-ME-FIRST-{macos,windows,linux}.txt`, bundled into each
    zip: first-run warning steps, controls, save locations.
  - New `DISTRIBUTING.md`: the full guide — what ships, the unsigned
    first-run warning per platform and how to get past it, hosting
    (itch.io), and how to cut a release.
  - `project.godot`: `config/version="1.0.0"` and
    `rendering/textures/vram_compression/import_etc2_astc=true` (required
    for macOS universal/arm64 export).
  - Built and verified all three platforms: macOS app launches from the
    unzipped copy with its ad-hoc signature intact, Linux binary keeps its
    executable bit, `tests/`/`tools/` confirmed absent from packed data.
    Full suite: 1127 assertions across 98 tests, 0 failures (`make test`).
- **Milestone 9 — v2 candidates (M9 complete)** (2026-07-27)
  - New `docs/v2-candidates.md`: five sketched-but-not-built candidates from
    the plan (deposit depletion, depot/logistics radius, hostile events,
    terrain elevation, second colonist tier), each with sim/view impact,
    risks, and size, plus a suggested order and explicit non-goals. This
    completes Milestone 9's acceptance criteria — three playtests without
    exploits or dead-ends (`make playtest`: 5/5 seeds win, 20.3–41.4 min,
    avg 29.9) and the v2 list written down — and with it all nine
    milestones (0–9) of `colony-game-plan.md`. Docs only; no code changed.
    Full suite: 1127 assertions across 98 tests, 0 failures (`make test`).
- **Milestone 9 — Balance pass** (2026-07-27)
  - New `Balance.demolish_refund` (default `0.5`, clamped `0.0`–`1.0`),
    exposed as `colony.demolish_refund` in `data/balance.json`.
    `Colony.demolish_at()` now credits `floor(cost × refund)` per resource
    via a new `_refund()` — the colony's only way to recover resources from
    an over-committed building, fixing a soft-lock the pacing harness found
    (a running parts factory can eat an entire two-smelter metal income,
    permanently pinning metal at ~0 with no way to afford the crystal
    extractor). Flooring the refund means a build/demolish cycle is always
    a net loss, so it can't be farmed. Demolish button tooltip
    (`ui/sidebar.gd`) states the refund percentage.
  - New tests in `tests/test_tuning.gd`: refund amount, can't-be-farmed,
    `0.0` disables it, out-of-range values clamp.
- **Milestone 9 — Pacing tuning** (2026-07-27)
  - `data/balance.json`: `victory.xenite` 50 → 150, `colony.growth_ticks`
    80 → 110. `data/buildings.json`: mine `base_per_tick` 0.5 → 0.35,
    crystal extractor `base_per_tick` 0.25 → 0.15, `ticks_per_ring` 2 → 3
    for both the hub and the survey station (prospecting is the dominant
    term in the ramp). Moves the bot's win time from 11.1–19.4 min (avg
    15.8) to 20.3–41.4 min (avg 29.9) across the 5 playtest seeds, landing
    a human session in the plan's 45–90 minute window.
  - `tests/test_pacing.gd`: replaced the "not trivially short" floor check
    with `test_sessions_land_in_the_intended_window`, asserting every seed
    finishes in 15–50 bot-minutes.
  - `tools/colony_bot.gd`: the bot now waits for the hub's first survey
    sweep (a confirmed iron tile) before building anything else — it's
    possible to bury the hub's guaranteed iron deposit under a building
    placed before prospecting confirms it, since the guarantee lands in the
    tiles right beside the hub and an unconfirmed deposit is invisible.
- **Milestone 9 — Pacing harness (`ColonyBot`, `make playtest`)** (2026-07-27)
  - New `tools/colony_bot.gd` (`ColonyBot`): a scripted reference player
    driving the real `Colony`/`ColonyMap` classes headlessly (no autoloads,
    no rendering) — follows the intended build order (metal loop → power →
    life support → housing → prospect outward → parts chain → crystal
    extractor), buying the instant it can afford to, so its times are a
    *floor* on session length, not a prediction of human play. Reports a
    first-appearance timeline per resource and the full build order.
    `ColonyBot.load_defs()` preprocesses `buildings.json` the way `Defs`
    does, for headless scripts with no autoloads.
  - New `tools/playtest.gd` + `make playtest`: runs 5 seeds, prints
    outcome/ticks/minutes/timeline/build order per seed and a summary;
    exits non-zero if any seed fails to win. Currently 5/5 seeds win,
    11.1–19.4 min of game time (average 15.8).
  - New `tests/test_pacing.gd`: every seed wins, no seed starves the
    colony, the full ore→metal→parts→xenite chain is exercised, and a
    session isn't trivially short (CI guard against an unwinnable or
    degenerate balance change).
- **Milestone 9 — Tuning layer (`Balance`/`data/balance.json`)** (2026-07-27)
  - New `sim/balance.gd` (`Balance`, `class_name`, `RefCounted`): every
    tunable sim number in one injectable object (starting population/
    capacity, starve/growth ticks, victory xenite, guaranteed-deposit
    richness, life support, starting stockpile, tick rate, autosave
    interval, low-stock floor, prospecting reading jitter), with the
    shipped values as defaults so a bare `Balance.new()`/`Colony` behaves
    exactly as before. `Balance.from_dict()` applies a partial or missing
    file over those defaults.
  - New `data/balance.json`: the pacing/pressure dial, separate from
    `data/buildings.json` (costs/power/recipes/yields). Loaded by
    `Defs._load_balance()` into `Defs.balance`.
  - `Colony`, `ColonyMap`, `AlertMonitor`, and `Sim` now take/read an
    injected `Balance` instead of hard-coded constants
    (`STARTING_POPULATION`, `STARVE_TICKS`, `LIFE_SUPPORT`,
    `READING_JITTER`, `LOW_STOCK`, `TICKS_PER_SECOND`, `AUTOSAVE_SECONDS`,
    `STARTING_STOCKPILE`, etc. are gone). Pure extraction — no shipped
    number changed.
  - New `tests/test_tuning.gd`: the tuning contract itself (shipped file
    parses, empty/partial overrides behave correctly, JSON numeric types
    are preserved, a tuned `Balance` actually reaches `Colony`, sanity
    guards on the shipped numbers).

- **Milestone 8 — Audio (M8 complete)** (2026-07-27)
  - New `Audio` autoload (`audio/audio.gd`), a fourth (view-layer-only)
    autoload alongside `Sim`/`Defs`/`Events` — listens on `Events`, never
    touches sim state, and is a singleton solely so the ambient bed
    survives the menu↔game scene switch. Two runtime-created buses
    (Music, SFX), an 8-voice one-shot pool with voice stealing, per-cue
    pitch jitter, a 40ms same-cue repeat guard, mute + music/SFX volume
    persisted to `user://settings.cfg`, and `shutdown()`. Validates the
    cue manifest but plays nothing in headless runs (no audio device).
  - New `audio/audio_cues.gd` (`AudioCues`): the pure cue vocabulary and
    event→cue mapping (`for_alert(level)` clamps so an alert can never go
    silent; `for_game_over(won)`).
  - New `data/audio.json` (loaded into `Defs.audio`): the cue manifest —
    file, bus, volume_db, optional pitch range, loop. Adding a sound is a
    WAV plus a manifest entry, no engine code.
  - New `tools/gen_audio.py` + `make audio`: synthesizes every WAV with
    Python's stdlib only (no deps, no downloaded assets) — nine
    chiptune-ish SFX (ui_click, place, denied, demolish, alert tiers,
    win, lose) and a 32-second, mathematically seamless ambient bed.
  - New `assets/audio/*.wav` (+ `.import` sidecars, committed): lossless
    PCM; `ambient.wav` loops via the `edit/loop_mode` import property.
  - Event hooks: place/demolish/alert/game-over play their matching cue;
    `main.gd` plays `denied` on a refused action; every sidebar/menu/
    pause-menu button plays `ui_click`. New pause-menu "Sound: On/Off"
    toggle, persisted.
  - New `tests/test_audio.gd`: manifest contract (every required cue
    defined, files exist, valid bus/volume/pitch ranges, only the bed
    loops) and the alert/game-over cue mapping including out-of-range
    clamping. Full suite: 1068 assertions across 83 tests, 0 failures
    (`make test`). This completes Milestone 8.

- **Building FX overlays** (2026-07-25)
  - New `render/building_fx.gd` (`BuildingFX`): data-driven decorative
    overlays anchored on building art, so static sprites feel alive without
    animating the art itself. Seven kinds (`BuildingFX.TYPES`): `smoke`,
    `steam`, `dust`, `sparks`, `shimmer` (CPUParticles2D, sharing one
    procedurally-built puff texture) plus drawn `lamp` (blinking beacon,
    `lamp_intensity(t, period, duty)` gives the blink curve) and `glow`
    (pulsing bloom). `set_active(false)` stops emitters and darkens lamps.
  - `data/buildings.json`: new optional `fx` array per building (`at` is a
    pixel offset from the sprite's anchor, plus per-entry color/rate/scale/
    alpha/period/duty/radius overrides). All 11 buildings now have fx —
    beacon/status lamps, smokestack plumes, vent steam, ground dust, furnace
    embers and glow, crystal shimmer.
  - `sim/defs.gd`: preprocesses each fx entry's `color` hex into
    `color_value` (Defs doesn't validate effect kinds — the renderer owns
    those).
  - `render/buildings_view.gd`: `_attach_fx()` parents a `BuildingFX` to an
    art-backed building's sprite, phase-offset by building id so identical
    buildings don't blink/puff in lockstep. `render/building_sprite.gd`:
    `attach_fx()`; `set_dimmed()` now also stops/darkens the fx, so a
    shut-down building stops venting and its lights go dark.
  - New `tests/test_building_fx.gd`: fx JSON contract (known types, anchors
    land on the sprite, valid hex colors/positive periods, fx only on
    buildings with art) and the lamp blink curve. Full suite: 991
    assertions across 76 tests, 0 failures (`make test`).

- **Milestone 8 — Building art integration, part 2** (2026-07-23)
  - `data/buildings.json`: the remaining six buildings — solar panel,
    survey station, crystal extractor, habitat, parts factory, ice
    harvester — gained a `sprite` field, so **all 11 buildings now render
    custom PixelLab art**. Refreshed `hub.png` art. `survey_station`
    footprint reduced 2×2→1×1 to match its art (cost/power/scan/prereqs
    unchanged); the only remaining 2×2 buildings are `hub`, `habitat`,
    `hydroponics_farm`. Removed the last `smoke: true` flag
    (`parts_factory`) — its art carries its own smokestacks.
  - New `assets/`: `solar.png`, `iceharvester.png`, `crystalextractor.png`
    (64×64), `habitat.png`, `partsfactory.png` (128×128), plus `.import`
    sidecars.
  - The procedural building-block path (dithered blocks, blinking lamps,
    smoke puffs) is now a fallback exercised by no shipped building — kept
    for robustness / future spriteless buildings.
  - Only audio remains pending for Milestone 8. No sim/test changes — full
    suite still 835 assertions across 70 tests, 0 failures (`make test`).

- **Milestone 8 — Building art integration** (2026-07-23)
  - `render/building_sprite.gd`: `BuildingSprite`/`configure()` gained an
    optional `Texture2D` arg; when set, it draws that texture instead of
    the procedural block, anchored so the art's bottom-centre sits on the
    front footprint cell's bottom vertex (one formula, works at any
    footprint size). Textured sprites are static — no lamps/smoke.
  - `render/buildings_view.gd`: loads/caches each building's `sprite` def
    path and spawns one sprite for the whole footprint when art exists,
    falling back to the procedural per-cell blocks otherwise. Occlusion
    still comes from the existing y-sorted `Buildings` layer.
  - `data/buildings.json`: new `sprite` field on 5 of 11 buildings — hub,
    mine, smelter, electrolysis plant, hydroponics farm now render custom
    PixelLab art (`assets/*.png`). Smelter's footprint reduced 2×2→1×1 to
    match its art (cost/workers/power/recipe unchanged). Six buildings
    (solar panel, habitat, ice harvester, survey station, parts factory,
    crystal extractor) still render procedurally, pending art.
  - New `assets/` folder: 5 PNGs + Godot `.import` sidecars.
  - No sim/test changes — full suite still 835 assertions across 70
    tests, 0 failures (`make test`).

- **Milestone 8 (visual half) — Retro art pass** (2026-07-22)
  - New `render/palette.gd` (`Palette`): one shared warm "regolith"
    dusty-brown/ochre colour family with amber highlights, plus cool cyan
    (ice) and violet (crystal) accents and building-detail tones (lit/unlit
    lamp, smoke). Every renderer now pulls colours from here.
  - `render/terrain_view.gd` rewritten: the procedural iso tileset now
    builds several dithered (4x4 Bayer), raised-edge variants per terrain
    (4 for regolith/highlands, 2 for ice/crystal/void) with a top-lit
    gradient, mottling, rim outline, and bevels; `render_map()` picks a
    variant per cell deterministically so the ground looks varied but
    stable. Ice and crystal get 3 animation frames (shifting sparkle
    pixels, ~0.4s each) so they shimmer.
  - `render/building_sprite.gd` rewritten: placed buildings gained a
    recessed roof panel, warm edge lines, and idle animation — two
    out-of-phase blinking indicator lamps and, on industrial buildings,
    rising/fading exhaust smoke puffs. A dimmed (shut-down) building's
    lamps go dark and it stops smoking. The placement ghost stays flat and
    static.
  - `data/buildings.json` / `render/buildings_view.gd`: new `smoke: true`
    field on the hub, smelter, and parts_factory; `BuildingsView` passes it
    only to the front-most footprint cell's sprite, so a multi-tile
    building has one plume.
  - Audio (the other half of Milestone 8) is deferred. No sim/test changes
    — full suite still 835 assertions across 70 tests, 0 failures
    (`make test`).

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

- **Colony Hub early-game rework** (2026-07-22)
  - New `hub` building (`data/buildings.json`, now 11 buildings): 2×2, 40
    metal, +15 power, `capacity: 4`, a new `life_support: 4` field, a `scan`
    block (radius 6), and `guarantees_deposit: "IRON"`. It's the only
    building unlocked at game start and the new tech root — Solar Panel,
    Habitat, Ice Harvester, Survey Station, and Mine now `requires_built:
    ["hub"]` (Mine no longer requires Survey Station), so the basic loop is
    hub → mine → smelter; Survey Station now exists to extend prospecting
    farther out for copper/xenite.
  - `Colony.life_support_covered()` sums `life_support` across active
    buildings; life support only charges the stockpile for colonists beyond
    that coverage, so the hub's base 4 colonists never starve while it
    stands (`BASE_CAPACITY` 4→0 — housing now comes from the hub, not an
    implicit colony ship).
  - Guaranteed reachable iron: `ColonyMap.set_deposit()` (new) plus
    `Colony._ensure_deposit_in_range()` — placing a building with
    `guarantees_deposit`/`scan` injects a mineable iron deposit into its
    survey radius if none is already reachable.
  - `Sim.STARTING_STOCKPILE` reduced (metal 200→120, oxygen/water/food
    100→60 each) — the buffer now only needs to cover the hub+mine+smelter
    bootstrap and the time until the hub is placed.
  - Inspector shows a "sustains N colonists" line for buildings with
    `life_support`.
  - New `tests/test_hub.gd`; `tests/test_balance.gd` updated for the
    hub+mine+smelter bootstrap and a requires-built-roots-at-hub check.
    Full suite: 835 assertions across 70 tests, 0 failures (`make test`).

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

- **Canyon rendering: missing wall on lone mesas' south corner**: grid
  diagonals are screen cardinals in this projection, so `_void_mask()` was
  missing the case where the tile directly north on screen (`x-1, y-1`) is
  solid ground but both edge neighbours are rift — the two flanking walls'
  corner column has to project down through this tile, and without it the
  tile got a black notch instead. New `VOID_N` mask bit in
  `render/terrain_view.gd` (atlas grown 4→8 masks × variants).

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
