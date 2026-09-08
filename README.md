# Wrecking Crew

A native Android demolition runner for a phone, built in Godot 4.7.

You drive a rig down a condemned street. The wrecking ball swings on a chain about a
second behind you, so you never aim it directly — you aim it by deciding where you were.
Swerve early and the ball whips out sideways into a tower; swerve late and it clips the
thing you were trying to keep.

Copied from `godot-template`, which is the stack every game here starts from: a pure
simulation core with no renderer in it, headless tests, a whole-run golden, an APK size
guard, CI as the gate, a build stamp and a changelog.

```powershell
$godot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"

& $godot --headless --path . --script res://test/run_tests.gd    # pure tests
& $godot --headless --path . --script res://test/run_smoke.gd    # boots the real scene
& $godot --headless --path . --export-debug "Android" build/wrecking-crew.apk
& $godot --path .                                                 # open the editor
```

`CLAUDE.md` has the toolchain paths and the invariants. `NOTES.md` has the design, what is
proven, and what to do next.
