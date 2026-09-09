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
## Touches nothing for a minute. `hits` is ZERO - the field to watch, because
## it read five hundred on an earlier build where the machine spawned with its
## ball inside a column, and nothing else in the suite would have said so.
const PASSIVE := {
	"level": 2, "rubble": 0, "columns_down": 0, "walls_down": 0,
	"integrity": 1.0, "collapsing": false, "escape_left": 0.0,
	"x": 0.0, "z": -14.3, "heading": 0.0, "speed": 0.0, "turret": 0.0,
	"ball_x": 0.0, "ball_z": -10.7, "ball_speed": 0.0,
	"over": false, "won": false, "peak_ball": 0.0, "hits": 0, "seconds": 60.0,
}
## Creeps at the columns at a quarter throttle for the whole minute. Eleven
## contacts, ONE column, and the collapse never starts - because the ball never
## gets above 7.9 m/s and damage is speed squared.
##
## This is the policy that proves the machine is not a bulldozer. It uses the
## same targeting as the two below and differs only in throttle.
## Creeps at the columns at a quarter throttle for a full minute and lands
## ZERO hits. Not "a few weak ones" - none: the ball never gets above 8.3 m/s,
## and at that speed a pass does not even reach a column with enough left to
## register a contact.
##
## This is the policy that proves the machine is not a bulldozer. It uses the
## same targeting as the two below and differs only in throttle.
## Creeps at the columns at a quarter throttle for a full minute: ONE contact,
## no columns, nothing earned. The ball never gets above 11 m/s and a pass at
## that speed does not survive the trip.
##
## This is the policy that proves the machine is not a bulldozer. It shares its
## targeting and its driving with the two below and differs only in throttle.
const NUDGER := {
	"level": 2, "rubble": 0, "columns_down": 0, "walls_down": 0,
	"integrity": 1.0, "collapsing": false, "escape_left": 0.0,
	"x": -4.33, "z": -9.73, "heading": -1.556, "speed": 1.601, "turret": 0.0,
	"ball_x": -9.356, "ball_z": -10.21, "ball_speed": 7.535,
	"over": false, "won": false, "peak_ball": 11.093, "hits": 1, "seconds": 60.0,
}
## Wrecks properly and never leaves. Four columns down, the slab lets go at 33
## seconds - and it is still in the room at 44.65 with `escape_left` past zero.
## 515 rubble and a loss.
## Wrecks properly and never leaves. Five columns down, the slab lets go, and
## it is still in the room at 32.17 seconds with `escape_left` past zero. 670
## rubble and a loss.
## Wrecks properly and never leaves. EIGHT columns down and 1030 rubble on the
## ground - more than the policy below manages - and it is still in the room at
## 26.15 seconds with `escape_left` past zero. All of it counts for nothing.
const GREEDY := {
	"level": 2, "rubble": 1030, "columns_down": 8, "walls_down": 2,
	"integrity": 0.329, "collapsing": true, "escape_left": -0.013,
	"x": -3.952, "z": 11.438, "heading": 1.699, "speed": 4.574, "turret": 0.0,
	"ball_x": 1.057, "ball_z": 14.911, "ball_speed": 12.447,
	"over": true, "won": false, "peak_ball": 27.331, "hits": 20, "seconds": 26.15,
}
## The same run, one boolean apart: this one heads for the ramp when the slab
## goes. Out at 33.5 seconds with 11.1 to spare, and the time left pays - 959
## against the same four columns and the same seven contacts.
##
## GREEDY and WRECKER are the pair that matters. Identical code, identical
## driving, identical damage on the ground; nearly twice the money and the
## difference between a win and being crushed, for knowing when to leave. If
## these two ever converge, the escape has stopped being a decision.
## The same run, one boolean apart: this one heads for the ramp when the slab
## goes. Out at 21.8 seconds with 10.3 to spare, and the time left pays - 962
## against 670, on one FEWER column.
##
## GREEDY and WRECKER are the pair that matters. Identical code, identical
## driving; the one that knows when to stop earns half again as much and lives.
## If these two ever converge, the escape has stopped being a decision.
## The same run, one boolean apart: this one heads for the ramp when the slab
## goes. Out at 16.15 seconds with 10 to spare.
##
## The pair is worth reading carefully, because it is no longer a simple win.
## The greedy policy puts TWICE the columns down and banks 1030 against 879 -
## and loses, because it is under the slab when it lands. What the escape buys
## is not more rubble, it is keeping the rubble you have. If these two ever stop
## differing, the collapse has stopped being a decision.
const WRECKER := {
	"level": 2, "rubble": 879, "columns_down": 4, "walls_down": 0,
	"integrity": 0.675, "collapsing": true, "escape_left": 9.987,
	"x": 1.198, "z": -16.599, "heading": -2.61, "speed": 9.039, "turret": 0.0,
	"ball_x": 0.451, "ball_z": -15.718, "ball_speed": 15.548,
	"over": true, "won": true, "peak_ball": 27.331, "hits": 12, "seconds": 16.15,
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
	t.gt(float(driving), float(creeping) * 4.0,
		"creeping at the columns earns nearly as much as driving at them - speed does not matter")
	# Stronger, and it is worth stating as its own claim: with the chain
	# carrying momentum properly, a machine that creeps does not merely score
	# less - it cannot bring a single column down in a minute.
	t.eq(Policies.play(Policies.NUDGER, 2)["columns_down"], 0,
		"creeping at a column is enough to fell it, so driving fast is optional")


func test_getting_out_is_worth_more_than_staying(t: TestHarness) -> void:
	# The other claim. Same code, same driving, one boolean apart: whether the
	# policy heads for the ramp when the slab lets go.
	var stayed := 0
	var stayed_wins := 0
	var left := 0
	var wins := 0
	for level in [1, 2, 3, 4]:
		var under := Policies.play(Policies.GREEDY, level)
		stayed += int(under["rubble"])
		if under["won"]:
			stayed_wins += 1
		var out := Policies.play(Policies.WRECKER, level)
		left += int(out["rubble"])
		if out["won"]:
			wins += 1
	# NOT a comparison of rubble. The greedy policy stays under the slab and
	# keeps wrecking, so it often has MORE on the ground when the ceiling lands
	# on it - 1030 against 879 on level 2. That is the shape the mechanic
	# should have: greed genuinely pays right up until it does not.
	#
	# What has to be true is that staying never WORKS. If a policy that ignores
	# the collapse can finish a level, the collapse is scenery.
	t.eq(stayed_wins, 0,
		"a policy that never leaves still finishes levels - the collapse is not a real threat")
	t.gt(float(wins), 0.0,
		"the policy that runs for the ramp never once gets out - the escape is not winnable")
	t.gt(float(left), 0.0, "the escaping policy earns nothing at all")


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
