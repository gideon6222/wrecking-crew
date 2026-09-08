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
## Each takes the sim and issues one `steer_to` per step. Deliberately crude.
## A policy with cleverness in it becomes a second thing that can change, and
## then a golden failure means "the bot got better" as often as "the game
## changed".

const PASSIVE := "passive"
const WEAVER := "weaver"
const WRECKER := "wrecker"
const DODGER := "dodger"

const ALL := [PASSIVE, WEAVER, WRECKER, DODGER]


## `mem` is the policy's own scratch space for one run. Only WRECKER uses it,
## and it uses it for one thing: sticking to a target once it has picked one.
## Re-choosing every frame let two buildings at similar distances on opposite
## kerbs swap the intent back and forth, and a pendulum given contradictory
## pushes at four hertz simply stops swinging - which measured as the street
## being empty when it was the fullest one in the set.
static func steer(name: String, s: Sim, mem: Dictionary) -> void:
	match name:
		PASSIVE:
			pass
		WEAVER:
			_weaver(s)
		WRECKER:
			_wrecker(s, mem)
		DODGER:
			_dodger(s)


## Rail to rail on the pendulum's own period, ignoring the street entirely.
##
## This one exists to answer a question the other policies cannot: is the swing
## actually drivable to its limit? It is the resonance case, so `max reach`
## measured under it is the honest ceiling rather than the arithmetic one.
static func _weaver(s: Sim) -> void:
	var half := Tuning.swing_period() * 0.5
	var phase := fmod(s.time, half * 2.0)
	s.steer_to(Tuning.LANE_HALF_WIDTH if phase < half else -Tuning.LANE_HALF_WIDTH)


## Playing the game: pick a kerb, load the swing away from it, turn back a
## quarter period out so the ball arrives with the rig, and stay alive.
##
## It also has to survive, and that is not a detail. A bot that only aims dies
## on every street, and a mean taken over dead runs measures how long the game
## lets you live rather than how well the tool works. The first measured build
## had exactly that: the aiming bot finished six streets out of six with no
## lives left, and every balance reading was of a game nobody had played to the
## end.
##
## Where the two jobs disagree, survival wins - which is also how a person
## plays, and is why the cost of a barricade is the aim it makes you give up
## rather than the life it takes.
static func _wrecker(s: Sim, mem: Dictionary) -> void:
	var speed := Tuning.speed_for(s.level)
	var quarter := Tuning.swing_period() * 0.25
	var want := 0.0

	# Hold the previous target while it is still ahead and still standing.
	var side: int = mem.get("side", 0)
	var mark: float = mem.get("z", -1.0)
	var soonest: float = (mark - s.ball_z()) / speed if side != 0 else INF
	if side != 0 and (soonest < -Tuning.BUILDING_HALF_DEPTH / speed or _felled(s, side, mark)):
		side = 0
		soonest = INF

	if side == 0:
		for b in s.buildings:
			if b.left <= 0:
				continue
			# Time until the BALL is level with it, not the cab. The ball leads
			# by BOOM_FORWARD, and every decision here is about where the ball
			# will be.
			var t: float = (b.z - s.ball_z()) / speed
			# Anything closer than a quarter period cannot be swung at any
			# more; committing to it only spoils the swing for the next one.
			if t < quarter or t > quarter * 3.0:
				continue
			if t < soonest:
				soonest = t
				side = b.side
				mark = b.z
		mem["side"] = side
		mem["z"] = mark

	if side != 0:
		# The crane operator's technique, and the reason this game is not a
		# lane-changer: driving AT the thing you want to hit throws the ball
		# the other way, because the ball is driven by the pivot's
		# acceleration. So load the swing by pulling away from the target, and
		# turn back one quarter period out - which is exactly when the ball
		# reaches its far extreme and starts travelling toward the kerb.
		#
		# An earlier bot steered straight at the target side the whole way in.
		# It scored BELOW a bot that ignored the street entirely and weaved on
		# the pendulum's period, which is how this was found: if the policy
		# that reads the level loses to the policy that does not, the bot is
		# wrong before the game is.
		var rail := Tuning.LANE_HALF_WIDTH - 0.05
		want = float(side) * rail if soonest <= quarter else -float(side) * rail

	for w in s.barricades:
		if w.taken:
			continue
		var gap: float = w.z - s.distance
		if gap < 0.0 or gap > 22.0:
			continue
		# Standing in the blocked half with a barricade this close is a life.
		if signf(want) == signf(float(w.side)) or absf(want) < Tuning.BARRICADE_INNER_X:
			want = -float(w.side) * (Tuning.LANE_HALF_WIDTH - 0.3)
		break

	s.steer_to(want)


## Survives without playing: steers only to keep the cab out of a barricade and
## never goes near a kerb.
##
## The measurement that matters is this one against WRECKER. If a run that
## never aims the ball earns anything close to a run that does, the swing is
## decoration and the game is a lane-changer with scenery - which is exactly
## the failure a sibling game shipped and only a measurement found.
static func _dodger(s: Sim) -> void:
	for w in s.barricades:
		if w.taken:
			continue
		var gap: float = w.z - s.distance
		if gap < 0.0 or gap > 26.0:
			continue
		s.steer_to(-float(w.side) * (Tuning.LANE_HALF_WIDTH - 0.4))
		return
	s.steer_to(0.0)


## Has the building this policy committed to already come down? Without this
## the bot keeps loading a swing for a kerb that is now an empty lot.
static func _felled(s: Sim, side: int, z: float) -> bool:
	for b in s.buildings:
		if b.side == side and is_equal_approx(b.z, z):
			return b.left <= 0
	return true


## Play one whole street with one policy and hand back the final state, plus
## the extra readings a balance pass wants that the golden does not.
static func play(name: String, level: int = 1, seconds: float = 0.0) -> Dictionary:
	var s := Sim.new(level)
	var mem := {}
	var step := 1.0 / 60.0
	var limit := seconds if seconds > 0.0 else Tuning.level_seconds(level) + 2.0
	var n := int(round(limit / step))
	var peak_reach := 0.0
	var peak_omega := 0.0
	for i in n:
		if s.over:
			break
		steer(name, s, mem)
		s.advance(step)
		peak_reach = maxf(peak_reach, absf(s.ball_x()))
		peak_omega = maxf(peak_omega, absf(s.omega))
	var out := s.state()
	out["peak_reach"] = snappedf(peak_reach, 0.001)
	out["peak_omega"] = snappedf(peak_omega, 0.001)
	out["seconds"] = snappedf(s.time, 0.001)
	return out
