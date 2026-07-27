# Distributing Regolith

```sh
make release        # runs the test suite, then builds all three platforms
ls build/*.zip      # macOS, Windows, Linux — send these to people
```

That's the whole loop. The rest of this document explains what those zips are,
the one thing your friends will hit on first launch, and what it would take to
make that go away.

## What gets built

| File | Contains | Size |
| --- | --- | --- |
| `Regolith-<version>-macos.zip` | `Regolith.app` (universal: Intel + Apple Silicon) + READ ME FIRST | ~59 MB |
| `Regolith-<version>-windows.zip` | `Regolith.exe` (data embedded, single file) + READ ME FIRST | ~38 MB |
| `Regolith-<version>-linux.zip` | `Regolith.x86_64` (data embedded) + READ ME FIRST | ~29 MB |

Each zip carries the right `READ ME FIRST.txt` for its platform (sources in
`dist/`), covering the first-run warning, the controls, and where saves live.

**There is no installer, deliberately.** A `.pkg` or `.msi` buys nothing here:
the game is a single self-contained executable with no dependencies, no
registry entries and nothing to uninstall. An installer would also need the
same code signing that the plain executable does — so it would add work and
still show the same warnings. Unzip and run is the right shape for this.

## The first-run warning (read this before you send anything)

The builds are **unsigned**, which means every desktop OS will warn about them
once. This is not something you did wrong, and it is not fixable for free.
Tell people in advance or they will assume the game is broken:

- **macOS** — "Regolith can't be opened because Apple cannot check it for
  malicious software". They must **right-click the app and choose Open**, then
  Open again in the dialog. Once, on first launch.
  If macOS instead says the app **"is damaged"**, that's the quarantine flag on
  downloaded files: `xattr -dr com.apple.quarantine /path/to/Regolith.app`.
- **Windows** — SmartScreen shows "Windows protected your PC". **More info →
  Run anyway.** Once.
- **Linux** — no warning; the executable bit is preserved in the zip.

The macOS build *is* ad-hoc signed (`codesign/codesign=1` in the preset). That
isn't for Gatekeeper — it's because macOS refuses to run unsigned arm64 binaries
at all, so without it the app would simply fail to launch on any Apple Silicon
Mac. Verify a build with `codesign --verify --deep --strict Regolith.app`.

## Getting the files to people

Any file host works — the zips are self-contained. Google Drive, Dropbox and
WeTransfer are the path of least resistance for a handful of friends.

If you want something nicer, **itch.io** is the standard home for this kind of
thing: free, upload the three zips to one page, mark it private or
password-protected, and people get a single link with per-platform downloads.
It also handles updates gracefully — friends re-download from the same link
rather than hunting for the newest attachment in a chat thread.

## Making the warnings go away

Only worth it if the game escapes the friends-and-family circle:

- **macOS**: an Apple Developer Program membership (around $99/year — check
  current pricing), then set a signing identity and team ID in the preset and
  enable notarization. Apple staples a ticket to the app and Gatekeeper stops
  complaining.
- **Windows**: a code-signing certificate from a CA (a few hundred dollars a
  year). Note that a *new* certificate still trips SmartScreen until it builds
  reputation, so the first few hundred downloads warn anyway.

For a game you're handing to friends, the two-second right-click is a better
trade than a yearly bill.

## Requirements to build

- Godot 4.7.1 on `PATH` (`brew install --cask godot`).
- **Export templates for the exact same version**, which are a ~1 GB download
  and are *not* in this repo. Either open the editor → Editor → Manage Export
  Templates → Download, or fetch them directly:

  ```sh
  curl -L -o templates.tpz \
    https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz
  unzip templates.tpz -d /tmp/tpl
  mkdir -p "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable"
  cp /tmp/tpl/templates/* "$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable/"
  ```

  If the templates don't match the engine version exactly, exports fail.

All three platforms cross-export from macOS; no Windows or Linux machine is
needed.

## Cutting a release

1. Bump `config/version` in `project.godot` (it names the zips and fills in the
   macOS bundle version).
2. `make release` — this runs the full test suite **first** and stops if
   anything fails, so a broken build can't be packaged. It also runs the
   pacing harness's completability tests, which is the closest thing to a
   guarantee that the version you're shipping can actually be finished.
3. Spot-check one build by hand: `open build/stage/*/Regolith.app`.
4. Upload, and tell people about the first-run warning.

`make export` skips the tests if you just want artifacts quickly.

## Where saves live

Useful when someone reports a bug, or wants to wipe and start over:

- macOS: `~/Library/Application Support/Godot/app_userdata/Regolith/`
- Windows: `%APPDATA%\Godot\app_userdata\Regolith\`
- Linux: `~/.local/share/godot/app_userdata/Regolith/`

Saves are plain JSON, so a broken one can be inspected and usually salvaged.
The sound on/off setting lives beside them in `settings.cfg`.

## Notes for future builds

- `export_presets.cfg` is committed; the `build/` directory is gitignored.
- The presets exclude `tests/*` and `tools/*`, so the pacing harness and the
  test suite aren't shipped to players.
- macOS universal builds require
  `rendering/textures/vram_compression/import_etc2_astc=true` in
  `project.godot`. Godot refuses to export arm64 without it. Our pixel art
  imports lossless, so nothing actually uses the compressed variant.
