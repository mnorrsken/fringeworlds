# Progress log

Milestone-by-milestone status. See [`colony-game-plan.md`](../colony-game-plan.md)
for the plan and acceptance criteria this tracks.

Current test count: **773 assertions across 49 tests, 0 failures** (`make test`).

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
  sidebar; faster panning; overhead minimap (`M`).
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
- **M6 — Real UI — pending.** Sidebar already covers some ground (rates,
  power, colonists); still missing an alert ticker, building inspector,
  overlay toggles.
- **M7 — Save/load & main menu — pending.**
- **M8 — Retro art pass & audio — pending.** All art is currently
  procedural placeholder.
- **M9 — Balance, polish, v2 hooks — pending.**
