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

## Three lanes, because the rig is moved by two thumb pads rather than by a
## drag - the drag is spent on the crane now. A discrete nudge wants a discrete
## destination, and three is the fewest that still gives a left, a middle and a
## right to be caught out of position in.
const LANES := [-2.35, 0.0, 2.35]
const START_LANE := 1

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

# --- the crane ------------------------------------------------------------
#
# The turret slews to where the thumb drags; the ball hangs off the boom tip
# and TRAILS the boom, swinging wider the harder the turret is slewed. So the
# player points at what they want and then has to lead the lag - which is the
# same skill the first build had, but legible, because the boom is visibly
# pointing somewhere.
#
# The first build welded the boom forward and drove the ball off the rig's
# lateral acceleration. It worked and it measured well, and Gideon's note on it
# was right: aiming was the whole game and yet you could not see yourself aim.

## Deliberately just too short. At rest the ball reaches 4.07 out from the
## rig and a kerb needs 4.15, so POINTING AT A BUILDING IS NOT ENOUGH - the
## ball only gets there once it is actually travelling round. That margin is
## the whole reason this is a game rather than a cursor, and test_tuning.gd
## asserts it in both directions rather than trusting this comment.
##
## It was 4.4 with a gain of 1.75 and a cap of 11 for one measured build, and
## that combination broke the mechanic completely: the radius sat PINNED at its
## cap for most of a sweep, so the ball blanketed a band twice as wide as the
## street and could not miss. Swinging the crane blindly on the ball's own
## period out-earned aiming it. The cap must be somewhere the ball rarely
## reaches, or reach stops being a consequence of speed and becomes a constant.
const BOOM := 3.2                 ## turret to ball at rest
const PIVOT_Y := 6.4
const BALL_RADIUS := 1.05

## How far round the boom can point, either side of straight ahead. Not a full
## circle: the rig is driving, the street is ahead, and a boom that can point
## backwards is a boom the player can lose track of.
const YAW_MAX := 1.18             ## radians, about 68 degrees

## The slew, as a rate-limited approach to where the thumb is. Same shape as
## the rig's drive: a target VELOCITY approached exponentially, so the angular
## acceleration is smooth and bounded rather than a spike on the frame the
## input changes.
const YAW_GAIN := 3.2             ## target slew rate per radian of error
const MAX_SLEW := 2.7             ## radians per second, the crane's top speed
const YAW_RATE := 9.0             ## exponential rate of slew toward its target

## The ball trailing the boom, as a damped spring on the ball's bearing.
##
## Underdamped on purpose: the ball overshoots where the boom is pointing,
## which is what a real ball on a chain does and is the entire reason to lead a
## target rather than point at it. sqrt(BALL_PULL) is the natural frequency, so
## a quarter period - the lag the player is learning - is ball_lag().
const BALL_PULL := 9.0
const BALL_DAMP := 1.55

## Centrifugal reach. A ball being swung hard flies outward, so how far the
## crane can hit is set by how hard it was slewed rather than by a constant -
## which is what stops "point at the building" being the whole game.
const RADIUS_GAIN := 0.62         ## metres of reach per rad/s of bearing speed
const RADIUS_RATE := 7.0          ## how fast the radius follows that
const RADIUS_MAX := 8.2

## What a hit does. An impact throws the ball back the other way and hands some
## of the speed back, so a street can still be chained kerb to kerb - the one
## piece of the first build that was working and is kept exactly.
const REBOUND := 0.70             ## fraction of bearing speed returned, reversed
## Failed twice: at 1.05 under the old pendulum and at 1.30 once the boom was
## shortened. Both times the fix was this number and not the test - it is the
## smallest rebound that can still carry the ball round to the OPPOSITE kerb,
## which is what makes a street a rhythm rather than a list of setups.
const REBOUND_MIN := 1.75         ## rad/s floor, so a dead-slow tap still kicks back

# --- what is on the street ------------------------------------------------

## Measured against the policies rather than chosen. At 0.46 the aiming bot and
## a bot that just waves the crane on the ball's period score within 2% of each
## other; thinning the street makes the AIMING bot worse, not better, because
## it starts committing to buildings that are not there yet.
##
## That is the open design problem in this build and it is worth stating
## plainly: reach rises with swing speed and nothing anywhere punishes swinging
## flat out, so maximum swing is never wrong. See NOTES.md - the fix is targets
## that are worth different amounts, which is the next thing to build.
const BUILDING_CHANCE := 0.46     ## of chunks that hold a building on either side
const BUILDING_HALF_DEPTH := 3.0
## Renderer-only since the height rule was removed - it sets how tall a floor
## is drawn and nothing in the simulation reads it. Kept here because it is a
## number that shapes how the game LOOKS, and the skyline is most of what the
## player is reading.
const FLOOR_HEIGHT := 3.1
const RUBBLE_PER_FLOOR := 12
const FLATTEN_BONUS := 30         ## for taking a building down to nothing

const BARRICADE_CHANCE := 0.11
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
const METER_BASE := 260           ## rubble for the first power up
const METER_STEP := 1.90          ## and each one after costs this much more

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
## 18.0 until the boom was shortened. The window a building is aimable in is
## (BOOM + depth) / speed, so making the tool shorter lowers the speed the
## ladder may reach - the design test found it 0.511s against a 0.524s lag at
## street 10, which is the ladder having outrun its own tool again.
const MAX_FORWARD_SPEED := 16.5


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


## The ball's natural period against the boom. A quarter of it is how long
## after a slew the ball reaches its extreme, which is the lag the player is
## learning to lead - the single number that decides how this game feels.
static func swing_period() -> float:
	return TAU / sqrt(BALL_PULL)


## That lag, named, because it is what nearly every design test is about.
static func ball_lag() -> float:
	return swing_period() * 0.25


## How far off the centre line the ball can possibly reach: the outer lane,
## plus the longest the boom gets, swung fully to the side. Compared against
## KERB_X by a design test, because a target the tool cannot reach is not a
## target - and eyeballing that relationship is how it silently stops being
## true.
static func max_ball_reach() -> float:
	return absf(LANES[LANES.size() - 1]) + RADIUS_MAX * sin(YAW_MAX)


## And the reach from the MIDDLE lane, which is the one that matters: with the
## rig moved by buttons the player will spend most of a street centred, so if a
## kerb needs a lane change as well as a swing then the crane is not the main
## control after all.
static func centre_reach() -> float:
	return RADIUS_MAX * sin(YAW_MAX)


## The ball rides a little lower as the boom swings out, which is the only
## trace left of the old pendulum and is kept because a ball that stays at one
## height reads as a floating sphere rather than as a weight on a chain.
static func ball_height(bearing: float) -> float:
	return PIVOT_Y - 1.5 - 0.9 * absf(sin(bearing))


## The smallest bearing that reaches a kerb from the centre lane, at rest
## radius. Anything below this is the ball out over the road hitting nothing.
static func min_reaching_bearing() -> float:
	return asin(clampf((KERB_X - BALL_RADIUS) / RADIUS_MAX, -1.0, 1.0))


## How long a street takes at its own speed. Used by the tests to assert the
## street is a sane length rather than to drive anything.
static func level_seconds(level: int) -> float:
	return (CHUNK * CHUNKS_PER_LEVEL) / speed_for(level)
