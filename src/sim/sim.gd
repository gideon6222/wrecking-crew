class_name Sim
extends RefCounted

## The whole game, with no renderer in it.
##
## `Sim` owns every number that decides what happens; the scene in `src/game/`
## reads those numbers and draws them, and never the other way round. Two
## things fall out of that, and both are worth more than they cost:
##
## 1. `test/` can play a whole demolition in milliseconds with no window, no
##    GPU and no scene tree - so a golden over an entire run is possible, which
##    is a far stronger safety net than testing any single function.
## 2. Rendering can be rewritten, or replaced entirely, without touching a line
##    of game logic. That has now happened twice: a lane runner became a
##    crane-aiming runner became this, and the tests came across each time.
##
## The rule that keeps it true: **nothing in this file may reference a Node, a
## Viewport, an input event or a delta that came from a real frame.**
##
## It is doing more work here than usual, because the obvious way to build a
## collapsing building in Godot is a pile of RigidBody3Ds. That would put the
## outcome of every demolition inside the physics server, at the mercy of its
## tick rate and its solver, and end any possibility of a golden. The structure
## below is arithmetic. **Physics is for debris, which decides nothing.**

signal column_struck(bay: int, hp_left: int)
signal bay_fell(bay: int, floors: int)
signal building_down(clean: bool)
signal toppled(direction: float)
signal out_of_swings()
signal level_finished(won: bool)

var level: int = 1
var swings_left: int = 0
var rubble: int = 0
var over: bool = false
var won: bool = false
var time: float = 0.0

## The structure. One entry per bay, left to right.
##
## `hp` is the column at the base of that bay; `standing` is whether its stack
## of floors is still up. A bay whose column reaches zero drops, and the floors
## it drops are what pays.
var bays: Array[Dictionary] = []
var floors_down: int = 0

## Which way the remainder is leaning, normalised so 1.0 is the point of no
## return. Positive is toward the player's right.
##
## Two numbers rather than one: `lean_target` is where the imbalance says it
## should be right now, and `lean` follows it. A building does not snap to a
## new attitude the instant a bay lands, and more importantly the player needs
## the moment in between - it is the whole difference between a gauge you can
## steer back from and a delayed death sentence.
var lean: float = 0.0
var lean_target: float = 0.0

## The worst it ever got, which is what the clean-drop bonus is judged on.
##
## Not the lean at the end: when the last bay lands there is nothing left to
## be off-centre, so the final reading is always zero and a bonus keyed on it
## would pay out for every demolition including the reckless ones. What is
## being rewarded is never having come close, and that is a maximum over the
## whole job.
var worst_lean: float = 0.0

# --- the crane ------------------------------------------------------------

var x: float = 0.0               ## where the crane is parked
var vx: float = 0.0
var target_x: float = 0.0
var lane: int = Tuning.START_LANE

## `yaw` is where the boom points, `bearing` is where the BALL actually is, and
## the gap between them is the game. The player drags to set `yaw_target`; the
## turret slews toward it at a bounded rate; the ball trails as an underdamped
## spring, arriving about a quarter period late and swinging past. `radius`
## grows with how fast the ball is travelling, which is why a hard slew reaches
## into the building and a gentle one waves at it.
var yaw: float = 0.0
var yaw_target: float = 0.0
var yaw_vel: float = 0.0
var bearing: float = 0.0
var bearing_vel: float = 0.0
var radius: float = Tuning.BOOM


func _init(start_level: int = 1) -> void:
	restart(start_level)


## Full reset, to the first site of a fresh run.
func restart(start_level: int = 1) -> void:
	level = start_level
	rubble = 0
	_build_site()


## The next building, keeping what the RUN owns - which is the score and
## nothing else. Every demolition starts with a full swing budget and an
## upright structure, because a site you arrive at half-wrecked is not a site.
func next_site() -> void:
	level += 1
	_build_site()


func _build_site() -> void:
	swings_left = Tuning.swings_for(level)
	over = false
	won = false
	time = 0.0
	floors_down = 0
	lean = 0.0
	lean_target = 0.0
	worst_lean = 0.0

	bays.clear()
	var n := Tuning.bays_for(level)
	var floors := Tuning.floors_for(level)
	for b in n:
		bays.append({
			"hp": Tuning.column_hp_at(level, b),
			"floors": floors,
			"standing": true,
			"cool": 0.0,
		})

	lane = Tuning.START_LANE
	x = Tuning.LANES[lane]
	target_x = x
	vx = 0.0
	yaw = 0.0
	yaw_target = 0.0
	yaw_vel = 0.0
	bearing = 0.0
	bearing_vel = 0.0
	radius = Tuning.BOOM


## One step. `dt` is seconds; the caller decides whether that came from a real
## frame or from a test stepping at a fixed rate, and the result is identical
## either way.
func advance(dt: float) -> void:
	if over:
		return
	time += dt
	_drive(dt)
	_slew(dt)
	_strike(dt)
	_settle(dt)


## Point the boom. The main input, and the one the game is about.
func aim_to(new_yaw: float) -> void:
	yaw_target = clampf(new_yaw, -Tuning.YAW_MAX, Tuning.YAW_MAX)


## Move the crane one parking spot along the site. The secondary input.
func nudge(dir: int) -> void:
	lane = clampi(lane + signi(dir), 0, Tuning.LANES.size() - 1)
	target_x = Tuning.LANES[lane]


## Kept so a test or a policy can park the crane directly. Snaps to a real
## spot, so there is no way to sit between two and quietly invalidate every
## assertion about them.
func steer_to(new_target_x: float) -> void:
	var best := 0
	for i in Tuning.LANES.size():
		if absf(Tuning.LANES[i] - new_target_x) < absf(Tuning.LANES[best] - new_target_x):
			best = i
	lane = best
	target_x = Tuning.LANES[lane]


# --- derived, and derived is the only way these are obtained --------------

## Where the ball is. Never stored: it is a FUNCTION of the crane, the bearing
## and the radius, so the thing the collision tests and the thing the renderer
## draws cannot drift apart. On a sibling game a score that disagreed with the
## drawn object was the one bug that could not be forgiven.
func ball_x() -> float:
	return x + radius * sin(bearing)


func ball_z() -> float:
	return radius * cos(bearing)


func ball_y() -> float:
	return Tuning.ball_height(bearing)


func boom_tip_x() -> float:
	return x + Tuning.BOOM * sin(yaw)


func boom_tip_z() -> float:
	return Tuning.BOOM * cos(yaw)


func bays_standing() -> int:
	var n := 0
	for b in bays:
		if b.standing:
			n += 1
	return n


func floors_total() -> int:
	return Tuning.bays_for(level) * Tuning.floors_for(level)


## Everything a harness or a HUD needs, in one flat dictionary. A golden test
## asserts the whole thing at once, and a nested structure would make a
## one-field change unreadable in the diff.
func state() -> Dictionary:
	return {
		"level": level,
		"swings_left": swings_left,
		"rubble": rubble,
		"floors_down": floors_down,
		"bays_standing": bays_standing(),
		"lean": snappedf(lean, 0.001),
		"worst_lean": snappedf(worst_lean, 0.001),
		"x": snappedf(x, 0.001),
		"lane": lane,
		"yaw": snappedf(yaw, 0.001),
		"bearing": snappedf(bearing, 0.001),
		"radius": snappedf(radius, 0.001),
		"ball_x": snappedf(ball_x(), 0.001),
		"ball_z": snappedf(ball_z(), 0.001),
		"over": over,
		"won": won,
	}


# --- the crane ------------------------------------------------------------

func _drive(dt: float) -> void:
	var want := clampf((target_x - x) * Tuning.STEER_GAIN,
		-Tuning.MAX_STEER_SPEED, Tuning.MAX_STEER_SPEED)
	vx = lerpf(vx, want, SimUtil.smooth(Tuning.STEER_RATE, dt))
	x += vx * dt


func _slew(dt: float) -> void:
	# The turret: a target velocity approached exponentially, assigned and
	# never added, so it cannot overshoot and ring.
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

	# The ball, as an underdamped spring toward where the boom points.
	# Underdamped is the point: it arrives late and swings PAST, so the player
	# leads a target instead of pointing at one.
	var alpha := (yaw - bearing) * Tuning.BALL_PULL - Tuning.BALL_DAMP * bearing_vel
	bearing_vel += alpha * dt
	bearing += bearing_vel * dt

	# Centrifugal reach. A ball swung hard flies outward, so how deep the crane
	# can reach is a consequence of how hard it was slewed rather than a
	# constant - which is what stops "point at it" being the whole game.
	var want_r := minf(Tuning.BOOM + Tuning.RADIUS_GAIN * absf(bearing_vel),
		Tuning.RADIUS_MAX)
	radius = lerpf(radius, want_r, SimUtil.smooth(Tuning.RADIUS_RATE, dt))


## An impact throws the ball back the other way and hands some of the speed
## back, so a demolition can be worked as a rhythm rather than as a series of
## separate setups.
func _impact() -> void:
	var speed := maxf(absf(bearing_vel) * Tuning.REBOUND, Tuning.REBOUND_MIN)
	var away := -signf(bearing) if not is_zero_approx(bearing) else -signf(bearing_vel)
	if is_zero_approx(away):
		away = -1.0
	bearing_vel = away * speed


# --- the building ---------------------------------------------------------

## The ball against the columns.
##
## Three conditions, and each is a decision the player is making:
##   across  - the ball is level with this bay
##   deep    - it has got past the face of the building
##   moving  - it is actually swinging rather than drifting
##
## The middle one is what makes where the crane is parked matter. The ball's
## distance from the crane falls away as it swings round, so reaching ACROSS
## the front and reaching INTO the building trade against each other, and the
## outer bays of a wide building have to be parked in front of.
func _strike(dt: float) -> void:
	var bx := ball_x()
	var bz := ball_z()
	for i in bays.size():
		var b := bays[i]
		if b.cool > 0.0:
			b.cool -= dt
			continue
		if not b.standing or b.hp <= 0:
			continue
		if absf(bx - Tuning.bay_x(level, i)) > Tuning.COLUMN_HALF_WIDTH + Tuning.BALL_RADIUS:
			continue
		if bz < Tuning.FACE_Z - Tuning.BALL_RADIUS:
			continue
		if absf(bearing_vel) < Tuning.STRIKE_MIN_SWING:
			continue

		b.cool = Tuning.STRIKE_COOLDOWN
		b.hp -= 1
		swings_left -= 1
		_impact()
		column_struck.emit(i, b.hp)
		if b.hp <= 0:
			_drop_bay(i)
		_check_finished()
		return  # one column per step; two at once is the ball in two places


## A bay loses its column, so its stack comes down.
##
## The load it was carrying goes with it, and that is what moves the lean: a
## bay that falls on the left shifts the remainder left. Dropping the middle
## first costs almost nothing; working along one side is what tips it over.
func _drop_bay(i: int) -> void:
	var b := bays[i]
	b.standing = false
	var floors: int = b.floors
	floors_down += floors
	rubble += floors * Tuning.RUBBLE_PER_FLOOR
	bay_fell.emit(i, floors)
	_recompute_lean()


## Where the imbalance currently sits.
##
## Recomputed from the standing set rather than accumulated, so it is a
## property of the structure rather than a running total that can drift out of
## step with what is on screen. That matters: the gauge is the only thing
## telling the player how much trouble they are in, and one derived from the
## same thing being drawn cannot lie about it.
##
## Zero when what is left is symmetric about the middle, whatever is missing.
func _recompute_lean() -> void:
	var arm := Tuning.half_width(level)
	var moment := 0.0
	var mass := 0.0
	for i in bays.size():
		if not bays[i].standing:
			continue
		var w: float = float(bays[i].floors)
		moment += Tuning.bay_x(level, i) * w
		mass += w
	if mass <= 0.0:
		lean_target = 0.0
		return
	# The centre of what is still standing, as a fraction of the half width. A
	# remainder sitting entirely off to one side is a building on its way over;
	# one centred on the middle is stable however much has gone.
	lean_target = clampf((moment / mass) / arm, -2.0, 2.0)


func _settle(dt: float) -> void:
	lean = lerpf(lean, lean_target, SimUtil.smooth(Tuning.LEAN_SETTLE, dt))
	if over:
		return
	# `worst_lean` only counts while the structure could actually have gone
	# over. A lone bay reads as a maximum lean and cannot topple - see below -
	# so recording it would put every demolition, however carefully worked, at
	# 1.00 and make the clean-drop bonus unearnable by anybody. Measured: it
	# did exactly that, for all four policies, on every building.
	if bays_standing() >= 2:
		worst_lean = maxf(worst_lean, absf(lean))
	# A LONE bay cannot topple, and that clause is load bearing rather than a
	# nicety. The lean is the centroid of what is still standing, so the last
	# bay left is by definition sitting at its own offset and reads as a
	# maximum - without this, no building could ever be finished, whatever
	# order it was taken down in. A single bay is a column standing on its own
	# footing; it is not a slab with nothing under one end.
	if bays_standing() < 2:
		return
	if absf(lean) >= Tuning.TOPPLE_LIMIT:
		over = true
		won = false
		toppled.emit(signf(lean))
		level_finished.emit(false)


func _check_finished() -> void:
	if over:
		return
	if bays_standing() == 0:
		# Clean drop: everything down, and never leaning past the warning on
		# the way. The bonus is deliberately larger than the rubble a whole
		# building pays, because the game is not "knock it down" - anyone can
		# do that - it is "knock it down without putting it on the neighbours".
		var clean := worst_lean < Tuning.LEAN_WARN
		rubble += swings_left * Tuning.SWING_SAVED_BONUS
		if clean:
			rubble += Tuning.CLEAN_DROP_BONUS
		over = true
		won = true
		building_down.emit(clean)
		level_finished.emit(true)
		return
	if swings_left <= 0:
		over = true
		won = false
		out_of_swings.emit()
		level_finished.emit(false)
