extends SceneTree

## A balance probe, not a test. Nothing here can fail.
##
##   godot --headless --script res://test/run_probe.gd
##
## The rows that matter are NUDGER against WRECKER - which says whether speed
## is really what does the damage - and GREEDY against WRECKER, which says
## whether the escape is a real cost or a formality.

const LEVELS := [1, 2, 3, 4]


func _initialize() -> void:
	print("")
	print("  escape margin at level 1: %.1fs   collapse at %.0f%% support   deck %.0f x %.0f"
		% [Tuning.escape_margin(1), Tuning.COLLAPSE_AT * 100.0, Tuning.DECK_W, Tuning.DECK_D])
	print("  damage at 4 m/s %.1f | at 8 %.1f | at 13 %.1f   (column has %.0f hp)"
		% [Tuning.damage_at(4.0), Tuning.damage_at(8.0), Tuning.damage_at(13.0), Tuning.COLUMN_HP])
	print("")
	print("  %-9s %5s %7s %6s %6s %6s %7s %6s %6s"
		% ["policy", "level", "rubble", "cols", "walls", "hits", "peakBall", "secs", "won"])
	print("  %s" % "-".repeat(74))

	for name in Policies.ALL:
		var rubble := 0
		var wins := 0
		for level in LEVELS:
			var r := Policies.play(name, level)
			rubble += int(r["rubble"])
			if r["won"]:
				wins += 1
			print("  %-9s %5d %7d %6d %6d %6d %7.1f %6.1f %6s" % [
				name, level, r["rubble"], r["columns_down"], r["walls_down"],
				r["hits"], r["peak_ball"], r["seconds"], str(r["won"]),
			])
		print("  %-9s %5s %7.0f %6s %6s %6s %7s %6s %6d/%d" % [
			name, "MEAN", float(rubble) / LEVELS.size(), "", "", "", "", "", wins, LEVELS.size()])
		print("")
	quit(0)
