extends RefCounted

## THE important one.
##
## The simulation is deterministic given a level: the columns are keyed on
## (bay, level) through the hash, and nothing consults randf() or a real clock.
## So a whole demolition produces the same numbers on every machine, every
## time.
##
## That makes a golden test over the *whole game* possible, which is a far
## stronger safety net than testing any single function - and it is what makes
## a large refactor safe to attempt at all. It has now carried this game across
## two complete rewrites of what the game IS.
##
## Four runs are recorded, and the set is the point:
##
##   PASSIVE     touches nothing
##   WAVER       swings the crane blindly and never moves it
##   RECKLESS    works the bays from one end
##   DEMOLISHER  works them in the order that keeps the building balanced
##
## The last two are the pair that matters. They use the SAME control, spend the
## same effort and take down the same building - they differ only in the order.
## If those two ever converge, the order has stopped mattering and the game has
## no decision left in it, which is exactly the failure the street version was
## retired for.
##
## The numbers were recorded, not designed. If a deliberate balance change
## moves them, re-record in the same commit and say so in the message. A change
## to rendering, layout, input or the build must not touch them - if it does,
## something has leaked into the simulation.

## Touches nothing for ninety seconds. The building is still standing, the
## budget is untouched, and the ball has not moved off the boom. `over` stays
## false because nothing ends a demolition except finishing it, running out of
## swings, or putting it on the neighbours - and doing nothing does none of
## those. That is deliberate: there is no clock.
const PASSIVE := {
	"level": 1, "swings_left": 12, "rubble": 0, "floors_down": 0,
	"bays_standing": 3, "lean": 0.0, "worst_lean": 0.0, "x": 0.0, "lane": 1,
	"yaw": 0.0, "bearing": 0.0, "radius": 3.2, "ball_x": 0.0, "ball_z": 3.2,
	"over": false, "won": false, "peak_depth": 3.2, "peak_omega": 0.0,
	"seconds": 90.0,
}
## Swings the crane flat out and never moves it. On a three-bay building that
## is enough - it takes the whole thing down in 12.6 seconds, faster than
## anyone, and by luck its symmetric sweep drops the bays in a balanced order
## so it collects the clean bonus too.
##
## Which is exactly why the goldens are recorded at several widths and why
## `test_a_blind_swinger_cannot_finish_a_wide_building` exists. On the first
## building a blind swinger looks like the best player in the game; by the
## sixth it cannot reach the outer bays at all.
const WAVER := {
	"level": 1, "swings_left": 4, "rubble": 470, "floors_down": 12,
	"bays_standing": 0, "lean": -0.964, "worst_lean": 0.0, "x": 0.0, "lane": 1,
	"yaw": -1.057, "bearing": -0.339, "radius": 5.318, "ball_x": -1.768,
	"ball_z": 5.015, "over": true, "won": true, "peak_depth": 5.87,
	"peak_omega": 5.096, "seconds": 12.6,
}
## Takes the bay that leaves the remainder most centred, every time. Middle
## first, then the outsides - `worst_lean` never leaves 0.00, so the building
## goes straight down and the bonus is paid.
##
## `lean` reads 0.96 at the end and that is not a contradiction: it is the
## centroid of what is standing, and with a single bay left there is nothing
## for it to be centred against. Nothing can topple from there, which is why
## `worst_lean` - the number the bonus is judged on - stops counting once one
## bay is left. See `test_the_worst_lean_ignores_what_cannot_topple`.
const DEMOLISHER := {
	"level": 1, "swings_left": 4, "rubble": 470, "floors_down": 12,
	"bays_standing": 0, "lean": 0.963, "worst_lean": 0.0, "x": 4.2, "lane": 2,
	"yaw": 0.378, "bearing": -0.046, "radius": 4.973, "ball_x": 3.971,
	"ball_z": 4.968, "over": true, "won": true, "peak_depth": 5.346,
	"peak_omega": 4.036, "seconds": 23.917,
}
## Works the bays from the left-hand end. Takes the same building down with
## the same swings - and earns 220 against the balanced policy's 470, because
## `worst_lean` reached 0.50 and the clean-drop bonus is only paid under 0.45.
##
## This pair is the whole game in two numbers. Same control, same effort, same
## result on the ground; less than half the money, for the order alone.
const RECKLESS := {
	"level": 1, "swings_left": 4, "rubble": 220, "floors_down": 12,
	"bays_standing": 0, "lean": 0.964, "worst_lean": 0.5, "x": 4.2, "lane": 2,
	"yaw": 0.376, "bearing": -0.071, "radius": 4.971, "ball_x": 3.849,
	"ball_z": 4.958, "over": true, "won": true, "peak_depth": 4.976,
	"peak_omega": 3.327, "seconds": 23.9,
}


## Asserted directly, and separately from the goldens below, so that when they
## fail together it is obvious which is the cause. A golden mismatch with this
## passing is a real behaviour change; a golden mismatch with this failing is
## not the golden's fault.
func test_the_same_demolition_replays_identically(t: TestHarness) -> void:
	for name in Policies.ALL:
		t.dict_eq(_play(name), _play(name),
			"two %s runs differed - the simulation is not deterministic" % name)


func test_touching_nothing_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.PASSIVE), PASSIVE, "PASSIVE")


func test_swinging_blindly_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.WAVER), WAVER, "WAVER")


func test_working_from_one_end_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.RECKLESS), RECKLESS, "RECKLESS")


func test_a_balanced_demolition_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.DEMOLISHER), DEMOLISHER, "DEMOLISHER")


## Recorded goldens pin the numbers; these pin the RELATIONSHIPS, so
## re-recording carelessly cannot quietly accept a game where the order stopped
## mattering. That has happened twice on this project, and only a measurement
## noticed either time.
func test_touching_nothing_brings_nothing_down(t: TestHarness) -> void:
	var p := _play(Policies.PASSIVE)
	t.eq(p["floors_down"], 0, "a run with no input at all brought floors down")
	t.eq(p["swings_left"], Tuning.swings_for(1), "a run with no input at all spent swings")


func test_the_order_is_worth_more_than_the_effort(t: TestHarness) -> void:
	# The measurement that decides whether this is a demolition game or a
	# knocking-things-over game. Both policies use the same control and take
	# down the same buildings; the balanced one must be worth substantially
	# more, over several sites, because a single site swings on layout luck.
	var balanced := 0
	var one_sided := 0
	for level in [1, 2, 3, 4, 5, 6]:
		balanced += int(Policies.play(Policies.DEMOLISHER, level)["rubble"])
		one_sided += int(Policies.play(Policies.RECKLESS, level)["rubble"])
	t.gt(float(balanced), float(one_sided) * 1.5,
		"working the bays in a good order is barely worth more than working from one end")


func test_a_blind_swinger_cannot_finish_a_wide_building(t: TestHarness) -> void:
	# The reason the crane can move. A policy that never repositions has to
	# fail on the buildings that are wider than its reach - otherwise parking
	# is decoration, which is what it measured as before the site was widened.
	var wide := Policies.play(Policies.WAVER, 6)
	t.eq(wide["won"], false,
		"a crane that never moves finished the widest building - parking does nothing")
	t.gt(float(wide["bays_standing"]), 0.0, "the blind policy left nothing standing")


func test_working_from_one_end_puts_it_on_the_neighbours(t: TestHarness) -> void:
	var one_sided := Policies.play(Policies.RECKLESS, 6)
	t.eq(one_sided["won"], false, "taking a wide building down from one end succeeded")
	t.gt(one_sided["worst_lean"], Tuning.LEAN_WARN,
		"a one-sided demolition never even threatened to go over")


func test_a_balanced_demolition_drops_it_clean(t: TestHarness) -> void:
	for level in [1, 3, 6]:
		var r := Policies.play(Policies.DEMOLISHER, level)
		t.eq(r["won"], true, "the balanced policy failed level %d" % level)
		t.lt(r["worst_lean"], Tuning.LEAN_WARN,
			"the balanced policy did not manage a clean drop on level %d" % level)


func _check(t: TestHarness, actual: Dictionary, expected: Dictionary, label: String) -> void:
	if expected.is_empty():
		# Print rather than pass silently, so a baseline is never recorded by
		# accident. A golden you have never seen fail is one you do not know
		# works.
		print("")
		print("  %s NOT YET RECORDED. Paste into test_golden.gd:" % label)
		print("  const %s := %s" % [label, str(actual)])
		print("")
		t.ok(false, "no %s golden recorded yet - see the printed state above" % label)
		return
	t.dict_eq(actual, expected, "the simulation changed (%s)" % label)


func _play(name: String) -> Dictionary:
	return Policies.play(name, 1)
