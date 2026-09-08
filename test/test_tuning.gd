extends RefCounted

## Design tests: assertions about *intent* rather than about values.
##
## A snapshot of the constants pins the numbers but says nothing about what
## they are for. These say what the numbers have to remain true of, so a
## balance change that breaks the shape of the game fails here rather than in
## a playtest three weeks later.


func test_the_ball_can_reach_a_column_at_all(t: TestHarness) -> void:
	# The one relationship the whole game rests on. A target the tool cannot
	# reach is not a target - it is scenery that looks like content, and the
	# failure is silence: nothing errors, nothing is missing on screen, the
	# game simply has no scoring in it.
	t.gt(Tuning.RADIUS_MAX, Tuning.FACE_Z + Tuning.BALL_RADIUS,
		"the ball cannot get past the face of the building even at full swing")
	t.gt(Tuning.reach_at_face(), Tuning.BAY_WIDTH,
		"the ball can only reach the bay directly in front of the crane")


func test_pointing_at_a_column_is_not_enough(t: TestHarness) -> void:
	# At rest the ball hangs BOOM from the turret, which must fall short of the
	# face. If a parked crane already overlapped the building, aiming would be
	# the whole game and the swing would be decoration.
	t.lt(Tuning.BOOM + Tuning.BALL_RADIUS, Tuning.FACE_Z,
		"a ball hanging still already reaches the building - the swing does nothing")
	t.gt(Tuning.BOOM + Tuning.BALL_RADIUS, Tuning.FACE_Z * 0.55,
		"the ball hangs so far short that reaching the building at all is a feat")


func test_a_column_is_narrower_than_a_bay(t: TestHarness) -> void:
	# Otherwise the ball landing anywhere in a bay counts, being roughly right
	# is as good as being right, and there is nothing to aim at. That was the
	# first measured build: it used half a bay plus the ball as the tolerance,
	# and a policy that never looked at the building scored top.
	var tolerance := Tuning.COLUMN_HALF_WIDTH + Tuning.BALL_RADIUS
	t.lt(tolerance, Tuning.BAY_WIDTH * 0.75,
		"the strike tolerance covers most of a bay, so aiming inside one does not matter")
	t.gt(tolerance, Tuning.BALL_RADIUS,
		"the column is narrower than nothing - it can never be hit")


func test_a_wide_building_cannot_be_worked_from_one_spot(t: TestHarness) -> void:
	# The reason the crane can move. With every bay reachable from the middle,
	# parking is decoration - measured, and a policy that never moved scored
	# identically to one that worked the site properly.
	var widest := Tuning.half_width(20)  # clamps to BAYS_MAX
	t.gt(widest, Tuning.reach_at_face(),
		"the widest building fits inside the reach from a single parking spot")

	# And the other direction: with the crane moved as far as it goes, every
	# bay of the widest building must be reachable. A bay that can never be hit
	# is a building that can never be finished.
	var furthest: float = absf(Tuning.LANES[Tuning.LANES.size() - 1]) + Tuning.reach_at_face()
	t.gt(furthest, widest + Tuning.COLUMN_HALF_WIDTH,
		"the outer bay of the widest building cannot be reached from any parking spot")


func test_the_swing_lags_by_about_half_a_second(t: TestHarness) -> void:
	# A quarter period is how long after a slew the ball reaches its extreme.
	# That lag IS the game: too short and the ball is a cursor, too long and
	# nothing can be aimed.
	var lag := Tuning.ball_lag()
	t.gt(lag, 0.35, "the ball answers the thumb almost immediately - there is nothing to lead")
	t.lt(lag, 1.1, "the lag is so long that a strike cannot be aimed at all")


func test_the_budget_is_enough_to_finish_the_job(t: TestHarness) -> void:
	# The budget is derived from the columns rather than set as a rate, and
	# this is the assertion that keeps it honest. A flat rate drifted out of
	# step with the content the moment columns started varying: five bays of
	# four hit points got 17 swings for a job needing 20, so the last two
	# buildings were arithmetically unwinnable however well they were played.
	for level in range(1, 15):
		var needed := 0
		for bay in Tuning.bays_for(level):
			needed += Tuning.column_hp_at(level, bay)
		t.gt(float(Tuning.swings_for(level)), float(needed),
			"level %d cannot be finished even with a perfect swing on every column" % level)
		t.lt(float(Tuning.swings_for(level)), float(needed) * 2.0,
			"level %d has so many spare swings that wasting them costs nothing" % level)


func test_the_spare_is_small_enough_to_be_felt(t: TestHarness) -> void:
	t.gt(float(Tuning.SWINGS_SPARE), 0.0, "no margin at all makes the first miss fatal")
	t.lt(float(Tuning.SWINGS_SPARE), 8.0, "the margin is wide enough that swings are not a resource")


func test_working_along_one_side_topples_a_big_building(t: TestHarness) -> void:
	# The claim the whole game rests on: the ORDER matters. Taking the bays
	# from one end has to be punished at the sizes where a real choice exists.
	#
	# Computed from the geometry rather than eyeballed. The lean is the
	# centroid of what is still standing over the half width, so dropping the
	# first k bays of n leaves a known, checkable number.
	for n in [5, 7]:
		var arm := float(n - 1) * 0.5 * Tuning.BAY_WIDTH
		var worst := 0.0
		for k in range(1, n - 1):  # at least two bays must remain to topple
			var moment := 0.0
			var mass := 0.0
			for i in range(k, n):
				moment += (float(i) - float(n - 1) * 0.5) * Tuning.BAY_WIDTH
				mass += 1.0
			worst = maxf(worst, absf((moment / mass) / arm))
		t.gt(worst, Tuning.TOPPLE_LIMIT,
			"a %d-bay building can be taken down entirely from one end without going over" % n)


func test_a_balanced_order_is_always_survivable(t: TestHarness) -> void:
	# And the other half. If there is no order that keeps the thing up, the
	# game is a coin flip rather than a puzzle.
	for n in [3, 4, 5, 6, 7]:
		var arm := maxf(Tuning.BAY_WIDTH, float(n - 1) * 0.5 * Tuning.BAY_WIDTH)
		var standing := []
		for i in n:
			standing.append(true)
		# Work outside-in alternately, which is what the gauge teaches.
		var order := []
		var lo: int = 0
		var hi: int = n - 1
		while lo <= hi:
			order.append(lo)
			if hi != lo:
				order.append(hi)
			lo += 1
			hi -= 1

		var worst := 0.0
		for drop in order:
			standing[drop] = false
			var moment := 0.0
			var mass := 0.0
			for i in n:
				if not standing[i]:
					continue
				moment += (float(i) - float(n - 1) * 0.5) * Tuning.BAY_WIDTH
				mass += 1.0
			if mass >= 2.0:
				worst = maxf(worst, absf((moment / mass) / arm))
		t.lt(worst, Tuning.TOPPLE_LIMIT,
			"a %d-bay building cannot be taken down in any order without going over" % n)


func test_a_clean_drop_is_possible_and_not_free(t: TestHarness) -> void:
	t.lt(Tuning.LEAN_WARN, Tuning.TOPPLE_LIMIT,
		"the clean threshold is above the topple limit, so a clean drop is impossible")
	t.gt(Tuning.LEAN_WARN, 0.1,
		"the clean threshold is so low that no demolition could ever qualify")

	# A single outer bay dropped from a three-bay building must cost the bonus,
	# which is what makes "start in the middle" a decision on the very first
	# building rather than something that only matters later.
	var three_bay_single_drop := 0.5
	t.lt(Tuning.LEAN_WARN, three_bay_single_drop,
		"dropping an outer bay first still counts as clean, so order does not matter early")


func test_the_clean_bonus_beats_the_building_it_is_paid_on(t: TestHarness) -> void:
	# Otherwise the game is "knock it down", which anyone can do. It has to be
	# "knock it down without putting it on the neighbours".
	var whole_building := Tuning.bays_for(1) * Tuning.floors_for(1) * Tuning.RUBBLE_PER_FLOOR
	t.gt(float(Tuning.CLEAN_DROP_BONUS), float(whole_building) * 0.5,
		"the clean bonus is small enough beside the rubble that being careful is not worth it")


func test_a_building_grows_but_stays_workable(t: TestHarness) -> void:
	t.gt(Tuning.bays_for(9), Tuning.bays_for(1), "buildings never get wider")
	t.gt(Tuning.floors_for(9), Tuning.floors_for(1), "buildings never get taller")
	t.eq(Tuning.bays_for(99), Tuning.BAYS_MAX, "the width never settles at its cap")
	t.eq(Tuning.floors_for(99), Tuning.FLOORS_MAX, "the height never settles at its cap")


func test_a_hit_needs_a_moving_ball(t: TestHarness) -> void:
	t.gt(Tuning.STRIKE_MIN_SWING, 0.0,
		"a still ball breaks columns, so parking in front of one is free")
	t.lt(Tuning.STRIKE_MIN_SWING, Tuning.REBOUND_MIN,
		"the rebound from one strike cannot land the next, so a demolition never flows")


func test_the_lean_settles_fast_enough_to_be_steered(t: TestHarness) -> void:
	# A gauge that takes longer to move than a demolition takes to finish is a
	# gauge that reports history rather than state.
	t.gt(Tuning.LEAN_SETTLE, 0.5, "the lean gauge lags so far behind that it cannot be steered by")
	t.lt(Tuning.LEAN_SETTLE, 12.0, "the lean snaps instantly, so there is no moment to react in")
