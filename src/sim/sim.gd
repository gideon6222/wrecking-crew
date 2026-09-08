class_name Sim
extends RefCounted

## The whole game, with no renderer in it.
##
## This is the shape that everything else in the repo depends on. `Sim` owns
## every number that decides what happens; the scene in `src/game/` reads those
## numbers and draws them, and never the other way round. Two things fall out
## of that, and both are worth more than they cost:
##
## 1. `test/` can play a whole street in milliseconds with no window, no GPU
##    and no scene tree - so a golden test over an entire run is possible,
##    which is a far stronger safety net than testing any single function.
## 2. Rendering can be rewritten, or replaced entirely, without touching a line
##    of game logic.
##
## The rule that keeps it true: **nothing in this file may reference a Node, a
## Viewport, an input event or a delta that came from a real frame.** If it
## needs to know something about the world, it takes it as an argument.
##
## That rule is doing more work here than it did in the template, because the
## obvious way to build a swinging ball in Godot is a PhysicsBody on a joint -
## which would put the outcome of every run inside the physics server, at the
## mercy of its tick rate, and end any possibility of a whole-run golden. The
## pendulum below is thirty lines of arithmetic instead. Physics may be used
## for DEBRIS, which decides nothing; it may never decide anything.

signal floors_down(x: float, z: float, floors: int, flattened: bool)
signal barricade_smashed(x: float, z: float)
signal rig_hit(x: float, z: float)
signal power_up(power: int)
signal level_finished(won: bool)

var level: int = 1
var lives: int = Tuning.START_LIVES
var rubble: int = 0              ## the score, and what fills the meter
var power: int = Tuning.POWER_START
var meter: int = 0               ## rubble banked toward the next power up
var distance: float = 0.0        ## metres travelled down this street
var over: bool = false
var won: bool = false
var time: float = 0.0
var hit_timer: float = 0.0

## Counters the golden reads. `flattened` in particular is the one number that
## says whether the player is finishing buildings or only clipping them, which
## is the difference between playing this game and driving down it.
var floors_felled: int = 0
var flattened: int = 0

# --- the rig --------------------------------------------------------------

var x: float = 0.0               ## lateral position of the cab
var vx: float = 0.0              ## lateral velocity
var ax: float = 0.0              ## lateral acceleration, this step
var target_x: float = 0.0        ## the lane the rig is heading for
var lane: int = Tuning.START_LANE

# --- the ball -------------------------------------------------------------

## The crane. `yaw` is where the boom points, `bearing` is where the BALL
## actually is, and the gap between them is the game.
##
## The player drags to set `yaw_target`; the turret slews toward it at a
## bounded rate; the ball trails the boom as an underdamped spring, so it
## arrives about a quarter period late and swings past. `radius` grows with how
## fast the ball is travelling round, which is why a hard slew reaches a kerb
## and a gentle one does not.
##
## Zero is straight down the street; positive is to the player's right.
var yaw: float = 0.0
var yaw_target: float = 0.0
var yaw_vel: float = 0.0
var bearing: float = 0.0
var bearing_vel: float = 0.0
var radius: float = Tuning.BOOM

## Live entities. Plain dictionaries rather than nodes, because a node here
## would drag the scene tree into the test runner.
var buildings: Array[Dictionary] = []
var barricades: Array[Dictionary] = []

## Spawning is keyed on (chunk, level) through the hash, so street 3 is the
## same street 3 every time it is played, on any device. There is no rng
## stream in the simulation at all - `SimRng` exists for the renderer's debris,
## which must be reproducible for the smoke test but decides nothing.
var _chunk_spawned: int = -1


func _init(start_level: int = 1) -> void:
	restart(start_level)


## Full reset. Called at boot and between streets; the test harness calls it to
## get a clean, identical starting state on any machine.
func restart(start_level: int = 1) -> void:
	level = start_level
	lives = Tuning.START_LIVES
	rubble = 0
	power = Tuning.POWER_START
	meter = 0
	distance = 0.0
	over = false
	won = false
	time = 0.0
	hit_timer = 0.0
	floors_felled = 0
	flattened = 0
	x = 0.0
	vx = 0.0
	ax = 0.0
	lane = Tuning.START_LANE
	target_x = Tuning.LANES[lane]
	x = target_x
	yaw = 0.0
	yaw_target = 0.0
	yaw_vel = 0.0
	bearing = 0.0
	bearing_vel = 0.0
	radius = Tuning.BOOM
	buildings.clear()
	barricades.clear()
	_chunk_spawned = -1


## The next street, keeping everything the RUN owns.
##
## A run spans streets; a street is one stretch of road inside it. Lives,
## rubble and the power ladder carry over, which is what makes the ladder worth
## climbing - dying is what ends a run and sends you back to street one.
##
## This exists because the first build shipped without it. `over` went true at
## the end of street one, `advance()` returned early from then on, and the game
## stopped dead with the HUD still showing - which is indistinguishable from a
## crash to the person holding the phone. A known gap in NOTES.md is still a
## blocker if the thing it is missing is the only way out of the screen.
func next_street() -> void:
	level += 1
	distance = 0.0
	hit_timer = 0.0
	over = false
	won = false
	lane = Tuning.START_LANE
	x = Tuning.LANES[lane]
	target_x = x
	vx = 0.0
	ax = 0.0
	yaw = 0.0
	yaw_target = 0.0
	yaw_vel = 0.0
	bearing = 0.0
	bearing_vel = 0.0
	radius = Tuning.BOOM
	buildings.clear()
	barricades.clear()
	_chunk_spawned = -1


## One step. `dt` is seconds; the caller decides whether that came from a real
## frame or from a test stepping at a fixed rate, and the result is identical
## either way.
func advance(dt: float) -> void:
	if over:
		return

	time += dt
	if hit_timer > 0.0:
		hit_timer -= dt

	distance += Tuning.speed_for(level) * dt

	_drive(dt)
	_slew(dt)

	_spawn_ahead()
	_hit_buildings(dt)
	_hit_barricades()
	_retire_passed()

	if distance >= Tuning.CHUNK * Tuning.CHUNKS_PER_LEVEL:
		over = true
		won = true
		level_finished.emit(true)


## Point the boom. The MAIN input, and the one the game is about.
func aim_to(new_yaw: float) -> void:
	yaw_target = clampf(new_yaw, -Tuning.YAW_MAX, Tuning.YAW_MAX)


## Nudge the rig one lane. The secondary input: a discrete press, because the
## drag is spent on the crane and obstacles are now occasional rather than the
## thing the run is about.
func nudge(dir: int) -> void:
	lane = clampi(lane + signi(dir), 0, Tuning.LANES.size() - 1)
	target_x = Tuning.LANES[lane]


## Kept so a test or a policy can place the rig directly without pretending to
## press a button. Snaps to the nearest lane, so there is no way to end up
## between two of them and quietly invalidate every lane assertion.
func steer_to(new_target_x: float) -> void:
	var best := 0
	for i in Tuning.LANES.size():
		if absf(Tuning.LANES[i] - new_target_x) < absf(Tuning.LANES[best] - new_target_x):
			best = i
	lane = best
	target_x = Tuning.LANES[lane]


# --- derived, and derived is the only way these are ever obtained ----------

## Where the ball is. Never stored: the ball's position is a FUNCTION of the
## rig and the swing angle, so the thing the collision tests and the thing the
## renderer draws cannot drift apart. On a sibling game, a score that
## disagreed with the picture was the one bug that could not be forgiven, and
## the only fix that makes it impossible is having one source.
func ball_x() -> float:
	return x + radius * sin(bearing)


func ball_y() -> float:
	return Tuning.ball_height(bearing)


func ball_z() -> float:
	return distance + radius * cos(bearing)


## Where the boom tip is - the chain hangs from here, and it is not where the
## ball is. The gap between the two IS the lag, drawn.
func boom_tip_x() -> float:
	return x + Tuning.BOOM * sin(yaw)


func boom_tip_z() -> float:
	return distance + Tuning.BOOM * cos(yaw)


## Rubble still needed for the next power up, and 0 once the ladder is topped
## out. The HUD draws this; the tests assert against it.
func meter_target() -> int:
	if power >= Tuning.POWER_MAX:
		return 0
	return Tuning.meter_for(power)


## Everything a harness or a HUD needs, in one dictionary.
##
## Deliberately flat and all-scalar: a golden test asserts this whole thing at
## once, and a nested structure would make a one-field change unreadable in the
## diff.
func state() -> Dictionary:
	return {
		"level": level,
		"lives": lives,
		"rubble": rubble,
		"power": power,
		"floors_felled": floors_felled,
		"flattened": flattened,
		"distance": snappedf(distance, 0.001),
		"x": snappedf(x, 0.001),
		"lane": lane,
		"yaw": snappedf(yaw, 0.001),
		"bearing": snappedf(bearing, 0.001),
		"radius": snappedf(radius, 0.001),
		"ball_x": snappedf(ball_x(), 0.001),
		"ball_z_ahead": snappedf(ball_z() - distance, 0.001),
		"buildings": buildings.size(),
		"barricades": barricades.size(),
		"over": over,
		"won": won,
	}


# --- the rig --------------------------------------------------------------

## Lateral motion as a velocity with a bounded acceleration, rather than an
## exponential lerp on position.
##
## The lerp is what the template used and it is right when nothing reads the
## derivative. Here the pendulum does: a position lerp's acceleration is a
## spike on the frame the target changes and zero afterwards, so the ball gets
## kicked once and then hangs. Approaching a target VELOCITY exponentially
## gives a smooth, bounded acceleration that lasts as long as the player holds
## the drag, which is what makes a swing build.
##
## The approach is assigned, never added. Adding a correction onto a velocity
## that is already carrying the object toward the target is a spring with no
## damping term, and it rings - which reads to a player as "bouncy".
func _drive(dt: float) -> void:
	var want := clampf((target_x - x) * Tuning.STEER_GAIN,
		-Tuning.MAX_STEER_SPEED, Tuning.MAX_STEER_SPEED)
	var new_vx := lerpf(vx, want, SimUtil.smooth(Tuning.STEER_RATE, dt))
	ax = (new_vx - vx) / dt
	vx = new_vx
	x += vx * dt

	# Hitting a rail stops the drive dead, and that jolt is felt by the ball -
	# which is correct, and is also a small piece of skill: a player who pins
	# the rig against the kerb gets a sharper kick than one who eases into it.
	if x > Tuning.LANE_HALF_WIDTH:
		x = Tuning.LANE_HALF_WIDTH
		vx = 0.0
	elif x < -Tuning.LANE_HALF_WIDTH:
		x = -Tuning.LANE_HALF_WIDTH
		vx = 0.0


# --- the ball -------------------------------------------------------------

func _slew(dt: float) -> void:
	# The turret. Same shape as the rig's drive - a target velocity approached
	# exponentially, assigned and never added, so it cannot overshoot and ring.
	var want := clampf((yaw_target - yaw) * Tuning.YAW_GAIN,
		-Tuning.MAX_SLEW, Tuning.MAX_SLEW)
	yaw_vel = lerpf(yaw_vel, want, SimUtil.smooth(Tuning.YAW_RATE, dt))
	yaw += yaw_vel * dt
	if yaw > Tuning.YAW_MAX:
		yaw = Tuning.YAW_MAX
		yaw_vel = minf(yaw_vel, 0.0)
	elif yaw < -Tuning.YAW_MAX:
		yaw = -Tuning.YAW_MAX
		yaw_vel = maxf(yaw_vel, 0.0)

	# The ball, as an underdamped spring toward where the boom is pointing.
	# Underdamped is the whole point: it arrives late and swings PAST, so the
	# player leads a target instead of pointing at it.
	var alpha := (yaw - bearing) * Tuning.BALL_PULL - Tuning.BALL_DAMP * bearing_vel
	bearing_vel += alpha * dt
	bearing += bearing_vel * dt

	# Centrifugal reach. A ball swung hard flies outward, so how far the crane
	# can hit is a consequence of how hard it was slewed rather than a
	# constant - which is what stops "point at it" being the whole game.
	var want_r := minf(Tuning.BOOM + Tuning.RADIUS_GAIN * absf(bearing_vel),
		Tuning.RADIUS_MAX)
	radius = lerpf(radius, want_r, SimUtil.smooth(Tuning.RADIUS_RATE, dt))


## An impact throws the ball back the other way and hands some of the speed
## back.
##
## This is the piece of the first build that was working and is kept exactly.
## Hitting a building on the left kicks the ball toward the right, so a street
## reads as a rhythm the player can chain - and a miss costs twice, because the
## damping has bled the swing away and the next kerb is now short of reach.
func _impact() -> void:
	var speed := maxf(absf(bearing_vel) * Tuning.REBOUND, Tuning.REBOUND_MIN)
	var away := -signf(bearing) if not is_zero_approx(bearing) else -signf(bearing_vel)
	if is_zero_approx(away):
		away = -1.0
	bearing_vel = away * speed


# --- what is on the street ------------------------------------------------

## Spawn decisions are keyed on (chunk, level) through the hash, never on a
## stream, so they do not shift when something unrelated draws a value.
func _spawn_ahead() -> void:
	var horizon := distance + 90.0
	var last_chunk := int(horizon / Tuning.CHUNK)
	while _chunk_spawned < last_chunk:
		_chunk_spawned += 1
		_spawn_chunk(_chunk_spawned)


func _spawn_chunk(c: int) -> void:
	# Two empty chunks, so the ball is hanging still and the street is legible
	# before anything is asked of the player.
	if c < 2:
		return
	var z := float(c) * Tuning.CHUNK

	# Each side rolls on its own seed offset, so a street can have buildings
	# facing each other, one side only, or a gap - and adding or removing one
	# side later does not reshuffle the other.
	for side in [-1, 1]:
		var roll := SimUtil.hash2(c, (91 if side < 0 else 191) + level)
		if roll >= Tuning.BUILDING_CHANCE:
			continue
		var tall := SimUtil.hash2(c, (301 if side < 0 else 401) + level)
		var floors := Tuning.MIN_FLOORS + int(floor(tall * Tuning.height_for(level)))
		buildings.append({
			"side": side,
			"z": z,
			"floors": mini(floors, Tuning.MAX_FLOORS),
			"left": mini(floors, Tuning.MAX_FLOORS),
			"cool": 0.0,
			"taken": false,
		})

	# A separate seed offset again. Sharing one is the classic way a small
	# content change turns into a total reshuffle of the world.
	if SimUtil.hash2(c, 555 + level) < Tuning.BARRICADE_CHANCE:
		var side_roll := SimUtil.hash2(c, 655 + level)
		barricades.append({
			"side": 1 if side_roll > 0.5 else -1,
			"z": z + Tuning.CHUNK * 0.5,
			"taken": false,
		})


## The ball against the kerbs. Two conditions: the ball has swung far enough
## out to be over the pavement, and it is level with the building in z.
##
## There was a third for two measured builds - the ball had to be below what
## was left standing, since a pendulum rises as it swings out - and it is worth
## saying why it is gone, because it sounded like the best idea in the design.
##
## It has no middle setting. With buildings two floors and up it never once
## fired: a hidden condition that is always true, which is strictly worse than
## no condition at all. With one-floor shopfronts in the mix it fired on nearly
## all of them, because a full swing arrives three and a half metres up - so
## the whole of street one, which is where Gideon actually plays, became immune
## to the only tool in the game. Measured: the aiming bot felled two floors in
## thirty seconds.
##
## The choice it was meant to create - how hard to swing, not just when - is
## worth having, but it needs to be a cost rather than a wall, and it needs to
## be on the HUD. Left for the yard, in NOTES.md.
func _hit_buildings(dt: float) -> void:
	var bz := ball_z()
	var bx := ball_x()
	for b in buildings:
		if b.left <= 0:
			continue
		if b.cool > 0.0:
			b.cool -= dt
			continue
		# Two dimensions now, not one. The ball sweeps an ARC through the
		# street ahead rather than sliding along a fixed line in front of the
		# cab, so where it is along the road is as much a decision as how far
		# out it has swung.
		if absf(b.z - bz) > Tuning.BUILDING_HALF_DEPTH + Tuning.BALL_RADIUS:
			continue
		if float(b.side) * bx < Tuning.KERB_X - Tuning.BALL_RADIUS:
			continue

		var felled: int = mini(power, b.left)
		b.left -= felled
		b.cool = 0.25
		floors_felled += felled
		var down: bool = b.left <= 0
		if down:
			flattened += 1
			b.taken = true
		_earn(Tuning.RUBBLE_PER_FLOOR * felled + (Tuning.FLATTEN_BONUS if down else 0))
		_impact()
		floors_down.emit(float(b.side) * Tuning.KERB_X, b.z, felled, down)
		return  # one kerb per step; two at once is the ball being in two places


## The ball, then the rig, against a barricade.
##
## The ball is out ahead of the cab whenever the boom is anywhere near
## straight, so it meets a barricade before the rig does - long enough to watch
## the swing arrive and see whether it was enough. Swung fully to the side the
## ball is barely ahead at all, which is the honest cost of aiming at a kerb
## while something is coming down the road.
func _hit_barricades() -> void:
	var bz := ball_z()
	var bx := ball_x()
	for w in barricades:
		if w.taken:
			continue
		var lo: float = -Tuning.LANE_HALF_WIDTH if w.side < 0 else Tuning.BARRICADE_INNER_X
		var hi: float = -Tuning.BARRICADE_INNER_X if w.side < 0 else Tuning.LANE_HALF_WIDTH

		if absf(w.z - bz) < Tuning.BARRICADE_HALF_DEPTH + Tuning.BALL_RADIUS:
			var overlaps := bx + Tuning.BALL_RADIUS > lo and bx - Tuning.BALL_RADIUS < hi
			if overlaps and absf(bearing_vel) >= Tuning.BARRICADE_MIN_SWING:
				w.taken = true
				_earn(Tuning.BARRICADE_RUBBLE)
				_impact()
				barricade_smashed.emit(bx, w.z)
				continue

		if hit_timer > 0.0:
			continue
		if absf(w.z - distance) > Tuning.BARRICADE_HALF_DEPTH + Tuning.RIG_HALF_WIDTH:
			continue
		if x + Tuning.RIG_HALF_WIDTH > lo and x - Tuning.RIG_HALF_WIDTH < hi:
			w.taken = true
			lives -= 1
			hit_timer = Tuning.HIT_COOLDOWN
			# The cab clipping a barricade shakes the boom. Deterministic, and
			# it means a mistake is felt in the tool as well as on the counter.
			bearing_vel += 1.6 * signf(-x if not is_zero_approx(x) else 1.0)
			rig_hit.emit(x, w.z)
			if lives <= 0:
				over = true
				won = false
				level_finished.emit(false)
			return


## Rubble is the score AND the meter. One resource with two jobs is a
## deliberate choice for this first street: a second currency with no shop to
## spend it in would be a row on the HUD that never does anything, and a
## station the player can pass through and get nothing from teaches them to
## stop reading the signs. The persistent currency arrives with the yard.
func _earn(amount: int) -> void:
	rubble += amount
	if power >= Tuning.POWER_MAX:
		return
	meter += amount
	while power < Tuning.POWER_MAX and meter >= Tuning.meter_for(power):
		meter -= Tuning.meter_for(power)
		power += 1
		power_up.emit(power)


## Entities behind the player are dropped. Without this the arrays grow for the
## whole street and every collision check gets slower as the run goes on -
## which reads as "the game slows down near the end" and gets blamed on
## rendering.
func _retire_passed() -> void:
	var cutoff := distance - 20.0
	buildings = buildings.filter(func(b): return b.z > cutoff)
	barricades = barricades.filter(func(w): return w.z > cutoff)
