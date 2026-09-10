# Wrecking Crew

A native Android demolition game for Gideon's S26 Ultra, built in Godot 4.7 and copied
from `C:\dev\godot-template`.

**The game in one sentence:** you are parked in front of a condemned building with a
wrecking crane and a fixed number of swings, and you have to bring it down into its own
footprint rather than onto the block next door.

@../gamedev-notes/INDEX.md

The shared rules, the Godot traps, the toolchain paths, the export and signing rules and
the process are in `C:\dev\gamedev-notes` (`INDEX.md` above, then `GODOT.md`, `CRAFT.md`,
`TESTING.md`, `ASSETS.md`, `POLISH.md`). **This file carries only what is specific to this
game.** `NOTES.md` has the decisions and measurements; `PLAN.md` the milestones;
`C:\dev\gamedev-notes\playtests\wrecking-crew.md` his words about it.

---

## The design, in the order it has to be understood

1. **The turret slews to where the thumb drags; the ball TRAILS the boom** as an underdamped
   spring, arriving about half a second late and swinging past. That lag is what you lead.
2. **Pointing at a column is not enough.** At rest the ball hangs short of the face, so it
   only reaches the building once it is really travelling. Reach is a consequence of speed.
3. **Reaching across the site and reaching into the building trade against each other**,
   because the ball's distance from the crane falls away as it swings round. That is why the
   crane can be moved, and why a wide building cannot be worked from one spot.
4. **Every bay dropped shifts the load.** The lean is the centroid of what is still standing.
   Work along one side and it goes over onto the neighbours, which is a failed demolition.
5. **A lone bay never topples** — without that clause no building could ever be finished.
6. **The clean bonus is judged on the worst lean reached**, never the final one.

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
| `src/sim/sim.gd` | **The whole game, with no renderer in it.** The crane, the structure, the lean |
| `src/sim/tuning.gd` | Every number that shapes how it feels, plus the derived arithmetic |
| `src/sim/util.gd` | `smooth`, `hash2`, `fmt` — pure, and the hash is load-bearing |
| `src/sim/rng.gd` | A seeded stream. Used only by the renderer's debris, never by the sim |
| `src/game/main.gd` | The shell: reads `Sim`, draws it, feeds it input. Decides nothing |
| `src/game/main.tscn` | Four lines. One node with the script; the world is built in code |
| `test/policies.gd` | The scripted players. **The definition of "playing well"** |
| `test/run_probe.gd` | Balance readings over six sites. Prints; never fails |
| `test/test_tuning.gd` | Design tests — assertions about intent, not values |
| `test/test_golden.gd` | Whole-run goldens over three policies |
| `scripts/shot.gd` | Deterministic screenshot of a chosen second of a chosen site |
| `scripts/check_size.gd` | APK size guard, fails in both directions |

## Invariants

Shared invariants (pure sim, no `randf()` in state, the hash, `_ensure_booted`, `looking_at`, the flush, freeze-before-advance, anchored HUD, `FLOAT_EPS`, headless MultiMesh colours, `global_transform`, Dictionary Variants, `use_colors`, `Basis.scaled`, `TorusMesh`, culling against the camera) are in `GODOT.md` and are not repeated here.

- **The pendulum is arithmetic, never a PhysicsBody on a joint.** A joint would put the
  outcome of every run inside the physics server at the mercy of its tick rate and end any
  chance of a golden. **Physics may be used for debris, which decides nothing.**
- **The world draws the street along -Z**, so the camera is never turned around and screen
  right IS world +X. A chase camera behind an object moving toward +Z has to be rotated
  180° about Y, which mirrors X and inverts the steering — a sibling game shipped exactly
  that for its entire life. `run_smoke.gd` asserts it in camera space anyway.

## Shared rules and recording

Everything general lives in `C:\dev\gamedev-notes`: the invariants every game keeps and the
engine traps in `GODOT.md`, design in `CRAFT.md`, the ship gate in `POLISH.md`. Record a
lesson the moment it is learned with `/record-lesson` (it writes to the notes' `inbox/`),
and his words with `/record-lesson playtest wrecking-crew`. Never edit the notes' topic files from
a build session.
