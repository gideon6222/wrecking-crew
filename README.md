# Wrecking Crew

A native Android demolition game for a phone, built in Godot 4.7.

You are parked in front of a condemned building with a wrecking crane and a fixed number
of swings. Break the columns at the base to drop each bay - but every bay that falls shifts
the load, and taking them from one side puts the whole thing over onto the block next door.
Drop it into its own footprint and the clean bonus is worth more than the building.

The boom slews to where you drag; the ball trails it and swings past, so you lead the lag
rather than pointing. Pointing at a column is not enough - the ball only reaches the
building once it is really travelling.

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
