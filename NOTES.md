# Notes — Wrecking Crew

Decisions specific to this game, and what to do next in it. General lessons belong in
`C:\dev\gamedev-notes`, not here.

> **Rewritten on 2026-09-12 against the shipped code.** Until then this file described the
> v0.3.0 above-ground demolition - bays, a fixed swing budget, a lean that is the centroid of
> what is still standing, topple at 0.72, a clean bonus under 0.45 - and `src/` has contained
> none of that since 0.4.0. Its measurements have NOT been deleted; they are kept in
> "Superseded measurements" at the bottom, dated and labelled as measuring a game that no
> longer exists, because a measurement is expensive and a future session may want to know what
> the old numbers were.
>
> Everything above that section is either read out of the code or arithmetic done on constants
> that are in the code, and says which. **Godot could not be run while this was written**, so
> nothing here is a fresh reading of a live build; where a claim would need one, it says
> UNVERIFIED.

## Why this game is what it is

Four shapes in two days, and the reason each one changed is worth keeping - except for the
last one, where there is no reason on record at all.

1. **A lane runner** (0.1.x). The ball was driven by the rig's lateral acceleration. Aiming was
   the whole game and you could not see yourself aim.
2. **A crane runner** (0.2.x). The turret slewed to the thumb, on his ask: *"it would be more
   fun if the main goal was to rotate the crane part to hit the buildings"*. Legible, and it
   bought the one thing that mattered - a policy that never touched the crane scored **exactly
   zero**, against 138 before - but the buildings were still things you drove past, so hitting
   them was optional and there was no risk anywhere.
3. **An above-ground demolition** (0.3.0), on his note: *"there isn't really a risk or reward
   yet... I want to focus on the breaking part and don't know if this forward lane style game
   is the best option."* He was right, and it was not a balance problem: in a runner the
   buildings are scenery you pass, passing is free, and no tuning makes optional destruction
   necessary.
4. **The basement** (0.4.0, and what ships today). A parking level under a slab: drive a
   tracked machine, swing a real chain, take the columns out, then get out yourself.

**The move from 3 to 4 changed the genre and has no quote and no note behind it.** There is no
line from Gideon asking for it, no entry in this file from the session that did it, and the
commit message (`82754b9`, "Down in the basement: drive a machine, swing a real chain, get
out") only describes it. It is the one change on this project not traceable to a measurement
or to something he said. **UNKNOWN why it was made** - do not reconstruct a reason for it, and
if the basement turns out to be the wrong game, note that nothing was ever recorded about why
the old one was abandoned.

The crane, the lag, the pure-simulation core and the whole test stack came across all four
times, which is what the pure-simulation core was for.

## The design

The six-point statement of what the game is now lives in `CLAUDE.md` and is not repeated here.
This file is the decisions and the numbers behind it.

## What is measured, as of 2026-09-12 (v0.4.2, the basement)

**The goldens** (`test/test_golden.gd`, committed constants, level 2, read out of the file -
not re-run here). Four whole runs, each failing for a different, legible reason:

| policy | rubble | columns | walls | integrity | hits | peak ball | ends at | outcome |
|---|---|---|---|---|---|---|---|---|
| `PASSIVE` — touches nothing | 0 | 0 | 0 | 1.000 | 0 | 0.0 | 60.0 s | still standing; there is no clock until you start one |
| `NUDGER` — creeps at a quarter throttle | 0 | 0 | 0 | 1.000 | 1 | 11.093 | 60.0 s | one contact in a minute, and nothing broken: speed is the damage |
| `GREEDY` — wrecks well, never leaves | **1030** | 8 | 2 | 0.329 | 20 | 27.331 | 26.15 s | **crushed** (`escape_left` -0.013); all of it lost |
| `WRECKER` — wrecks well, gets out | 879 | 4 | 0 | 0.675 | 12 | 27.331 | 16.15 s | **won**, out with 9.987 s to spare |

`GREEDY` banks more rubble than `WRECKER` and loses anyway. **What the escape buys is not more
rubble, it is keeping the rubble you have** - and the two policies share every line of code and
differ in one boolean, so the pair is a measurement of the decision rather than of two bots.

**Arithmetic on the shipped constants** (computed here from `tuning.gd`; each is checked in
`test_tuning.gd` as a relationship rather than as a value):

- **Pendulum period `2*PI*sqrt(CHAIN/SWING_G)` = 2.39 s** on a 4.2 m chain at `SWING_G` 29.0.
  The lag the player leads is a consequence of that, not a tuned constant. **UNKNOWN what lead
  time it reads as in the hand** - nobody has played it.
- **The escape is genuinely escapable.** Far corner to the ramp is `hypot(19.0, 33.0)` = 38.08 m,
  4.01 s at `DRIVE_MAX` 9.5. `escape_margin` is 8.99 s at level 1, 5.53 s at level 6, and floors
  at 2.99 s from level 12 on, because `escape_seconds_for` never goes below 7.0.
- **Total support is 12.83**: twelve columns at 1.0 plus `expected_walls()` 3.78 panels at 0.22.
  So `COLLAPSE_AT` 0.7 is **four columns** (integrity 0.688 with four down), which is what
  `WRECKER` does. Solving the `WRECKER` and `GREEDY` goldens backwards says the level-2 basement
  has **three** infill panels, fewer than the 3.78 the gauge normalises against - which is
  exactly why `integrity` is clamped to 1.0.
- **A column is about two and a half solid passes**: `damage_at(0.8 * HIT_FULL_SPEED)` = 30.93
  against `COLUMN_HP` 78.0. Level 2 is 88.9 and level 5 is 131.7 on `LEVEL_HP_STEP` 1.14.
- **A pivot on the spot is a real attack**: `TURN_RATE` 2.3 on a 7.8 m arm gives 17.94 m/s, past
  `HIT_FULL_SPEED` 11.0, so a boxed-in machine has something to do. It is bounded the other way
  by `BOOM_LEN + CHAIN` 7.8 < `BAY` 8.6 - a machine spinning where it stands cannot reach the
  next column along, so driving is not optional.
- **The room is bigger than the swing**: reach 8.8 m against a half-deck of 19.0 across and 16.5
  deep.
- A basement takes **20 to 50 seconds** (recorded in the 0.4.1 changelog entry, against 8 s
  before the columns were toughened). UNVERIFIED against the current build.

**Test counts, counted from the source rather than from a run:** 71 test functions in seven
pure suites - `test_sim` 26, `test_tuning` 16, `test_golden` 9, `test_util` 8, `test_controls`
6, `test_sim_boundary` 3, `test_version` 3 - plus `run_smoke.gd` and `run_probe.gd`.
**UNVERIFIED: the assertion count and the runtime.** The old figure of "57 tests / 4,567
assertions / 40 smoke assertions" in this file measured the v0.3.0 suite and has been moved
below with the rest of that build's numbers.

## Things that were built, measured, and removed or changed

Kept so they are not rediscovered as good ideas. The reasons are in the comments beside the
constants in `src/sim/tuning.gd`; the numbers are theirs.

1. **Twenty columns.** The best bot took nine down in two minutes and never reached the
   threshold, so the level had no ending in it - a content decision masquerading as a balance
   one. Twelve (`GRID_X` 4 by `GRID_Z` 3) makes a basement about a minute of work.
2. **A collapse threshold of 0.45**, which needed seven of twelve columns down while the best
   policy managed five in two and a half minutes. A threshold nobody can cross is not
   difficulty, it is a level with no exit. **The comment beside `COLLAPSE_AT` explains a value
   of 0.6 ("at 0.6 it takes five") and the constant is 0.7, which takes four. UNKNOWN why the
   last step was taken** - it is not recorded anywhere.
3. **A 5.2 m chain on a 4.6 m boom.** Nearly ten metres of reach, spent mostly at full stretch:
   a chain long enough that taut is the normal state stops being a chain and becomes a rigid
   arm with a hinge. 4.2 on a 3.6 m boom swings.
4. **`TURRET_SLEW` at 1.7 rad/s**, which added 13 m/s to the ball on its own and made the
   turret, rather than the driving, the fastest way to build a swing - when the driving is
   meant to be the wind-up. 1.15 now, and a slider is far less twitchy at it.
5. **`BALL_DRAG` at 0.55.** A swing was dead inside two seconds and every hit had to be set up
   from nothing. 0.16 is the fix for "it doesn't have enough momentum".
6. **A constant-magnitude pull toward the boom tip** instead of a pendulum. A constant force
   does not care how far out the ball is, so once the ball was out it stayed out, and there was
   no period at all.
7. **`BALL_MAX_SPEED` at 34.** It clamped during ordinary hard driving, which hides the runaway
   it exists to catch - and a position constraint really can inject energy: it measured **216
   m/s** on a machine that cannot exceed 9.5. At 60 it never fires in normal play, so its
   firing is a signal. The real fix was deriving the ball's velocity from actual displacement.
8. **`WALL_CAPACITY` defined and never read**, for one build: `integrity` counted columns only.
   A constant that exists and does nothing is worse than no constant, because it reads as a
   decision that was made.
9. **A 45 per cent throttle floor through a turn.** The machine drove through its own turns and
   every change of direction came out as a long curving arc, which under a camera that holds
   still reads as sliding. `ALIGN_CONE` at zero throttle is the difference between a tracked
   machine and a car.

## Known gaps / next, roughly in order

1. **Nobody has played the basement.** Every quote in
   `C:\dev\gamedev-notes\playtests\wrecking-crew.md` is about the runner or the crane runner.
   Whether the support gauge is readable while driving, whether the escape clock bites or nags,
   whether pivot-then-go is satisfying in the hand - all unverified. **Play it before tuning
   it.**
2. **The building does not visibly fall.** Columns and walls stop being drawn and debris comes
   off them; there is a slab pool and a dust emitter, but nothing that reads as a structure
   coming down. This is the single biggest thing the game is missing and it is what going
   native was for: pre-fractured slabs becoming rigid bodies on collapse. **Physics may only
   ever be cosmetic** - see the note at the top of `sim.gd`.
3. **No audio at all.** Nothing is loaded and nothing is played. An action with no sound reads
   as not having happened, and a wrecking ball is the easiest sound design in any of these
   games.
4. **No end-of-site summary.** A banner and a rubble readout, and on to the next basement. It
   wants the haul, the seconds saved and the columns taken, which are the three things the
   player was actually managing.
5. **Every column is worth the same**, so "which one next" is only ever a support question.
   Differentiated targets would make it a richer one.
6. **No yard**: no salvage, no upgrades - a longer boom, a heavier ball. Deliberately not built
   before the core is known to be fun.
7. **No shell**: no title, no settings, no pause, no erase-progress. `POLISH.md` wants all four.
8. **No self-hosted type.** Everything is the Godot default at an overridden size.
9. **No replay scenarios.** `test/replays/` does not exist, so `/playtest` has nothing to film
   and `movie.ps1` has nothing to play.
10. **No asset provenance.** Three files in `assets/` with no `CREDITS.md` and no licence
    recorded for any of them, which `ASSETS.md` requires. The HDRI's name matches a Poly Haven
    file; that is an inference, not a record.
11. **The save is not round-tripped.** It lives in `main.gd` (`user://wrecking-crew.save`),
    which `INDEX.md` rule 2 permits, but there is no pure `state → Dictionary → state` pair and
    no round-trip test, which rule 2 requires.
12. **CI has no `play` job.** This repo was scaffolded sixteen minutes before the template grew
    one.
13. **No release keystore and no Play listing.** Direct APK from a GitHub Release for now;
    `PRIVACY.md` was added 2026-09-12.

## Things this repo does that the template does not

Worth folding back into `godot-template` when convenient:

- `test/policies.gd` - scripted players as a first-class file rather than a closure inside the
  golden.
- `test/run_probe.gd` - a balance probe that prints and cannot fail.
- `TestHarness.FLOAT_EPS` - a golden over floats cannot use exact equality.
- The smoke test's **screen-right assertion**, and `test/test_controls.gd` behind it: the only
  things that catch inverted steering on a chase camera.

---

## Superseded measurements: the v0.3.0 above-ground demolition (2026-09-08)

**These numbers measure a game that no longer exists.** v0.3.0 was one condemned building seen
from outside, worked from a crane with a fixed number of swings; the load shifted as bays came
down, the lean was the centroid of what was still standing, and the payout was a clean drop.
`src/sim/sim.gd` has had no lean, no centroid, no bay toppling and no swing budget since
v0.4.0 replaced it on the same day. Nothing here is a live reading of anything, and none of it
should be used to tune the basement. It is kept because measuring is expensive and a future
session may want to know what the old numbers were - and because if the basement is ever
abandoned in turn, this is what the game before it was worth.

Over six sites, each policy playing the whole demolition:

| policy | mean rubble | sites won | why it loses |
|---|---|---|---|
| `passive` — touches nothing | 0 | 0/6 | nothing happens; there is no clock |
| `reckless` — works from one end | 283 | 4/6 | topples on the wide ones, never clean |
| `waver` — swings blindly, never moves | 450 | 4/6 | cannot reach the outer bays |
| `demolisher` — balanced order | **623** | **6/6** | — |

Every policy failed for a different, legible reason, which was the first time that had been
true on this project. `demolisher` against `reckless` was the pair that mattered: same control,
same effort, same building down - 2.2x the money, for the order alone. (The four policies in
the repo today are `PASSIVE`, `NUDGER`, `GREEDY` and `WRECKER`, and none of them is one of
these.)

Other v0.3.0 numbers:

- Ball period **2.09 s**, so the lag you led was about **0.52 s**. (The basement's chain gives
  2.39 s; the old figure does not apply to it.)
- At rest the ball reached **3.2** and the building face was at **6.0**. Pointing was not
  hitting.
- Reach at the face **6.16** against a widest half-width of **9.6** - so the widest building
  genuinely needed the crane moved.
- The lean values were quantised by the geometry, so the thresholds were solved rather than
  picked: 3 bays with one outer gone is 0.50; 5 bays with three down one side is 0.75; any width
  worked alternately is 0.00. Hence topple at 0.72, clean under 0.45.
- **57 pure tests / 4,567 assertions in about a second; 40 smoke assertions.**

Removed or changed during the runner and above-ground eras, kept so they are not rediscovered
as good ideas:

1. **The ball-height rule** (runner era). The ball rose as it swung, so it could only damage
   what it was not sailing over. No middle setting: inert at one size, and it made the whole
   first street immune at the other.
2. **A faster pendulum** (runner era). Measured 24% worse for the aiming bot - a faster swing
   needs tighter timing, so it rewards the policy that ignores the level.
3. **A flat swing budget** (v0.3.0). Three per bay drifted out of step the moment columns
   varied: five bays of four hit points got 17 swings for a job needing 20, so the last sites
   were arithmetically unwinnable. The budget was derived from the actual columns after that.
4. **A saturating reach** (v0.3.0). Gain 1.75 with a cap of 11 left the radius PINNED at the cap
   for most of a sweep, so the ball blanketed twice the width of the street and could not miss.
   A value clamped at the top of its range is only a mechanic in the part it moves through.
5. **Uniform columns** (v0.3.0). With every column identical, a symmetric sweep produced a
   symmetric collapse by accident, and a policy that never looked at the building scored top.
6. **Recording the lean while a lone bay stood** (v0.3.0), which put every demolition at 1.00
   and made the clean bonus unearnable by anybody.
