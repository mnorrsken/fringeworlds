# Regolith

A retro-styled isometric alien colony builder. Visual reference: SimCity
2000, Populous, Civilization I/II. Mechanical reference: the Anno series,
heavily simplified. Its signature mechanic: resource deposits are hidden
underground and must be found through prospecting before they can be
extracted.

Place buildings on the isometric terrain and watch a real fixed-tick
economy run: generators and consumers balance against a shared power
budget, production buildings turn inputs into outputs on a per-building
progress timer, and the whole thing runs at pause / 1× / 3× speed. A
Survey Station sweeps the ground in expanding rings, upgrading each tile's
reading from unscanned to a coarse guess to a confirmed deposit type and
richness — toggle the `P` overlay to see it happen — and mines/extractors
can only be built on confirmed ore, producing faster on richer tiles.
Colonists need oxygen, water, and food every tick, drawn from a
production chain you build (ice → water → oxygen/food); go hungry too
long and the colony starts losing colonists, keep everyone fed and housed
under capacity and it grows. Refine ore into metal into parts, extract
xenite once you've got enough parts to build the extractor, and hit the
victory threshold to "launch the beacon" — or lose everyone and see the
colony end, either way followed by a one-key restart.

The build menu unlocks new buildings as you build their prerequisites —
🔒 marks what's still out of reach — so a first playthrough naturally
walks: Solar Panel → Survey Station → Mine → Smelter → Parts Factory →
Crystal Extractor (plus Ice Harvester → Electrolysis Plant/Hydroponics
Farm on the side). The whole starter loop runs on robots (`workers: 0`);
colonists only become a labor requirement once you reach the
processing/advanced tier (Smelter, Parts Factory, Crystal Extractor), so
early pressure comes from power and resources, not headcount.

## Tech stack

- **Engine:** [Godot](https://godotengine.org/) 4.7.1
- **Language:** GDScript
- **Rendering:** 2D dimetric ("isometric") projection, 64×32 px tiles, low
  internal resolution (800×450, window 1600×900) with integer scaling and
  nearest-neighbor filtering for a crisp pixel-art look

## Getting Godot

```
brew install --cask godot
```

Or download from [godotengine.org/download](https://godotengine.org/download).
This project targets Godot **4.7.1**; `project.godot` requests the
`GL Compatibility` renderer, which runs on essentially any GPU.

## Running

```
make run       # play the game
make editor    # open the project in the Godot editor
```

Both wrap the `godot` binary. If it isn't on your `PATH`, override it:
`make run GODOT=/path/to/godot`.

## Testing

```
make test
```

Runs the headless sim test suite (`godot --headless --script
res://tests/run_tests.gd`) and exits non-zero on any failure. Currently:
**800 assertions across 60 tests, 0 failures.**

Other Makefile targets: `make build` / `make import` (headless import, fails
on script/asset errors — good for CI), `make clean` (remove the generated
`.godot/` cache).

## Folder structure

```
data/       JSON content definitions: resources.json, buildings.json (recipes live inline per building)
sim/        Pure simulation logic and state — no rendering dependency
render/     Views of sim state: tilemap, buildings, camera, hover cursor
ui/         Screen-space UI: the sidebar
tests/      Headless tests for sim logic
main.gd / main.tscn   Current game root
```

Simulation and rendering are kept strictly separate: the sim is plain data
and logic, testable headlessly and trivially serializable; rendering only
reads sim state and never writes game rules back. See
[`docs/architecture.md`](docs/architecture.md) for the full breakdown.

## Controls

| Input | Action |
|---|---|
| WASD / arrow keys, middle-mouse drag | Pan camera (faster than it used to be) |
| Z | Toggle zoom 1×↔2× (from 3×/4× snaps straight back to 1×) |
| Pinch, `+`/`-` | Fine zoom (secondary controls, up to 4×) |
| M | Toggle the overhead map (terrain, buildings, camera view; click to jump) |
| P | Toggle the prospecting overlay (tints tiles by scan state / deposit type) |
| O | Toggle the status overlay (green/red dot per building: running/idle) |
| Left click | Place selected building, demolish (in demolish mode), or inspect a building (in select mode) |
| Right click | Demolish at cursor, or cancel current mode |
| Esc | Close the overhead map if open, otherwise cancel current mode |
| Space | Pause / unpause (resumes at whatever speed was running) |
| 1 | Set speed to 1× |
| 3 | Set speed to 3× |
| F1 | Toggle debug overlay (grid coords, terrain, zoom, seed, FPS) |

Mouse wheel / trackpad scroll do **not** zoom (removed — it felt twitchy on
a trackpad); use `Z`, pinch, or `+`/`-` instead. Buildings and Demolish are
selected from the right-hand scrollable sidebar, which also shows the
current mode, the hovered tile's info, the stockpile with live per-second
rates, power used/produced (red on deficit), population/housing/workforce,
and the current speed. Clicking a building outside build/demolish mode
inspects it in a sidebar INSPECT section (status, why it's idle if it is,
power, workers, housing, recipe/mine progress); a fading alert ticker in
the bottom-left corner announces power deficits, low life support, and
newly confirmed deposits. When the colony wins or loses, press **Enter** on
the game-over screen to start a fresh colony.

## Buildings (current 10)

| Building | Footprint | Cost | Power | Workers | Produces | Requires built | Terrain / deposit |
|---|---|---|---|---|---|---|---|
| Solar Panel | 1×1 | 10 metal | +15 | 0 | — | — | Regolith, Highlands |
| Habitat | 2×2 | 30 metal | −2 | 0 | houses +6 colonists | — | Regolith |
| Ice Harvester | 1×1 | 15 metal | −5 | 0 | 1 water / 4 ticks (no inputs) | — | Ice |
| Survey Station | 2×2 | 25 metal | −3 | 0 | scans outward, ring every 2 ticks, radius 7 | Solar Panel | Regolith, Highlands |
| Electrolysis Plant | 1×1 | 20 metal | −4 | 0 | water → 1 oxygen / 3 ticks | Ice Harvester | Regolith, Highlands |
| Hydroponics Farm | 2×2 | 20 metal | −3 | 0 | water → 1 food / 3 ticks | Ice Harvester | Regolith |
| Mine | 1×1 | 20 metal | −4 | 0 | iron/copper ore, `0.5 × richness` / tick | Survey Station | confirmed Iron or Copper |
| Smelter | 2×2 | 25 metal | −4 | 2 | 2 iron ore → 1 metal / 2 ticks | Mine | Regolith, Highlands |
| Parts Factory | 2×2 | 35 metal | −5 | 3 | 2 metal + 1 copper ore → 1 parts / 4 ticks | Smelter | Regolith, Highlands |
| Crystal Extractor | 1×1 | 20 metal + 8 parts | −6 | 2 | xenite, `0.25 × richness` / tick | Parts Factory | confirmed Xenite |

Defined in `data/buildings.json`. Every building has a power figure and a
worker requirement; generators (positive power) always run, and both power
and workforce are allocated oldest-placed-first, with the newest
under-supplied buildings shutting down (and dimming on screen) when
demand exceeds supply of either. Only the processing/advanced tier
(Smelter, Parts Factory, Crystal Extractor) needs colonists to run — the
rest of the starter loop is fully automated. Mine and Crystal Extractor
can only be placed on a tile whose prospecting scan is CONFIRMED and whose
hidden deposit matches; their output rate scales with that deposit's
richness (0–100%, revealed exactly only once confirmed — a coarse scan
gives an imprecise guess). A locked building (unmet "Requires built")
can't be placed and shows 🔒 in the build menu until its prerequisite is
built — the unlock persists even if that prerequisite is later demolished.
The design plan's Geothermal Plant (a second power source, sited on a
surface vent) is deferred — the map doesn't generate vents yet, so Solar
Panel is the only power source for now.

## Status

Milestones 0 (project skeleton), 1 (isometric terrain rendering and
camera), 2 (building placement), 3 (simulation core: tick economy,
stockpile, power balance, speed controls), 4 (deposits and prospecting),
5 (full production chains and colonists), and 6 (real UI — building
inspector, alert ticker, status overlay) are done, plus a pre-M6
fixes-and-balance pass (correct multi-tile building depth-sorting, a
gentler early game, and the tech-unlock system described above).
Milestone 7 (save/load & main menu) is next. See
[`docs/progress.md`](docs/progress.md) for what's implemented, what's
verified by test vs. eyeballed on screen, and what's next.

## Documentation

- [`colony-game-plan.md`](colony-game-plan.md) — the authoritative design
  and milestone plan (architecture principles, game design, Milestones 0–9
  with acceptance criteria). Read this first.
- [`docs/architecture.md`](docs/architecture.md) — a map of the codebase for
  new contributors.
- [`docs/progress.md`](docs/progress.md) — milestone-by-milestone status log.
- [`CHANGELOG.md`](CHANGELOG.md) — dated record of notable changes.
