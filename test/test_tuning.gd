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
	t.gt(Tuning.centre_reach(), Tuning.KERB_X + Tuning.BALL_RADIUS,
		"the ball cannot reach a building from the middle lane even swung fully")

	# And the other direction, which is the one that decides whether this is a
	# game or a cursor: at REST, with the boom pointed as far round as it goes,
	# the ball must fall SHORT of the kerb. Pointing at a building cannot be
	# enough - the ball has to be travelling.
	var at_rest := Tuning.BOOM * sin(Tuning.YAW_MAX)
	t.lt(at_rest, Tuning.KERB_X - Tuning.BALL_RADIUS,
		"a boom held still already reaches the kerb, so aiming is all there is to do")
	# The lower bound is loose on purpose. It exists to catch a boom so short
	# that reaching a kerb needs an absurd swing every single time - not to pin
	# a ratio. It sat at 0.85 while the boom was long enough that a nudge of
	# speed was enough, which made the margin decorative; at 0.71 the ball has
	# to extend by 40% to touch a kerb, and that IS the decision.
	t.gt(at_rest, (Tuning.KERB_X - Tuning.BALL_RADIUS) * 0.6,
		"a boom held still falls so far short that a slew is a formality, not a judgement")


func test_reaching_a_kerb_costs_a_real_swing(t: TestHarness) -> void:
	var need := Tuning.min_reaching_bearing()
	t.gt(need, 0.15, "the bearing needed to reach a kerb is too small to be a decision")
	t.lt(need, Tuning.YAW_MAX * 0.8,
		"reaching a kerb needs almost the full slew, so there is no margin to aim with")


func test_the_swing_lags_by_about_a_second(t: TestHarness) -> void:
	# A quarter period is how long after a swerve the ball reaches its extreme.
	# That lag IS the game: too short and the ball is a cursor, too long and
	# the building is behind you before the swing arrives.
	var lag := Tuning.ball_lag()
	t.gt(lag, 0.35, "the ball answers the thumb almost immediately - there is nothing to lead")
	t.lt(lag, 1.1, "the lag is longer than a building is on screen")


func test_a_building_is_on_screen_longer_than_the_lag(t: TestHarness) -> void:
	# If a kerb arrives and leaves faster than a swerve can be paid off, the
	# player is guessing rather than aiming, at every speed the ladder reaches.
	var lag := Tuning.ball_lag()
	for level in [1, 5, 10, 20]:
		var window: float = (Tuning.BOOM + Tuning.BUILDING_HALF_DEPTH * 2.0) / Tuning.speed_for(level)
		t.gt(window, lag,
			"at street %d a building passes faster than the ball can be swung at it" % level)


func test_a_barricade_leaves_a_lane_to_be_in(t: TestHarness) -> void:
	# It blocks one side plus a little of the middle, so there is always a lane
	# clear of it - and the rig has to actually fit there, hitbox and all.
	# Checked against the LANES the buttons can reach, never against a
	# continuous band: a gap the rig cannot be nudged into is not a gap.
	for side in [-1, 1]:
		var lo: float = -Tuning.LANE_HALF_WIDTH if side < 0 else Tuning.BARRICADE_INNER_X
		var hi: float = -Tuning.BARRICADE_INNER_X if side < 0 else Tuning.LANE_HALF_WIDTH
		var safe := 0
		for lane_x in Tuning.LANES:
			if not (lane_x + Tuning.RIG_HALF_WIDTH > lo and lane_x - Tuning.RIG_HALF_WIDTH < hi):
				safe += 1
		t.gt(float(safe), 0.0,
			"a barricade on side %d blocks every lane the rig can be nudged into" % side)
		t.lt(float(safe), float(Tuning.LANES.size()),
			"a barricade on side %d blocks no lane at all, so it is scenery" % side)


func test_the_starting_lane_is_never_safe_by_default(t: TestHarness) -> void:
	# Standing in the lane the run starts in must not be a strategy.
	for side in [-1, 1]:
		var lo: float = -Tuning.LANE_HALF_WIDTH if side < 0 else Tuning.BARRICADE_INNER_X
		var hi: float = -Tuning.BARRICADE_INNER_X if side < 0 else Tuning.LANE_HALF_WIDTH
		var mid: float = Tuning.LANES[Tuning.START_LANE]
		t.ok(mid + Tuning.RIG_HALF_WIDTH > lo and mid - Tuning.RIG_HALF_WIDTH < hi,
			"a barricade on side %d misses the starting lane - never moving is safe" % side)


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
	# The ball's bearing is a spring of natural frequency sqrt(BALL_PULL), so a
	# kick of w rad/s swings it about w/sqrt(BALL_PULL) radians before it turns
	# round. That has to clear the bearing a kerb needs.
	var amplitude := Tuning.REBOUND_MIN / sqrt(Tuning.BALL_PULL)
	t.gt(amplitude, Tuning.min_reaching_bearing(),
		"the smallest rebound cannot carry the ball round to the opposite kerb - chaining is impossible")


func test_the_power_ladder_is_reachable_inside_one_street(t: TestHarness) -> void:
	# Measured, not assumed: the aiming bot's mean street earns this much.
	# If the first rung costs more than a good street pays, the in-run power
	# fantasy never starts and the meter is a bar that only ever fills a third.
	const MEASURED_GOOD_STREET := 310
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
	var widest: float = absf(Tuning.LANES[0] - Tuning.LANES[Tuning.LANES.size() - 1])
	var seconds_to_cross := widest / Tuning.MAX_STEER_SPEED
	var seconds_of_warning := 60.0 / Tuning.speed_for(1)
	t.gt(seconds_of_warning, seconds_to_cross * 2.0,
		"a barricade arrives faster than the rig can change lanes - the game is unfair by construction")


func test_the_crane_can_be_swung_across_faster_than_the_street_arrives(t: TestHarness) -> void:
	# The same question for the control that actually matters now: can the boom
	# be got from one kerb to the other inside the time a building is visible?
	# If not, a street with buildings on alternating sides is a street where
	# half of them cannot be played, and that failure shows as absence.
	var sweep := Tuning.YAW_MAX * 2.0 / Tuning.MAX_SLEW
	var seconds_of_warning := 60.0 / Tuning.speed_for(1)
	t.gt(seconds_of_warning, sweep + Tuning.ball_lag(),
		"the crane cannot be swung kerb to kerb inside the time a building is on screen")


func test_a_hit_costs_something_and_gives_a_moment_back(t: TestHarness) -> void:
	t.gt(float(Tuning.START_LIVES), 1.0, "one life makes the first mistake the last one")
	t.gt(Tuning.HIT_COOLDOWN, 0.0,
		"without immunity after a hit, one barricade takes every life in a single frame")
