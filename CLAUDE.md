# CLAUDE.md — Regolith

Retro isometric alien-colony builder in **Godot 4.7** (GDScript). Signature
mechanic: hidden subsurface deposits found by prospecting before they can be
mined.

- **The plan is authoritative:** `colony-game-plan.md` defines the milestones
  (0–9) and the architecture principles. Read it before starting work.
- **Current status & codebase map:** `docs/progress.md` (milestone status) and
  `docs/architecture.md` (how the code fits together). Keep these as the source
  of truth for "where are we" — do not duplicate status into this file.

## Commands

Godot is installed via Homebrew (`brew install --cask godot`), on PATH as
`godot`. All work goes through the Makefile:

- `make run` — run the game
- `make editor` — open the Godot editor
- `make test` — headless test suite (exits non-zero on failure)
- `make import` / `make build` — headless import; catches script/asset errors
- `make clean` — remove the `.godot/` cache

Override the binary if needed: `make test GODOT=/path/to/godot`.

## Architecture (don't violate these — see the plan §2)

- **Sim and rendering are separate.** Sim is pure data + logic; rendering only
  reads sim state. No game rules in sprite/node scripts.
- **Pure, injectable sim classes.** Core logic lives in `RefCounted` classes
  with **no autoload/Events/rendering dependencies** — `ColonyMap` (`sim/map.gd`)
  and `Colony` (`sim/colony.gd`, placement + tick economy + prospecting). This is
  what makes the sim headlessly testable. The `Sim` autoload wraps `Colony` and
  adds `Events` signal emission.
- **Three autoloads only:** `Sim` (state + fixed tick loop), `Defs` (loads
  `data/*.json`), `Events` (signal bus). UI never pokes sim internals — it calls
  Sim methods and listens on `Events`.
- **Grid math in one place:** `IsoGrid` (`sim/iso_grid.gd`) owns all
  grid↔screen conversion, matched to Godot's isometric TileMapLayer (tested).
- **Content is data-driven:** buildings/resources live in `data/*.json`. Adding
  content = editing JSON, not engine code. `Defs` preprocesses defs at load
  (terrain/deposit name→id, hex→Color).

Folders: `sim/` (logic), `render/` (views), `ui/` (HUD/sidebar), `data/` (JSON),
`tests/` (headless tests), `assets/`.

## Development flow (follow this loop)

1. **One milestone at a time**, in plan order. Don't move on until its
   acceptance criteria pass. Big milestones are built as a few logical features.
2. **Put new logic in the pure sim classes** (`Colony`/`ColonyMap`) so it can be
   tested without the engine. The `Sim` autoload is a thin wrapper that emits
   `Events`.
3. **Write headless tests** in `tests/test_*.gd`. The runner
   (`tests/run_tests.gd`) auto-discovers every `test_*` method and passes a
   tester `t` with `t.ok(cond, msg)` / `t.eq(a, b, msg)`. Test pure logic
   directly — construct `Colony`/`ColonyMap` with hand-made defs; don't rely on
   autoloads in tests.
4. **Verify before declaring done:**
   - `make import` — compiles cleanly (no script errors)
   - `make test` — all green
   - `godot --headless --quit-after 20` — no runtime errors in `_ready`/`_process`
   - **Visual check via a throwaway capture scene** (see below) when a change is
     visual — headless can't be eyeballed otherwise.
5. **After each logical feature/change, hand off to the docs agent** (see next
   section) to update docs + README + CHANGELOG and commit.

### Visual verification (headless screenshots)

The game window can't be eyeballed from a background session, so to check
visuals, create a *throwaway* `capture.tscn` + `capture.gd`, run it, read the
PNG, then delete both files. Pattern:

```gdscript
extends Node
var _f := 0
func _ready() -> void:
    add_child(load("res://main.tscn").instantiate())
func _process(_d: float) -> void:
    _f += 1
    if _f == 30:  # let a few frames render (set up sim state earlier if needed)
        get_viewport().get_texture().get_image().save_png("<scratch>/shot.png")
        get_tree().quit()
```

Run with `godot res://capture.tscn`, view the PNG, then `rm capture.gd
capture.tscn capture.gd.uid`. Save PNGs to a scratch/tmp dir, never the repo.

## Docs & commits (automated per feature/change)

Docs and git are handled by the **`docs` agent** (defined in
`.claude/agents/docs.md`, Sonnet — invoke with `subagent_type: "docs"`), after
each logical, working change (not per file save). The invariant rules live in
that definition; when invoking, just describe *what changed*. It:

- updates `docs/progress.md` (milestone status), `README.md`, and `CHANGELOG.md`;
- runs `make test` first and commits **only if green**;
- makes scoped commits (separate feature code from docs), **does not push**;
- ends every commit message with the trailer
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`;
- touches docs + git only — it never modifies game code.

Commit only when work is verified. Never commit `.godot/` (it's gitignored).

## GDScript notes

- **Indent with tabs** (Godot convention) — mixed spaces/tabs won't parse.
- Cast `InputEvent` subtypes before accessing subtype fields
  (`var mb := event as InputEventMouseButton`) or type inference fails.
- Keep the F1 debug coordinate overlay working — when something looks wrong
  on screen, suspect coordinate conversion first (plan §5).
