class_name Tuning
extends RefCounted

## Every number that shapes how it feels, in one place, plus the arithmetic
## derived from it.
##
## Pure: nothing here reads live state. That is what lets `test/` check the
## shape of the curves - which is what a balance change accidentally breaks -
## without booting a game.
##
## The game in one sentence: a rig drives down a condemned street, a wrecking
## ball swings on a boom out in front of it, and the player aims the ball only
## by deciding where the rig was a moment ago.

# --- the street -----------------------------------------------------------

const LANE_HALF_WIDTH := 3.0      ## how far from the centre line the RIG may go
const KERB_X := 5.2               ## the near face of the buildings, both sides
const CHUNK := 9.0                ## metres between spawn decisions
const CHUNKS_PER_LEVEL := 44      ## a street is 44 chunks, then the yard

# --- the rig --------------------------------------------------------------

const FORWARD_SPEED := 13.0       ## metres per second on street 1
const RIG_HALF_WIDTH := 1.1
const START_LIVES := 3
const HIT_COOLDOWN := 0.9         ## seconds of immunity after a barricade

## Steering is a velocity, not a position write. The pendulum below is driven
## by the pivot's lateral ACCELERATION, so the rig has to have one: an
## exponential position lerp has an acceleration that spikes on the frame the
## input changes and is zero everywhere else, which makes the ball twitch
## rather than swing.
const STEER_GAIN := 3.4           ## target lateral speed per metre of error
const MAX_STEER_SPEED := 7.5      ## metres per second across the street
## 7.0 for one measured build, and a design test caught it overshooting its
## target by 4%. vx lags `want`, so by the time the rig arrives the target
## velocity is zero and the actual one is not - which is a spring with no
## damping term, and the player's word for that on a sibling game was
## "bouncy". Raising the rate shortens the lag that causes it.
const STEER_RATE := 11.0          ## exponential rate of vx toward its target

# --- the ball -------------------------------------------------------------

const CHAIN := 5.0                ## pivot to ball centre
const BOOM_FORWARD := 7.0         ## the pivot hangs this far AHEAD of the cab
const PIVOT_Y := 6.6
const BALL_RADIUS := 1.05

## Gravity here is a tuning constant, not 9.8. A real ball on a five-metre
## chain has a period of 4.5 seconds, which is majestic and unplayable: the
## lag has to be about a second so a swerve pays off inside the time a
## building is on screen. sqrt(SWING_G / CHAIN) sets that; see swing_period().
##
## 34.0 was tried, for a 2.4-second period instead of 2.8. It puts more
## turning points on a street, which sounds like more chances to hit
## something, and it measured 24% WORSE for the aiming bot: a faster swing
## needs more precise timing, so it rewards the policy that ignores the street
## and weaves on the beat. That is the wrong game. This number is the lag the
## player is learning to lead, and it is a FEEL decision - it is set from what
## a thumb can anticipate, and the bot only gets a veto if it says the game is
## unplayable.
const SWING_G := 26.0
const SWING_DAMP := 0.55          ## per second, on angular velocity
const MAX_THETA := 1.15           ## radians from vertical; the chain never goes over

## What a hit does to the swing. This is the mechanic the whole game is built
## on: an impact REVERSES the ball and gives some of the energy back, so
## hitting a building on the left kicks the ball toward the right and a street
## can be chained left-right-left. Miss, and the damping bleeds the swing away
## and the next building is out of reach.
const REBOUND := 0.72             ## fraction of angular speed returned, reversed
## Not a round number: it is the smallest rebound that can still carry the
## ball across to the OPPOSITE kerb, which is what makes a street a rhythm
## rather than a list of separate setups. test_tuning.gd derives the bound
## from CHAIN, SWING_G and the swing a kerb needs, and it failed at 1.05.
const REBOUND_MIN := 1.30         ## rad/s floor, so a dead-slow tap still kicks back

# --- what is on the street ------------------------------------------------

const BUILDING_CHANCE := 0.52     ## of chunks that hold a building on either side
const BUILDING_HALF_DEPTH := 3.0
## Renderer-only since the height rule was removed - it sets how tall a floor
## is drawn and nothing in the simulation reads it. Kept here because it is a
## number that shapes how the game LOOKS, and the skyline is most of what the
## player is reading.
const FLOOR_HEIGHT := 3.1
const RUBBLE_PER_FLOOR := 12
const FLATTEN_BONUS := 30         ## for taking a building down to nothing

const BARRICADE_CHANCE := 0.22
const BARRICADE_HALF_DEPTH := 0.9
const BARRICADE_INNER_X := 0.35   ## the blocked span runs from its rail to here
const BARRICADE_RUBBLE := 24

## A ball hanging straight down does not break anything; a swinging one does.
## Without this a barricade clears itself the moment the player drives at it,
## which is a station that plays itself rather than a decision.
##
## It is also the second half of the rhythm the whole street is built on. A
## pendulum is at its widest where it is SLOWEST and at its fastest where it is
## CENTRED, so a building at the kerb wants the ball at a turning point and a
## barricade wants it mid-swing. One tool, two phases, and the street asks for
## both.
const BARRICADE_MIN_SWING := 0.9  ## rad/s of |omega| needed to smash one

## How tall a building can be. A skyline that is all one height reads as a
## fence, and the floor count is also the health bar, so the range is what
## makes one kerb worth more than another at a glance.
##
## Collision does not test the ball's height against it - see the long note in
## sim.gd for why that idea was built, measured and removed.
const MIN_FLOORS := 1
const MAX_FLOORS := 6

# --- the in-run power fantasy ---------------------------------------------

## Rubble fills a meter; a full meter is another floor per swing, permanently
## for the rest of the run. That is the whole in-run ladder: street one you
## can only clip the tops off, and by the yard you are flattening towers.
const POWER_START := 1
const POWER_MAX := 4
const METER_BASE := 90            ## rubble for the first power up
const METER_STEP := 1.70          ## and each one after costs this much more

# --- how it scales --------------------------------------------------------

const LEVEL_SPEED_STEP := 1.05
const LEVEL_HEIGHT_STEP := 0.55   ## extra floors per street, on average

## Speed stops climbing here, and that is a design decision rather than a
## safety rail.
##
## The ball's lag is a fixed number of SECONDS, so every increase in speed
## shortens the window a building is aimable in by the same fraction. A design
## test found street 10 already passing a building faster than the ball could
## be swung at it, and street 20 at half that - the ladder had outrun its own
## tool, and no amount of skill would have helped.
##
## Past the cap the streets get harder by growing the skyline instead, which
## asks for more power rather than more reaction.
const MAX_FORWARD_SPEED := 18.0


## Speed compounds per street, and it is the only difficulty knob that moves on
## its own. Anything else that scales should be checked against this one: if a
## threat grows faster than the player's ability to react, the ladder ends.
static func speed_for(level: int) -> float:
	return minf(MAX_FORWARD_SPEED, FORWARD_SPEED * pow(LEVEL_SPEED_STEP, level - 1))


## How tall buildings get. Kept as a float and floored at the spawn, so the
## growth is gradual rather than every building gaining a floor at once.
static func height_for(level: int) -> float:
	return 1.4 + LEVEL_HEIGHT_STEP * float(level - 1)


## Rubble needed for the nth power up, counting from 1.
static func meter_for(power: int) -> int:
	return int(round(METER_BASE * pow(METER_STEP, power - POWER_START)))


## The pendulum's natural period. Everything about how the ball FEELS is this
## number: a quarter of it is how long after a swerve the ball reaches its
## extreme, which is the lag the player is learning to lead.
static func swing_period() -> float:
	return TAU / sqrt(SWING_G / CHAIN)


## How far off the centre line the ball can possibly reach, with the rig
## pinned to a rail and the chain at full swing. Compared against KERB_X by a
## design test, because a target the tool cannot reach is not a target - and
## eyeballing that relationship is how it silently stops being true.
static func max_ball_reach() -> float:
	return LANE_HALF_WIDTH + CHAIN * sin(MAX_THETA)


## Where the centre of the ball sits at a given swing angle. The ball RISES as
## it swings out, which is why the reach and the height are the same decision
## and not two: a wide swing arrives high and a gentle one arrives low.
static func ball_height(theta: float) -> float:
	return PIVOT_Y - CHAIN * cos(theta)


## The smallest swing that still reaches a kerb from the near rail. Below this
## the ball is over the street and nothing can be hit, which makes it the
## natural lower bound on the height arithmetic in test_tuning.gd.
static func min_reaching_theta() -> float:
	var need := (KERB_X - BALL_RADIUS - LANE_HALF_WIDTH) / CHAIN
	return asin(clampf(need, -1.0, 1.0))


## How long a street takes at its own speed. Used by the tests to assert the
## street is a sane length rather than to drive anything.
static func level_seconds(level: int) -> float:
	return (CHUNK * CHUNKS_PER_LEVEL) / speed_for(level)
