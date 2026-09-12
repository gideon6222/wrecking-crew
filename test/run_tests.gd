extends SceneTree

## Entry point for the pure tests.
##
##   godot --headless --script res://test/run_tests.gd
##
## Nothing loaded here touches a Node, a viewport or an input event, so this
## runs in a container with no GPU and no display in about a second. The scene
## is exercised separately by run_smoke.gd, which is slower and catches a
## different class of bug.
##
## **The suite list is a glob, not a hand-written array.** A hand-maintained
## list is a second place to remember, and this studio has already paid for
## that: nine tests were added to a sibling game, the list was not, and the
## runner cheerfully reported "65 passing" for a suite that never ran. An
## empty glob FAILS rather than passing - zero tests is not zero failures.


func _initialize() -> void:
	var names: Array[String] = []
	var dir := DirAccess.open("res://test")
	if dir == null:
		print("  FAIL  cannot open res://test - the runner is broken, not the game")
		quit(1)
		return
	for f in dir.get_files():
		# `.gd` in the editor and in a source checkout, `.gd.remap` in an
		# exported build, where the script itself has been compiled away.
		var file := f.trim_suffix(".remap")
		if not file.begins_with("test_") or not file.ends_with(".gd"):
			continue
		if not names.has(file):
			names.append(file)
	names.sort()

	if names.is_empty():
		print("")
		print("  FAIL  the glob matched no suites in res://test")
		print("        Zero tests is not zero failures. Either the files moved or the")
		print("        naming convention did; a green exit here would be a lie.")
		quit(1)
		return

	var suites := []
	for file in names:
		suites.append(load("res://test/" + file).new())

	print("  suites: %s" % ", ".join(names))
	var code := TestHarness.run_all(suites)
	quit(code)
