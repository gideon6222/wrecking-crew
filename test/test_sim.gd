extends RefCounted

## Unit tests on the simulation.
##
## Weighted toward the things that actually go wrong. "The rig moves when you
## steer it" is not worth a test; frame-rate dependence, a derived value
## drifting from the thing it is derived from, and a mechanic whose condition
## can never be true are.

const STEP := 1.0 / 60.0


## A rig on an empty street.
##
## The crane tests below are about the crane, and a real street ruins them: the
## ball swings out, hits a building, and `_impact()` kicks it - so "does the
## ball settle" and "how far does one swing reach" end up measuring the level
## layout instead. Pushing the spawn cursor past the horizon leaves the rest of
## the simulation completely untouched, which is what makes this honest rather
## than a mock.
##
## It reaches into a private, deliberately. The alternative is a test-only flag
## on Sim, and production state that exists for tests is worse.
func _bare() -> Sim:
	var s := Sim.new()
	s.buildings.clear()
	s.barricades.clear()
	s._chunk_spawned = 1 << 30
	return s


## Steps the sim without touching either control. Anything that needs input
## issues it itself - there is no "steer toward" argument any more, because
## there are two controls now and a single one would hide which was being
## tested.
func _run(s: Sim, seconds: float) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		s.advance(STEP)


# --- the crane ------------------------------------------------------------

func test_a_rig_that_is_never_aimed_leaves_the_ball_hanging(t: TestHarness) -> void:
	var s := _bare()
	_run(s, 4.0)
	t.approx(s.yaw, 0.0, 0.0001, "the boom slewed with no input at all")
	t.approx(s.bearing, 0.0, 0.0001, "the ball moved with no input at all")
	t.approx(s.ball_x(), Tuning.LANES[Tuning.START_LANE], 0.0001,
		"the ball is not straight out in front of the rig on an untouched run")


func test_the_ball_trails_the_boom_and_swings_past_it(t: TestHarness) -> void:
	# The single most important behaviour in the game. Slew the boom right and
	# the ball must lag BEHIND it on the way out, then overshoot it - that
	# overshoot is the whole reason a player leads a target instead of pointing
	# at one. If it ever became critically damped the crane would be a cursor.
	var s := _bare()
	s.aim_to(Tuning.YAW_MAX)

	var lagged := false
	var overshot := false
	var n := int(round(3.0 / STEP))
	for i in n:
		s.advance(STEP)
		if s.yaw > 0.15 and s.bearing < s.yaw - 0.05:
			lagged = true
		if s.bearing > s.yaw + 0.02:
			overshot = true

	t.ok(lagged, "the ball kept up with the boom - there is no lag to lead")
	t.ok(overshot, "the ball never swung past the boom - the spring is overdamped")


func test_pointing_at_a_kerb_without_slewing_does_not_reach_it(t: TestHarness) -> void:
	# The measured margin the design rests on. Let the crane settle fully at
	# full lock, so the ball is at rest and the radius has decayed to BOOM: the
	# ball must fall SHORT of the kerb. Pointing is not hitting.
	var s := _bare()
	s.aim_to(Tuning.YAW_MAX)
	_run(s, 9.0)
	t.approx(s.yaw, Tuning.YAW_MAX, 0.001, "the boom never reached full lock")
	t.approx(s.bearing_vel, 0.0, 0.02, "the ball never settled")
	t.lt(absf(s.ball_x() - s.x), Tuning.KERB_X - Tuning.BALL_RADIUS,
		"a settled boom at full lock already reaches the kerb - aiming is all there is to do")


func test_slewing_hard_is_what_reaches_a_kerb(t: TestHarness) -> void:
	# And the other half: swung across, the ball must get there. Measured at
	# the PEAK over the manoeuvre, because the ball is only out that far for a
	# moment - and that moment is the game. A test that samples one instant is
	# testing its own timing.
	var s := _bare()
	var peak := 0.0
	var n := int(round(2.4 / STEP))
	for i in n:
		s.aim_to(-Tuning.YAW_MAX if float(i) * STEP < Tuning.swing_period() * 0.5 else Tuning.YAW_MAX)
		s.advance(STEP)
		peak = maxf(peak, s.ball_x() - s.x)
	t.gt(peak, Tuning.KERB_X,
		"slewing the crane across never gets the ball properly into a building")


func test_the_boom_never_points_backwards(t: TestHarness) -> void:
	var s := _bare()
	for i in 10:
		s.aim_to(99.0 if i % 2 == 0 else -99.0)
		_run(s, Tuning.swing_period() * 0.5)
		t.lt(absf(s.yaw), Tuning.YAW_MAX + 0.0001, "the boom slewed past its stop")


func test_aiming_is_clamped_at_the_seam(t: TestHarness) -> void:
	var s := Sim.new()
	s.aim_to(50.0)
	t.approx(s.yaw_target, Tuning.YAW_MAX, 0.0001, "aim_to accepted a bearing off the stop")
	s.aim_to(-50.0)
	t.approx(s.yaw_target, -Tuning.YAW_MAX, 0.0001, "aim_to accepted a bearing off the stop")


func test_the_radius_grows_with_how_hard_the_ball_is_travelling(t: TestHarness) -> void:
	# Reach is a consequence of speed, not of where the boom points. That is
	# what stops "point at the building" being the whole game.
	var gentle := _bare()
	gentle.aim_to(Tuning.YAW_MAX)
	_run(gentle, 9.0)

	var hard := _bare()
	var peak := 0.0
	var n := int(round(2.4 / STEP))
	for i in n:
		hard.aim_to(-Tuning.YAW_MAX if float(i) * STEP < Tuning.swing_period() * 0.5 else Tuning.YAW_MAX)
		hard.advance(STEP)
		peak = maxf(peak, hard.radius)

	t.approx(gentle.radius, Tuning.BOOM, 0.05, "a settled crane is not at its rest length")
	t.gt(peak, gentle.radius + 1.0, "swinging hard does not lengthen the reach at all")
	t.lt(peak, Tuning.RADIUS_MAX + 0.0001, "the reach went past its cap")


func test_the_crane_is_frame_rate_independent(t: TestHarness) -> void:
	# Two 8ms steps must land where one 16ms step lands. `min(1, dt * rate)`
	# passes at 60fps and is a different spring at 120, which is what the phone
	# actually runs at.
	var a := _bare()
	var b := _bare()
	for i in 240:
		a.aim_to(Tuning.YAW_MAX)
		a.advance(1.0 / 120.0)
	for i in 120:
		b.aim_to(Tuning.YAW_MAX)
		b.advance(1.0 / 60.0)
	t.approx(a.yaw, b.yaw, 0.03, "the boom ends up somewhere different at 120fps")
	t.approx(a.bearing, b.bearing, 0.05, "the ball ends up somewhere different at 120fps")


func test_the_ball_position_is_derived_and_never_stored(t: TestHarness) -> void:
	# The score and the picture must come from one source. On a sibling game a
	# score that disagreed with the drawn object was the one bug that could not
	# be forgiven; the only fix that makes it impossible is this.
	var s := _bare()
	s.aim_to(0.7)
	_run(s, 1.2)
	t.approx(s.ball_x(), s.x + s.radius * sin(s.bearing), 0.0001,
		"ball_x() is not the rig plus the boom")
	t.approx(s.ball_z(), s.distance + s.radius * cos(s.bearing), 0.0001,
		"ball_z() is not the rig plus the boom")
	t.gt(s.ball_y(), 0.0, "the ball is underground")


func test_the_ball_is_always_somewhere_ahead_of_or_beside_the_cab(t: TestHarness) -> void:
	# A ball that can end up BEHIND the rig is a ball the player cannot watch
	# and the camera cannot frame.
	var s := _bare()
	for i in 12:
		s.aim_to(Tuning.YAW_MAX if i % 2 == 0 else -Tuning.YAW_MAX)
		_run(s, Tuning.swing_period() * 0.5)
		t.gt(s.ball_z() - s.distance, -0.5, "the ball got behind the cab")


# --- the rig, which is now nudged between lanes ---------------------------

func test_a_nudge_moves_exactly_one_lane(t: TestHarness) -> void:
	var s := _bare()
	t.eq(s.lane, Tuning.START_LANE, "the run did not start in the starting lane")
	s.nudge(1)
	t.eq(s.lane, Tuning.START_LANE + 1, "a nudge did not move one lane")
	s.nudge(-1)
	s.nudge(-1)
	t.eq(s.lane, Tuning.START_LANE - 1, "two nudges back did not land one lane left")


func test_nudging_off_the_end_of_the_street_does_nothing(t: TestHarness) -> void:
	var s := _bare()
	for i in 8:
		s.nudge(1)
	t.eq(s.lane, Tuning.LANES.size() - 1, "the rig ran off the right of the street")
	for i in 16:
		s.nudge(-1)
	t.eq(s.lane, 0, "the rig ran off the left of the street")


func test_the_rig_actually_arrives_in_the_lane_it_was_sent_to(t: TestHarness) -> void:
	var s := _bare()
	s.nudge(1)
	_run(s, 2.5)
	t.approx(s.x, Tuning.LANES[Tuning.START_LANE + 1], 0.05, "the rig never reached its lane")


func test_the_rig_eases_rather_than_snapping(t: TestHarness) -> void:
	# A correction that is assigned rather than added cannot overshoot. The
	# player's word for the alternative is "bouncy".
	var s := _bare()
	s.nudge(1)
	var target: float = Tuning.LANES[Tuning.START_LANE + 1]
	var peak := 0.0
	var n := int(round(3.0 / STEP))
	for i in n:
		s.advance(STEP)
		peak = maxf(peak, s.x)
	t.lt(peak, target + 0.02, "the rig overshot its lane - the approach is a spring, not an approach")


func test_steer_to_snaps_to_a_real_lane(t: TestHarness) -> void:
	# There must be no way to end up between two lanes, or every lane
	# assertion in the suite is quietly measuring something else.
	var s := _bare()
	s.steer_to(99.0)
	t.eq(s.lane, Tuning.LANES.size() - 1, "steer_to did not clamp to the outermost lane")
	s.steer_to(0.1)
	t.approx(s.target_x, Tuning.LANES[s.lane], 0.0001, "the rig is heading between two lanes")


# --- what is on the street ------------------------------------------------

func test_the_first_moments_are_empty(t: TestHarness) -> void:
	var s := Sim.new()
	s.advance(STEP)
	for b in s.buildings:
		t.gt(b.z, Tuning.RADIUS_MAX, "a building spawned close enough to be hit on frame one")
	for w in s.barricades:
		t.gt(w.z, Tuning.RADIUS_MAX, "a barricade spawned on top of the player")


func test_both_kerbs_get_built_on(t: TestHarness) -> void:
	# A content band that is never reached is the failure that shows as
	# absence: no error, nothing missing on screen, the game simply plays
	# differently than it reads.
	var left := 0
	var right := 0
	for level in [1, 2, 3, 4, 5]:
		var s := Sim.new(level)
		_run(s, 20.0)
		for b in s.buildings:
			if b.side < 0:
				left += 1
			else:
				right += 1
	t.gt(float(left), 0.0, "nothing is ever built on the left kerb")
	t.gt(float(right), 0.0, "nothing is ever built on the right kerb")


func test_both_barricade_sides_occur(t: TestHarness) -> void:
	var sides := {}
	for level in range(1, 9):
		var s := Sim.new(level)
		_run(s, 26.0)
		for w in s.barricades:
			sides[w.side] = true
	t.eq(sides.size(), 2, "barricades only ever block one side of the street")


func test_buildings_span_the_whole_height_range(t: TestHarness) -> void:
	var lo := 999
	var hi := 0
	for level in range(1, 13):
		var s := Sim.new(level)
		_run(s, 26.0)
		for b in s.buildings:
			lo = mini(lo, b.floors)
			hi = maxi(hi, b.floors)
	t.eq(lo, Tuning.MIN_FLOORS, "the shortest building never occurs")
	t.eq(hi, Tuning.MAX_FLOORS, "the tallest building never occurs - MAX_FLOORS is unreachable")


func test_a_building_is_never_taller_than_the_cap(t: TestHarness) -> void:
	for level in [1, 10, 40]:
		var s := Sim.new(level)
		_run(s, 26.0)
		for b in s.buildings:
			t.lt(float(b.floors), float(Tuning.MAX_FLOORS) + 0.5,
				"a building at street %d is taller than MAX_FLOORS" % level)


func test_entities_behind_the_rig_are_retired(t: TestHarness) -> void:
	# Without this the arrays grow all street and collision gets slower as the
	# run goes on, which reads as "it slows down near the end" and gets blamed
	# on rendering.
	var s := Sim.new()
	_run(s, 25.0)
	for b in s.buildings:
		t.gt(b.z, s.distance - 25.0, "a building far behind the rig is still being tested")


# --- scoring and the ladder ----------------------------------------------

func test_the_power_meter_climbs_and_stops(t: TestHarness) -> void:
	var s := Sim.new()
	for i in 400:
		s._earn(50)
	t.eq(s.power, Tuning.POWER_MAX, "the power ladder never topped out")
	t.eq(s.meter_target(), 0, "a topped-out ladder still advertises a next rung")


func test_rubble_never_moves_backwards(t: TestHarness) -> void:
	var s := Sim.new()
	var last := 0
	var mem := {}
	var n := int(round(25.0 / STEP))
	for i in n:
		Policies.steer(Policies.WRECKER, s, mem)
		s.advance(STEP)
		t.ok(s.rubble >= last, "rubble went down")
		last = s.rubble


func test_a_flattened_building_stops_paying(t: TestHarness) -> void:
	var s := Sim.new()
	var mem := {}
	var n := int(round(28.0 / STEP))
	for i in n:
		Policies.steer(Policies.WRECKER, s, mem)
		s.advance(STEP)
		for b in s.buildings:
			t.ok(b.left >= 0, "a building was knocked past zero floors")
	t.eq(s.floors_felled >= s.flattened, true,
		"more buildings were flattened than floors were felled, which is impossible")


func test_a_barricade_taken_by_the_cab_costs_a_life(t: TestHarness) -> void:
	# Never pressing a button must be punished, or standing still is a strategy.
	var s := Sim.new()
	_run(s, 30.0)
	t.lt(float(s.lives), float(Tuning.START_LIVES),
		"a rig driven straight down the centre line never hit anything")


func test_running_out_of_lives_ends_the_run(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 60.0)
	t.eq(s.over, true, "the run did not end after the lives ran out")
	t.eq(s.won, false, "a run that ran out of lives was recorded as won")
	t.eq(s.lives, 0, "the run ended with lives to spare")


func test_advancing_a_finished_run_changes_nothing(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 60.0)
	var before := s.state()
	_run(s, 5.0)
	t.dict_eq(s.state(), before, "a run that is over kept simulating")

# --- what happens AFTER a street, which is where the first build froze ------

func test_a_finished_street_can_be_continued(t: TestHarness) -> void:
	# The bug this pins: `over` went true at the end of street one and nothing
	# in the game could clear it, so `advance()` returned early forever and the
	# phone showed a live HUD over a dead world.
	#
	# Every other test in this file plays a street and reads the state at the
	# end - which is the exact instant the freeze began. The lesson is not
	# "add a test for this"; it is that a suite which always stops where the
	# content stops cannot see past the end of the content.
	# Played, not passive. A passive run runs out of lives at about twelve
	# seconds and never reaches the end of the street at all - so the first
	# version of this test asserted the winning path against a run that had
	# died, and reported the wrong thing twice.
	var s := Sim.new()
	var mem := {}
	var guard := 0
	while not s.over and guard < 6000:
		Policies.steer(Policies.WRECKER, s, mem)
		s.advance(STEP)
		guard += 1
	t.eq(s.over, true, "the street never finished")
	t.eq(s.won, true, "reaching the end of the street was not recorded as a win")
	t.gt(float(s.lives), 0.0, "the aiming policy died on street one")

	var rubble_before := s.rubble
	var power_before := s.power
	var lives_before := s.lives

	s.next_street()
	t.eq(s.over, false, "the run is still over after moving to the next street")
	t.eq(s.level, 2, "the street number did not advance")
	t.approx(s.distance, 0.0, 0.0001, "the next street did not start at its beginning")
	t.approx(s.bearing, 0.0, 0.0001, "the ball carried its swing into the next street")
	t.approx(s.yaw, 0.0, 0.0001, "the boom kept its aim into the next street")

	# The run owns these; the street does not.
	t.eq(s.rubble, rubble_before, "rubble was lost between streets")
	t.eq(s.power, power_before, "the power ladder reset between streets")
	t.eq(s.lives, lives_before, "lives were restored for free between streets")

	# And it must actually play.
	for i in 360:
		Policies.steer(Policies.WRECKER, s, mem)
		s.advance(STEP)
	t.gt(s.distance, 40.0, "the next street does not advance when stepped")


func test_a_dead_run_restarts_from_the_first_street(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 60.0)
	t.eq(s.over, true, "the run did not end")
	s.restart(1)
	t.eq(s.over, false, "restarting left the run over")
	t.eq(s.level, 1, "a dead run did not go back to street one")
	t.eq(s.lives, Tuning.START_LIVES, "a fresh run did not get its lives back")
	t.eq(s.rubble, 0, "a fresh run kept the last run's rubble")
	t.eq(s.power, Tuning.POWER_START, "a fresh run kept the last run's power")
	_run(s, 6.0)
	t.gt(s.distance, 40.0, "a restarted run does not advance when stepped")


func test_several_streets_can_be_played_back_to_back(t: TestHarness) -> void:
	# The ladder, end to end. A street that cannot be left is a game with one
	# street in it however many are generated.
	var s := Sim.new()
	var mem := {}
	for street in 4:
		var guard := 0
		while not s.over and guard < 6000:
			Policies.steer(Policies.WRECKER, s, mem)
			s.advance(STEP)
			guard += 1
		t.eq(s.over, true, "street %d never ended" % (street + 1))
		if s.lives <= 0:
			break
		s.next_street()
		mem.clear()
	t.gt(float(s.level), 1.0, "the run never got past the first street")
