class_name Tuning
extends RefCounted

## Every number that shapes how it feels, in one place, plus the arithmetic
## derived from it.
##
## Pure: nothing here reads live state. That is what lets `test/` check the
## shape of the curves - which is what a balance change accidentally breaks -
## without booting a game.
##
## The game in one sentence: you are parked in front of a condemned building
## with a wrecking crane and a fixed number of swings, and you have to bring it
## down INTO ITS OWN FOOTPRINT rather than onto the block next door.

# --- the site -------------------------------------------------------------

## The building stands in bays across the front. Knocking a bay's column out
## drops that bay's stack; the ORDER you do it in is the whole game, because
## every stack that falls shifts the load and the remainder leans.
## Wide enough that a big building is wider than the crane's reach from one
## spot. That is the whole reason the crane can move: at 2.6 every bay of every
## building was reachable from the middle, so parking was decoration and a
## policy that never moved scored identically to one that worked the site
## properly. Measured, on all four policies, at all six levels.
const BAY_WIDTH := 3.2
const FLOOR_HEIGHT := 3.1
const FACE_Z := 6.0               ## the near face of the building
const BUILDING_DEPTH := 5.2

const BAYS_MIN := 3
const BAYS_MAX := 7
const FLOORS_MIN := 4
const FLOORS_MAX := 9

# --- the crane ------------------------------------------------------------
#
# Unchanged from the street version, deliberately. The control is the part of
# that build that was working: the turret slews to where the thumb drags, the
# ball trails the boom as an underdamped spring, and reach comes from how fast
# the ball is travelling round rather than from where the boom points.
# Pointing at a column is not enough - the ball has to be moving.

const BOOM := 3.2                 ## turret to ball at rest
const PIVOT_Y := 6.4
const BALL_RADIUS := 1.05

const YAW_MAX := 1.18             ## radians either side of straight ahead
const YAW_GAIN := 3.2
const MAX_SLEW := 2.7
const YAW_RATE := 9.0

const BALL_PULL := 9.0            ## the ball's spring toward the boom
const BALL_DAMP := 1.55           ## underdamped: it arrives late and swings past

const RADIUS_GAIN := 0.62         ## metres of reach per rad/s of bearing speed
const RADIUS_RATE := 7.0
const RADIUS_MAX := 8.6

const REBOUND := 0.70
const REBOUND_MIN := 1.75

## How wide a column is to hit. Tight on purpose: at half a bay width plus the
## ball, the ball landed anywhere in the bay and counted, so being roughly
## right was as good as being right and there was nothing to aim at.
const COLUMN_HALF_WIDTH := 0.55

## A ball drifting into a column does nothing; a swinging one breaks it. This
## is what stops the crane being a cursor, and it is the same constant that
## stopped a hanging ball clearing barricades in the street build - kept
## because it was doing real work there.
const STRIKE_MIN_SWING := 0.9     ## rad/s of |bearing_vel| needed to land a strike
const STRIKE_COOLDOWN := 0.35     ## seconds before the same column can be hit again

# --- the crane's own position ---------------------------------------------

## The crane can reposition along the site, and that is what the swipe does.
## It is not decoration: the outer bays of a wide building cannot be reached
## from the middle, so where you park is a decision made several times a demo.
const LANES := [-4.2, 0.0, 4.2]
const START_LANE := 1
const RIG_HALF_WIDTH := 1.1
const STEER_GAIN := 3.4
const MAX_STEER_SPEED := 7.5
const STEER_RATE := 11.0

# --- what a demolition costs and pays -------------------------------------

## Swings are the whole risk. A wasted strike is one you do not have for the
## column you needed it on, and running out with the building still standing is
## how a demo fails - rather than by any hazard, which is what the street
## version was missing.
##
## The budget is DERIVED from the building rather than set as a rate. It was a
## flat 3 per bay, which happened to be less than the columns actually needed
## once they varied and grew with the level: at five bays of four hit points it
## gave 17 swings for a job needing 20, so the last two buildings were
## arithmetically unwinnable however well they were played. A budget that has
## to be kept in step with the content by hand will drift out of step with it.
##
## So: exactly enough to break every column, plus a few. The margin IS the
## difficulty, and it is the same margin at every size.
const SWINGS_SPARE := 4

## Columns are NOT all the same, and that is a design decision rather than
## flavour. With every column identical, sweeping the boom symmetrically across
## the front produces a symmetric collapse by accident - so a policy that never
## looked at the building scored higher than one that worked it properly.
## Varying them means the weak bays fall wherever they happen to be, and the
## player has to choose which column to work and, more interestingly, which one
## to LEAVE because dropping it now would unbalance the rest.
const COLUMN_HP_BASE := 2
const COLUMN_HP_SPREAD := 2       ## extra hp a column may have, 0 to this
const RUBBLE_PER_FLOOR := 10
const CLEAN_DROP_BONUS := 250     ## for putting all of it inside the footprint
const SWING_SAVED_BONUS := 25     ## per swing not needed

# --- leaning, which is the thing that goes wrong --------------------------

## Every stack that falls shifts the load toward the side it fell on. Drop the
## bays down one side and the remainder leans until it goes over, onto the
## block next door, and the demo is a failure however much came down.
##
## The gauge on the HUD is a direct reading of this number rather than a scaled
## one, because a gauge that has to be explained is a gauge that gets ignored.
##
## Both limits are derived, not chosen. With bays at even spacing the centroid of what is
## still standing can only take a handful of values, so these were solved
## against them rather than picked:
##
##   3 bays, one outer gone   -> 0.50   under the limit: street one is safe
##   5 bays, three down one side -> 0.75   over it: a one-sided demo kills you
##   7 bays, five down one side  -> 0.83   over it
##   any width, worked alternately -> 0.00 clean
##
## So 0.72 is the smallest number that punishes working along one side at five
## bays while leaving the three-bay building survivable, and 0.45 is under the
## 0.50 that a single outer drop costs - which is what makes "start in the
## middle" a real decision on the very first building.
const TOPPLE_LIMIT := 0.72
const LEAN_WARN := 0.45           ## a clean drop never goes above this

## How quickly a lean settles as the load re-centres. Not instant, and not
## never: a building that forgives nothing turns the first bad swing into a
## finished run, and a gauge you cannot steer back from is a death sentence
## with a delay rather than a decision.
const LEAN_SETTLE := 2.2          ## per second, toward the current imbalance


static func bays_for(level: int) -> int:
	return clampi(BAYS_MIN + (level - 1) / 2, BAYS_MIN, BAYS_MAX)


static func floors_for(level: int) -> int:
	return clampi(FLOORS_MIN + (level - 1), FLOORS_MIN, FLOORS_MAX)


static func column_hp_for(level: int) -> int:
	return COLUMN_HP_BASE + (level - 1) / 3


## This bay's column, which is keyed on the place so a given building is the
## same building every time it is played, on any device.
static func column_hp_at(level: int, bay: int) -> int:
	var roll := SimUtil.hash2(bay, 701 + level)
	return column_hp_for(level) + int(floor(roll * float(COLUMN_HP_SPREAD + 1)))


## The swing budget: exactly what this building's columns need, plus the spare.
## Never a rate - see the note beside SWINGS_SPARE for what that cost.
static func swings_for(level: int) -> int:
	var needed := 0
	for b in bays_for(level):
		needed += column_hp_at(level, b)
	return needed + SWINGS_SPARE


## Half the building's width, which is the arm the lean is measured against.
static func half_width(level: int) -> float:
	return maxf(BAY_WIDTH, float(bays_for(level) - 1) * 0.5 * BAY_WIDTH)


## Where a bay's centre sits, left to right.
static func bay_x(level: int, bay: int) -> float:
	return (float(bay) - float(bays_for(level) - 1) * 0.5) * BAY_WIDTH


## The ball's natural period against the boom. A quarter of it is how long
## after a slew the ball reaches its extreme - the lag the player leads, and
## the single number that decides how this feels.
static func swing_period() -> float:
	return TAU / sqrt(BALL_PULL)


static func ball_lag() -> float:
	return swing_period() * 0.25


## How far sideways the ball can get, from the outermost parking spot.
static func max_ball_reach() -> float:
	return absf(LANES[LANES.size() - 1]) + RADIUS_MAX * sin(YAW_MAX)


## The ball has to get PAST the face to touch a column, and its distance from
## the crane falls away as it swings round - so reach across the front and
## reach into the building trade against each other. This is the furthest
## sideways the ball can be while still deep enough to strike, and it is the
## number that decides whether the widest building is playable at all.
static func reach_at_face() -> float:
	if RADIUS_MAX <= FACE_Z:
		return 0.0
	return sqrt(RADIUS_MAX * RADIUS_MAX - FACE_Z * FACE_Z)


## Where the centre of the ball sits. A function so the renderer and the
## collision cannot disagree about it.
static func ball_height(bearing: float) -> float:
	return 3.0 - 0.55 * absf(sin(bearing))
