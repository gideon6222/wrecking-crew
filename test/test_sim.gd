extends RefCounted

## Unit tests on the simulation.
##
## Weighted toward the things that actually go wrong. "The rig moves when you
## steer it" is not worth a test; frame-rate dependence, a derived value
## drifting from the thing it is derived from, and a mechanic whose condition
## can never be true are.

const STEP := 1.0 / 60.0


func _run(s: Sim, seconds: float, target: float = INF) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		if target != INF:
			s.steer_to(target)
		s.advance(STEP)


# --- the pendulum ---------------------------------------------------------

func test_a_still_rig_leaves_the_ball_hanging(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 4.0)
	t.approx(s.theta, 0.0, 0.0001, "the ball swung with no input at all")
	t.approx(s.ball_x(), 0.0, 0.0001, "the ball is not under the boom on a straight run")


func test_the_ball_lags_the_rig_and_swings_the_other_way_first(t: TestHarness) -> void:
	# The single most important behaviour in the game, and the one a player
	# has to discover: pushing the rig right throws the ball LEFT, because the
	# ball is driven by the pivot's acceleration. If this ever inverts, the
	# whole control scheme has quietly become a lane-changer.
	var s := Sim.new()
	_run(s, 0.35, Tuning.LANE_HALF_WIDTH)
	t.gt(s.x, 0.2, "the rig did not move right")
	t.lt(s.theta, 0.0, "the ball did not trail behind the rig - it led it")


func test_loading_the_swing_then_turning_back_reaches_a_kerb(t: TestHarness) -> void:
	# The crane operator's technique, asserted end to end: pull AWAY from the
	# kerb you want, then turn back into it.
	#
	# Measured at the PEAK, not at the end. The first version of this test read
	# ball_x() after the manoeuvre and found it 2.6 metres the wrong way, which
	# looked like the physics being inverted and was really the test arriving
	# half a swing late. The ball is only over the kerb for a moment - that
	# moment is the whole game - so a test that samples one instant is testing
	# its own timing.
	# Swept, not reasoned about. Holding the load for a QUARTER period - which
	# is what "turn back when the ball reaches its extreme" suggests - peaks at
	# 4.19, a hand's breadth past the kerb. Holding it for a HALF period peaks
	# at 6.76, deep into the building. The difference is that the rig has to
	# travel too, and its own trip across the street is most of the swing's
	# amplitude; waiting for the ball alone throws away the half that comes
	# from where the cab ends up.
	#
	# Both numbers are worth keeping. The sloppy version still connects, which
	# is what makes the first minute forgiving; the timed version connects
	# twice as hard, which is what there is to get good at.
	var s := Sim.new()
	var load := Tuning.swing_period() * 0.5
	var peak := -INF
	var n := int(round(4.0 / STEP))
	for i in n:
		s.steer_to(-Tuning.LANE_HALF_WIDTH if float(i) * STEP < load else Tuning.LANE_HALF_WIDTH)
		s.advance(STEP)
		peak = maxf(peak, s.ball_x())
	t.gt(peak, Tuning.KERB_X + Tuning.BALL_RADIUS,
		"a half-period load and a turn back never puts the ball into a building")


func test_the_chain_never_goes_over_the_top(t: TestHarness) -> void:
	var s := Sim.new()
	# Drive rail to rail on the resonant period for a long time: if the clamp
	# leaks, this is what finds it.
	var half := Tuning.swing_period() * 0.5
	for i in 12:
		_run(s, half, Tuning.LANE_HALF_WIDTH if i % 2 == 0 else -Tuning.LANE_HALF_WIDTH)
		t.lt(absf(s.theta), Tuning.MAX_THETA + 0.0001, "the chain swung past its clamp")


func test_the_swing_is_frame_rate_independent(t: TestHarness) -> void:
	# Two 8ms steps must land where one 16ms step lands. `min(1, dt * rate)`
	# passes at 60fps and is a different spring at 120, which is what the
	# phone actually runs at.
	var a := Sim.new()
	var b := Sim.new()
	for i in 240:
		a.steer_to(Tuning.LANE_HALF_WIDTH)
		a.advance(1.0 / 120.0)
	for i in 120:
		b.steer_to(Tuning.LANE_HALF_WIDTH)
		b.advance(1.0 / 60.0)
	t.approx(a.x, b.x, 0.05, "the rig ends up somewhere different at 120fps")
	t.approx(a.theta, b.theta, 0.05, "the swing is different at 120fps")


func test_the_ball_position_is_derived_and_never_stored(t: TestHarness) -> void:
	# The score and the picture must come from one source. On a sibling game a
	# score that disagreed with the drawn object was the one bug that could not
	# be forgiven; the only fix that makes it impossible is this.
	var s := Sim.new()
	_run(s, 1.2, Tuning.LANE_HALF_WIDTH)
	t.approx(s.ball_x(), s.x + Tuning.CHAIN * sin(s.theta), 0.0001,
		"ball_x() is not the rig plus the chain")
	t.approx(s.ball_y(), Tuning.PIVOT_Y - Tuning.CHAIN * cos(s.theta), 0.0001,
		"ball_y() does not follow the chain")
	t.gt(s.ball_y(), 0.0, "the ball is underground")


func test_the_ball_rises_as_it_swings_out(t: TestHarness) -> void:
	t.gt(Tuning.ball_height(Tuning.MAX_THETA), Tuning.ball_height(0.0),
		"the ball does not rise on a pendulum, which means the chain is not a chain")


# --- the rig --------------------------------------------------------------

func test_the_rig_is_held_inside_the_street(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 6.0, 999.0)
	t.approx(s.x, Tuning.LANE_HALF_WIDTH, 0.0001, "the rig left the street")
	t.approx(s.vx, 0.0, 0.0001, "the rig is still driving into the kerb it is already against")


func test_steering_is_clamped_at_the_seam(t: TestHarness) -> void:
	var s := Sim.new()
	s.steer_to(50.0)
	t.approx(s.target_x, Tuning.LANE_HALF_WIDTH, 0.0001, "steer_to accepted a target off the street")


func test_the_rig_eases_rather_than_snapping(t: TestHarness) -> void:
	# A correction that is assigned rather than added cannot overshoot. The
	# player's word for the alternative is "bouncy".
	var s := Sim.new()
	var peak := 0.0
	var n := int(round(3.0 / STEP))
	for i in n:
		s.steer_to(1.5)
		s.advance(STEP)
		peak = maxf(peak, s.x)
	t.lt(peak, 1.5 + 0.02, "the rig overshot its target - the approach is a spring, not an approach")
	t.approx(s.x, 1.5, 0.05, "the rig never arrived at its target")


# --- what is on the street ------------------------------------------------

func test_the_first_moments_are_empty(t: TestHarness) -> void:
	var s := Sim.new()
	s.advance(STEP)
	for b in s.buildings:
		t.gt(b.z, Tuning.BOOM_FORWARD, "a building spawned close enough to be hit on frame one")
	for w in s.barricades:
		t.gt(w.z, Tuning.BOOM_FORWARD, "a barricade spawned on top of the player")


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
	# Driving down the middle must be punished, or standing still is a strategy.
	var s := Sim.new()
	_run(s, 30.0, 0.0)
	t.lt(float(s.lives), float(Tuning.START_LIVES),
		"a rig driven straight down the centre line never hit anything")


func test_running_out_of_lives_ends_the_run(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 40.0, 0.0)
	t.eq(s.over, true, "the run did not end after the lives ran out")
	t.eq(s.won, false, "a run that ran out of lives was recorded as won")
	t.eq(s.lives, 0, "the run ended with lives to spare")


func test_advancing_a_finished_run_changes_nothing(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 40.0, 0.0)
	var before := s.state()
	_run(s, 5.0, 0.0)
	t.dict_eq(s.state(), before, "a run that is over kept simulating")
