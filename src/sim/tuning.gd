class_name Tuning
extends RefCounted

## Every number that shapes how it feels, in one place, plus the arithmetic
## derived from it.
##
## Pure: nothing here reads live state. That is what lets `test/` check the
## shape of the curves - which is what a balance change accidentally breaks -
## without booting a game.
##
## The game in one sentence: you are in the basement of a condemned tower with
## a wrecking machine, and you take out the columns holding it up until it
## starts coming down - and then you have to get out.

# --- the deck -------------------------------------------------------------
#
# A parking level: a grid of columns under a slab, with infill walls between
# some of them and a ramp out at one end. Everything is on one storey, because
# the player never leaves the floor they are standing on.

const DECK_W := 38.0              ## across
const DECK_D := 33.0              ## front to back
const CEILING := 4.6              ## slab soffit height
const WALL_MARGIN := 1.2          ## how far the perimeter sits outside the grid

## Twelve columns, not twenty. At twenty, the best bot took down nine in two
## minutes and never reached the threshold that starts the collapse - so the
## level had no ending in it, which is a content decision masquerading as a
## balance one. Twelve makes a basement about a minute of work.
const GRID_X := 4                 ## columns across
const GRID_Z := 3                 ## columns deep
const BAY := 8.6                  ## metres between column centres

const COLUMN_RADIUS := 0.62
const WALL_THICK := 0.45

## The way out. A demolition where you cannot be caught by the thing you
## started is a sandbox; this is the corner that turns it into a run.
const RAMP_W := 7.0
const RAMP_DEPTH := 5.0

# --- the machine ----------------------------------------------------------

const RIG_RADIUS := 1.5
const DRIVE_ACCEL := 13.0         ## metres per second per second
const DRIVE_MAX := 9.5
const DRIVE_DRAG := 2.4           ## per second, when the stick is released
const DRIVE_REVERSE := 0.45       ## fraction of forward speed, going backwards

## Turning is speed-dependent, the way a tracked machine turns - but only
## mildly, and that mildness is load bearing.
##
## At 2.5 rad/s on the spot, spinning in place whipped the ball at 24 m/s while
## driving flat out only managed 9.5 - so the best strategy was to stand still
## and rotate, which is neither what the game is about nor any fun. The two
## numbers now put a fast pass with a turn at about 19 m/s against a standing
## spin at 12, so driving is the technique and spinning is the fallback.
const TURN_RATE := 1.2            ## radians per second at a standstill
const TURN_AT_SPEED := 0.8        ## multiplier once at DRIVE_MAX

## Dead zone on the drive stick. Without one a virtual stick reads every
## tremor and the machine wanders; this is the single most-cited fix for touch
## controls feeling twitchy.
const STICK_DEADZONE := 0.14

# --- the crane ------------------------------------------------------------
#
# The boom slews on the machine, and the ball hangs from its tip on a chain
# that cannot stretch. Nothing pulls the ball toward a target - it goes where
# momentum takes it, and the ONLY way to move it is to move the thing it is
# attached to. That is the whole feel of the game: the vehicle is the wind-up.

const BOOM_LEN := 4.6             ## turret to boom tip
const BOOM_HEIGHT := 5.4
const CHAIN := 5.2                ## boom tip to ball, and it does not stretch
const BALL_RADIUS := 1.0

## A guard, not a mechanic. The chain is solved as a position constraint and a
## position constraint can inject energy if anything moves the ball without
## that motion being accounted for - which happened, and measured 216 m/s on a
## machine that cannot exceed 9.5. The velocity is now derived from actual
## displacement so it cannot happen by construction, and this exists purely so
## that if it ever does, it fails loudly at a number a test can catch rather
## than quietly making a crawling policy the best one in the game.
const BALL_MAX_SPEED := 34.0

const TURRET_MAX := 2.35          ## radians either side of straight ahead
const TURRET_GAIN := 3.4
const TURRET_SLEW := 1.7          ## radians per second
const TURRET_RATE := 9.0

## What the chain does when it goes taut. Some of the ball's outward speed is
## returned rather than absorbed, which is what makes a hard turn crack the
## ball out sideways instead of just dragging it.
const CHAIN_BOUNCE := 0.22
const BALL_DRAG := 0.55           ## per second, so a swing dies if left alone
const BALL_SETTLE := 1.1          ## weak pull back under the tip

# --- breaking things ------------------------------------------------------

## Damage is the ball's SPEED, not a hit count. A ball drifting into a column
## does nothing; one whipped round at ten metres a second takes a chunk out.
## That is the whole reason the chain is inextensible and the vehicle drives
## freely - both exist to let the player build speed.
const HIT_MIN_SPEED := 3.2        ## below this the ball just clunks
const HIT_FULL_SPEED := 13.0      ## at and above this, maximum damage
## Per target, so a single pass through a column is a hit rather than one per
## frame - which would make damage a function of the frame rate, the one thing
## a golden cannot survive. Short enough that a slow orbit round one column
## lands several.
const HIT_COOLDOWN := 0.16

const COLUMN_HP := 40.0
const WALL_HP := 24.0
const HIT_DAMAGE := 60.0          ## at HIT_FULL_SPEED

## What each thing was carrying. A column holds the slab up; a wall panel is
## mostly infill and barely does - so both are worth breaking, but only one of
## them really moves the gauge, and the player learns which by watching rather
## than by being told.
##
## WALL_CAPACITY was defined and then never read for one build: `integrity`
## counted columns only. A constant that exists and does nothing is worse than
## no constant, because it reads as a decision that was made.
const COLUMN_CAPACITY := 1.0
const WALL_CAPACITY := 0.22

const COLUMN_RUBBLE := 120
const WALL_RUBBLE := 35

# --- coming down ----------------------------------------------------------

## How much of the original support has to go before the slab lets go.
##
## 0.45 for one measured build, which needed seven of twelve columns down - and
## the best policy managed five in two and a half minutes, so no level ever
## reached its own ending. A threshold no one can cross is not difficulty, it
## is a level with no exit. At 0.6 it takes five, which is also about what
## losing forty per cent of your columns would really do to a building.
const COLLAPSE_AT := 0.7

## Seconds to reach the ramp once it starts. Measured against the diagonal of
## the deck at full speed - see escape_margin(), which is asserted rather than
## eyeballed, because "can the player actually get out" is the one number that
## turns this from a tense run into an unfair one.
const ESCAPE_SECONDS := 13.0

const ESCAPE_BONUS_PER_SECOND := 40
const TOTAL_TEARDOWN_BONUS := 400  ## for taking every column out before leaving

# --- how it scales --------------------------------------------------------

const LEVEL_HP_STEP := 1.14       ## columns get tougher
const LEVEL_ESCAPE_STEP := 0.94   ## and the way out gets tighter


static func column_hp_for(level: int) -> float:
	return COLUMN_HP * pow(LEVEL_HP_STEP, level - 1)


static func wall_hp_for(level: int) -> float:
	return WALL_HP * pow(LEVEL_HP_STEP, level - 1)


static func escape_seconds_for(level: int) -> float:
	return maxf(7.0, ESCAPE_SECONDS * pow(LEVEL_ESCAPE_STEP, level - 1))


## Where a column stands. The grid is centred on the deck.
static func column_x(col: int) -> float:
	return (float(col) - float(GRID_X - 1) * 0.5) * BAY


static func column_z(row: int) -> float:
	return (float(row) - float(GRID_Z - 1) * 0.5) * BAY


## The middle of the ramp mouth, at the back of the deck.
static func ramp_z() -> float:
	return -DECK_D * 0.5


## Damage from a given impact speed, 0 to HIT_DAMAGE.
##
## Ramped rather than thresholded: a glancing blow should do something, or the
## player cannot tell a near miss from a miss. Squared, so the difference
## between a lazy swing and a committed one is felt rather than merely counted.
static func damage_at(speed: float) -> float:
	if speed <= HIT_MIN_SPEED:
		return 0.0
	var t := clampf((speed - HIT_MIN_SPEED) / (HIT_FULL_SPEED - HIT_MIN_SPEED), 0.0, 1.0)
	return HIT_DAMAGE * t * t


## The worst case the player can be asked to escape: the far corner of the deck
## to the ramp, at full speed, with a little left over for turning around.
##
## Computed rather than eyeballed. "Can the player actually get out" is the one
## number that decides whether the collapse is tense or unfair, and it is the
## kind of relationship that silently stops being true when the deck grows.
static func escape_margin(level: int) -> float:
	var corner := Vector2(DECK_W * 0.5, DECK_D * 0.5)
	var ramp := Vector2(0.0, ramp_z())
	var run := corner.distance_to(ramp)
	return escape_seconds_for(level) - run / DRIVE_MAX


## How much support the deck starts with, so `integrity` is a fraction.
## The deck's full support, columns and infill together. Walls are counted so
## the gauge is a reading of the whole structure - a player who spends a minute
## on panels should see SOMETHING move, just far less than a column moves it.
static func total_capacity() -> float:
	return float(GRID_X * GRID_Z) * COLUMN_CAPACITY + expected_walls() * WALL_CAPACITY


## How many infill panels a deck has, on average. Used only to normalise the
## gauge, so it does not need to be exact - but it does need to exist, or a
## basement with more panels than usual would start below 100%.
static func expected_walls() -> float:
	return float(GRID_Z * (GRID_X - 1)) * 0.42


## Turn rate at a given speed. Quick on the spot, lazy at speed.
static func turn_rate_at(speed: float) -> float:
	var t := clampf(absf(speed) / DRIVE_MAX, 0.0, 1.0)
	return TURN_RATE * lerpf(1.0, TURN_AT_SPEED, t)
