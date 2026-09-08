extends SceneTree

## A balance probe, not a test. Nothing here can fail.
##
##   godot --headless --script res://test/run_probe.gd
##
## Plays every policy over several streets and prints the readings a tuning
## pass needs: rubble, floors felled, buildings flattened, how far the ball
## actually reached, and how fast it was swinging at its fastest.
##
## It exists because a single street is not a calibration. On a sibling game
## four scripted policies swung 25% street to street on layout luck alone, and
## a `par` set from street one put the best policy on three stars there and two
## everywhere else - none of which was visible in the street-one numbers, which
## looked clean and well separated.

const LEVELS := [1, 2, 3, 4, 5, 6]


func _initialize() -> void:
	print("")
	print("  reach ceiling from the arithmetic: %.2f   kerb: %.2f   swing period: %.2fs"
		% [Tuning.max_ball_reach(), Tuning.KERB_X, Tuning.swing_period()])
	print("")
	print("  %-9s %6s %7s %7s %6s %6s %6s %7s %7s"
		% ["policy", "street", "rubble", "floors", "flat", "power", "lives", "reach", "omega"])
	print("  %s" % "-".repeat(72))

	for name in Policies.ALL:
		var totals := {"rubble": 0, "floors_felled": 0, "flattened": 0}
		for level in LEVELS:
			var r := Policies.play(name, level)
			for k in totals:
				totals[k] += r[k]
			print("  %-9s %6d %7d %7d %6d %6d %6d %7.2f %7.2f" % [
				name, level, r["rubble"], r["floors_felled"], r["flattened"],
				r["power"], r["lives"], r["peak_reach"], r["peak_omega"],
			])
		print("  %-9s %6s %7.0f %7.1f %6.1f" % [
			name, "MEAN",
			float(totals["rubble"]) / LEVELS.size(),
			float(totals["floors_felled"]) / LEVELS.size(),
			float(totals["flattened"]) / LEVELS.size(),
		])
		print("")

	quit(0)
