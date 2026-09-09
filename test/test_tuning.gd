extends RefCounted

## Design tests: assertions about *intent* rather than about values.
##
## A snapshot of the constants pins the numbers but says nothing about what
## they are for. These say what the numbers have to remain true of, so a
## balance change that breaks the shape of the game fails here rather than in
## a playtest three weeks later.


func test_the_player_can_actually_get_out(t: TestHarness) -> void:
	# The one number that decides whether the collapse is tense or unfair.
	# Computed from the deck's diagonal at full speed, never eyeballed - it is
	# exactly the sort of relationship that silently stops being true when the
	# room grows, and the player's only evidence would be losing runs they
	# thought they had.
	for level in [1, 3, 6, 12, 30]:
		t.gt(Tuning.escape_margin(level), 2.0,
			"level %d cannot be escaped from the far corner even driving flat out" % level)
		t.lt(Tuning.escape_margin(level), 30.0,
			"level %d gives so long to escape that the collapse is not a threat" % level)


func test_the_escape_tightens_but_never_becomes_impossible(t: TestHarness) -> void:
	t.lt(Tuning.escape_seconds_for(9), Tuning.escape_seconds_for(1),
		"the way out never gets tighter, so the ladder has no pressure in it")
	t.gt(Tuning.escape_seconds_for(99), 5.0,
		"the escape window shrinks to nothing, so a deep run ends by arithmetic")


func test_speed_is_what_does_the_damage(t: TestHarness) -> void:
	# The whole reason the machine drives freely and the chain does not stretch.
	# If a slow ball did most of the damage of a fast one, none of that would
	# be worth anything.
	t.eq(Tuning.damage_at(0.0), 0.0, "a stationary ball damages things")
	t.eq(Tuning.damage_at(Tuning.HIT_MIN_SPEED), 0.0, "a ball at the floor speed still damages things")
	t.gt(Tuning.damage_at(Tuning.HIT_FULL_SPEED), 0.0, "a ball at full speed does nothing")
	var half := Tuning.damage_at((Tuning.HIT_MIN_SPEED + Tuning.HIT_FULL_SPEED) * 0.5)
	t.lt(half, Tuning.damage_at(Tuning.HIT_FULL_SPEED) * 0.45,
		"damage rises so gently with speed that driving fast is barely worth it")


func test_a_column_takes_a_few_good_hits(t: TestHarness) -> void:
	# Not one - that makes the room a checklist. Not ten - that makes it a
	# chore. Measured against the damage of a solid pass rather than assumed.
	var solid := Tuning.damage_at(Tuning.HIT_FULL_SPEED * 0.8)
	var hits := Tuning.COLUMN_HP / maxf(solid, 0.01)
	t.gt(hits, 1.2, "a column falls to a single pass, so there is no working at one")
	t.lt(hits, 8.0, "a column takes so many passes that a room is a chore")


func test_a_wall_is_easier_than_a_column_and_worth_less(t: TestHarness) -> void:
	t.lt(Tuning.WALL_HP, Tuning.COLUMN_HP, "an infill panel is tougher than a structural column")
	t.lt(float(Tuning.WALL_RUBBLE), float(Tuning.COLUMN_RUBBLE),
		"a panel pays as well as a column, so there is no reason to prefer the hard target")
	t.lt(Tuning.WALL_CAPACITY, Tuning.COLUMN_CAPACITY * 0.5,
		"panels hold the slab up nearly as much as columns, so the gauge says nothing")
	t.gt(Tuning.WALL_CAPACITY, 0.0,
		"panels count for nothing at all, so a minute spent on them moves no gauge")


func test_the_ball_can_be_swung_faster_than_the_machine_drives(t: TestHarness) -> void:
	# The point of a chain. If the ball could only ever go as fast as the
	# vehicle, the vehicle would be the weapon and the chain would be a
	# decoration hanging off it.
	var arm := Tuning.BOOM_LEN + Tuning.CHAIN
	var spin := Tuning.TURN_RATE * arm
	t.gt(spin, Tuning.HIT_MIN_SPEED,
		"turning on the spot cannot even reach the speed that starts doing damage")
	t.lt(spin, Tuning.DRIVE_MAX * 1.6,
		"turning on the spot beats driving, so the best play is to stand still and rotate")


func test_the_collapse_needs_real_work_but_is_reachable(t: TestHarness) -> void:
	# Both directions. A threshold nobody can cross is a level with no exit;
	# one that trips on the first column is a level with no middle.
	var columns := float(Tuning.GRID_X * Tuning.GRID_Z)
	var total := Tuning.total_capacity()
	var needed := 0
	var left := total
	while left / total > Tuning.COLLAPSE_AT and needed < columns:
		left -= Tuning.COLUMN_CAPACITY
		needed += 1
	t.gt(float(needed), 2.0, "the slab lets go after two columns, so there is no room to play in")
	t.lt(float(needed), columns * 0.75,
		"the slab needs three quarters of its columns gone, which is most of a room per level")


func test_the_deck_is_bigger_than_the_swing(t: TestHarness) -> void:
	# Otherwise the ball reaches the walls from the middle of the room and the
	# level is one long scrape rather than a place to drive around in.
	var reach := Tuning.BOOM_LEN + Tuning.CHAIN + Tuning.BALL_RADIUS
	t.gt(Tuning.DECK_W * 0.5, reach, "the room is narrower than the machine's own reach")
	t.gt(Tuning.DECK_D * 0.5, reach, "the room is shallower than the machine's own reach")


func test_the_grid_fits_inside_the_room(t: TestHarness) -> void:
	var half_grid_x := absf(Tuning.column_x(0))
	var half_grid_z := absf(Tuning.column_z(0))
	t.lt(half_grid_x + Tuning.COLUMN_RADIUS, Tuning.DECK_W * 0.5,
		"the outer columns are outside the room")
	t.lt(half_grid_z + Tuning.COLUMN_RADIUS, Tuning.DECK_D * 0.5,
		"the outer columns are outside the room")


func test_the_way_out_is_wide_enough_to_drive_through(t: TestHarness) -> void:
	t.gt(Tuning.RAMP_W * 0.5, Tuning.RIG_RADIUS * 1.5,
		"the ramp is barely wider than the machine, so escaping is a parking test")
	t.lt(Tuning.RAMP_W, Tuning.DECK_W * 0.4,
		"the ramp is so wide that being anywhere near the back wall counts as out")


func test_the_stick_has_a_dead_zone(t: TestHarness) -> void:
	# The single most-cited fix for touch controls feeling twitchy: without one
	# a virtual stick reads every tremor of a thumb and the machine wanders.
	t.gt(Tuning.STICK_DEADZONE, 0.0, "no dead zone - the machine will drift on a resting thumb")
	t.lt(Tuning.STICK_DEADZONE, 0.35, "the dead zone is so wide that gentle steering is impossible")


func test_a_swing_carries_but_does_not_last_forever(t: TestHarness) -> void:
	# Drag was 0.55 for one build and a swing was dead inside two seconds, so
	# every hit had to be set up from nothing - "it doesn't have enough
	# momentum". It still has to die eventually, or a ball flung once orbits
	# for the rest of the level.
	t.gt(Tuning.BALL_DRAG, 0.0, "a swung ball never slows, so it orbits forever")
	t.lt(Tuning.BALL_DRAG, 0.35, "the swing dies so fast that every hit is set up from nothing")


func test_the_chain_swings_like_a_pendulum(t: TestHarness) -> void:
	# The restoring force is a real one - proportional to how far the ball has
	# swung - so the chain has a PERIOD. A constant tug does not, which is why
	# the ball used to stay wherever it was last flung: "it flies out too much".
	var period := TAU * sqrt(Tuning.CHAIN / Tuning.SWING_G)
	t.gt(period, 0.8, "the ball snaps back so fast it reads as a rubber band, not a chain")
	t.lt(period, 4.0, "the swing is so slow that a pass at a column cannot be timed")


func test_the_ball_cannot_reach_across_the_room(t: TestHarness) -> void:
	# Total reach was 9.8 metres for one build, which is a quarter of the room -
	# so the taut state was the normal state and the chain stopped reading as a
	# chain. It still has to reach past the machine's own body.
	var reach := Tuning.BOOM_LEN + Tuning.CHAIN
	t.gt(reach, Tuning.RIG_RADIUS * 2.5, "the ball barely clears the machine it hangs off")
	t.lt(reach, Tuning.BAY * 1.1, "the ball reaches more than a whole bay - it is an arm, not a chain")
