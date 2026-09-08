class_name Policies
extends RefCounted

## Scripted players.
##
## These are not test fixtures, they are the definition of "playing well" - the
## thing every balance number in the game is measured against. That is why they
## live in the repo rather than in a session: on a sibling game, `par` was once
## set from a policy typed into a browser console whose lookahead was slightly
## longer than the committed one, it scored 65% higher, and the constant went
## in 44% too high. Nobody could have caught that by reading the number.
##
## Four of them, and the set is the point. `DEMOLISHER` and `RECKLESS` do
## exactly the same amount of work with exactly the same control - they differ
## only in the ORDER they take the bays down. If those two ever score the same,
## the order does not matter and the game has no decision in it.

const PASSIVE := "passive"
const WAVER := "waver"
const DEMOLISHER := "demolisher"
const RECKLESS := "reckless"

const ALL := [PASSIVE, WAVER, DEMOLISHER, RECKLESS]

## How far either side of the target the boom sweeps. Wide enough that the ball
## is always moving when it crosses the column, narrow enough that it is still
## aimed at one.
const SWEEP := 0.55


static func steer(name: String, s: Sim, mem: Dictionary) -> void:
	match name:
		PASSIVE:
			pass
		WAVER:
			_waver(s)
		DEMOLISHER:
			_worker(s, mem, true)
		RECKLESS:
			_worker(s, mem, false)


## Slews the boom side to side on the ball's own period and never moves the
## crane. Hits whatever happens to be in front of it.
##
## This is the control against which aiming has to prove it is doing something.
## On the street version the equivalent policy scored LEVEL with the one that
## read the level, which is how it became clear that game had no decision in
## it - the finding that led to this one.
static func _waver(s: Sim) -> void:
	var half := Tuning.swing_period() * 0.5
	var phase := fmod(s.time, half * 2.0)
	s.aim_to(Tuning.YAW_MAX if phase < half else -Tuning.YAW_MAX)


## Works the building bay by bay, parking in front of each one and swinging
## across it until the column goes.
##
## `balanced` is the ONLY difference between the two policies that use this.
## True picks the bay that leaves the remainder most centred; false works from
## the left-hand end. Same control, same effort, same swings - only the order
## changes, which is exactly the claim this game is making.
static func _worker(s: Sim, mem: Dictionary, balanced: bool) -> void:
	var target: int = mem.get("bay", -1)
	if target < 0 or target >= s.bays.size() or not s.bays[target].standing:
		target = _pick(s, balanced)
		mem["bay"] = target
	if target < 0:
		return

	work_bay(s, target)


## Park in front of a bay and swing across its column. One step of it.
##
## Public, and the tests drive columns through THIS rather than through a
## sweep of their own. There was a version where they had their own, and it
## was quietly worse at the game - so tests that should have been checking
## "does a column take its hit points to break" were really checking "can this
## particular sweep connect at all", and eight of them failed for a reason that
## had nothing to do with what they were asserting. One definition of how a
## column is worked, used by the policy and the tests alike.
static func work_bay(s: Sim, bay: int) -> void:
	var bx := Tuning.bay_x(s.level, bay)

	# The crane comes to the bay. The ball's distance from the crane falls away
	# as it swings round, so an outer bay cannot be reached deeply from the
	# middle of the site.
	var best := 0
	for i in Tuning.LANES.size():
		if absf(Tuning.LANES[i] - bx) < absf(Tuning.LANES[best] - bx):
			best = i
	if s.lane < best:
		s.nudge(1)
	elif s.lane > best:
		s.nudge(-1)

	# Swing ACROSS the column rather than pointing at it. A ball that arrives
	# with no speed does nothing, so the boom oscillates about the bearing to
	# the column and the ball crosses it fast on every pass. That is the crane
	# technique the whole control scheme is built on, in three lines.
	var aim := atan2(bx - s.x, Tuning.FACE_Z)
	var half := Tuning.swing_period() * 0.5
	var phase := fmod(s.time, half * 2.0)
	var swing := SWEEP if phase < half else -SWEEP
	s.aim_to(clampf(aim + swing, -Tuning.YAW_MAX, Tuning.YAW_MAX))


## Which bay to take next.
##
## The balanced version tries every standing bay and keeps the one that leaves
## the smallest imbalance behind - which is the strategy of a real controlled
## demolition, and is discoverable from the gauge without being told. The
## reckless version just works along the row.
static func _pick(s: Sim, balanced: bool) -> int:
	var best := -1
	var best_lean := INF
	for i in s.bays.size():
		if not s.bays[i].standing:
			continue
		if not balanced:
			return i
		var after := _lean_without(s, i)
		if after < best_lean:
			best_lean = after
			best = i
	return best


## What the lean would be if this bay came down, computed the same way the
## simulation computes it. Duplicated deliberately rather than exposed from
## Sim: a policy that could ask the game for its own answer would stop being a
## player and start being an oracle, and the golden would then only be testing
## that the game agrees with itself.
static func _lean_without(s: Sim, drop: int) -> float:
	var arm := Tuning.half_width(s.level)
	var moment := 0.0
	var mass := 0.0
	for i in s.bays.size():
		if i == drop or not s.bays[i].standing:
			continue
		var w: float = float(s.bays[i].floors)
		moment += Tuning.bay_x(s.level, i) * w
		mass += w
	if mass <= 0.0:
		return 0.0
	return absf((moment / mass) / arm)


## Play one whole demolition with one policy and hand back the final state,
## plus the extra readings a balance pass wants that the golden does not.
static func play(name: String, level: int = 1, seconds: float = 0.0) -> Dictionary:
	var s := Sim.new(level)
	var mem := {}
	var step := 1.0 / 60.0
	var limit := seconds if seconds > 0.0 else 90.0
	var n := int(round(limit / step))
	var peak_depth := 0.0
	var peak_omega := 0.0
	for i in n:
		if s.over:
			break
		steer(name, s, mem)
		s.advance(step)
		peak_depth = maxf(peak_depth, s.ball_z())
		peak_omega = maxf(peak_omega, absf(s.bearing_vel))
	var out := s.state()
	out["peak_depth"] = snappedf(peak_depth, 0.001)
	out["peak_omega"] = snappedf(peak_omega, 0.001)
	out["seconds"] = snappedf(s.time, 0.001)
	return out
