# Regolith

A retro-styled isometric alien colony builder. Visual reference: SimCity
2000, Populous, Civilization I/II. Mechanical reference: the Anno series,
heavily simplified. Its signature mechanic: resource deposits are hidden
underground and must be found through prospecting before they can be
extracted.

## Tech stack

- **Engine:** [Godot](https://godotengine.org/) 4.7.1
- **Language:** GDScript
- **Rendering:** 2D dimetric ("isometric") projection, 64×32 px tiles, low
  internal resolution (640×360) with integer scaling and nearest-neighbor
  filtering for a crisp pixel-art look

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
**701 assertions across 9 tests, 0 failures.**

Other Makefile targets: `make build` / `make import` (headless import, fails
on script/asset errors — good for CI), `make clean` (remove the generated
`.godot/` cache).

## Folder structure

```
data/       JSON content definitions (resources, buildings, recipes)
sim/        Pure simulation logic and state — no rendering dependency
render/     Views of sim state: tilemap rendering, camera
tests/      Headless tests for sim logic
main.gd / main.tscn   Current game root
```

Simulation and rendering are kept strictly separate: the sim is plain data
and logic, testable headlessly and trivially serializable; rendering only
reads sim state and never writes game rules back. See
[`docs/architecture.md`](docs/architecture.md) for the full breakdown.

## Status

Milestones 0 (project skeleton) and 1 (isometric terrain rendering and
camera) are done. See [`docs/progress.md`](docs/progress.md) for what's
implemented, what's verified by test vs. eyeballed on screen, and what's
next.

## Documentation

- [`colony-game-plan.md`](colony-game-plan.md) — the authoritative design
  and milestone plan (architecture principles, game design, Milestones 0–9
  with acceptance criteria). Read this first.
- [`docs/architecture.md`](docs/architecture.md) — a map of the codebase for
  new contributors.
- [`docs/progress.md`](docs/progress.md) — milestone-by-milestone status log.
- [`CHANGELOG.md`](CHANGELOG.md) — dated record of notable changes.
