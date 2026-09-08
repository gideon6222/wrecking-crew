extends RefCounted

## Unit tests on the simulation.
##
## Weighted toward the things that actually go wrong. "The boom moves when you
## aim it" is not worth a test; frame-rate dependence, a derived value drifting
## from the thing it is derived from, a mechanic whose condition can never be
## true, and a state the game cannot get out of are.

const STEP := 1.0 / 60.0


## Steps the sim without touching either control. Anything that needs input
## issues it itself - there is no "aim toward" argument, because there are two
## controls and a single one would hide which was being tested.
func _run(s: Sim, seconds: float) -> void:
	var n := int(round(seconds / STEP))
	for i in n:
		s.advance(STEP)


## Drives the ball through one bay's column until it goes, or gives up.
## Returns how many swings it cost.
## Driven through `Policies.work_bay`, which is the same code the scripted
## player uses. An earlier version of this helper had a sweep of its own and
## was worse at the game than the committed policy - so tests meant to check
## the building's behaviour were really checking whether that sweep could
## connect, and eight of them failed for reasons unrelated to their subject.
func _work(s: Sim, bay: int, seconds: float = 20.0) -> int:
	var before := s.swings_left
	var n := int(round(seconds / STEP))
	for i in n:
		if s.over or not s.bays[bay].standing:
			break
		Policies.work_bay(s, bay)
		s.advance(STEP)
	return before - s.swings_left


# --- the crane ------------------------------------------------------------

func test_an_untouched_crane_does_nothing(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 6.0)
	t.approx(s.yaw, 0.0, 0.0001, "the boom slewed with no input at all")
	t.approx(s.bearing, 0.0, 0.0001, "the ball moved with no input at all")
	t.eq(s.swings_left, Tuning.swings_for(1), "a swing was spent without the player doing anything")
	t.eq(s.bays_standing(), Tuning.bays_for(1), "the building fell down on its own")


func test_the_ball_trails_the_boom_and_swings_past_it(t: TestHarness) -> void:
	# The single most important behaviour in the game. Slew the boom and the
	# ball must lag BEHIND it on the way out, then overshoot - that overshoot
	# is the whole reason a player leads a target instead of pointing at one.
	# If it ever became critically damped the crane would be a cursor.
	var s := Sim.new()
	s.aim_to(Tuning.YAW_MAX)
	var lagged := false
	var overshot := false
	for i in int(round(3.0 / STEP)):
		s.advance(STEP)
		if s.yaw > 0.15 and s.bearing < s.yaw - 0.05:
			lagged = true
		if s.bearing > s.yaw + 0.02:
			overshot = true
	t.ok(lagged, "the ball kept up with the boom - there is no lag to lead")
	t.ok(overshot, "the ball never swung past the boom - the spring is overdamped")


func test_a_parked_crane_cannot_reach_the_building(t: TestHarness) -> void:
	# The margin the design rests on: pointing is not hitting. Let the crane
	# settle fully at full lock, so the ball is at rest and the radius has
	# decayed to BOOM - it must still be short of the face.
	var s := Sim.new()
	s.aim_to(Tuning.YAW_MAX)
	_run(s, 9.0)
	t.approx(s.bearing_vel, 0.0, 0.02, "the ball never settled")
	t.lt(s.radius, Tuning.FACE_Z - Tuning.BALL_RADIUS,
		"a settled crane already reaches the building - aiming is all there is to do")
	t.eq(s.swings_left, Tuning.swings_for(1), "a settled ball spent a swing")


func test_swinging_hard_reaches_past_the_face(t: TestHarness) -> void:
	var s := Sim.new()
	var deepest := 0.0
	for i in int(round(4.0 / STEP)):
		var half := Tuning.swing_period() * 0.5
		s.aim_to(Tuning.YAW_MAX * 0.6 if fmod(s.time, half * 2.0) < half else -Tuning.YAW_MAX * 0.6)
		s.advance(STEP)
		deepest = maxf(deepest, s.ball_z())
	# The ball only has to get within its own radius of the face to touch a
	# column, which is the same threshold the strike uses. Asserting against
	# the face itself would be asserting something the game never requires.
	t.gt(deepest, Tuning.FACE_Z - Tuning.BALL_RADIUS,
		"swinging the crane never gets the ball to the building")


func test_the_crane_is_frame_rate_independent(t: TestHarness) -> void:
	# Two 8ms steps must land where one 16ms step lands. `min(1, dt * rate)`
	# passes at 60fps and is a different spring at 120, which is what the phone
	# actually runs at.
	var a := Sim.new()
	var b := Sim.new()
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
	var s := Sim.new()
	s.aim_to(0.7)
	_run(s, 1.2)
	t.approx(s.ball_x(), s.x + s.radius * sin(s.bearing), 0.0001,
		"ball_x() is not the crane plus the boom")
	t.approx(s.ball_z(), s.radius * cos(s.bearing), 0.0001,
		"ball_z() is not the crane plus the boom")
	t.gt(s.ball_y(), 0.0, "the ball is underground")


func test_aiming_is_clamped_at_the_seam(t: TestHarness) -> void:
	var s := Sim.new()
	s.aim_to(50.0)
	t.approx(s.yaw_target, Tuning.YAW_MAX, 0.0001, "aim_to accepted a bearing off the stop")
	s.aim_to(-50.0)
	t.approx(s.yaw_target, -Tuning.YAW_MAX, 0.0001, "aim_to accepted a bearing off the stop")


func test_the_crane_parks_where_it_is_sent(t: TestHarness) -> void:
	var s := Sim.new()
	t.eq(s.lane, Tuning.START_LANE, "the demo did not start in the starting spot")
	s.nudge(1)
	_run(s, 3.0)
	t.approx(s.x, Tuning.LANES[Tuning.START_LANE + 1], 0.05, "the crane never reached its spot")
	for i in 8:
		s.nudge(1)
	t.eq(s.lane, Tuning.LANES.size() - 1, "the crane drove off the end of the site")
	for i in 16:
		s.nudge(-1)
	t.eq(s.lane, 0, "the crane drove off the other end of the site")


func test_steer_to_snaps_to_a_real_spot(t: TestHarness) -> void:
	var s := Sim.new()
	s.steer_to(99.0)
	t.eq(s.lane, Tuning.LANES.size() - 1, "steer_to did not clamp to the outermost spot")
	s.steer_to(0.1)
	t.approx(s.target_x, Tuning.LANES[s.lane], 0.0001, "the crane is heading between two spots")


# --- the building ---------------------------------------------------------

func test_the_site_is_built_from_the_level(t: TestHarness) -> void:
	for level in [1, 3, 6, 12]:
		var s := Sim.new(level)
		t.eq(s.bays.size(), Tuning.bays_for(level), "level %d has the wrong number of bays" % level)
		t.eq(s.swings_left, Tuning.swings_for(level), "level %d has the wrong swing budget" % level)
		for i in s.bays.size():
			t.eq(s.bays[i].hp, Tuning.column_hp_at(level, i),
				"level %d bay %d does not match its keyed column" % [level, i])
			t.ok(s.bays[i].standing, "a bay started already down")


func test_the_same_building_is_the_same_every_time(t: TestHarness) -> void:
	# Keyed on the place, never on a stream, so a given site is the same site
	# on any device and a golden over a whole demolition is possible at all.
	for level in [1, 4, 9]:
		var a := Sim.new(level)
		var b := Sim.new(level)
		for i in a.bays.size():
			t.eq(a.bays[i].hp, b.bays[i].hp,
				"level %d bay %d differed between two builds" % [level, i])


func test_a_column_takes_its_hit_points_to_break(t: TestHarness) -> void:
	var s := Sim.new()
	var hp: int = s.bays[1].hp
	var spent := _work(s, 1)
	t.eq(s.bays[1].standing, false, "the middle bay never came down")
	t.eq(spent, hp, "the column cost a different number of swings than it had hit points")


func test_dropping_a_bay_pays_its_floors(t: TestHarness) -> void:
	var s := Sim.new()
	var floors: int = s.bays[1].floors
	_work(s, 1)
	t.eq(s.floors_down, floors, "the floors that came down were not counted")
	t.eq(s.rubble, floors * Tuning.RUBBLE_PER_FLOOR, "the rubble does not match the floors")


func test_a_fallen_bay_cannot_be_hit_again(t: TestHarness) -> void:
	# Otherwise the swing budget drains into thin air and the player is being
	# charged for hitting nothing.
	var s := Sim.new()
	_work(s, 1)
	var after := s.swings_left
	_work(s, 1, 3.0)
	t.eq(s.swings_left, after, "swings were spent on a bay that had already fallen")


# --- the lean, which is the thing that goes wrong -------------------------

func test_the_middle_bay_costs_almost_no_lean(t: TestHarness) -> void:
	var s := Sim.new()
	_work(s, 1)
	_run(s, 2.0)
	t.lt(absf(s.lean), Tuning.LEAN_WARN,
		"taking the middle bay out unbalances the building, so there is no safe opening move")


func test_an_outer_bay_costs_real_lean(t: TestHarness) -> void:
	var s := Sim.new()
	_work(s, 0)
	_run(s, 2.0)
	t.gt(absf(s.lean), Tuning.LEAN_WARN,
		"taking an outer bay out first is free, so the order does not matter")


func test_working_along_one_side_topples_a_wide_building(t: TestHarness) -> void:
	# The claim the game rests on, driven through the real simulation rather
	# than through the arithmetic in test_tuning.
	var s := Sim.new(5)
	for bay in s.bays.size():
		if s.over:
			break
		_work(s, bay)
		_run(s, 1.5)
	t.eq(s.over, true, "a one-sided demolition of a wide building did not end")
	t.eq(s.won, false, "a one-sided demolition of a wide building was recorded as a success")
	t.gt(float(s.bays_standing()), 0.0,
		"the building came all the way down and still counted as a failure")


func test_a_lone_bay_never_topples(t: TestHarness) -> void:
	# The clause that makes the game finishable at all. The lean is the
	# centroid of what is still standing, so the last bay is by definition at
	# its own offset and reads as a maximum - without this, no building could
	# ever be completed, in any order.
	var s := Sim.new()
	_work(s, 1)
	_work(s, 0)
	_run(s, 3.0)
	t.eq(s.bays_standing(), 1, "the test did not reach a single standing bay")
	t.eq(s.over, false, "a lone standing bay toppled the building")


func test_the_worst_lean_ignores_what_cannot_topple(t: TestHarness) -> void:
	# Measured: recording the lean while a lone bay stood put every demolition
	# at 1.00 and made the clean-drop bonus unearnable by anybody.
	var s := Sim.new()
	_work(s, 1)
	_work(s, 0)
	_run(s, 3.0)
	t.lt(s.worst_lean, Tuning.TOPPLE_LIMIT,
		"the worst lean recorded a value that could never have toppled the building")


# --- finishing ------------------------------------------------------------

func test_bringing_it_all_down_wins(t: TestHarness) -> void:
	var s := Sim.new()
	for bay in [1, 0, 2]:
		_work(s, bay)
		_run(s, 1.0)
	t.eq(s.bays_standing(), 0, "the building did not come all the way down")
	t.eq(s.over, true, "the demolition never finished")
	t.eq(s.won, true, "bringing the whole building down was not a win")


func test_a_clean_drop_pays_the_bonus(t: TestHarness) -> void:
	var s := Sim.new()
	var floors := s.floors_total()
	for bay in [1, 0, 2]:
		_work(s, bay)
		_run(s, 1.0)
	t.lt(s.worst_lean, Tuning.LEAN_WARN, "the balanced order was not clean")
	t.gt(float(s.rubble),
		float(floors * Tuning.RUBBLE_PER_FLOOR + Tuning.CLEAN_DROP_BONUS) - 1.0,
		"a clean drop did not pay the bonus")


func test_running_out_of_swings_ends_the_demolition(t: TestHarness) -> void:
	var s := Sim.new()
	var guard := 0
	while not s.over and guard < 40:
		guard += 1
		var worked := false
		for bay in s.bays.size():
			if s.bays[bay].standing:
				_work(s, bay, 6.0)
				worked = true
				break
		if not worked:
			break
	t.eq(s.over, true, "the demolition never ended one way or the other")


func test_advancing_a_finished_demolition_changes_nothing(t: TestHarness) -> void:
	var s := Sim.new()
	for bay in [1, 0, 2]:
		_work(s, bay)
		_run(s, 1.0)
	var before := s.state()
	_run(s, 5.0)
	t.dict_eq(s.state(), before, "a demolition that is over kept simulating")


func test_the_next_site_is_a_fresh_building(t: TestHarness) -> void:
	# The bug this pins, in its new clothes: the first street build set `over`
	# at the end and had nothing to clear it, so the game froze with a live HUD.
	# Every test in that suite read the state at the end of a level, which is
	# the exact instant the freeze began.
	var s := Sim.new()
	for bay in [1, 0, 2]:
		_work(s, bay)
		_run(s, 1.0)
	t.eq(s.over, true, "the first site never finished")
	var banked := s.rubble

	s.next_site()
	t.eq(s.over, false, "the demolition is still over after moving to the next site")
	t.eq(s.level, 2, "the site number did not advance")
	t.eq(s.rubble, banked, "the haul was lost between sites")
	t.eq(s.bays_standing(), Tuning.bays_for(2), "the next site did not arrive standing up")
	t.eq(s.swings_left, Tuning.swings_for(2), "the next site did not get a fresh swing budget")
	t.approx(s.bearing, 0.0, 0.0001, "the ball carried its swing into the next site")
	t.approx(s.worst_lean, 0.0, 0.0001, "the next site inherited the last one's lean")

	# And it must actually play.
	_work(s, 1)
	t.gt(float(s.floors_down), 0.0, "the next site cannot be worked")


func test_a_fresh_run_starts_from_the_first_site(t: TestHarness) -> void:
	var s := Sim.new(4)
	_work(s, 0)
	s.restart(1)
	t.eq(s.level, 1, "a fresh run did not go back to the first site")
	t.eq(s.rubble, 0, "a fresh run kept the last run's haul")
	t.eq(s.over, false, "restarting left the demolition over")
	t.eq(s.bays_standing(), Tuning.bays_for(1), "a fresh run did not get a whole building")
