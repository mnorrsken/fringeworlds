# Regolith

A retro-styled isometric alien colony builder. Visual reference: SimCity
2000, Populous, Civilization I/II. Mechanical reference: the Anno series,
heavily simplified. Its signature mechanic: resource deposits are hidden
underground and must be found through prospecting before they can be
extracted.

Place buildings on the isometric terrain and watch a real fixed-tick
economy run: generators and consumers balance against a shared power
budget, production buildings turn inputs into outputs on a per-building
progress timer, and the whole thing runs at pause / 1× / 3× speed.

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
**734 assertions across 26 tests, 0 failures.**

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
| WASD / arrow keys, middle-mouse drag | Pan camera |
| Mouse wheel, trackpad scroll, pinch, `+`/`-` | Zoom (stepped, 1×–4×) |
| Left click | Place selected building, or demolish (in demolish mode) |
| Right click | Demolish at cursor, or cancel current mode |
| Esc | Cancel current mode |
| Space | Pause / unpause (resumes at whatever speed was running) |
| 1 | Set speed to 1× |
| 3 | Set speed to 3× |
| F1 | Toggle debug overlay (grid coords, terrain, zoom, seed, FPS) |

Buildings and Demolish are selected from the right-hand scrollable sidebar,
which also shows the current mode, the hovered tile's info, the stockpile
with live per-second rates, power used/produced (red on deficit), and the
current speed. Zoom works via a two-finger scroll or pinch on a MacBook
trackpad / Magic Mouse, not just a physical scroll wheel.

## Buildings (current 4)

| Building | Footprint | Cost | Power | Recipe | Terrain |
|---|---|---|---|---|---|
| Solar Panel | 1×1 | 10 metal | +10 | — | Regolith, Highlands |
| Ice Harvester | 1×1 | 15 metal | −5 | 1 water / 4 ticks (no inputs) | Ice |
| Habitat | 2×2 | 30 metal | −2 | — | Regolith |
| Survey Station | 2×2 | 25 metal | −3 | — | Regolith, Highlands |

Defined in `data/buildings.json`. Every building has a power figure;
generators (positive power) always run, consumers (negative power) run
oldest-placed-first and the newest ones shut down (and dim on screen) when
demand exceeds supply. Only Ice Harvester has a recipe so far — the rest of
the production chain from the design plan arrives in later milestones.

## Status

Milestones 0 (project skeleton), 1 (isometric terrain rendering and
camera), 2 (building placement), and 3 (simulation core: tick economy,
stockpile, power balance, speed controls) are done. See
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
