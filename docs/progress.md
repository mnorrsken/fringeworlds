# Progress log

Milestone-by-milestone status. See [`colony-game-plan.md`](../colony-game-plan.md)
for the plan and acceptance criteria this tracks.

Current test count: **1329 assertions across 147 tests, 0 failures** (`make test`).

- **M0 — Project skeleton — done.** Godot project setup, autoloads
  (`Events`/`Defs`/`Sim`), `data/resources.json`, Makefile, headless test
  harness.
- **M1 — Isometric terrain & camera — done.** `ColonyMap` terrain gen,
  `IsoGrid` conversion (pinned against Godot's own TileMapLayer), pan/zoom
  camera, hover highlight. Visual "does it look right" was never
  human-verified, only the math.
- **M2 — Building placement — done.** `Colony` placement/occupancy,
  data-driven `buildings.json`, ghost preview, Dune II sidebar, bigger
  viewport.
- **M3 — Tick economy — done.** Power balance (oldest-first, newest
  shed), recipe production, speed controls (pause/1×/3×).
- **UI/UX passes (not milestones).** macOS trackpad zoom fix → later
  replaced by a `Z`-toggle zoom scheme (scroll no longer zooms); scrollable
  sidebar; faster panning; overhead minimap (`M`); post-M6: bigger window,
  a top glyph-based resource bar, sidebar where only the build list scrolls;
  follow-up: smaller sidebar font, resource-glyph tooltips, low-stock alerts
  broadened to any net-drained resource (not just life support).
- **M4 — Deposits & prospecting — done.** Hidden deposit/richness layers,
  survey ring-scan (coarse→confirmed), prospecting overlay (`P`),
  deposit-gated mines with richness-scaled output.
- **M5 — Production chains & colonists — done.** Full resource chain
  (ore→metal→parts, water→oxygen/food), colonists with life
  support/workforce/growth/starvation, win (xenite) / lose (population 0)
  with a restart screen. Geothermal Plant deferred (needs a vent feature
  not yet on the map).
- **Pre-M6 fixes & balance (not a milestone) — done.** Multi-tile
  buildings now render per-tile (fixed depth/occlusion); early game
  automated (robots run the starter loop, colonists only needed for
  advanced buildings); tech-unlock gating on the build menu; starting
  metal and Solar Panel power raised to fix an early bootstrap dead-end
  ("metal cliff").
- **M6 — Real UI — done.** Building inspector (click to inspect, shows
  running/idle + why), alert ticker (power deficit, low life support,
  confirmed deposits), status overlay (`O`, running/idle dot per building).
- **M7 — Save/load & main menu — done.** Full sim state serializes via
  `ColonyMap`/`Colony` `to_dict`/`from_dict`; `Sim` save/load/list/delete
  API, autosave (~3 min), and an `active` gate so nothing simulates at the
  menu. New main menu (New Game/Continue/Load/Quit) is now the boot scene;
  a new in-game system menu (Escape) offers Resume/Save/Main Menu/Quit.
- **Colony Hub rework (not a milestone) — done.** New Hub building is the
  only thing unlocked at game start and the tech root; it sustains the
  base 4 colonists for free, prospects, and guarantees a reachable iron
  deposit, replacing the earlier "large starting stockpile" safety net
  with a structural one.
- **M8 — Retro art pass & audio — done.** Terrain and building art: a shared
  warm palette (`render/palette.gd`), dithered/raised/animated terrain
  tiles, and all 11 buildings render custom PixelLab art under `assets/`
  (procedural block rendering remains only as a fallback), each now with
  data-driven `BuildingFX` overlays (particle plumes/vents/dust/sparks/
  shimmer, blinking lamps, glows) so the static art reads as alive. Audio:
  a new view-layer `Audio` autoload (listens on `Events` only, never
  touches sim state) plays a data-driven cue set (`data/audio.json`) —
  nine SFX plus a looping ambient bed, all synthesized by
  `tools/gen_audio.py`/`make audio` rather than downloaded — with an
  8-voice pool, pitch jitter, mute/volume persisted to
  `user://settings.cfg`, and a new pause-menu Sound toggle.
- **M9 — Balance, polish, v2 hooks — done.** Every tunable sim
  number (population/capacity, starve/growth ticks, victory xenite, hub
  guaranteed richness, demolish refund, life support, starting stockpile,
  tick rate, autosave interval, low-stock floor, reading jitter) is now
  data-driven via `Balance`/`data/balance.json` (see `docs/architecture.md`)
  — a pure extraction, shipped numbers unchanged at the time. Pacing is
  measured, not eyeballed: `ColonyBot`/`make playtest` (see
  `docs/architecture.md`) bot-plays the real sim. The balance pass acted on
  that data: a demolition refund (50% of cost) fixes a soft-lock the
  harness found (an over-committed colony — e.g. a parts factory outrunning
  its metal supply — had no way to recover resources since buildings can't
  be switched off), and pacing was retuned (`victory.xenite` 50→150,
  `growth_ticks` 80→110, slower mine/extractor output, slower prospecting
  rings) so the bot's win time moved from 11.1–19.4 min (avg 15.8) to
  20.3–41.4 min (avg 29.9), landing a human session in the plan's 45–90
  minute window; `tests/test_pacing.gd` now guards a 15–50 minute bot
  window. The v2 hooks list is now written down:
  [`docs/v2-candidates.md`](v2-candidates.md) sketches five candidates
  (deposit depletion, depot/logistics radius, hostile events, terrain
  elevation, second colonist tier) with sim/view impact, risks, size,
  suggested order, and explicit non-goals. This completes M9 — and with it
  all nine milestones (0–9) of `colony-game-plan.md`. Acceptance evidence:
  `make playtest` wins 5/5 seeds (20.3–41.4 min, avg 29.9), no dead-ends
  found in that run, and `tests/test_pacing.gd` guards the pacing window in
  CI so a future change can't silently regress it.

## All milestones complete

Milestones 0 through 9 are all done — see the plan
(`colony-game-plan.md`) for the original scope. Further work is tracked as
v2 candidates: [`docs/v2-candidates.md`](v2-candidates.md).

- **Distribution — done.** `make release`/`make export` build unsigned,
  self-contained macOS/Windows/Linux zips (`export_presets.cfg`,
  `dist/READ-ME-FIRST-*.txt`). A tagged push (`vX.Y.Z`) also builds and
  publishes a GitHub release via `.github/workflows/release.yml`. See
  [`DISTRIBUTING.md`](../DISTRIBUTING.md).
- **UI restructure — done.** Colony stats moved from the sidebar to the top
  bar, controls help moved to a popup (`H` or the `?` button), and
  building/tile info moved from click-to-select to a cursor hover panel
  (`ui/hover_panel.gd`). The sidebar is now mode/speed/build-list only. See
  `docs/architecture.md`'s "UI layer".
- **Finite deposits & required hub — done.** The biggest sim change since
  M9: deposits now hold a finite reserve (richness sizes it, not the
  extraction rate) and idle "worked out" at zero; xenite only generates on
  visible CRYSTAL terrain; the Colony Hub is free, unique, and required
  (every building, including life support, goes idle without one
  standing); survey stations must be built inside existing coverage; and
  confirming a deposit's richness away from the hub is now a slow,
  scattered resample rather than a second fast sweep. Rebalanced
  accordingly (`victory.xenite` 260, much slower extractor rates) and
  `ColonyBot` reworked to relocate worked-out extractors and manage a
  finite ore supply. `make playtest`: 5/5 seeds win, 24.2–24.6 min (avg
  24.4). See `docs/architecture.md`'s "Deposits and prospecting" and
  "Pacing harness".
- **Limited storage & Warehouse — done.** Storage is now capped, not
  infinite: buildings declare a `storage` block, `Colony.storage_for()`
  sums it over everything standing, and a full store stalls the producer
  feeding it ("Storage full") rather than destroying output or the ore
  underground. The Hub's small yard can't hold xenite at all, so a new
  Warehouse (12th building) is required — three of them, to hold the
  beacon's 260-xenite target. `ColonyBot` learned to build them; starting
  metal dropped 120 → 50 to fit the smaller hub yard. `make playtest`:
  5/5 seeds win, 25.4–26.4 min (avg 25.9). Warehouse now has its own art
  and rooftop steam/lamp FX. See `docs/architecture.md`'s "Storage limits".
- **Internal building buffers — done.** Producers/extractors now hold a
  small hopper (`building_buffer`, default 4) so a full colony store backs
  up before a line actually stalls. Overlay FX (plumes/vents/lamps) now
  track "actually working" separately from "dimmed" (shut down), so a
  stalled-on-storage building stays lit/staffed but goes visibly quiet.
  `make playtest`: 5/5 seeds win, 24.9–25.8 min (avg 25.3). See
  `docs/architecture.md`'s "Storage limits" and "Two visual states".
- **Patch mining & depletion taper — done.** Extractors now work a 3×3
  patch of matching ore around where they're sited (`mine.radius`),
  draining it nearest-first, and slow to 20% rate as the patch empties
  rather than running flat-out to the last unit. `deposit_units` roughly
  doubled (IRON 1400, COPPER 620, XENITE 70) so extractors relocate far
  less often. Xenite is now framed as an ordinary high-energy material
  rather than a bespoke victory token — banking the quota is "phase 1"
  (game-over title "PHASE 1 COMPLETE"), not the whole game. `make
  playtest`: 5/5 seeds win, average 29.1 min (up from 25.3). See
  `docs/architecture.md`'s "Deposits and prospecting".
- **Walking colonists — done.** A visible crowd (`ColonistCrowd`,
  `ColonistsView`) now walks the base — out of building doors, across open
  ground, back in for a shift — purely a view-layer reading of the
  population number; the sim is untouched (`make playtest` tick counts are
  identical). See `docs/architecture.md`'s "The colonist crowd".
