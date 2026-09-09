class_name Sim
extends RefCounted

## The whole game, with no renderer in it.
##
## `Sim` owns every number that decides what happens; the scene in `src/game/`
## reads those numbers and draws them, and never the other way round. Two
## things fall out of that, and both are worth more than they cost:
##
## 1. `test/` can play a whole demolition in milliseconds with no window, no
##    GPU and no scene tree - so a golden over an entire run is possible.
## 2. The renderer can be replaced without touching game logic. That has now
##    happened three times on this game, and the tests came across each time.
##
## The rule that keeps it true: **nothing in this file may reference a Node, a
## Viewport, an input event or a delta that came from a real frame.** `Vector2`
## is fine - it is arithmetic, not a scene object.
##
## It is doing more work here than usual, because the obvious way to build a
## wrecking ball and a collapsing basement in Godot is RigidBody3D and a
## PinJoint. That would put the outcome of every demolition inside the physics
## server, at the mercy of its tick rate and its solver, and end any
## possibility of a golden. The chain below is a distance constraint solved in
## nine lines. **Physics is for debris and for the slab coming down, neither of
## which decides anything.**

signal target_hit(kind: int, index: int, speed: float, at: Vector2)
signal target_broken(kind: int, index: int, at: Vector2)
signal collapse_started()
signal escaped(seconds_left: float)
signal crushed()
signal level_finished(won: bool)

enum { COLUMN, WALL }

var level: int = 1
var rubble: int = 0
var over: bool = false
var won: bool = false
var time: float = 0.0

## The structure. Columns hold the slab up; walls are worth score and almost no
## support, which the player learns from the gauge rather than from a tooltip.
var columns: Array[Dictionary] = []
var walls: Array[Dictionary] = []
var columns_down: int = 0
var walls_down: int = 0

## How much of the original support is left, 1.0 down to 0.0. Below
## `COLLAPSE_AT` the slab lets go and the clock starts.
var integrity: float = 1.0
var collapsing: bool = false
var escape_left: float = 0.0

# --- the machine ----------------------------------------------------------

var pos := Vector2.ZERO           ## on the deck, x across and y into the room
var vel := Vector2.ZERO
var heading: float = 0.0          ## radians, 0 is toward +z (into the room)
var speed: float = 0.0            ## signed, along the heading

## Input, as set by the shell each step. Held rather than passed so a policy
## and a thumb drive exactly the same seam.
var throttle: float = 0.0         ## -1 back, +1 forward
var steer: float = 0.0            ## -1 left, +1 right

## The crane. `turret` is the boom's angle relative to the MACHINE, so driving
## carries the whole assembly round with it.
var turret: float = 0.0
var turret_target: float = 0.0
var turret_vel: float = 0.0

## The ball is a free point mass on an inextensible chain. Nothing aims it.
var ball := Vector2.ZERO
var ball_vel := Vector2.ZERO
var _prev_tip := Vector2.ZERO


func _init(start_level: int = 1) -> void:
	restart(start_level)


func restart(start_level: int = 1) -> void:
	level = start_level
	rubble = 0
	_build_deck()


## The next basement, keeping what the RUN owns - the score, and nothing else.
func next_site() -> void:
	level += 1
	_build_deck()


func _build_deck() -> void:
	over = false
	won = false
	time = 0.0
	columns_down = 0
	walls_down = 0
	integrity = 1.0
	collapsing = false
	escape_left = 0.0

	columns.clear()
	walls.clear()
	var chp := Tuning.column_hp_for(level)
	var whp := Tuning.wall_hp_for(level)

	for row in Tuning.GRID_Z:
		for col in Tuning.GRID_X:
			columns.append({
				"at": Vector2(Tuning.column_x(col), Tuning.column_z(row)),
				"hp": chp,
				"max_hp": chp,
				"standing": true,
				"cool": 0.0,
			})

	# Infill walls, keyed on the place so a given basement is the same basement
	# every time it is played, on any device. They span between neighbouring
	# columns along the back and the sides - never across the ramp mouth, which
	# would let a wall block the only way out.
	for row in Tuning.GRID_Z:
		for col in Tuning.GRID_X - 1:
			if SimUtil.hash2(row * 31 + col, 411 + level) > 0.42:
				continue
			var a := Vector2(Tuning.column_x(col), Tuning.column_z(row))
			var b := Vector2(Tuning.column_x(col + 1), Tuning.column_z(row))
			if _blocks_ramp(a, b):
				continue
			walls.append({
				"a": a, "b": b, "at": (a + b) * 0.5,
				"hp": whp, "max_hp": whp, "standing": true, "cool": 0.0,
			})

	# At the ramp mouth, clear of the grid. It spawned six metres in for one
	# measured build, which put it ON TOP of a column with the ball already
	# touching another - so the ball was in permanent contact, took a bounce
	# every cooldown, and compounded until it was moving at twenty times the
	# machine's top speed. A policy that crawled then outscored one that drove
	# flat out, because the instability was doing all the damage.
	# Somewhere provably clear of every column, rather than a hand-picked
	# offset. It was on the centre line for one build and half a bay across for
	# the next, and BOTH put the ball inside a column on the first frame - the
	# first because the grid was odd and had a column at zero, the second
	# because the grid then became even and the columns moved to half-bay
	# offsets. A spawn tied to the grid's parity is a spawn that breaks every
	# time the grid changes; `test_sim.gd` asserts the clearance instead.
	pos = Vector2(_clear_spawn_x(), Tuning.ramp_z() + 2.2)
	vel = Vector2.ZERO
	heading = 0.0
	speed = 0.0
	throttle = 0.0
	steer = 0.0
	turret = 0.0
	turret_target = 0.0
	turret_vel = 0.0
	# The ball hangs straight down from the boom tip, which is where a chain
	# actually puts it, and means the horizontal distance starts at zero.
	_prev_tip = boom_tip()
	ball = _prev_tip
	ball_vel = Vector2.ZERO


## The widest gap along the front row, so the machine and its hanging ball both
## start clear of everything. Searched rather than chosen.
func _clear_spawn_x() -> float:
	var best := 0.0
	var best_gap := -INF
	var span := Tuning.DECK_W * 0.5 - Tuning.RIG_RADIUS
	var z := Tuning.ramp_z() + 2.2
	var x := -span
	while x <= span:
		# Both the machine AND the boom tip, because the ball starts hanging at
		# the tip four and a half metres ahead - and it was the BALL that ended
		# up inside something, not the machine. Walls count too: checking only
		# columns left level one spawning against an infill panel and logging
		# five hundred contacts in a run nobody played.
		var here := Vector2(x, z)
		var tip := here + Vector2(0.0, Tuning.BOOM_LEN)
		var gap := INF
		for c in columns:
			gap = minf(gap, here.distance_to(c.at) - Tuning.COLUMN_RADIUS - Tuning.RIG_RADIUS)
			gap = minf(gap, tip.distance_to(c.at) - Tuning.COLUMN_RADIUS - Tuning.BALL_RADIUS)
		for w in walls:
			gap = minf(gap, _distance_to_segment(here, w.a, w.b) - Tuning.WALL_THICK - Tuning.RIG_RADIUS)
			gap = minf(gap, _distance_to_segment(tip, w.a, w.b) - Tuning.WALL_THICK - Tuning.BALL_RADIUS)
		# Prefer a spot near the ramp so the player starts by the way out.
		var score: float = gap - absf(x) * 0.05
		if score > best_gap:
			best_gap = score
			best = x
		x += 0.5
	return best


## A wall across the ramp mouth would make the level unfinishable in a way the
## player could not see coming, which is the worst kind of unfair.
func _blocks_ramp(a: Vector2, b: Vector2) -> bool:
	var mid := (a + b) * 0.5
	return mid.y < Tuning.ramp_z() + Tuning.BAY * 0.6 and absf(mid.x) < Tuning.RAMP_W


# --- the step -------------------------------------------------------------

## `dt` is seconds; the caller decides whether that came from a real frame or
## from a test stepping at a fixed rate, and the result is identical either way.
func advance(dt: float) -> void:
	if over:
		return
	time += dt
	_drive(dt)
	_slew(dt)
	_swing(dt)
	_hit(dt)
	_settle(dt)


## Drive toward a direction in the WORLD, at a given power.
##
## This is the seam the thumb uses, and it replaced a throttle-and-steer pair
## for a reason Gideon found immediately: "the driving controls almost feel
## backward".
##
## They were, half the time. The camera holds a fixed orientation, so when the
## machine happened to be facing back toward it, pushing the stick forward drove
## the machine DOWN the screen and steering right turned it left on screen.
## Vehicle-relative controls under a fixed camera are tank controls, and tank
## controls are a thing players tolerate rather than enjoy.
##
## Push the stick where you want to go and the machine goes there. The heading
## is then something the machine works out, not something the player has to
## track - and because the direction is in world space, it means the same thing
## whichever way the machine is pointing.
func drive_dir(dir: Vector2, power: float) -> void:
	if dir.length() < 0.001 or power <= 0.0:
		drive(0.0, 0.0)
		return
	var want := atan2(dir.x, dir.y)
	var err := wrapf(want - heading, -PI, PI)

	# Counter-rotate at full lock until the nose is nearly on the bearing, then
	# ease so it settles instead of hunting.
	var turn := clampf(err / Tuning.TURN_SETTLE, -1.0, 1.0)

	# And NO throttle until the machine is pointing roughly where it is being
	# sent. This is the whole difference between a tracked machine and a car:
	# outside the cone the tracks counter-rotate and nothing else happens, so a
	# change of direction is a pivot rather than an arc.
	#
	# It had a floor of 45% here, so the machine drove through its own turns and
	# every correction came out as a long curve - which, under a camera that
	# holds still, reads as the machine sliding sideways.
	var align: float = 1.0 - clampf(absf(err) / Tuning.ALIGN_CONE, 0.0, 1.0)
	drive(power * align, turn)


## The low-level seam, still here because the tests and the collision model are
## written against it and because "how hard is it turning" is a real quantity.
func drive(new_throttle: float, new_steer: float) -> void:
	throttle = clampf(new_throttle, -1.0, 1.0)
	steer = clampf(new_steer, -1.0, 1.0)


func aim_to(new_turret: float) -> void:
	turret_target = clampf(new_turret, -Tuning.TURRET_MAX, Tuning.TURRET_MAX)


# --- derived, and derived is the only way these are obtained --------------

## The direction the machine points. 0 is +y in sim space, which the renderer
## maps to "into the room".
func forward() -> Vector2:
	return Vector2(sin(heading), cos(heading))


## Where the boom tip is. Never stored: it is a function of the machine and the
## turret, so the thing the chain hangs from and the thing the renderer draws
## cannot drift apart.
func boom_tip() -> Vector2:
	var a := heading + turret
	return pos + Vector2(sin(a), cos(a)) * Tuning.BOOM_LEN


func ball_speed() -> float:
	return ball_vel.length()


## How high the ball rides. Derived from the chain rather than stored: the
## chain is a fixed length, so the further the ball swings out horizontally the
## higher it must be, and at full stretch it is level with the boom tip. That
## is why a hard swing arrives high and a lazy one drags along the floor - and
## it is one function, so the collision and the drawing cannot disagree.
func ball_y() -> float:
	var out := ball.distance_to(boom_tip())
	var drop := sqrt(maxf(0.0, Tuning.CHAIN * Tuning.CHAIN - out * out))
	return maxf(Tuning.BALL_RADIUS, Tuning.BOOM_HEIGHT - drop)


func columns_standing() -> int:
	var n := 0
	for c in columns:
		if c.standing:
			n += 1
	return n


## Everything a harness or a HUD needs, in one flat dictionary. A golden test
## asserts the whole thing at once, and a nested structure would make a
## one-field change unreadable in the diff.
func state() -> Dictionary:
	return {
		"level": level,
		"rubble": rubble,
		"columns_down": columns_down,
		"walls_down": walls_down,
		"integrity": snappedf(integrity, 0.001),
		"collapsing": collapsing,
		"escape_left": snappedf(escape_left, 0.001),
		"x": snappedf(pos.x, 0.001),
		"z": snappedf(pos.y, 0.001),
		"heading": snappedf(heading, 0.001),
		"speed": snappedf(speed, 0.001),
		"turret": snappedf(turret, 0.001),
		"ball_x": snappedf(ball.x, 0.001),
		"ball_z": snappedf(ball.y, 0.001),
		"ball_speed": snappedf(ball_speed(), 0.001),
		"over": over,
		"won": won,
	}


# --- the machine ----------------------------------------------------------

func _drive(dt: float) -> void:
	# Dead zone. Without one a virtual stick reads every tremor of a thumb and
	# the machine wanders on its own, which reads as the controls being loose
	# rather than as the player being imprecise.
	var t := throttle if absf(throttle) > Tuning.STICK_DEADZONE else 0.0
	var s := steer if absf(steer) > Tuning.STICK_DEADZONE else 0.0

	# The throttle sets a TARGET SPEED, not an acceleration.
	#
	# It accumulated acceleration for one measured build, which meant a fifth
	# of throttle still reached top speed - just later. So the policy written to
	# prove that speed does the damage was not actually slow, and it outscored
	# the one driving flat out. A control that only changes how long something
	# takes is not a control the player can use.
	if t == 0.0:
		# Coast. Exponential rather than a subtraction, so the stop is the same
		# at 60fps and at 120 - which is what the phone actually runs at.
		speed = lerpf(speed, 0.0, SimUtil.smooth(Tuning.DRIVE_DRAG, dt))
	else:
		var want := Tuning.DRIVE_MAX * t
		if t < 0.0:
			want *= Tuning.DRIVE_REVERSE
		speed = move_toward(speed, want, Tuning.DRIVE_ACCEL * dt)

	# Turning while stationary is allowed and is most of what makes a tracked
	# machine feel like one. Reversing steers the other way, as it does in a
	# real vehicle, because the back of the machine is now the front.
	var turn := Tuning.turn_rate_at(speed) * s * dt
	if speed < 0.0:
		turn = -turn
	heading = wrapf(heading + turn, -PI, PI)

	vel = forward() * speed
	pos += vel * dt
	_clamp_to_deck()


## The deck has walls. A machine that can leave the room is a machine that can
## be lost off the edge of the world, and the collapse then has nothing to
## catch it.
func _clamp_to_deck() -> void:
	var hx := Tuning.DECK_W * 0.5 - Tuning.RIG_RADIUS
	var hz := Tuning.DECK_D * 0.5 - Tuning.RIG_RADIUS
	if absf(pos.x) > hx:
		pos.x = signf(pos.x) * hx
		speed *= 0.4
	# The back wall has the ramp in it, so that stretch is open.
	if pos.y < -hz and absf(pos.x) > Tuning.RAMP_W * 0.5:
		pos.y = -hz
		speed *= 0.4
	elif pos.y < -hz - Tuning.RAMP_DEPTH:
		pos.y = -hz - Tuning.RAMP_DEPTH
		speed *= 0.4
	if pos.y > hz:
		pos.y = hz
		speed *= 0.4


func _slew(dt: float) -> void:
	var want := clampf((turret_target - turret) * Tuning.TURRET_GAIN,
		-Tuning.TURRET_SLEW, Tuning.TURRET_SLEW)
	turret_vel = lerpf(turret_vel, want, SimUtil.smooth(Tuning.TURRET_RATE, dt))
	turret += turret_vel * dt
	if turret > Tuning.TURRET_MAX:
		turret = Tuning.TURRET_MAX
		turret_vel = minf(turret_vel, 0.0)
	elif turret < -Tuning.TURRET_MAX:
		turret = -Tuning.TURRET_MAX
		turret_vel = maxf(turret_vel, 0.0)


## The chain, as a distance constraint.
##
## This is the heart of the game and it is nine lines. The ball is a free point
## mass: nothing aims it, nothing pulls it toward a target, and the only way to
## move it is to move the thing it hangs from. Drive in an arc and it flails
## out behind; stop dead and it keeps going and swings round in front.
##
## The important half is the velocity handling when the chain goes taut. It is
## not enough to put the ball back on the circle - the OUTWARD component of the
## ball's velocity relative to the boom tip has to be removed, or the ball
## keeps trying to leave and the constraint fights it every frame, which reads
## as jitter. Returning a fraction of it instead of all is what makes a hard
## turn crack the ball out sideways rather than merely dragging it.
## The chain, and the whole feel of the game.
##
## The ball is a free point mass. Nothing aims it, nothing pulls it toward a
## target, and the only way to move it is to move the thing it hangs from - so
## driving IS the wind-up.
##
## Two forces and one constraint:
##
##   restoring   a real pendulum, proportional to how far the ball has swung
##   drag        low, so a swing carries
##   the chain   inextensible, and it removes only the RADIAL velocity
##
## That last point is what took two attempts. An earlier version derived the
## ball's velocity from how far it actually moved, which stopped the constraint
## injecting energy but destroyed momentum with it: a taut chain clamps the
## ball to a circle, so its per-frame displacement is small, so the derived
## velocity was small, and every swing died the moment it went taut. Gideon's
## words for the result were that the ball "flies out too much but also feels
## like it doesn't have enough momentum", which is exactly those two faults
## sitting on top of each other.
##
## The correct constraint zeroes the ball's radial velocity RELATIVE TO THE
## TIP and leaves the tangential component completely alone. Tangential is the
## momentum, so it carries; radial is the stretch, so it cannot. It cannot add
## energy either, because it only ever removes a component - which is what
## makes it stable without the displacement trick.
func _swing(dt: float) -> void:
	var tip := boom_tip()
	var tip_vel := (tip - _prev_tip) / maxf(dt, 0.00001)
	_prev_tip = tip

	# The restoring force. Proportional to the swing, so the ball has a period
	# instead of hanging wherever it was last flung.
	var rel := ball - tip
	var dist := rel.length()
	if dist > 0.001:
		ball_vel -= (rel / dist) * (Tuning.SWING_G * dist / Tuning.CHAIN) * dt

	ball_vel = ball_vel.lerp(Vector2.ZERO, SimUtil.smooth(Tuning.BALL_DRAG, dt))
	ball += ball_vel * dt
	_pull_chain_taut(tip, tip_vel)


## The chain as a distance constraint, run in TWO places: after the ball moves,
## and again after a collision has pushed the ball clear of whatever it hit.
##
## That second call is not tidiness. The push-out moves the ball along the line
## away from the target with no regard for the chain, so a ball that connected
## at full stretch ended up beyond the chain's length - measured at 5.43
## against a chain of 5.2. A constraint enforced in only one of the two places
## the position changes is not a constraint.
func _pull_chain_taut(tip: Vector2, tip_vel: Vector2) -> void:
	var rel := ball - tip
	var dist := rel.length()
	if dist <= Tuning.CHAIN or dist < 0.0001:
		return
	var n := rel / dist
	ball = tip + n * Tuning.CHAIN
	# Match the ball's radial velocity to the tip's, and touch nothing else.
	# Both directions, unconditionally: pulling away has to DRAG the ball, and
	# swinging outward has to stop at the chain's length. The tangential
	# component is the momentum and is left exactly as it was.
	var radial := (ball_vel - tip_vel).dot(n)
	ball_vel -= n * radial
	ball_vel = ball_vel.limit_length(Tuning.BALL_MAX_SPEED)


# --- breaking things ------------------------------------------------------

## Damage is the ball's speed, never a hit count.
##
## One target per step, and a per-target cooldown, so a single pass through a
## column is one hit rather than one per frame - which would make damage a
## function of the frame rate, the one thing a golden cannot survive.
func _hit(dt: float) -> void:
	for c in columns:
		if c.cool > 0.0:
			c.cool -= dt
	for w in walls:
		if w.cool > 0.0:
			w.cool -= dt

	var hit_speed := ball_speed()

	for i in columns.size():
		var c := columns[i]
		if not c.standing or c.cool > 0.0:
			continue
		if ball.distance_to(c.at) > Tuning.BALL_RADIUS + Tuning.COLUMN_RADIUS:
			continue
		_land(COLUMN, i, c, hit_speed, c.at)
		return

	for i in walls.size():
		var w := walls[i]
		if not w.standing or w.cool > 0.0:
			continue
		if _distance_to_segment(ball, w.a, w.b) > Tuning.BALL_RADIUS + Tuning.WALL_THICK:
			continue
		_land(WALL, i, w, hit_speed, w.at)
		return


func _land(kind: int, index: int, target: Dictionary, hit_speed: float, at: Vector2) -> void:
	target.cool = Tuning.HIT_COOLDOWN
	var damage := Tuning.damage_at(hit_speed)
	target_hit.emit(kind, index, hit_speed, at)

	# The ball comes off whatever it hits, and is pushed clear of it.
	#
	# The push-out is not cosmetic. Without it the ball can sit inside a target
	# it cannot damage, take a fresh bounce every cooldown, and compound - which
	# is how a policy that never touched the controls logged forty-three hits.
	# Resolving the overlap means one contact is one contact.
	var away := (ball - at)
	var clearance := Tuning.BALL_RADIUS + (Tuning.COLUMN_RADIUS if kind == COLUMN else Tuning.WALL_THICK)
	if away.length() > 0.001:
		var n := away.normalized()
		ball = at + n * (clearance + 0.02)
		# Reflected off the face it struck, keeping most of the speed. A ball
		# that stopped dead on every column would make a demolition a series of
		# separate set-ups; one that comes off cleanly keeps the swing alive
		# for the next one, which is the rhythm the game is actually about.
		var into := ball_vel.dot(n)
		if into < 0.0:
			ball_vel -= n * into * 1.7
		ball_vel = ball_vel.limit_length(Tuning.BALL_MAX_SPEED)
		# And the chain still applies. Pushing the ball clear of what it hit
		# can take it past the chain's length if it connected at full stretch.
		_pull_chain_taut(boom_tip(), Vector2.ZERO)

	if damage <= 0.0:
		return
	target.hp -= damage
	if target.hp > 0.0:
		return

	target.standing = false
	if kind == COLUMN:
		columns_down += 1
		rubble += Tuning.COLUMN_RUBBLE
	else:
		walls_down += 1
		rubble += Tuning.WALL_RUBBLE
	target_broken.emit(kind, index, at)
	_recompute_integrity()


## What is left holding the slab up, as a fraction of what it started with.
##
## Recomputed from the standing set rather than accumulated, so it is a
## property of the structure rather than a running total that can drift out of
## step with what is on screen. The gauge is the only thing telling the player
## how close the ceiling is to letting go, and one derived from the same source
## being drawn cannot lie about it.
func _recompute_integrity() -> void:
	var left := 0.0
	for c in columns:
		if c.standing:
			left += Tuning.COLUMN_CAPACITY
	for w in walls:
		if w.standing:
			left += Tuning.WALL_CAPACITY
	# Clamped, because `total_capacity` normalises against the AVERAGE number of
	# infill panels and a given basement may have more than average. Without
	# this the gauge reads "SUPPORT 102%", which is not wrong so much as
	# nonsense - a fraction of the whole cannot exceed the whole.
	integrity = minf(1.0, left / Tuning.total_capacity())
	if not collapsing and integrity <= Tuning.COLLAPSE_AT:
		collapsing = true
		escape_left = Tuning.escape_seconds_for(level)
		collapse_started.emit()


func _settle(dt: float) -> void:
	if not collapsing:
		return
	escape_left -= dt

	if _on_the_ramp():
		over = true
		won = true
		rubble += int(maxf(0.0, escape_left) * float(Tuning.ESCAPE_BONUS_PER_SECOND))
		if columns_standing() == 0:
			rubble += Tuning.TOTAL_TEARDOWN_BONUS
		escaped.emit(escape_left)
		level_finished.emit(true)
		return

	if escape_left <= 0.0:
		over = true
		won = false
		crushed.emit()
		level_finished.emit(false)


## Out through the mouth at the back. Only counts once the slab is going -
## otherwise the player could park in the exit and never play.
func _on_the_ramp() -> bool:
	return pos.y < Tuning.ramp_z() and absf(pos.x) < Tuning.RAMP_W * 0.5


# --- geometry -------------------------------------------------------------

static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.00001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
