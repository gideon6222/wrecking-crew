extends RefCounted

## Unit tests on the simulation.
##
## Weighted toward the things that actually go wrong. "The machine moves when
## you drive it" is not worth a test; frame-rate dependence, a constraint that
## injects energy, a spawn inside geometry, and a state the game cannot get out
## of are - and every one of those has happened here.

const STEP := 1.0 / 60.0


func _run(s: Sim, seconds: float, throttle := 0.0, steer := 0.0) -> void:
	for i in int(round(seconds / STEP)):
		s.drive(throttle, steer)
		s.advance(STEP)


# --- the machine ----------------------------------------------------------

func test_an_untouched_machine_stays_put(t: TestHarness) -> void:
	var s := Sim.new()
	var start := s.pos
	_run(s, 5.0)
	t.approx(s.pos.distance_to(start), 0.0, 0.001, "the machine wandered off on its own")
	t.approx(s.speed, 0.0, 0.001, "the machine is moving with no throttle")
	t.eq(s.columns_down, 0, "columns fell with nobody touching anything")


func test_the_spawn_is_clear_of_everything(t: TestHarness) -> void:
	# This one is not hypothetical. The spawn was on the centre line for one
	# build and half a bay across for the next, and BOTH put the ball inside a
	# column on frame one - the first because the grid was odd, the second
	# because the grid became even and the columns moved. The ball then sat in
	# permanent contact and logged five hundred hits in a run nobody played.
	for level in [1, 2, 3, 4, 5, 8]:
		var s := Sim.new(level)
		for c in s.columns:
			t.gt(s.pos.distance_to(c.at), Tuning.RIG_RADIUS + Tuning.COLUMN_RADIUS,
				"level %d spawns the machine inside a column" % level)
			t.gt(s.ball.distance_to(c.at), Tuning.BALL_RADIUS + Tuning.COLUMN_RADIUS,
				"level %d spawns the BALL inside a column" % level)
		for w in s.walls:
			t.gt(Sim._distance_to_segment(s.ball, w.a, w.b), Tuning.BALL_RADIUS + Tuning.WALL_THICK,
				"level %d spawns the ball inside a wall panel" % level)


func test_the_throttle_sets_a_speed_not_an_acceleration(t: TestHarness) -> void:
	# It accumulated acceleration for one build, so a fifth of throttle still
	# reached top speed - just later. A control that only changes how long
	# something takes is not a control the player can use, and the policy
	# written to prove that speed does the damage was not actually slow.
	# Measured as a PEAK over the run rather than at the end. Both machines
	# drive the length of the room and stop against the far wall, so reading
	# the final speed measures the wall rather than the throttle - which the
	# first version of this test did, and reported that full throttle could not
	# reach full speed.
	t.lt(_top_speed(0.25), _top_speed(1.0) * 0.45, "a quarter throttle reaches nearly full speed")
	t.approx(_top_speed(1.0), Tuning.DRIVE_MAX, 0.3, "full throttle does not reach full speed")


func _top_speed(throttle: float) -> float:
	var s := Sim.new()
	var peak := 0.0
	for i in int(round(6.0 / STEP)):
		s.drive(throttle, 0.0)
		s.advance(STEP)
		peak = maxf(peak, s.speed)
	return peak


func test_the_machine_coasts_to_a_stop(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 3.0, 1.0)
	t.gt(s.speed, 1.0, "the machine never got moving")
	_run(s, 4.0, 0.0)
	t.approx(s.speed, 0.0, 0.15, "the machine never coasts to a stop")


func test_turning_is_slower_at_speed(t: TestHarness) -> void:
	t.gt(Tuning.turn_rate_at(0.0), Tuning.turn_rate_at(Tuning.DRIVE_MAX),
		"the machine turns as sharply at full speed as it does standing still")


func test_the_machine_cannot_leave_the_room(t: TestHarness) -> void:
	# A machine that can drive off the edge is a machine that can be lost, and
	# the collapse then has nothing to catch it.
	for dir in [0.0, PI * 0.5, PI, -PI * 0.5]:
		var s := Sim.new()
		s.heading = dir
		_run(s, 14.0, 1.0)
		t.lt(absf(s.pos.x), Tuning.DECK_W * 0.5 + 0.01, "the machine left the room sideways")
		t.lt(s.pos.y, Tuning.DECK_D * 0.5 + 0.01, "the machine left the room forwards")
		t.gt(s.pos.y, -Tuning.DECK_D * 0.5 - Tuning.RAMP_DEPTH - 0.01,
			"the machine left the room through the back")


# --- the chain ------------------------------------------------------------

func test_the_ball_hangs_still_when_the_machine_does(t: TestHarness) -> void:
	var s := Sim.new()
	_run(s, 6.0)
	t.approx(s.ball_speed(), 0.0, 0.05, "the ball moves with the machine parked")
	t.approx(s.ball.distance_to(s.boom_tip()), 0.0, 0.05, "the ball is not hanging under the boom")


func test_the_chain_never_stretches(t: TestHarness) -> void:
	var s := Sim.new()
	for i in int(round(20.0 / STEP)):
		# Drive hard and turn hard, which is the worst case for the constraint.
		s.drive(1.0, sin(s.time * 1.7))
		s.aim_to(sin(s.time * 0.9) * Tuning.TURRET_MAX)
		s.advance(STEP)
		t.lt(s.ball.distance_to(s.boom_tip()), Tuning.CHAIN + 0.05,
			"the chain stretched past its length")


func test_the_chain_does_not_invent_energy(t: TestHarness) -> void:
	# THE test for this game's physics, and it exists because the constraint did
	# exactly that. Solving a distance constraint by moving the ball and leaving
	# its velocity alone injects energy on every taut frame and it compounds:
	# measured peak ball speed was 216 m/s on a machine that cannot exceed 9.5.
	# The symptom was not an error - it was a policy that crawled at a fifth
	# throttle outscoring one that drove flat out.
	#
	# What this asserts is SATURATION, not a ceiling. An earlier version of this
	# test computed a hand-derived bound from the machine's top speed and its
	# rotation rates, and failed - correctly, but for the wrong reason: driving
	# a pendulum near its own period PUMPS it, so the speed legitimately climbs
	# well past anything the machine can produce in one push. That is resonance,
	# not a bug, and the honest distinction is whether it converges.
	#
	# So: drive adversarially for a full minute and compare the worst of the
	# second half against the worst of the first. Real damping settles to a
	# steady state; an energy leak grows without bound.
	var s := Sim.new()
	var early := 0.0
	var late := 0.0
	var half := int(round(30.0 / STEP))
	for i in half * 2:
		s.drive(1.0, sin(s.time * 2.3))
		s.aim_to(sin(s.time * 1.1) * Tuning.TURRET_MAX)
		s.advance(STEP)
		if i < half:
			early = maxf(early, s.ball_speed())
		else:
			late = maxf(late, s.ball_speed())
		t.lt(s.ball_speed(), Tuning.BALL_MAX_SPEED - 0.001,
			"the emergency clamp is firing during ordinary driving, so it cannot signal a runaway")
	t.gt(early, 1.0, "the adversarial drive never got the ball moving at all")
	t.lt(late, early * 1.15,
		"the swing is still gaining energy after a minute - the constraint is leaking")


func test_driving_is_what_moves_the_ball(t: TestHarness) -> void:
	var parked := Sim.new()
	_run(parked, 4.0)
	var driven := Sim.new()
	var peak := 0.0
	for i in int(round(4.0 / STEP)):
		driven.drive(1.0, 0.6)
		driven.advance(STEP)
		peak = maxf(peak, driven.ball_speed())
	t.approx(parked.ball_speed(), 0.0, 0.05, "the parked machine's ball is moving")
	t.gt(peak, Tuning.HIT_MIN_SPEED,
		"driving and turning cannot get the ball above the speed that does damage")


func test_the_ball_rides_higher_the_further_it_swings(t: TestHarness) -> void:
	# The chain is a fixed length, so a ball out at full stretch has to be level
	# with the boom tip. One function, so the collision and the drawing agree.
	var s := Sim.new()
	var low := s.ball_y()
	for i in int(round(6.0 / STEP)):
		s.drive(1.0, 1.0)
		s.advance(STEP)
	t.gt(s.ball.distance_to(s.boom_tip()), 1.0, "the ball never swung out")
	t.gt(s.ball_y(), low, "the ball does not rise as it swings out")


func test_the_crane_is_frame_rate_independent(t: TestHarness) -> void:
	# Two 8ms steps must land where one 16ms step lands. `min(1, dt * rate)`
	# passes at 60fps and is a different spring at 120, which is what the phone
	# actually runs at.
	var a := Sim.new()
	var b := Sim.new()
	for i in 480:
		a.drive(1.0, 0.5)
		a.advance(1.0 / 120.0)
	for i in 240:
		b.drive(1.0, 0.5)
		b.advance(1.0 / 60.0)
	t.approx(a.pos.x, b.pos.x, 0.6, "the machine is somewhere else at 120fps")
	t.approx(a.pos.y, b.pos.y, 0.6, "the machine is somewhere else at 120fps")


# --- breaking things ------------------------------------------------------

func test_a_slow_ball_does_no_damage(t: TestHarness) -> void:
	# Otherwise nudging things over is as good as swinging at them, and the
	# whole reason the machine drives freely disappears.
	var s := Sim.new()
	var target: int = _nearest(s)
	var hp: float = s.columns[target].hp
	# Creep at the column and hold there.
	for i in int(round(30.0 / STEP)):
		var to_it: Vector2 = s.columns[target].at - s.pos
		var err := wrapf(atan2(to_it.x, to_it.y) - s.heading, -PI, PI)
		s.drive(0.12, clampf(err * 2.0, -1.0, 1.0))
		s.advance(STEP)
	t.eq(s.columns[target].standing, true, "a column fell to a machine creeping at it")
	t.approx(s.columns[target].hp, hp, 0.01, "a crawling ball took hit points off a column")


func test_the_gauge_only_falls_when_something_falls(t: TestHarness) -> void:
	var s := Sim.new()
	t.approx(s.integrity, 1.0, 0.001, "the deck does not start fully supported")
	var mem := {}
	var last := s.integrity
	for i in int(round(60.0 / STEP)):
		if s.over:
			break
		Policies.steer(Policies.WRECKER, s, mem)
		var before_down := s.columns_down + s.walls_down
		s.advance(STEP)
		if s.integrity < last:
			t.gt(float(s.columns_down + s.walls_down), float(before_down) - 0.5,
				"the gauge moved without anything coming down")
		last = s.integrity


func test_a_fallen_column_stays_fallen_and_stops_paying(t: TestHarness) -> void:
	var s := Sim.new()
	var mem := {}
	for i in int(round(60.0 / STEP)):
		if s.over or s.columns_down > 0:
			break
		Policies.steer(Policies.WRECKER, s, mem)
		s.advance(STEP)
	t.gt(float(s.columns_down), 0.0, "the aiming policy never brought a column down in a minute")
	var banked := s.rubble
	var down := 0
	for c in s.columns:
		if not c.standing:
			down += 1
			t.lt(c.hp, 0.01, "a column is down but still has hit points")
	t.eq(down, s.columns_down, "the count of fallen columns disagrees with the columns")
	t.gt(float(banked), 0.0, "bringing a column down paid nothing")


# --- coming down and getting out ------------------------------------------

func test_the_collapse_starts_when_the_support_goes(t: TestHarness) -> void:
	var s := Sim.new()
	t.eq(s.collapsing, false, "the deck starts already collapsing")
	# Knock the columns out directly rather than driving at them - this is a
	# test of the threshold, not of anybody's driving.
	for c in s.columns:
		if s.collapsing:
			break
		c.standing = false
		s.columns_down += 1
		s._recompute_integrity()
	t.eq(s.collapsing, true, "the deck never let go however many columns went")
	t.gt(s.escape_left, 0.0, "the collapse started with no time to get out")
	t.lt(s.integrity, Tuning.COLLAPSE_AT + 0.001, "the collapse started above its own threshold")


func test_reaching_the_ramp_wins_and_pays_for_the_time_left(t: TestHarness) -> void:
	var s := Sim.new()
	for c in s.columns:
		if s.collapsing:
			break
		c.standing = false
		s.columns_down += 1
		s._recompute_integrity()
	var banked := s.rubble
	var left := s.escape_left
	s.pos = Vector2(0.0, Tuning.ramp_z() - 1.0)
	s.advance(STEP)
	t.eq(s.over, true, "reaching the ramp did not end the demolition")
	t.eq(s.won, true, "reaching the ramp was not a win")
	t.gt(float(s.rubble), float(banked), "getting out early paid nothing")
	t.lt(s.rubble - banked, int(left * float(Tuning.ESCAPE_BONUS_PER_SECOND)) + 2,
		"the escape paid more than the time left is worth")


func test_running_out_of_time_is_a_loss(t: TestHarness) -> void:
	var s := Sim.new()
	for c in s.columns:
		if s.collapsing:
			break
		c.standing = false
		s.columns_down += 1
		s._recompute_integrity()
	# Park in the middle of the room and wait.
	s.pos = Vector2.ZERO
	_run(s, Tuning.escape_seconds_for(1) + 1.0)
	t.eq(s.over, true, "the collapse never finished")
	t.eq(s.won, false, "sitting under a collapsing slab was recorded as a win")


func test_the_ramp_only_counts_once_it_is_coming_down(t: TestHarness) -> void:
	# Otherwise the player can park in the exit and the level ends itself.
	var s := Sim.new()
	s.pos = Vector2(0.0, Tuning.ramp_z() - 1.0)
	_run(s, 3.0)
	t.eq(s.over, false, "parking in the exit ended the level before anything was broken")


func test_advancing_a_finished_run_changes_nothing(t: TestHarness) -> void:
	var s := Sim.new()
	for c in s.columns:
		if s.collapsing:
			break
		c.standing = false
		s.columns_down += 1
		s._recompute_integrity()
	s.pos = Vector2(0.0, Tuning.ramp_z() - 1.0)
	s.advance(STEP)
	var before := s.state()
	_run(s, 4.0, 1.0)
	t.dict_eq(s.state(), before, "a demolition that is over kept simulating")


func test_the_next_site_is_a_fresh_basement(t: TestHarness) -> void:
	# The bug this pins: an earlier build set `over` at the end of a level and
	# had nothing to clear it, so the game froze with a live HUD. Every test in
	# that suite read the state at the end of a level, which is the exact
	# instant the freeze began.
	var s := Sim.new()
	for c in s.columns:
		if s.collapsing:
			break
		c.standing = false
		s.columns_down += 1
		s._recompute_integrity()
	s.pos = Vector2(0.0, Tuning.ramp_z() - 1.0)
	s.advance(STEP)
	t.eq(s.over, true, "the first basement never finished")
	var banked := s.rubble

	s.next_site()
	t.eq(s.over, false, "still over after moving to the next basement")
	t.eq(s.level, 2, "the site number did not advance")
	t.eq(s.rubble, banked, "the haul was lost between sites")
	t.eq(s.collapsing, false, "the next basement arrived already collapsing")
	t.approx(s.integrity, 1.0, 0.001, "the next basement arrived already damaged")
	t.eq(s.columns_standing(), Tuning.GRID_X * Tuning.GRID_Z, "the next basement is missing columns")
	t.approx(s.ball_speed(), 0.0, 0.05, "the ball carried its swing into the next basement")


func test_a_fresh_run_starts_from_the_first_site(t: TestHarness) -> void:
	var s := Sim.new(5)
	s.rubble = 900
	s.restart(1)
	t.eq(s.level, 1, "a fresh run did not go back to the first basement")
	t.eq(s.rubble, 0, "a fresh run kept the last run's haul")
	t.eq(s.over, false, "restarting left the run over")


func test_the_same_basement_is_the_same_every_time(t: TestHarness) -> void:
	# Keyed on the place, never on a stream, so a given basement is the same on
	# any device and a golden over a whole demolition is possible at all.
	for level in [1, 3, 7]:
		var a := Sim.new(level)
		var b := Sim.new(level)
		t.eq(a.walls.size(), b.walls.size(), "level %d built a different number of panels" % level)
		for i in a.walls.size():
			t.approx(a.walls[i].at.x, b.walls[i].at.x, 0.0001, "level %d panel %d moved" % [level, i])


func test_no_panel_blocks_the_way_out(t: TestHarness) -> void:
	# A wall across the ramp mouth would make a level unfinishable in a way the
	# player could not see coming, which is the worst kind of unfair.
	for level in range(1, 20):
		var s := Sim.new(level)
		for w in s.walls:
			var blocks: bool = (Sim._distance_to_segment(Vector2(0.0, Tuning.ramp_z()), w.a, w.b)
				< Tuning.RAMP_W * 0.5)
			t.ok(not blocks, "level %d has a panel across the ramp mouth" % level)


func _nearest(s: Sim) -> int:
	var best := 0
	var best_d := INF
	for i in s.columns.size():
		var d: float = s.pos.distance_to(s.columns[i].at)
		if d < best_d:
			best_d = d
			best = i
	return best
