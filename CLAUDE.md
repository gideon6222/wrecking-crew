# Wrecking Crew

A native Android game for Gideon's S26 Ultra, built in Godot 4.7 and copied from
`C:\dev\godot-template` on 2026-09-08. Package `com.gideon.wreckingcrew`, repo
`github.com/gideon6222/wrecking-crew`.

@../gamedev-notes/INDEX.md

The shared rules, the Godot traps, the toolchain paths, the export and signing rules and the
process are in `C:\dev\gamedev-notes` (`INDEX.md` loaded above, then `GODOT.md`, `CRAFT.md`,
`TESTING.md`, `ASSETS.md`, `POLISH.md`). **This file carries only what is specific to this
game.** `PLAN.md` is a reconstructed record of what exists and what is missing; `NOTES.md`
has the decisions and the measured numbers; `C:\dev\gamedev-notes\playtests\wrecking-crew.md`
is his words about it - and every quote in it predates the game described here.

> **Rewritten on 2026-09-12 against the shipped code.** What this file said until then - a
> condemned building above ground, bays, a fixed number of swings, a lean that is the centroid
> of what is still standing, a topple threshold and a clean bonus - was v0.3.0, and `src/`
> stopped containing any of it on 2026-09-08. If anything below disagrees with `src/sim/`, the
> code is right and this file has gone stale again.

## This game

**You are alone in the basement of a condemned tower with a tracked wrecking machine, cutting
the columns out from under a slab that is going to come down on you.** Drive, build ball
speed, break a column, watch the support gauge fall; below 70 per cent the slab lets go and
you have thirteen seconds to reach the ramp with everything you have earned.

The design in the order it has to be understood:

1. **Nothing aims the ball.** It is a free point mass on an inextensible chain hanging from the
   boom tip - `CHAIN` 4.2 m, `SWING_G` 29.0, a period of about 2.4 s falling out of
   `2*PI*sqrt(CHAIN/SWING_G)`. The only way to move it is to move the thing it is attached to,
   so **the vehicle is the wind-up**. The slider slews the boom, which is where the ball hangs
   FROM; it is not an aim.
2. **Damage is SPEED, not contact.** Below `HIT_MIN_SPEED` 3.2 m/s the ball clunks and does
   nothing; `Tuning.damage_at()` ramps squared to `HIT_DAMAGE` 60.0 at `HIT_FULL_SPEED` 11.0,
   with `HIT_COOLDOWN` 0.16 s per target so damage is not a function of the frame rate. This is
   the claim the whole control scheme rests on, and the NUDGER golden is the proof: a full
   minute creeping at a quarter throttle lands one contact, no columns and no rubble.
3. **The support gauge is the resource, and spending it is irreversible.** `integrity` is the
   fraction of the deck's original capacity still standing. A column carries
   `COLUMN_CAPACITY` 1.0 and pays `COLUMN_RUBBLE` 120; an infill wall carries 0.22 and pays 35
   - so both are worth breaking and only one of them really moves the gauge. That is the trade
   the player learns by watching, not from a tooltip.
4. **At `COLLAPSE_AT` 0.7 the slab lets go**, `collapsing` goes true and `ESCAPE_SECONDS` 13.0
   starts. Reaching the ramp pays `ESCAPE_BONUS_PER_SECOND` 40 a second plus
   `TOTAL_TEARDOWN_BONUS` 400 for having taken every column; the clock running out is
   `crushed()` and the whole haul is gone. **The decision the game is made of is "one more
   column, or leave now"**, and the golden pair proves it is real rather than rhetorical:
   GREEDY banks 1030 and loses all of it, WRECKER banks 879 and keeps it.
5. **The machine is tracked: it pivots, then it goes.** The left stick is a WORLD direction
   (`drive_dir`), not a heading. Outside `ALIGN_CONE` 0.65 rad the tracks counter-rotate and no
   throttle is applied at all; inside it the throttle ramps in as the nose comes round. The
   45 per cent throttle floor this replaced is what made the previous build read as drifting.
6. **The same basement is the same basement every time**, keyed on (place, level) through
   `SimUtil.hash2`. That determinism is what makes a whole-run golden possible, and the golden
   is what makes every claim above a test rather than an opinion.

## Commands

```powershell
$env:GODOT = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"

scripts\check.ps1                 # import -> pure tests -> smoke -> size guard, fails fast
scripts\check.ps1 -Export         # plus the debug APK, then the size guard against it
scripts\device.ps1 install | launch | log | shot | record 30 | perf | back | home | resume
& $env:GODOT --path . --resolution 540x960 --script res://scripts/shot.gd -- 16.0 <tag>
& $env:GODOT --headless --path . --script res://test/run_probe.gd   # balance readings, cannot fail
& $env:GODOT --path .             # the editor
```

`scripts\movie.ps1 -Replay ...` works but has nothing to play: **`test/replays/` does not
exist in this repo**, so a filmed run needs a scenario recorded first with
`& $env:GODOT --path . -- record=test/replays/<name>.json`, and `scripts/rects.gd` (in a real
window, never headless) is the only thing that can tell you where the controls actually are.

Everything except the probe, the screenshot and `rects.gd` exits non-zero on failure, which is
what makes them a gate rather than something to read.

## Files

| File | What it is |
|---|---|
| `src/sim/sim.gd` | **The whole game, with no renderer in it**: the deck, the machine, the chain, damage, `integrity`, the collapse and the escape |
| `src/sim/tuning.gd` | Every number that shapes how it feels, with the reason beside it, plus `damage_at`, `escape_margin`, `total_capacity`, the per-level curves |
| `src/sim/util.gd`, `rng.gd` | `smooth`, `hash2`, `fmt` - the hash is load-bearing; the seeded stream, used only by the renderer's debris |
| `src/game/main.gd` | The shell: reads `Sim`, draws it, feeds it input. Decides nothing. Builds the whole world in code and owns the save |
| `src/game/main.tscn` | Four lines. One node with the script |
| `src/build_stamp.gd`, `src/changelog.gd` | Stamp (overwritten by CI, committed as "dev"/"unbuilt") and `VERSION` + patch notes |
| `test/run_tests.gd` | The pure suite. The list is a **glob**, and an empty glob fails - zero tests is not zero failures |
| `test/run_smoke.gd` | Boots the real scene; asserts the camera is behind the machine and facing in |
| `test/run_probe.gd` | Balance readings over levels 1-4. Prints; cannot fail |
| `test/harness.gd` | The assertions, with `FLOAT_EPS` - a golden over floats cannot use exact equality |
| `test/policies.gd` | `PASSIVE`, `NUDGER`, `GREEDY`, `WRECKER`. **The definition of "playing well"** |
| `test/test_golden.gd` | Whole-run goldens at level 2, one per policy, each failing for a different reason |
| `test/test_tuning.gd` | Design tests - assertions about intent, not values |
| `test/test_sim.gd`, `test/test_util.gd` | The simulation and the helpers |
| `test/test_controls.gd` | **The handedness gate.** Drives a real input event through the real handler and asserts screen right is world +X |
| `test/test_sim_boundary.gd` | `INDEX.md` standing rule 2 as a gate: nothing under `src/sim/` touches a Node, a Viewport, an input event or a real frame |
| `test/test_version.gd` | `Changelog.VERSION`, `RELEASES[0].version` and `version/name` + `version/code` in BOTH export presets are one fact |
| `scripts/check.ps1` | Everything that can run on the desk, in the order that fails fastest |
| `scripts/device.ps1` | The phone over adb: install, launch, log, shot, record, perf, poke |
| `scripts/movie.ps1` | Movie Maker plus an ffmpeg contact sheet. Needs a replay file; see above |
| `scripts/replay_player.gd` | Autoload: `-- record=<file>`, `-- replay=<file>`, `-- touch` |
| `scripts/rects.gd` | Where the controls REALLY are, in a real window - a headless root reports 100x100 and every anchored control resolves against it |
| `scripts/shot.gd` | Deterministic screenshot. First numeric user arg is the seconds, first non-numeric one is the tag |
| `scripts/check_size.gd`, `size-budget.json` | APK size guard, 31,154,417 bytes ±10%, failing in both directions, and refusing a stale APK rather than measuring it |
| `scripts/stamp.ps1`, `scripts/export_release.bat` | The build stamp written from git before an export; the release AAB, in a batch file so the preset name keeps its quotes |
| `assets/` | Three files: `abandoned_parking_1k.hdr`, `concrete_normal.webp`, `concrete_rough.webp`. **No `CREDITS.md`, and no licence recorded for any of them** |
| `PLAN.md`, `NOTES.md`, `PRIVACY.md` | The reconstructed record; the decisions and measurements; the store privacy page |

Against the template this repo is missing `test/replays/*.json`, `assets/CREDITS.md` and
`REFERENCE.md` (no reference game is named in any source), and its CI has no `play` job - it
was scaffolded sixteen minutes before the template grew one.

## Invariants specific to this game

Shared invariants (pure sim, no `randf()` in state, the hash, `_ensure_booted`, `looking_at`,
the flush, freeze-before-advance, anchored HUD, `FLOAT_EPS`, headless MultiMesh colours,
`global_transform`, Dictionary Variants, `use_colors`, `Basis.scaled`, `TorusMesh`, culling
against the camera) are in `GODOT.md` and are not repeated here.

- **The chain is arithmetic, never a PhysicsBody on a joint.** A joint would put the outcome of
  every run inside the physics server at the mercy of its tick rate and end any chance of a
  golden. **Physics is for debris and for the slab coming down, neither of which decides
  anything.**
- **The ball's velocity is derived from actual displacement, never integrated through the
  constraint.** A distance constraint injects energy if anything moves the ball without that
  motion being accounted for; it once measured 216 m/s on a machine that cannot exceed 9.5.
- **`BALL_MAX_SPEED` 60.0 is a guard, not a mechanic.** It sits above anything the machine can
  legitimately produce, so that it never fires in normal play and its firing is therefore a
  signal. At 34 it clamped during ordinary hard driving, which hides the runaway it exists to
  catch: a guard that is always on carries no information.
- **`ball_y()` is derived from the chain, in one function**, so the collision and the drawing
  cannot disagree about how high the ball is riding.
- **`integrity` is clamped to 1.0**, because `total_capacity()` normalises against the AVERAGE
  number of infill panels and a given basement may have more. Without the clamp the gauge reads
  "SUPPORT 102%".
- **The sim works in a 2D plane (x across, y INTO the room) and the world maps it to
  (x, height, -y), so depth runs along -Z.** A chase camera behind an object moving toward +Z
  has to be rotated 180 degrees about Y, which mirrors X and inverts the steering - a sibling
  game shipped exactly that for its entire life. An axis convention cannot come apart; a sign
  flip has to stay true through every future change to the camera.
- **Both controls are relative to the MACHINE**, which is the only reason the chase camera is
  allowed to turn with it here when it could not in the runner versions: there is no world axis
  left for a mirrored camera to invert. `test_controls.gd` and `run_smoke.gd` assert screen
  right is world +X anyway, because this studio has shipped inverted controls six times.
- **The ramp only counts once the slab is coming down**, or the player could park in the exit
  and never play; and `_blocks_ramp` refuses to place an infill wall across the mouth, because
  a level that is unfinishable in a way the player cannot see is the worst kind of unfair.
- **Difficulty is per-level arithmetic** (`column_hp_for`, `escape_seconds_for`), never a
  mutated constant, and `escape_margin()` is asserted rather than eyeballed: "can the player
  actually get out" is the number that decides whether the collapse is tense or unfair.

## Ports and identifiers

Nothing on the web stack here. Package `com.gideon.wreckingcrew`, APK
`build/wrecking-crew.apk` (preset "Android"), AAB `build/wrecking-crew.aab` (preset
"Android Release", gradle build on), launch component
`com.gideon.wreckingcrew/com.godot.game.GodotAppLauncher`.

## Shared rules and recording

Everything general lives in `C:\dev\gamedev-notes`: the invariants every game keeps and the
engine traps in `GODOT.md`, design in `CRAFT.md`, the ship gate in `POLISH.md`. Record a lesson
the moment it is learned with `/record-lesson` (it writes to the notes' `inbox/`), and his
words with `/record-lesson playtest wrecking-crew`. Never edit the notes' topic files from a
build session.
