extends RefCounted

## Design tests: assertions about *intent* rather than about values.
##
## A snapshot of the constants pins the numbers but says nothing about what
## they are for. These say what the numbers have to remain true of, so a
## balance change that breaks the shape of the game fails here rather than in
## a playtest three weeks later.


func test_the_ball_can_actually_reach_a_kerb(t: TestHarness) -> void:
	# The one relationship the whole game rests on. A target the tool cannot
	# reach is not a target - it is scenery that looks like content, and the
	# failure mode is silence: nothing errors, nothing is missing on screen,
	# the game simply has no scoring in it.
	#
	# Computed, never eyeballed. On a sibling game a moving obstacle shipped
	# covering 61% of the steerable band at every point in its swing, because
	# the clearance was judged by looking at it.
	t.gt(Tuning.max_ball_reach(), Tuning.KERB_X + Tuning.BALL_RADIUS,
		"the ball cannot reach the buildings even at full swing from the rail")

	# And it must not be so easy that the ball is over the pavement while
	# hanging still, which would make every building free.
	t.lt(Tuning.LANE_HALF_WIDTH, Tuning.KERB_X - Tuning.BALL_RADIUS,
		"a ball hanging straight down already overlaps the kerb - no swing needed")


func test_reaching_a_kerb_costs_a_real_swing(t: TestHarness) -> void:
	var need := Tuning.min_reaching_theta()
	t.gt(need, 0.15, "the swing needed to reach a kerb is too small to be a decision")
	t.lt(need, Tuning.MAX_THETA * 0.7,
		"reaching a kerb needs almost the maximum swing, so there is no margin to aim with")


func test_the_swing_lags_by_about_a_second(t: TestHarness) -> void:
	# A quarter period is how long after a swerve the ball reaches its extreme.
	# That lag IS the game: too short and the ball is a cursor, too long and
	# the building is behind you before the swing arrives.
	var lag := Tuning.swing_period() * 0.25
	t.gt(lag, 0.4, "the ball answers the thumb almost immediately - there is nothing to lead")
	t.lt(lag, 1.1, "the lag is longer than a building is on screen")


func test_a_building_is_on_screen_longer_than_the_lag(t: TestHarness) -> void:
	# If a kerb arrives and leaves faster than a swerve can be paid off, the
	# player is guessing rather than aiming, at every speed the ladder reaches.
	var lag := Tuning.swing_period() * 0.25
	for level in [1, 5, 10, 20]:
		var window := (Tuning.BOOM_FORWARD + Tuning.BUILDING_HALF_DEPTH * 2.0) / Tuning.speed_for(level)
		t.gt(window, lag,
			"at street %d a building passes faster than the ball can be swung at it" % level)


func test_a_barricade_leaves_a_way_through(t: TestHarness) -> void:
	# It blocks one half plus a little of the middle, so there is always a side
	# to be on - but the cab must actually fit in what is left, hitbox and all.
	var gap := Tuning.LANE_HALF_WIDTH + Tuning.BARRICADE_INNER_X
	t.gt(gap, Tuning.RIG_HALF_WIDTH * 2.0,
		"the gap beside a barricade is narrower than the rig - it cannot be dodged")
	t.gt(Tuning.BARRICADE_INNER_X + Tuning.RIG_HALF_WIDTH, 0.0,
		"a rig sitting on the centre line must be caught by a barricade, or standing still is safe")


func test_a_barricade_cannot_be_cleared_by_a_hanging_ball(t: TestHarness) -> void:
	# Otherwise the player drives at it and the game plays itself. On a sibling
	# game every station applied itself to the whole formation and four
	# completely different play styles measured identically.
	t.gt(Tuning.BARRICADE_MIN_SWING, 0.0,
		"a still ball smashes barricades, so driving straight at one is free")
	t.lt(Tuning.BARRICADE_MIN_SWING, Tuning.REBOUND_MIN,
		"a rebound from a building cannot smash the next barricade, so the two systems never chain")


func test_an_impact_hands_back_enough_to_reach_the_other_kerb(t: TestHarness) -> void:
	# The rebound is what makes a street a rhythm instead of a list. If the
	# energy returned cannot carry the ball back across, every kerb has to be
	# set up from nothing and there is no chaining to learn.
	#
	# Energy at the far side: (1/2)L*w^2 must clear the height of the swing
	# needed to reach the opposite kerb.
	var w := Tuning.REBOUND_MIN
	var rise := 0.5 * Tuning.CHAIN * w * w / Tuning.SWING_G
	var need := Tuning.CHAIN * (1.0 - cos(Tuning.min_reaching_theta()))
	t.gt(rise, need,
		"the smallest rebound cannot carry the ball back to the opposite kerb - chaining is impossible")


func test_the_power_ladder_is_reachable_inside_one_street(t: TestHarness) -> void:
	# Measured, not assumed: the aiming bot's mean street earns this much.
	# If the first rung costs more than a good street pays, the in-run power
	# fantasy never starts and the meter is a bar that only ever fills a third.
	const MEASURED_GOOD_STREET := 268
	t.lt(float(Tuning.meter_for(1)), float(MEASURED_GOOD_STREET),
		"the first power up costs more than a well played street earns")
	t.gt(float(Tuning.meter_for(1)), 40.0,
		"the first power up is so cheap it arrives before the player knows what it is")
	t.gt(Tuning.meter_for(2), Tuning.meter_for(1), "the ladder must get more expensive")
	t.eq(Tuning.POWER_MAX > Tuning.POWER_START, true, "there is no ladder at all")


func test_a_building_can_outlast_the_power_that_hits_it(t: TestHarness) -> void:
	# Floors are the health bar. If the tallest building falls to one swing at
	# starting power, the power ladder buys nothing and the skyline is flat.
	t.gt(float(Tuning.MAX_FLOORS), float(Tuning.POWER_START),
		"the tallest building falls to a single swing at starting power")
	t.gt(float(Tuning.MAX_FLOORS), float(Tuning.POWER_MAX) * 0.9,
		"even topped-out power flattens everything in one hit, so height stops meaning anything")


func test_flattening_is_worth_more_than_the_floors_it_takes(t: TestHarness) -> void:
	# The bonus is what makes finishing a building a goal rather than an
	# accident. It has to beat clipping one floor off two different buildings.
	t.gt(float(Tuning.FLATTEN_BONUS), float(Tuning.RUBBLE_PER_FLOOR),
		"finishing a building pays less than one more floor elsewhere")


func test_difficulty_compounds_but_stays_playable(t: TestHarness) -> void:
	t.gt(Tuning.LEVEL_SPEED_STEP, 1.0, "streets must get harder or there is no ladder")
	t.lt(Tuning.LEVEL_SPEED_STEP, 1.25, "a steeper curve than this outruns a human inside five streets")
	t.eq(Tuning.speed_for(1), Tuning.FORWARD_SPEED, "street 1 is the unscaled baseline")
	t.gt(Tuning.height_for(6), Tuning.height_for(1), "the skyline must grow with the ladder")


func test_a_street_is_a_sane_length(t: TestHarness) -> void:
	var first := Tuning.level_seconds(1)
	t.gt(first, 15.0, "a street under fifteen seconds is a menu with scenery")
	t.lt(first, 90.0, "a street over ninety seconds makes a death expensive enough to stop playing")


func test_the_rig_can_cross_the_street_faster_than_it_arrives(t: TestHarness) -> void:
	# If steering is slower than the street scrolls, no amount of skill helps.
	var seconds_to_cross := Tuning.LANE_HALF_WIDTH * 2.0 / Tuning.MAX_STEER_SPEED
	var seconds_of_warning := 60.0 / Tuning.speed_for(1)
	t.gt(seconds_of_warning, seconds_to_cross * 2.0,
		"a kerb arrives faster than the rig can cross the street - the game is unfair by construction")


func test_a_hit_costs_something_and_gives_a_moment_back(t: TestHarness) -> void:
	t.gt(float(Tuning.START_LIVES), 1.0, "one life makes the first mistake the last one")
	t.gt(Tuning.HIT_COOLDOWN, 0.0,
		"without immunity after a hit, one barricade takes every life in a single frame")
