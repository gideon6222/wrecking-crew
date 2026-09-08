# Wrecking Crew

A native Android demolition runner for Gideon's S26 Ultra, built in Godot 4.7 and copied
from `C:\dev\godot-template`.

**The game in one sentence:** a rig drives down a condemned street, a wrecking ball swings
on a boom out in front of it, and the player aims the ball only by deciding where the rig
was a moment ago.

**Read `C:\dev\gamedev-notes` first** — `SKILL.md` (process), `CRAFT.md` (design lessons,
all of which apply here; they are about games, not about a language), `PIPELINE.md` (both
stacks; the Godot one is at the end), `ASSETS.md`, `PLAYTESTS.md`. `NOTES.md` next to this
file has the design reasoning and what to do next.

---

## The design, in the order it has to be understood

1. **The ball is driven by the rig's lateral ACCELERATION, not its position.** Pushing the
   rig right throws the ball left; it arrives on the right about a quarter of a swing
   period later. The player never places the ball, they only ever push it.
2. **The technique is the crane operator's**: load the swing by pulling AWAY from the kerb
   you want, then turn back into it. Measured, not guessed — a quarter-period load peaks
   at 4.19 from the centre line, a half-period load at 6.76.
3. **An impact reverses the ball and hands some energy back.** That is what makes a street
   a rhythm to chain rather than a list of separate setups, and it is why `REBOUND_MIN` is
   derived from the swing a kerb needs rather than picked.
4. **Buildings want the ball at a turning point** (widest, slowest). **Barricades want it
   mid-swing** (fastest, centred) — a hanging ball will not break one. One tool, two
   phases, and the street asks for both.
5. **Rubble is the score and the meter.** A full meter is another floor per swing for the
   rest of the run. There is no second currency yet because there is nothing to spend one
   on, and a HUD row that never does anything teaches the player to stop reading the HUD.

## Toolchain, and where it lives

Nothing is installed system-wide and nothing needed admin rights.

| Piece | Version | Path |
|---|---|---|
| Godot | 4.7.2 stable | `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*\Godot_v4.7.2-stable_win64_console.exe` |
| JDK | Temurin 17.0.20.1 | `C:\dev\toolchain\jdk\jdk-17.0.20.1+1` |
| Android SDK | platform 36, build-tools 36.0.0 | `C:\dev\toolchain\android-sdk` |
| Debug keystore | | `C:\dev\toolchain\debug.keystore` (alias `androiddebugkey`, pass `android`) |

Godot finds the SDK, the JDK and the keystore through **editor settings**, not through
environment variables — `%APPDATA%\Godot\editor_settings-4.7.tres`, keys under
`export/android/`. Setting `ANDROID_HOME` alone does nothing.

CI shares one signing identity through the `ANDROID_DEBUG_KEYSTORE_B64` repository secret,
so builds install over each other on the phone instead of needing an uninstall.

## Commands

```powershell
$godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"

& $godot --headless --path . --import                                   # after adding files
& $godot --headless --path . --script res://test/run_tests.gd           # pure tests, ~1s
& $godot --headless --path . --script res://test/run_smoke.gd           # boots the real scene
& $godot --headless --path . --script res://test/run_probe.gd           # balance readings, cannot fail
& $godot --headless --path . --export-debug "Android" build/wrecking-crew.apk
& $godot --headless --path . --script res://scripts/check_size.gd       # size guard
& $godot --path . --resolution 540x960 --script res://scripts/shot.gd -- 16.0   # screenshot
& $godot --path .                                                        # open the editor
```

Every one except the probe and the screenshot exits non-zero on failure, which is what
makes them a CI gate rather than something to read.

## Files

| File | What it is |
|---|---|
| `src/sim/sim.gd` | **The whole game, with no renderer in it.** The rig, the pendulum, the street |
| `src/sim/tuning.gd` | Every number that shapes how it feels, plus the derived arithmetic |
| `src/sim/util.gd` | `smooth`, `hash2`, `fmt` — pure, and the hash is load-bearing |
| `src/sim/rng.gd` | A seeded stream. Used only by the renderer's debris, never by the sim |
| `src/game/main.gd` | The shell: reads `Sim`, draws it, feeds it input. Decides nothing |
| `src/game/main.tscn` | Four lines. One node with the script; the world is built in code |
| `test/policies.gd` | The scripted players. **The definition of "playing well"** |
| `test/run_probe.gd` | Balance readings over six streets. Prints; never fails |
| `test/test_tuning.gd` | Design tests — assertions about intent, not values |
| `test/test_golden.gd` | Whole-run goldens over three policies |
| `scripts/shot.gd` | Deterministic screenshot of a chosen second of a chosen street |
| `scripts/check_size.gd` | APK size guard, fails in both directions |

## Invariants

- **`src/sim/` may not reference a Node, a Viewport, an input event or a real frame.**
  That one rule is what makes the whole-run golden possible and lets the renderer be
  replaced without touching game logic.
- **The pendulum is arithmetic, never a PhysicsBody on a joint.** A joint would put the
  outcome of every run inside the physics server at the mercy of its tick rate and end any
  chance of a golden. **Physics may be used for debris, which decides nothing.**
- **Nothing that affects game state may use `randf()`.** Place-keyed decisions go through
  `SimUtil.hash2` seeded on (chunk, level). The debris uses `SimRng` — it is cosmetic and
  still must not be random, because the smoke test asserts what is drawn against what
  exists. **Anything that decides *when* something happens is simulation.**
- **The world draws the street along -Z**, so the camera is never turned around and screen
  right IS world +X. A chase camera behind an object moving toward +Z has to be rotated
  180° about Y, which mirrors X and inverts the steering — a sibling game shipped exactly
  that for its entire life. `run_smoke.gd` asserts it in camera space anyway.
- **`_ready` does not run at `add_child()`.** `main.gd` guards this with `_ensure_booted()`;
  keep that guard.
- **`Transform3D.looking_at`, never `Node3D.look_at`** — the node method errors outside the
  tree, which is the headless case. And **never `global_transform` in a harness**: outside
  the tree it does not error, it returns IDENTITY, which is a plausible wrong answer.
- **`visible_instance_count` is the flush.** Forgetting it fails completely silently.
- **Freeze before advancing** in any harness.
- **A headless run allocates no MultiMesh buffer**, so instance colours there read back as
  black and prove nothing. Check colour in a real renderer or not at all.

## Things the exporter will not tell you clearly

- `rendering/textures/vram_compression/import_etc2_astc=true` is **required** for an
  Android export.
- A `config/icon` is required, or the export errors even though it still writes a file.
- `gradle_build/use_gradle_build=false` uses the prebuilt template and needs no Gradle.

## Record as you go

Write lessons into `gamedev-notes` **in the same commit as the change that taught them**,
never at the end of a session. Several games run at once; a lesson recorded after this one
finishes is one the next game never got.
