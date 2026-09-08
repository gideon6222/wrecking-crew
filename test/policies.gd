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


## Slews the boom side to side on the ball's own period, ignoring the street
## entirely.
##
## This one exists to answer a question the other policies cannot: is the ball
## actually drivable to its limit? It is the resonance case, so `peak reach`
## measured under it is the honest ceiling rather than the arithmetic one - and
## it is the control against which the aiming policy has to prove it is doing
## something better than waving the crane about.
static func _weaver(s: Sim) -> void:
	var half := Tuning.swing_period() * 0.5
	var phase := fmod(s.time, half * 2.0)
	s.aim_to(Tuning.YAW_MAX if phase < half else -Tuning.YAW_MAX)


## Playing the game: pick the next building, slew the boom across it, and lead
## the ball's lag so it arrives while the kerb is level.
##
## The crane rewrite changed what "playing well" means, so this changed with
## it. The old version loaded a swing by pulling the RIG away from the target,
## because the ball was driven by the rig's acceleration. Nothing about that
## survives: the boom is now pointed directly and the only lead left is time.
##
## It also has to survive, and that is not a detail. A bot that only aims dies
## on every street, and a mean taken over dead runs measures how long the game
## lets you live rather than how well the tool works.
static func _wrecker(s: Sim, mem: Dictionary) -> void:
	var speed := Tuning.speed_for(s.level)
	var lag := Tuning.ball_lag()

	# Hold the chosen target while it is still ahead and still standing.
	# Re-choosing every frame let two buildings at similar distances on
	# opposite kerbs swap the intent back and forth, and a crane given
	# contradictory orders at four hertz never builds any swing at all.
	var side: int = mem.get("side", 0)
	var mark: float = mem.get("z", -1.0)
	if side != 0 and (mark < s.distance - Tuning.BUILDING_HALF_DEPTH or _felled(s, side, mark)):
		side = 0

	if side == 0:
		var soonest := INF
		for b in s.buildings:
			if b.left <= 0:
				continue
			# Time until the RIG is level with it. The ball's own position is
			# not the right clock any more: where the ball is depends on where
			# the boom is pointed, which is the thing being decided.
			var t: float = (b.z - s.distance) / speed
			if t < lag * 0.5 or t > lag * 5.0:
				continue
			if t < soonest:
				soonest = t
				side = b.side
				mark = b.z
		mem["side"] = side
		mem["z"] = mark

	# Point at the kerb the target is on, and come back through the middle
	# between targets - which is what keeps the ball moving, since reach comes
	# from how fast the ball is travelling and not from where the boom points.
	var want := float(side) * Tuning.YAW_MAX
	if side != 0:
		var t: float = (mark - s.distance) / speed
		# Swing back the other way while the target is still far off, so the
		# ball is already travelling when the boom comes round to it. This is
		# the crane version of loading a swing, and it is the difference
		# between reaching a kerb and waving at it.
		if t > lag * 1.4:
			want = -float(side) * Tuning.YAW_MAX
	s.aim_to(want)

	# And stay out of the barricades. One nudge per press, like a thumb.
	if mem.get("cool", 0.0) > 0.0:
		mem["cool"] = float(mem["cool"]) - 1.0 / 60.0
		return
	for w in s.barricades:
		if w.taken:
			continue
		var gap: float = w.z - s.distance
		if gap < 0.0 or gap > 26.0:
			continue
		var lo: float = -Tuning.LANE_HALF_WIDTH if w.side < 0 else Tuning.BARRICADE_INNER_X
		var hi: float = -Tuning.BARRICADE_INNER_X if w.side < 0 else Tuning.LANE_HALF_WIDTH
		if s.x + Tuning.RIG_HALF_WIDTH > lo and s.x - Tuning.RIG_HALF_WIDTH < hi:
			s.nudge(-w.side)
			mem["cool"] = 0.25
		break


## Survives without playing: steers only to keep the cab out of a barricade and
## never goes near a kerb.
##
## The measurement that matters is this one against WRECKER. If a run that
## never aims the ball earns anything close to a run that does, the swing is
## decoration and the game is a lane-changer with scenery - which is exactly
## the failure a sibling game shipped and only a measurement found.
static func _dodger(s: Sim) -> void:
	# Never touches the crane at all - the boom stays where it started.
	for w in s.barricades:
		if w.taken:
			continue
		var gap: float = w.z - s.distance
		if gap < 0.0 or gap > 26.0:
			continue
		var lo: float = -Tuning.LANE_HALF_WIDTH if w.side < 0 else Tuning.BARRICADE_INNER_X
		var hi: float = -Tuning.BARRICADE_INNER_X if w.side < 0 else Tuning.LANE_HALF_WIDTH
		if s.x + Tuning.RIG_HALF_WIDTH > lo and s.x - Tuning.RIG_HALF_WIDTH < hi:
			s.nudge(-w.side)
		return


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
		peak_omega = maxf(peak_omega, absf(s.bearing_vel))
	var out := s.state()
	out["peak_reach"] = snappedf(peak_reach, 0.001)
	out["peak_omega"] = snappedf(peak_omega, 0.001)
	out["seconds"] = snappedf(s.time, 0.001)
	return out
