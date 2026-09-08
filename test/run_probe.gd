extends SceneTree

## A balance probe, not a test. Nothing here can fail.
##
##   godot --headless --script res://test/run_probe.gd
##
## Plays every policy over several buildings and prints the readings a tuning
## pass needs: the score, how much came down, the worst lean reached, whether
## it went over, and how many swings were left.
##
## The row that matters is DEMOLISHER against RECKLESS. They use the same
## control and the same effort and differ only in the ORDER they take the bays
## down, so the gap between them is the size of the decision the game is
## actually offering.

const LEVELS := [1, 2, 3, 4, 5, 6]


func _initialize() -> void:
	print("")
	print("  lag %.2fs   topple at %.2f   clean under %.2f   reach at the face %.2f"
		% [Tuning.ball_lag(), Tuning.TOPPLE_LIMIT, Tuning.LEAN_WARN, Tuning.reach_at_face()])
	print("")
	print("  %-11s %5s %4s %6s %7s %7s %6s %6s %6s"
		% ["policy", "level", "bays", "rubble", "floors", "standing", "worst", "swings", "won"])
	print("  %s" % "-".repeat(74))

	for name in Policies.ALL:
		var rubble := 0
		var wins := 0
		for level in LEVELS:
			var r := Policies.play(name, level)
			rubble += int(r["rubble"])
			if r["won"]:
				wins += 1
			print("  %-11s %5d %4d %6d %7d %8d %6.2f %6d %6s" % [
				name, level, Tuning.bays_for(level), r["rubble"], r["floors_down"],
				r["bays_standing"], r["worst_lean"], r["swings_left"], str(r["won"]),
			])
		print("  %-11s %5s %4s %6.0f %7s %8s %6s %6s %6d/%d" % [
			name, "MEAN", "", float(rubble) / LEVELS.size(), "", "", "", "", wins, LEVELS.size()])
		print("")

	quit(0)
