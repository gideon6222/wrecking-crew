# Wrecking Crew

A native Android demolition game for a phone, built in Godot 4.7.

You are alone in the basement of a condemned tower with a tracked wrecking machine. Drive it,
build up the swing of the ball on its chain, and cut the columns out from under the slab
overhead - the gauge at the top is how much is still holding it up. Take out enough and the
whole thing lets go, and then you have seconds to reach the ramp before it comes down on you.
Everything you have earned is lost if you are still under it.

Nothing aims the ball. It hangs from the boom on a chain that does not stretch, so the only
way to move it is to move the machine: the vehicle is the wind-up. And damage is SPEED - a ball
drifting into a column does nothing, one whipped round at ten metres a second takes a chunk
out.

Copied from `godot-template`, which is the stack every game here starts from: a pure
simulation core with no renderer in it, headless tests, a whole-run golden, an APK size
guard, CI as the gate, a build stamp and a changelog.

```powershell
$env:GODOT = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"

scripts\check.ps1                 # import -> pure tests -> smoke -> size guard
scripts\check.ps1 -Export         # plus the debug APK
& $env:GODOT --path .             # open the editor
```

`CLAUDE.md` has the design, the toolchain paths and the invariants. `NOTES.md` has the
decisions and the measured numbers. `PLAN.md` is a record of what exists, reconstructed after
the fact.
