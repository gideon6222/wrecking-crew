# Notes — Wrecking Crew

Decisions specific to this game, and what to do next in it. General lessons belong in
`C:\dev\gamedev-notes`, not here.

## Why this game

The first real game on the Godot stack. It has been through three shapes in one day, and
the reason is worth keeping because each change came from a measurement or from Gideon:

1. **A lane runner** where the ball was driven by the rig's lateral acceleration. Aiming was
   the whole game and you could not see yourself aim.
2. **A crane runner** where the turret slewed to the thumb. Legible, and it bought the one
   thing that mattered - a policy that never touched the crane scored *exactly zero* - but
   the buildings were still things you drove past, so hitting them was optional and there
   was no risk anywhere.
3. **A demolition game**, on Gideon's note: *"there isn't really a risk or reward yet... I
   want to focus on the breaking part and don't know if this forward lane style game is the
   best option."* He was right, and it was not a balance problem. In a runner the buildings
   are scenery you pass; passing is free; no tuning makes optional destruction necessary.

Now each site is one building, you have a fixed number of swings, and the order you take the
columns in decides whether it folds into its own footprint or goes over onto the block next
door. The crane, the lag, the dial and the whole test stack came across all three times,
which is what the pure-simulation core was for.

## The design, in the order it has to be understood

1. **The turret slews to where the thumb drags; the ball trails the boom** as an underdamped
   spring, arriving about half a second late and swinging past. That lag is what you lead.
2. **Pointing at a column is not enough.** At rest the ball hangs 3.2 m out and the face is
   at 6.0, so the ball only reaches the building once it is actually travelling round. Reach
   is a consequence of speed, never a constant - a design test asserts both directions.
3. **Reaching ACROSS the site and reaching INTO the building trade against each other**,
   because the ball's distance from the crane falls away as it swings round. That is why the
   crane can move, and why a wide building cannot be worked from one spot.
4. **Every bay you drop shifts the load.** The lean is the centroid of what is still
   standing; past 0.72 it goes over. Working along one side is what kills you.
5. **A lone bay never topples.** Without that clause no building could ever be finished, in
   any order, because the last bay standing reads as a maximum lean by definition.
6. **The clean bonus is judged on the WORST lean reached**, not the final one - at the end
   there is nothing left to be off-centre, so a bonus keyed on the final reading would pay
   out for every demolition including the reckless ones.

## What is measured, as of 2026-09-08

Over six sites, each policy playing the whole demolition:

| policy | mean rubble | sites won | why it loses |
|---|---|---|---|
| `passive` — touches nothing | 0 | 0/6 | nothing happens; there is no clock |
| `reckless` — works from one end | 283 | 4/6 | topples on the wide ones, never clean |
| `waver` — swings blindly, never moves | 450 | 4/6 | cannot reach the outer bays |
| `demolisher` — balanced order | **623** | **6/6** | — |

Every policy fails for a *different, legible* reason, which is the first time that has been
true on this project. `demolisher` against `reckless` is the pair that matters: same control,
same effort, same building down - 2.2x the money, for the order alone.

Other measured numbers worth not re-deriving:

- Ball period **2.09 s**, so the lag you lead is about **0.52 s**.
- At rest the ball reaches **3.2** and the face is at **6.0**. Pointing is not hitting.
- Reach at the face **6.16** against a widest half-width of **9.6** - so the widest building
  genuinely needs the crane moved.
- The lean values are quantised by the geometry, so the thresholds were solved rather than
  picked: 3 bays with one outer gone is 0.50; 5 bays with three down one side is 0.75; any
  width worked alternately is 0.00. Hence topple at 0.72, clean under 0.45.
- 57 pure tests / 4,567 assertions in about a second; 40 smoke assertions.

## Things that were built, measured, and removed or changed

Kept here so they are not rediscovered as good ideas.

1. **The ball-height rule** (runner era). The ball rises as it swings, so it could only
   damage what it was not sailing over. No middle setting: inert at one size, and it made
   the whole first street immune at the other.
2. **A faster pendulum** (runner era). Measured 24% worse for the aiming bot - a faster swing
   needs tighter timing, so it rewards the policy that ignores the level.
3. **A flat swing budget.** Three per bay drifted out of step the moment columns varied: five
   bays of four hit points got 17 swings for a job needing 20, so the last sites were
   arithmetically unwinnable. The budget is now derived from the actual columns.
4. **A saturating reach.** Gain 1.75 with a cap of 11 left the radius PINNED at the cap for
   most of a sweep, so the ball blanketed twice the width of the street and could not miss.
   A value clamped at the top of its range is only a mechanic in the part it moves through.
5. **Uniform columns.** With every column identical, a symmetric sweep produced a symmetric
   collapse by accident, and a policy that never looked at the building scored top.
6. **Recording the lean while a lone bay stood**, which put every demolition at 1.00 and made
   the clean bonus unearnable by anybody.

## Known gaps / next, roughly in order

1. **He has not played the demolition.** Everything about how it FEELS is unverified -
   whether the lean gauge is readable while aiming, whether a clean drop feels earned,
   whether the swing budget bites or just nags.
2. **The building does not visibly fall.** A bay's cells stop being drawn and debris comes
   off the whole height, which is legible but not spectacular. This is the single biggest
   thing the game is missing, and it is what going native was for: pre-fractured floor slabs
   that become rigid bodies on collapse. **Physics may only ever be cosmetic** - see the
   note at the top of `sim.gd`.
3. **No audio at all.** An action with no sound reads as not having happened, and a wrecking
   ball is the easiest sound design in any of these games.
4. **No end-of-site summary.** A banner says CLEAN DROP or IT WENT OVER and moves on. It
   wants the haul, the swings saved and the worst lean, which are the three things the player
   was actually managing.
5. **Targets are not yet differentiated.** Every bay is worth its floors. Landmarks, or bays
   worth more, would make "which one next" a richer question than "which keeps it balanced".
6. **No yard.** No salvage, no upgrades - a longer boom, a heavier ball, a second parking
   spot. Deliberately not built before the core is known to be fun.
7. **No release keystore and no Play listing.** Direct APK from a GitHub Release for now.

## Things this repo does that the template does not

Worth folding back into `godot-template` when convenient:

- `test/policies.gd` — scripted players as a first-class file rather than a closure inside
  the golden.
- `test/run_probe.gd` — a balance probe that prints and cannot fail.
- `scripts/shot.gd` — a deterministic screenshot at a chosen second.
- `TestHarness.FLOAT_EPS` — a golden over floats cannot use exact equality.
- The smoke test's **screen-right assertion**, which is the only thing that catches
  inverted steering on a chase camera.
