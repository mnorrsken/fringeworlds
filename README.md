# Regolith

A retro-styled isometric alien colony builder. Visual reference: SimCity
2000, Populous, Civilization I/II. Mechanical reference: the Anno series,
heavily simplified. Its signature mechanic: resource deposits are hidden
underground and must be found through prospecting before they can be
extracted.

Start by placing the Colony Hub — free, unique, and the only building
unlocked at the beginning — which sustains your first 4 colonists for
free, generates power, prospects the surrounding ground, and guarantees a
reachable iron deposit nearby, so a new colony can never get stuck without
buildable ore. Nothing else in the colony runs without a hub standing —
demolish it and every building, including life support, goes idle until
you rebuild one.

Place buildings on the isometric terrain and watch a real fixed-tick
economy run: generators and consumers balance against a shared power
budget, production buildings turn inputs into outputs on a per-building
progress timer, and the whole thing runs at pause / 1× / 3× speed. A
Survey Station (built inside existing survey coverage) sweeps the ground
in expanding rings, upgrading each tile's reading from unscanned to a
coarse guess to a confirmed deposit — toggle the `P` overlay to see it
happen. Finding a deposit is quick; away from the hub, confirming how
rich it is is a slow, scattered resample. Deposits are finite: richness
sizes how many units are down there, not how fast they come up. An
extractor works the whole 3×3 patch of matching ore around where it's
sited, drawing it down nearest-first and slowing as the patch empties, and
eventually runs the whole patch dry and has to be moved. Xenite lives
visibly in crystal formations — an ordinary high-energy material now, not
just a victory token — you can see where the crystal is from the start,
but not how much is in it. Colonists
need oxygen, water, and food every tick, drawn from a production chain
you build (ice → water → oxygen/food); go hungry too long and the colony
starts losing colonists, keep everyone fed and housed under capacity and
it grows. Storage is limited too — the Colony Hub's yard is small and can't
hold xenite at all, so a full store stalls whatever's feeding it until you
build Warehouses. Refine ore into metal into parts, extract xenite once
you've got enough parts to build the extractor, and hit the victory
threshold to complete "phase 1" (the beacon launches) — or lose everyone
and see the colony end, either way followed by a one-key restart.

The build menu unlocks new buildings as you build their prerequisites —
🔒 marks what's still out of reach — so a first playthrough naturally
walks: Hub → Mine → Smelter → Parts Factory → Crystal Extractor (plus
Solar Panel for extra power, Ice Harvester → Electrolysis Plant/
Hydroponics Farm, and Survey Station to extend prospecting for copper and
xenite). The whole starter loop runs on robots (`workers: 0`);
colonists only become a labor requirement once you reach the
processing/advanced tier (Smelter, Parts Factory, Crystal Extractor), so
early pressure comes from power and resources, not headcount.

## Tech stack

- **Engine:** [Godot](https://godotengine.org/) 4.7.1
- **Language:** GDScript
- **Rendering:** 2D dimetric ("isometric") projection, 64×32 px tiles, low
  internal resolution (1280×720, window 1920×1080) with integer scaling and
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
**1276 assertions across 133 tests, 0 failures.**

Other Makefile targets: `make build` / `make import` (headless import, fails
on script/asset errors — good for CI), `make audio` (regenerates every WAV
under `assets/audio/` via `tools/gen_audio.py` — Python stdlib only, no
downloaded assets), `make playtest` (bot-plays several seeds headlessly and
prints win/loss, timing, and build order — see
[`docs/architecture.md`](docs/architecture.md#pacing-harness-colonybot-milestone-9)),
`make clean` (remove the generated `.godot/` cache and `build/`).

## Playing / distributing

`make release` (tests, then exports) or `make export` builds zipped,
self-contained builds for macOS, Windows, and Linux into `build/`. The
builds are unsigned, so first launch takes one extra click (macOS:
right-click → Open; Windows: SmartScreen → More info → Run anyway; Linux:
no warning). Pushing a version tag (`vX.Y.Z`, matching `config/version` in
`project.godot`) builds and publishes all three platforms as a GitHub
release via `.github/workflows/release.yml`. See
[`DISTRIBUTING.md`](DISTRIBUTING.md) for the full guide.

## Folder structure

```
data/       JSON content definitions: resources.json, buildings.json (recipes live inline per building), audio.json, balance.json (tuning — see docs/architecture.md)
sim/        Pure simulation logic and state — no rendering dependency
render/     Views of sim state: tilemap, buildings, camera, hover cursor, shared palette
ui/         Screen-space UI: sidebar, top status bar, cursor hover readout
audio/      Sound layer (Audio autoload + cue vocabulary) — view-layer only, never touches sim state
tools/      Asset generators (`gen_audio.py`, run via `make audio`) and the
            headless pacing harness (`colony_bot.gd`, `playtest.gd`, run via
            `make playtest`)
tests/      Headless tests for sim logic
main.gd / main.tscn   In-game scene and controller
menu.gd / menu.tscn   Main menu (new/continue/load/quit) — the project's main scene
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
| P | Toggle the prospecting overlay (tints tiles by scan state, deposit type, and how much is left) |
| O | Toggle the status overlay (green/red dot per building: running/idle) |
| Left click | Place selected building, or demolish (in demolish mode) |
| Right click | Demolish at cursor, or cancel current mode |
| Hover | Read a tile's terrain, survey reading and building (see below) |
| H | Open/close the controls help popup |
| Esc | Close the help popup or overhead map if open, otherwise cancel current mode |
| Space | Pause / unpause (resumes at whatever speed was running) |
| 1 | Set speed to 1× |
| 3 | Set speed to 3× |
| F1 | Toggle debug overlay (grid coords, terrain, zoom, seed, FPS) |
| Esc (nothing else to close) | Open the in-game system menu: Resume, Save Game, Main Menu, Quit |

The game has sound: an ambient bed plus SFX for placing/demolishing
buildings, denied actions, alerts, and win/lose. The pause menu's "Sound:
On/Off" button mutes/unmutes, persisted across sessions.

Mouse wheel / trackpad scroll do **not** zoom (removed — it felt twitchy on
a trackpad); use `Z`, pinch, or `+`/`-` instead. A top status bar shows each
stockpiled resource as a coloured glyph + amount + per-second rate (e.g.
`⬢ 185`), switching to `amount/cap` once a resource is close to its storage
limit and turning amber at capacity, revealing new resources as they enter
the stockpile, plus the
colony's standing numbers on the right — power drawn/generated (red on
deficit) and colonists/capacity/workers (amber at capacity) — and a `?`
button (or `H`) opening a help popup with the full controls list. Hover a
resource glyph for its name and description. Buildings and Demolish are
selected from the right-hand sidebar, which is otherwise just the current
mode, speed, and the build list (only the list scrolls). Hovering any tile
shows a panel next to the cursor with its terrain and survey reading, and,
if a building sits there, its live state (status, why it's idle if it is,
power, workers, housing, recipe/mine progress) — there is no click-to-select.
A fading alert ticker in the bottom-left corner announces power deficits,
any resource running low while being net-drained (not just life support —
ore/metal/parts too), and newly confirmed deposits. When the colony wins or
loses, press **Enter** on the game-over screen to start a fresh colony.

## Buildings (current 12)

| Building | Footprint | Cost | Power | Workers | Produces | Requires built | Terrain / deposit |
|---|---|---|---|---|---|---|---|
| Colony Hub | 2×2 | free | +15 | 0 | sustains 4 colonists free; scans; guarantees nearby iron; holds up to 75 metal, 50 of each ore/parts, no xenite | — | Regolith |
| Solar Panel | 1×1 | 10 metal | +15 | 0 | — | Hub | Regolith, Highlands |
| Habitat | 2×2 | 30 metal | −2 | 0 | houses +6 colonists | Hub | Regolith |
| Ice Harvester | 1×1 | 15 metal | −5 | 0 | 1 water / 4 ticks (no inputs) | Hub | Ice |
| Survey Station | 1×1 | 25 metal | −3 | 0 | scans outward (ring every 3 ticks, radius 7), then slow resample to confirm | Hub, inside existing survey coverage | Regolith, Highlands |
| Electrolysis Plant | 1×1 | 20 metal | −4 | 0 | water → 1 oxygen / 3 ticks | Ice Harvester | Regolith, Highlands |
| Hydroponics Farm | 2×2 | 20 metal | −3 | 0 | water → 1 food / 3 ticks | Ice Harvester | Regolith |
| Mine | 1×1 | 20 metal | −4 | 0 | iron/copper ore from a 3×3 patch, 0.30/tick tapering to 20% as it empties | Hub | confirmed Iron or Copper |
| Smelter | 1×1 | 25 metal | −4 | 2 | 2 iron ore → 1 metal / 2 ticks | Mine | Regolith, Highlands |
| Parts Factory | 2×2 | 35 metal | −5 | 3 | 2 metal + 1 copper ore → 1 parts / 4 ticks | Smelter | Regolith, Highlands |
| Warehouse | 2×2 | 45 metal + 6 parts | −2 | 0 | holds up to 100 metal/ore, 60 parts, 90 xenite, 150 life support | Parts Factory | Regolith, Highlands |
| Crystal Extractor | 1×1 | 20 metal + 8 parts | −6 | 2 | xenite from a 3×3 patch, 0.022/tick tapering to 20% as it empties | Parts Factory | confirmed Xenite, Crystal terrain |

Defined in `data/buildings.json`. Storage is capped and physical: a
building's `storage` block adds to what the colony can hold of each
resource whether or not it's powered. Every producing/extracting building
also holds a small internal buffer (4 units per resource) — a full colony
store backs up through that buffer first, so a line keeps working for a
moment before it actually stalls ("Storage full") rather than destroying
the output; extractors idle the same way, leaving the ore in the ground.
While a building is stalled on storage it stays lit and staffed but its
plume/vents/lamps go quiet — that's the visible cue the colony has run out
of room, distinct from a dimmed building, which means no power/workers/hub.
The Hub's yard is deliberately small and holds no xenite at all, so
reaching the beacon's xenite target requires building Warehouses (three, at
90 xenite each). Demolishing a storage building spills whatever no longer
fits.

The Hub is free, unique (only one may
stand at a time), and required: with none active, every other building —
including life support — goes idle ("No colony hub") until one is rebuilt.
It's also the only building unlocked at game start and the root of the
tech tree, and guarantees a mineable iron deposit within its scan radius
on placement (injecting one if none is already reachable), so Mine only
needs the Hub, not a separate Survey Station. Every building has a power
figure and a worker requirement; generators (positive power) always run,
and both power and workforce are allocated oldest-placed-first, with the
newest under-supplied buildings shutting down (and dimming on screen) when
demand exceeds supply of either. Only the processing/advanced tier
(Smelter, Parts Factory, Crystal Extractor) needs colonists to run — the
rest of the starter loop is fully automated. Mine and Crystal Extractor
can only be placed on a tile whose prospecting scan is CONFIRMED and whose
hidden deposit matches (Crystal Extractor additionally requires Crystal
terrain, since that's the only place xenite generates); once sited, an
extractor works every matching-ore tile in a 3×3 patch around it, not just
the one it stands on, drawing the nearest ground first and slowing to 20%
of its rate as the whole patch empties — a worked-out patch idles ("Deposit
worked out") until the extractor is demolished and rebuilt elsewhere. A
tile's richness sizes its share of that reserve rather than its output
rate. A locked building
(unmet "Requires built") can't be placed and shows 🔒 in the build menu
until its prerequisite is built — the unlock persists even if that
prerequisite is later demolished. Demolishing any building refunds half
its cost (rounded down per resource — see Status below), shown in the
Demolish button's tooltip. The design plan's Geothermal Plant (a second
power source, sited on a surface vent) is deferred — the map doesn't
generate vents yet, so Solar Panel and the Hub are the only power sources
for now.

## Status

Milestones 0 (project skeleton), 1 (isometric terrain rendering and
camera), 2 (building placement), 3 (simulation core: tick economy,
stockpile, power balance, speed controls), 4 (deposits and prospecting),
5 (full production chains and colonists), 6 (real UI — building
inspector, alert ticker, status overlay), and 7 (save/load & main menu)
are done, plus a pre-M6 fixes-and-balance pass (correct multi-tile
building depth-sorting, a gentler early game, and the tech-unlock system
described above), a post-M6 UI/UX refinement pass (bigger window, a
top glyph-based resource bar, and a sidebar where only the build list
scrolls), a further UI restructure moving colony stats to the top bar,
controls help to a popup, and building/tile info to a cursor-following
hover panel (leaving the sidebar as a command surface: mode, speed, build
list), and a Colony Hub early-game rework (the game now starts with a
single Hub that sustains the base 4 colonists for free and guarantees
reachable iron, gating everything else behind it). The game now boots to
a main menu (New Game/Continue/Load/Quit) and the full sim state can be
saved/loaded, with autosave every ~3 minutes. Milestone 8 is now complete —
a retro art pass gives terrain dithered, raised, animated tiles and
buildings idle lamp/smoke animation, all in one warm palette
(`render/palette.gd`), and all 11 buildings now render custom PixelLab
sprites instead of the procedural block (the procedural path remains only
as a fallback), each now dressed with data-driven FX overlays (plumes,
vents, dust, sparks, shimmer, blinking lamps, glows —
`render/building_fx.gd`) that run only while the building is actually
producing (they also go quiet on a storage stall, not just a shutdown); and a
new `Audio` autoload plays a data-driven, synthesized sound set (ambient
bed + SFX, `make audio` regenerates the WAVs). Milestone 9 (balance,
polish, v2 hooks) is now in progress: every tunable simulation number has
been extracted into `data/balance.json` (see
[`docs/architecture.md`](docs/architecture.md#tuning-balance-milestone-9)),
a headless pacing harness (`ColonyBot`, `make playtest`, see
[`docs/architecture.md`](docs/architecture.md#pacing-harness-colonybot-milestone-9))
bot-plays the real sim to confirm every seed is completable, and a balance
pass has since acted on that data — a demolition refund (50% of cost,
`Balance.demolish_refund`) fixes a soft-lock the harness found (an
over-committed colony had no way to recover resources), and pacing was
retuned (slower prospecting rings, slower mines, a higher xenite target and
growth-tick count) so the bot's win time moved from 11–19 minutes to a
20–41 minute average of ~30, putting a human session in the plan's 45–90
minute window. **Milestone 9 is now complete**, and with it all nine
milestones (0–9) of the plan — `make playtest` wins 5/5 seeds with no
dead-ends found, `tests/test_pacing.gd` guards the pacing window in CI, and
the v2 hooks list is written down at
[`docs/v2-candidates.md`](docs/v2-candidates.md). With all nine milestones
done, the game now exports to distributable macOS/Windows/Linux builds
(`make release`/`make export`, see
[`DISTRIBUTING.md`](DISTRIBUTING.md)). See
[`docs/progress.md`](docs/progress.md) for what's implemented, what's
verified by test vs. eyeballed on screen, and what's next.

## Documentation

- [`colony-game-plan.md`](colony-game-plan.md) — the authoritative design
  and milestone plan (architecture principles, game design, Milestones 0–9
  with acceptance criteria). Read this first.
- [`docs/architecture.md`](docs/architecture.md) — a map of the codebase for
  new contributors.
- [`docs/progress.md`](docs/progress.md) — milestone-by-milestone status log.
- [`docs/v2-candidates.md`](docs/v2-candidates.md) — designed-but-not-built
  candidates for the next round of features, written per Milestone 9.
- [`DISTRIBUTING.md`](DISTRIBUTING.md) — how to build and ship the
  macOS/Windows/Linux distributable zips.
- [`CHANGELOG.md`](CHANGELOG.md) — dated record of notable changes.
