extends RefCounted

## THE important one.
##
## The simulation is deterministic: the basement is keyed on (place, level)
## through the hash, and nothing consults randf() or a real clock. So a whole
## demolition produces the same numbers on every machine, every time - which is
## what makes a golden over the *whole game* possible, and what makes a large
## refactor safe to attempt at all.
##
## It has now carried this game across three complete rewrites of what the game
## IS: a lane runner, a crane runner, a controlled collapse, and this.
##
## Four runs are recorded, and the set is the point. Each policy has to fail
## for a DIFFERENT reason, or the table is not a description of the game:
##
##   PASSIVE  touches nothing
##   NUDGER   creeps at the columns - proves SPEED is what does the damage
##   GREEDY   wrecks properly and never leaves - proves the escape is real
##   WRECKER  wrecks properly and gets out
##
## GREEDY and WRECKER share every line of their code and differ in one boolean:
## whether they head for the ramp when the slab lets go. That is what makes the
## gap between them a claim about the game rather than about the bots.
##
## The numbers were recorded, not designed. If a deliberate balance change
## moves them, re-record in the same commit and say so in the message. A change
## to rendering, layout, input or the build must not touch them - if it does,
## something has leaked into the simulation.

## Touches nothing for a minute. The basement is untouched, the ball has not
## moved off the boom, and `hits` is ZERO - which is the field to watch. It read
## five hundred on an earlier build because the machine spawned with its ball
## inside a column, and nothing else in the suite would have said so.
const PASSIVE := {
	"level": 2, "rubble": 0, "columns_down": 0, "walls_down": 0,
	"integrity": 1.0, "collapsing": false, "escape_left": 0.0,
	"x": 0.0, "z": -14.3, "heading": 0.0, "speed": 0.0, "turret": 0.0,
	"ball_x": 0.0, "ball_z": -9.7, "ball_speed": 0.0,
	"over": false, "won": false, "peak_ball": 0.0, "hits": 0, "seconds": 60.0,
}
## Creeps at the columns at a quarter throttle for the whole minute. Eleven
## contacts, ONE column, and the collapse never starts - because the ball never
## gets above 7.9 m/s and damage is speed squared.
##
## This is the policy that proves the machine is not a bulldozer. It uses the
## same targeting as the two below and differs only in throttle.
const NUDGER := {
	"level": 2, "rubble": 120, "columns_down": 1, "walls_down": 0,
	"integrity": 0.909, "collapsing": false, "escape_left": 0.0,
	"x": -5.382, "z": -10.868, "heading": -1.132, "speed": 1.976, "turret": 0.0,
	"ball_x": -9.076, "ball_z": -14.092, "ball_speed": 7.166,
	"over": false, "won": false, "peak_ball": 7.859, "hits": 11, "seconds": 60.0,
}
## Wrecks properly and never leaves. Four columns down, the slab lets go at 33
## seconds - and it is still in the room at 44.65 with `escape_left` past zero.
## 515 rubble and a loss.
const GREEDY := {
	"level": 2, "rubble": 515, "columns_down": 4, "walls_down": 1,
	"integrity": 0.658, "collapsing": true, "escape_left": -0.013,
	"x": -3.436, "z": -5.092, "heading": 2.535, "speed": 7.578, "turret": 0.0,
	"ball_x": 1.868, "ball_z": -4.417, "ball_speed": 15.454,
	"over": true, "won": false, "peak_ball": 17.516, "hits": 7, "seconds": 44.65,
}
## The same run, one boolean apart: this one heads for the ramp when the slab
## goes. Out at 33.5 seconds with 11.1 to spare, and the time left pays - 959
## against the same four columns and the same seven contacts.
##
## GREEDY and WRECKER are the pair that matters. Identical code, identical
## driving, identical damage on the ground; nearly twice the money and the
## difference between a win and being crushed, for knowing when to leave. If
## these two ever converge, the escape has stopped being a decision.
const WRECKER := {
	"level": 2, "rubble": 959, "columns_down": 4, "walls_down": 1,
	"integrity": 0.658, "collapsing": true, "escape_left": 11.103,
	"x": -0.132, "z": -16.54, "heading": 2.986, "speed": 9.359, "turret": 0.0,
	"ball_x": -2.852, "ball_z": -17.18, "ball_speed": 11.852,
	"over": true, "won": true, "peak_ball": 17.516, "hits": 7, "seconds": 33.533,
}


## Asserted directly, and separately from the goldens below, so that when they
## fail together it is obvious which is the cause.
func test_the_same_demolition_replays_identically(t: TestHarness) -> void:
	for name in Policies.ALL:
		t.dict_eq(_play(name), _play(name),
			"two %s runs differed - the simulation is not deterministic" % name)


func test_touching_nothing_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.PASSIVE), PASSIVE, "PASSIVE")


func test_creeping_at_the_columns_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.NUDGER), NUDGER, "NUDGER")


func test_never_leaving_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.GREEDY), GREEDY, "GREEDY")


func test_a_played_run_is_unchanged(t: TestHarness) -> void:
	_check(t, _play(Policies.WRECKER), WRECKER, "WRECKER")


## Recorded goldens pin the numbers; these pin the RELATIONSHIPS, so
## re-recording carelessly cannot quietly accept a game where one of them has
## stopped being true. That has happened twice on this project, and only a
## measurement noticed either time.
func test_touching_nothing_breaks_nothing(t: TestHarness) -> void:
	var p := _play(Policies.PASSIVE)
	t.eq(p["columns_down"], 0, "a run with no input at all brought columns down")
	t.eq(p["walls_down"], 0, "a run with no input at all brought panels down")
	t.eq(p["rubble"], 0, "a run with no input at all earned something")
	t.eq(p["hits"], 0,
		"the ball is touching something in a run nobody played - check where the machine spawns")


func test_speed_is_what_does_the_damage(t: TestHarness) -> void:
	# The claim the free-driving machine and the inextensible chain both exist
	# to support. Taken over several basements, because a single one turns on
	# where the columns happen to be.
	var creeping := 0
	var driving := 0
	for level in [1, 2, 3, 4]:
		creeping += int(Policies.play(Policies.NUDGER, level)["rubble"])
		driving += int(Policies.play(Policies.WRECKER, level)["rubble"])
	t.gt(float(driving), float(creeping) * 1.5,
		"creeping at the columns earns nearly as much as driving at them - speed does not matter")


func test_getting_out_is_worth_more_than_staying(t: TestHarness) -> void:
	# The other claim. Same code, same driving, one boolean apart: whether the
	# policy heads for the ramp when the slab lets go.
	var stayed := 0
	var left := 0
	var wins := 0
	for level in [1, 2, 3, 4]:
		stayed += int(Policies.play(Policies.GREEDY, level)["rubble"])
		var out := Policies.play(Policies.WRECKER, level)
		left += int(out["rubble"])
		if out["won"]:
			wins += 1
	t.gt(float(left), float(stayed),
		"leaving when the slab goes earns no more than staying under it")
	t.gt(float(wins), 0.0,
		"the policy that runs for the ramp never once gets out - the escape is not winnable")


func test_a_basement_can_be_brought_down_at_all(t: TestHarness) -> void:
	# The level has to have an ending in it. An earlier build of this game set
	# a threshold nobody could cross: the best policy took five of twelve
	# columns in two and a half minutes and the collapse never started, which
	# is not difficulty - it is a room with no exit.
	var reached := 0
	for level in [1, 2, 3, 4]:
		if Policies.play(Policies.WRECKER, level)["collapsing"]:
			reached += 1
	t.gt(float(reached), 0.0,
		"no basement ever reaches its own collapse threshold - there is no ending in the level")


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


## Level 2, not level 1, and 60 seconds rather than 40.
##
## On level 1 nothing reaches the collapse threshold inside the window, so
## GREEDY and WRECKER recorded byte-for-byte identical states - a golden pair
## whose whole purpose is to differ. A golden recorded where the mechanic it
## guards never fires is a golden that cannot fail for the right reason.
func _play(name: String) -> Dictionary:
	return Policies.play(name, 2, 60.0)
