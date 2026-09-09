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
## Four of them, and the set is the point. Each has to fail for a DIFFERENT
## reason, or the table they produce is not a description of the game:
##
##   PASSIVE  never touches anything
##   NUDGER   drives at columns slowly - proves speed is what does damage
##   GREEDY   wrecks well and never leaves - proves the escape is real
##   WRECKER  wrecks well and gets out

const PASSIVE := "passive"
const NUDGER := "nudger"
const GREEDY := "greedy"
const WRECKER := "wrecker"

const ALL := [PASSIVE, NUDGER, GREEDY, WRECKER]

## How far to the side of a column the machine aims.
##
## Swept, not reasoned about. The intuition is that you pass close - about a
## chain's length - and the ball clips the column on the way by. Measured, the
## plateau is at 7.5 to 9.0, which is a wide ORBIT: the machine circles well
## outside the column and the ball, trailing up to nine metres behind, sweeps
## through it on a long arc. Close passes scored a third less.
##
## That is a technique worth a player discovering, and it is why the level is a
## room rather than a corridor.
const PASS_OFFSET := 8.0


static func steer(name: String, s: Sim, mem: Dictionary) -> void:
	match name:
		PASSIVE:
			s.drive(0.0, 0.0)
		NUDGER:
			_worker(s, mem, 0.22, false)
		GREEDY:
			_worker(s, mem, 1.0, false)
		WRECKER:
			_worker(s, mem, 1.0, true)


## Drives at the columns, passing beside each one so the trailing ball sweeps
## through it, and turns hard as it goes by to crack the ball out sideways.
##
## `power` is the throttle it is willing to use and `bolt` is whether it leaves
## when the slab lets go. Those two arguments are the ONLY difference between
## the three policies that use this - same code, same targeting, same driving -
## which is what makes the gap between their scores a claim about the game
## rather than about the bots.
static func _worker(s: Sim, mem: Dictionary, power: float, bolt: bool) -> void:
	if s.collapsing and bolt:
		_run_for_it(s)
		return

	var target: int = mem.get("col", -1)
	if target < 0 or target >= s.columns.size() or not s.columns[target].standing:
		target = _nearest_standing(s)
		mem["col"] = target
		mem["side"] = 1.0 if SimUtil.hash2(target, 7) > 0.5 else -1.0
	if target < 0:
		# Everything is down and it is still standing here. Head out anyway.
		_run_for_it(s)
		return

	var at: Vector2 = s.columns[target].at
	var side: float = mem.get("side", 1.0)

	# A wide continuous orbit, recomputed every frame. It looks crude and a
	# "line up, then commit" version was written to replace it - which measured
	# 55% WORSE, because the run-up point sat at a fixed world angle and the
	# machine spent most of its time driving to somewhere it did not need to be.
	# Kept, because the measurement says so and not because it reads well.
	var to_target := at - s.pos
	var across := Vector2(-to_target.y, to_target.x).normalized() * PASS_OFFSET * side
	_head_toward(s, at + across, power)


## Steer toward a point at a given throttle. Deliberately crude - a policy with
## cleverness in it becomes a second thing that can change, and then a golden
## failure means "the bot got better" as often as "the game changed".
static func _head_toward(s: Sim, goal: Vector2, power: float) -> void:
	var to_goal := goal - s.pos
	if to_goal.length() < 0.001:
		s.drive(power, 0.0)
		return
	# Angle between where the machine points and where it wants to go, wrapped
	# so a target behind it turns the short way round.
	var want := atan2(to_goal.x, to_goal.y)
	var err := wrapf(want - s.heading, -PI, PI)
	var turn := clampf(err * 2.2, -1.0, 1.0)
	# Ease off the throttle when the turn is hard, the way anyone drives - and
	# it matters mechanically, because the turn rate falls away with speed.
	var ease: float = 1.0 - 0.55 * clampf(absf(err) / PI, 0.0, 1.0)
	s.drive(power * ease, turn)


static func _run_for_it(s: Sim) -> void:
	_head_toward(s, Vector2(0.0, Tuning.ramp_z() - 2.0), 1.0)


static func _nearest_standing(s: Sim) -> int:
	var best := -1
	var best_d := INF
	for i in s.columns.size():
		if not s.columns[i].standing:
			continue
		var d: float = s.pos.distance_to(s.columns[i].at)
		if d < best_d:
			best_d = d
			best = i
	return best


## Play one whole basement with one policy and hand back the final state, plus
## the extra readings a balance pass wants that the golden does not.
static func play(name: String, level: int = 1, seconds: float = 0.0) -> Dictionary:
	var s := Sim.new(level)
	var mem := {}
	var step := 1.0 / 60.0
	var limit := seconds if seconds > 0.0 else 150.0
	var n := int(round(limit / step))
	var peak_ball := 0.0
	# An Array rather than an int, because a GDScript lambda captures an int by
	# VALUE - the closure increments its own copy and the counter outside stays
	# at zero, silently, which is exactly the kind of nothing-happened reading
	# that gets mistaken for a game with no hits in it.
	var hits := [0]
	s.target_hit.connect(func(_k, _i, _sp, _at): hits[0] += 1)
	for i in n:
		if s.over:
			break
		steer(name, s, mem)
		s.advance(step)
		peak_ball = maxf(peak_ball, s.ball_speed())
	var out := s.state()
	out["peak_ball"] = snappedf(peak_ball, 0.001)
	out["hits"] = hits[0]
	out["seconds"] = snappedf(s.time, 0.001)
	return out
