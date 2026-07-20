# Project Plan: Isometric Alien Colony Game

Working title: **Regolith** (rename freely)

A retro-styled isometric colony builder about settling an alien planet. Visual
reference: SimCity 2000, Populous, Civilization I/II. Mechanical reference: the
Anno series, heavily simplified. Core differentiator: resource deposits are
hidden and must be found through prospecting before they can be extracted.

This document is the reference plan for implementation with Claude Code. Work
milestone by milestone. Each milestone has acceptance criteria — do not move on
until they pass.

---

## 1. Technology decisions (locked)

- **Engine:** Godot 4.x (latest stable). Free, MIT-licensed, native editor on
  macOS and Windows, exports to both.
- **Language:** GDScript for everything initially. Consider C# or GDExtension
  only if a profiled hotspot demands it (unlikely at this scope).
- **Version control:** git from day one. Godot projects are plain text
  (`.tscn`, `.gd`, `.tres`), so diffs are meaningful. Add the standard Godot
  `.gitignore` (`.godot/` directory must be ignored).
- **Rendering style:** 2D dimetric ("isometric") projection, 2:1 tile ratio,
  tile size **64×32 px**. Low internal resolution (e.g. 640×360), integer
  scaling to window size, nearest-neighbor filtering, snap 2D transforms to
  pixel. These are project settings in Godot — set them in Milestone 0.
- **Placeholder art:** Kenney isometric asset packs (CC0) until custom pixel
  art exists. Custom art later in Aseprite with a restricted palette
  (32–64 colors, dithering for gradients — this is most of the SC2000 look).

## 2. Architecture principles (read before writing code)

These matter more than any individual feature. Violating them makes every
later milestone harder.

1. **Simulation and rendering are separate.** The simulation is pure data and
   logic: 2D arrays / dictionaries keyed by grid coordinates, advanced by a
   fixed tick (start with 4 ticks/second via a Timer or accumulator in
   `_process`). Rendering reads sim state and draws it. No game rules live in
   sprite nodes. This makes the sim testable headlessly and save/load trivial.
2. **Buildings and tiles are data, not scenes.** A placed building is an entry
   in the sim state (type id, grid position, condition, inventory). A
   lightweight sprite is spawned to represent it. Do not make each building a
   heavyweight scene with its own logic script.
3. **Data-driven definitions.** Building types, resource types, and recipes
   live in JSON files under `data/` (or Godot custom Resources — pick JSON for
   easier editing by hand and by Claude Code). Adding a new building must not
   require touching engine code.
4. **Autoload singletons, few of them:** `Sim` (game state + tick loop),
   `Defs` (loaded definitions), `Events` (signal bus for sim → UI
   communication). UI never pokes sim internals directly; it calls sim methods
   and listens to signals.
5. **Grid math in one place.** A single `IsoGrid` helper owns
   world↔grid↔screen coordinate conversion. Everything else uses it.

Suggested folder structure:

```
project/
  data/            # buildings.json, resources.json, recipes.json
  sim/             # pure logic: sim.gd, map.gd, prospecting.gd, economy.gd
  render/          # tilemap setup, building sprites, overlays
  ui/              # HUD, build menu, tooltips
  assets/          # sprites, palettes, audio
  tests/           # headless tests for sim logic
```

## 3. Game design summary

### Setting and core loop

You land a colony ship on an unexplored alien planet. The loop:

**survey terrain → prospect for deposits → place extractors → refine through
short production chains → sustain colonists → expand into harsher terrain.**

Life support (oxygen, water, food, power) is the constant pressure, replacing
Anno's population-tier demands. Keep it to one colonist tier for v1.

### Terrain types (v1)

Flat regolith (buildable), rocky highlands (buildable, some buildings only),
ice fields (source of water ice), crystal formations (impassable, decorative),
canyons/void (impassable). No water bodies, no ships — this cuts the hardest
part of Anno entirely.

### Resources and deposits

Two categories:

- **Surface resources** — visible on the map from the start: ice fields,
  geothermal vents (energy hotspots).
- **Subsurface deposits** — invisible until prospected: iron ore, copper ore,
  rare crystals ("xenite"). Generated at map creation as deposit blobs with a
  richness value per tile, stored in a hidden layer of the sim map.

### Prospecting (the signature mechanic)

- A **Survey Station** building scans a radius around itself over time
  (e.g. one ring of tiles per N ticks, expanding outward).
- Scan results are **uncertain at first**: a scanned tile initially shows a
  coarse reading ("traces of metal") drawn from its true value plus noise.
  Building a higher-tier survey upgrade, or scanning the same area again,
  narrows the reading to the true deposit type and richness.
- Extraction buildings (Mine, Crystal Extractor) can only be placed on tiles
  with a **confirmed** deposit of the matching type, and their output rate
  scales with deposit richness. Deposits deplete slowly (optional in v1 —
  implement the richness field now, depletion later).
- UI: a toggleable prospecting overlay tints tiles by scan state
  (unscanned / coarse reading / confirmed) — very SimCity-2000-ish.

### Production chains (short, Anno-flavored)

Global stockpile economy in v1 — no carts, no transport routes. Buildings pull
inputs from and push outputs to a shared colony inventory. (A depot/coverage
radius mechanic is a v2 candidate, noted in Milestone 9.)

- Ice Harvester (on ice field) → **Water**
- Electrolysis Plant: Water → **Oxygen**
- Hydroponics Farm: Water → **Food**
- Mine (on confirmed ore) → **Iron Ore** / **Copper Ore**
- Smelter: Ore → **Metal**
- Parts Factory: Metal → **Parts** (needed to construct advanced buildings)
- Crystal Extractor (on confirmed xenite) → **Xenite** (late-game currency /
  win-condition resource)
- Power: Solar Panel (steady, cheap) and Geothermal Plant (on vent, strong).
  Power is a capacity balance (produced vs. consumed), not a stored resource.

### Colonists

One habitat building type provides housing capacity. Colonists consume oxygen,
water, and food per tick; buildings require workforce (a simple number, not
simulated individuals walking around — no pathfinding in v1). If life support
runs out, colonists die and buildings shut down. Colonist count grows slowly
while all needs are met.

### Victory / failure (v1)

Failure: colony population reaches zero. Victory: accumulate a target amount
of Xenite to "launch the beacon". Enough to make a session have an arc;
sandbox beyond that.

---

## 4. Milestones

### Milestone 0 — Project skeleton

Create the Godot project with the folder structure above. Configure: internal
resolution + integer scaling (`viewport` stretch mode), nearest-neighbor
texture filtering, pixel snap. Add `.gitignore`, initialize git. Create empty
autoloads `Sim`, `Defs`, `Events`. Load a placeholder `data/resources.json`
in `Defs` to prove the data pipeline.

*Accept when:* project opens and runs an empty scene at the correct pixel
scale on both a small and a large window; `Defs` prints loaded resource
definitions.

### Milestone 1 — Isometric terrain rendering and camera

Generate a map (start 64×64 tiles) with FastNoiseLite: noise thresholds map to
terrain types. Store terrain in the sim as an array — the TileMapLayer is only
a view of it. Render with Godot's isometric TileMapLayer (diamond down, 64×32).
Camera: middle-mouse / WASD panning, stepped zoom at integer factors. Implement
`IsoGrid` screen↔grid conversion and prove it with a hover highlight on the
tile under the cursor, plus a debug label showing grid coordinates.

*Accept when:* a varied alien landscape renders; panning and zoom feel right;
the hovered tile is always correctly identified, including after pan/zoom.

### Milestone 2 — Building placement

Define 3–4 buildings in `data/buildings.json` (name, footprint size, cost,
allowed terrain, sprite). Build menu selects a building; a ghost preview
follows the cursor, tinted green/red by validity (terrain allowed, tiles
unoccupied, cost affordable). Click to place: sim records the building,
occupancy map updates, resources are deducted, sprite spawns at the correct
draw position (mind y-sorting for multi-tile footprints). Right-click or a
demolish tool removes buildings.

*Accept when:* buildings of at least two different footprint sizes (1×1 and
2×2) can be placed and demolished with correct validation and no visual
sorting glitches.

### Milestone 3 — Simulation core: tick, stockpile, power

Implement the fixed tick loop in `Sim`. Global stockpile dictionary
(resource id → amount). Producer/consumer logic: each tick, iterate buildings;
a building with a recipe consumes inputs if available and produces outputs
(carry a simple per-building progress counter so rates can be non-integer).
Power as a capacity check each tick: if consumption exceeds production,
buildings shut down in placement order (newest first) until balanced; shut
buildings render dimmed. Speed controls: pause / 1× / 3×.

*Accept when:* placing a Solar Panel and an Ice Harvester makes Water tick
upward; removing the panel stops the harvester; the resource HUD (temporary
debug UI is fine) updates live; pause works.

### Milestone 4 — Deposits and prospecting

At map generation, create the hidden deposit layer: blob-shaped deposits
(random walk or low-frequency noise masked by threshold) with per-tile
richness 0.0–1.0. Implement the Survey Station: expanding scan over ticks,
per-tile scan state machine (unscanned → coarse → confirmed), coarse readings
= true value + noise. Prospecting overlay toggle rendering scan state and
readings. Placement validation extended: Mine requires a confirmed matching
deposit under it; mine output rate = base rate × richness.

*Accept when:* a fresh map shows no deposits; building a Survey Station
progressively reveals coarse then confirmed readings; a Mine can only be
placed on confirmed ore and visibly produces faster on rich tiles.

### Milestone 5 — Full production chains and colonists

Add the remaining buildings and recipes from the design section. Implement
habitats, colonist count, per-tick life-support consumption, workforce: each
building declares workers needed; if total demand exceeds population, lowest-
priority buildings idle. Colonist growth when all needs met, deaths when
oxygen/food/water hit zero. Failure state (population 0) with a game-over
screen; Xenite victory threshold with a victory screen.

*Accept when:* a full playthrough is possible: survive on starter resources,
prospect, build the metal chain, reach xenite extraction, win — and starving
the colony on purpose triggers the loss state.

### Milestone 6 — Real UI

Replace debug UI: top resource bar with rates (+/- per second), build menu
with categories and cost/requirement tooltips, building inspection panel on
click (status, inputs/outputs, workers, "why am I idle" reason), alert ticker
for critical events (power deficit, oxygen low, deposit confirmed) via the
`Events` bus. Overlay toggles: prospecting, power coverage.

*Accept when:* the game is playable without reading the code — every idle
building explains itself, and every resource crisis is announced before it
kills the colony.

### Milestone 7 — Save/load and main menu

Serialize the entire sim state (map, deposits, scan states, buildings,
stockpile, colonists, tick counter, RNG seed) to JSON in `user://saves/`.
Main menu: New Game (map seed + size), Continue, Load, Quit. Autosave every
N minutes.

*Accept when:* save → quit → load reproduces the exact game state, verified
by comparing a re-serialized snapshot to the saved file.

### Milestone 8 — Retro art pass and audio

Replace placeholders with a consistent custom tileset: one 32–64 color
palette, dithered shading, SC2000-style raised edges on terrain. Building
sprites with 2–3 frame idle animations (blinking lights, smoke). Ambient
soundtrack loop + UI/placement/alert sounds. Optional flavor: subtle animated
tiles (crystal shimmer, vent steam).

*Accept when:* a screenshot reads unambiguously as "90s isometric sim" and
all art shares one palette.

### Milestone 9 — Balance, polish, v2 hooks

Tune numbers via a dedicated `data/balance.json`. Playtest full sessions and
adjust pacing (target: first win in 45–90 minutes). Candidate v2 features to
design but not build yet: deposit depletion, depot/logistics radius replacing
the global stockpile, hostile events (dust storms damaging solar output),
terrain elevation, a second colonist tier with new demands.

*Accept when:* three consecutive playtests are completable without exploits
or dead-ends, and the v2 list is written down.

---

## 5. Working with Claude Code on this project

- Tackle **one milestone per session/branch**; commit at each acceptance
  criterion. Reference this file and the current milestone explicitly.
- Ask for **headless tests** on sim logic (grid math, recipe ticking,
  scan-noise convergence, save/load round-trip). Godot can run scripts
  headlessly with `godot --headless --script`; GUT is the common test
  framework if more structure is wanted.
- Keep `data/*.json` as the single source of truth for content. When asking
  for a new building, ask for a data entry + sprite hookup, not new code
  paths.
- When something looks wrong on screen, suspect coordinate conversion first —
  keep the debug grid-coordinate overlay from Milestone 1 available behind a
  hotkey for the whole project lifetime.
