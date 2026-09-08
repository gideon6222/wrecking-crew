extends RefCounted

## THE important one.
##
## The simulation is deterministic given a street: spawning is keyed on
## (chunk, level) through the hash, and nothing consults randf() or a real
## clock. So a whole street produces the same numbers on every machine, every
## time.
##
## That makes a golden test over the *whole game* possible, which is a far
## stronger safety net than testing any single function - and it is what makes
## a large refactor safe to attempt at all. Record it before changing anything,
## never after.
##
## Three runs are recorded, not one, and the set is the point:
##
##   PASSIVE  never touches the screen
##   DODGER   stays alive and never aims the ball at anything
##   WRECKER  plays the game
##
## A change that moves only one of them says something a single golden could
## not. If PASSIVE moves and WRECKER does not, spawning changed. If WRECKER
## moves and PASSIVE does not, the swing or the collision did. If DODGER
## climbs toward WRECKER, the game has quietly stopped needing to be aimed.
##
## The numbers were recorded, not designed. If a deliberate balance change
## moves them, re-record them in the same commit and say so in the message. A
## change to rendering, layout, input or the build must not touch them - if it
## does, something has leaked into the simulation.

const SECONDS := 20.0

## Never touches the screen. Dead at 12.7 seconds with three barricades taken
## on the centre line, no rubble, and a ball that never left the boom.
## Never touches either control. Dead at 14.3 seconds on the barricades it
## never moved out of, and the boom still pointing straight down the street.
## `floors_felled` 0 is the number that matters.
const PASSIVE := {
	"level": 1, "lives": 0, "rubble": 0, "power": 1, "floors_felled": 0,
	"flattened": 0, "distance": 185.25, "x": 0.0, "lane": 1, "yaw": 0.0,
	"bearing": 0.141, "radius": 3.627, "ball_x": 0.508, "ball_z_ahead": 3.591,
	"buildings": 10, "barricades": 3, "over": true, "won": false,
	"peak_reach": 1.306, "peak_omega": 1.662, "seconds": 14.25,
}

## Stays alive the whole twenty seconds without ever aiming: full lives, and
## the 24 rubble is one barricade the dodging swerve happened to catch. Zero
## floors is the number that matters - surviving is not playing.
## Survives the whole twenty seconds by pressing the lane buttons and never
## once touching the crane: full lives, and EXACTLY ZERO rubble.
##
## That zero is the single most valuable number in this file. Under the old
## build the same policy scored 138 against the aiming policy's 268, because a
## ball driven by the rig's own movement swung into things by accident. With
## the crane on its own control there is no accident available - if this ever
## becomes non-zero, something has started scoring without being aimed.
const DODGER := {
	"level": 1, "lives": 3, "rubble": 0, "power": 1, "floors_felled": 0,
	"flattened": 0, "distance": 260.0, "x": 2.35, "lane": 2, "yaw": 0.0,
	"bearing": 0.0, "radius": 3.2, "ball_x": 2.35, "ball_z_ahead": 3.2,
	"buildings": 12, "barricades": 0, "over": false, "won": false,
	"peak_reach": 2.355, "peak_omega": 0.0, "seconds": 20.0,
}

## Playing it: same twenty seconds, same three lives, five times the rubble,
## two buildings flattened and the first power up already banked. `peak_reach`
## 6.73 against the dodger's 4.21 is the whole difference in one number - the
## ball is going a metre and a half deeper into the kerb.
## Playing it: same twenty seconds, same three lives, 306 rubble, seven floors
## felled and five buildings flattened. `peak_reach` 8.10 against the dodger's
## 2.36 is the whole difference in one number - the dodger's ball never left
## the front of the rig.
const WRECKER := {
	"level": 1, "lives": 3, "rubble": 306, "power": 2, "floors_felled": 7,
	"flattened": 5, "distance": 260.0, "x": 2.35, "lane": 2, "yaw": -0.306,
	"bearing": 0.733, "radius": 4.854, "ball_x": 5.597, "ball_z_ahead": 3.608,
	"buildings": 12, "barricades": 0, "over": false, "won": false,
	"peak_reach": 8.099, "peak_omega": 5.092, "seconds": 20.0,
}


## Asserted directly, and separately from the goldens below, so that when they
## fail together it is obvious which is the cause. A golden mismatch with this
## passing is a real behaviour change; a golden mismatch with this failing is
## not the golden's fault.
func test_the_same_street_replays_identically(t: TestHarness) -> void:
	for name in [Policies.PASSIVE, Policies.DODGER, Policies.WRECKER]:
		t.dict_eq(_play(name), _play(name),
			"two %s runs differed - the simulation is not deterministic" % name)


func test_never_touching_the_screen_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.PASSIVE), PASSIVE, "PASSIVE")


func test_a_surviving_run_that_never_aims_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.DODGER), DODGER, "DODGER")


func test_a_played_run_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.WRECKER), WRECKER, "WRECKER")


## Recorded goldens pin the numbers; these pin the *relationships*, so
## re-recording carelessly cannot quietly accept a game where aiming stopped
## mattering. That has happened: on a sibling game four completely different
## play styles scored identically and only a measurement noticed.
func test_never_touching_the_screen_earns_almost_nothing(t: TestHarness) -> void:
	var p := _play(Policies.PASSIVE)
	t.eq(p["floors_felled"], 0,
		"a run with no input at all knocked floors off buildings - the game plays itself")


func test_aiming_the_ball_beats_merely_surviving(t: TestHarness) -> void:
	# The measurement that decides whether this is a game about a wrecking ball
	# or a lane-changer with scenery. Taken over six streets, because a single
	# street swings wildly on layout luck: street 3 alone has the dodging
	# policy ahead, and calibrating on it would have hidden this entirely.
	var aimed := 0
	var survived := 0
	for level in [1, 2, 3, 4, 5, 6]:
		aimed += int(Policies.play(Policies.WRECKER, level)["rubble"])
		survived += int(Policies.play(Policies.DODGER, level)["rubble"])
	# The bar is now absolute rather than a ratio, because the dodger scores
	# exactly nothing: with the crane on its own control, a run that never
	# touches the boom cannot knock a single floor off anything. That is a far
	# cleaner separation than the old build's 2x, and it is the one thing the
	# rewrite unambiguously bought.
	t.eq(survived, 0,
		"a run that never touches the crane still earns rubble - the boom is not the only way to score")
	t.gt(float(aimed), 0.0, "the aiming policy earns nothing at all")


func test_a_played_run_survives_where_a_passive_one_dies(t: TestHarness) -> void:
	var played := _play(Policies.WRECKER)
	var passive := _play(Policies.PASSIVE)
	t.gt(float(played["lives"]), float(passive["lives"]),
		"playing well is no safer than not playing at all")


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
	return Policies.play(name, 1, SECONDS)
