# Wrecking Crew - plan

> **RECONSTRUCTED AFTER THE FACT. THIS PLAN WAS NOT WRITTEN BEFORE THE BUILD.**
>
> Wrecking Crew was scaffolded on 2026-09-08, a day before Framework v2 and sixteen
> minutes before the template grew its CI `play` job, so it never had the `/game-plan`
> gate. `INDEX.md` standing rule 3 requires a `PLAN.md` from the first commit and this
> repo had none, which the 2026-09-11 framework audit recorded in section 5.
>
> This file was assembled on 2026-09-12 from three sources and nothing else: the shipped
> code under `src/`, `test/` and `export_presets.cfg`; `src/changelog.gd`; and
> `C:\dev\gamedev-notes\playtests\wrecking-crew.md`, which is Gideon's words verbatim.
> **The milestone list below is a record of what exists, not a plan that was followed.**
> No design intent has been invented for it. Where the sources do not say, the section
> says UNKNOWN rather than guessing - and several do.
>
> **Two other repo documents are stale and this plan does not follow them.** `CLAUDE.md`
> and `NOTES.md` both still describe the v0.3.0 game - a condemned building above ground,
> bays, a fixed number of swings, a lean that is the centroid of what is standing, a
> topple threshold of 0.72 and a clean bonus under 0.45. **None of that is in the code.**
> `src/sim/sim.gd` has no lean, no centroid, no bay toppling and no swing budget; the
> shipped game is the v0.4.0 basement described below. `NOTES.md`'s measured policy table
> (`passive` / `reckless` / `waver` / `demolisher`, mean rubble 623) measures a game that
> no longer exists. Fixing those two files is owed and is not done here.

## Summary

**Fantasy:** you are alone in the basement of a condemned building with a tracked wrecking
machine, cutting the columns out from under a slab that is going to come down on you.

**Loop:** drive → build ball speed → break a column → the support gauge falls → below 70%
the slab lets go → run for the ramp before the clock runs out. The resource is *support
you have removed*; the decision is *one more column or leave now*; the consequence is that
everything you earned is lost if you are still under the slab.

**Engine:** Godot 4.7.2, native Android, real 3D. (Recorded, not decided here - the repo
was copied from `C:\dev\godot-template` in commit `d70b2d4`.)

**Reference:** none. There is no `REFERENCE.md` in this repo and no reference game is named
in any source. UNKNOWN whether one was consulted.

**The first minute:** UNKNOWN, and this is the single largest gap in this document. **Gideon
has never played the basement game.** Every quote in the playtest log predates v0.4.0. What
the code does in the first minute: the machine spawns in the widest clear gap on the front
row (`_clear_spawn_x`) with the ball hanging still, the support gauge reads 100%, and
nothing happens at all until the player drives - there is no clock and no pressure before
the first column goes. The golden for PASSIVE confirms it: sixty seconds, zero hits, zero
rubble, `over` still false.

**What you keep:** the rubble score, carried across sites by `next_site()`, and a best haul
in `user://wrecking-crew.save`. There is no collection, no ladder and no unlock.

**New technique:** UNKNOWN as a plan item. What the code actually does that no earlier game
here did: a wrecking ball as a **distance constraint solved in nine lines of arithmetic**
rather than a `RigidBody3D` on a `PinJoint`, so the whole demolition stays deterministic and
goldenable, with physics confined to debris and the falling slab, which decide nothing.

**His asks, expanded:** these are the five reports in the playtest log, all of them from the
runner and crane-runner eras. Each is recorded with what it actually became.

1. *"it would be more fun if the main goal was to rotate the crane part to hit the buildings"*
   → the turret slews to the thumb. Killed the accidental-hit problem: a bot that never
   touches the crane scored exactly zero afterwards, against 138 before.
2. *"The button icons don't line up with where you need to press. The icons are about .5
   inches too high."* → two separate faults, both fixed: `stretch/aspect = "expand"` keeps
   the base WIDTH so his 1080x2340 canvas was not the 1080x1920 the pads were laid out
   against, and the hit test scaled touches into a space of its own.
3. *"I would prefer having what looks like a joystick ... that you move to rotate the boom,
   then if you swipe below it, it moves the machine"* → built as a dial first, then, on his
   follow-up (*"the controls dont need to be a dial look ... it could just be a left and
   right joystick or slider"*), replaced by a horizontal slider. A dial is a two-dimensional
   control for a one-dimensional quantity.
4. *"there isn't really a risk or reward yet ... I want to focus on the breaking part and
   don't know if this forward lane style game is the best option."* → **this note changed
   the genre.** It was not a balance problem: in a runner the buildings are scenery you
   pass, passing is free, and no tuning makes optional destruction necessary. His own
   suggestion - breaking beams inside a larger building to collapse it - is the game now.
5. *"the driving controls almost feel backward"* and *"it doesnt seem locked to move forward
   and backward ... make it so that it works like a large machine on tracks ... if you hold
   right, it should automatically rotate itself to face right, then start moving"* → world-
   relative driving (`drive_dir`) replaced the throttle-and-steer pair, and an alignment cone
   (`ALIGN_CONE`, 0.65 rad) gives a true pivot-then-go instead of an arc.

**My additions:** none. Nothing is proposed in this document; it is a record.

**Assets:** see the Assets section. Three files, and that is the whole of it.

**Phases:** phase 1 (first playable) is complete and shipped as 0.4.2. Phase 2 and phase 3
are both largely unstarted - see Milestones.

## Player and controls

Portrait, two thumbs. Both controls are relative to the MACHINE, which is why the chase
camera is allowed to turn with it here when it could not in the runner versions.

| Verb | Gesture | Constants | What it looks like |
|---|---|---|---|
| Drive | Left virtual stick, dragged in any direction | `STICK_DEADZONE` 0.14, `DRIVE_ACCEL` 13.0 m/s², `DRIVE_MAX` 9.5 m/s, `DRIVE_DRAG` 2.4/s, `DRIVE_REVERSE` 0.45 | The stick is a world direction, not a heading. The machine pivots on the spot at `TURN_RATE` 2.3 rad/s until it is inside `ALIGN_CONE` 0.65 rad, then throttles up |
| Slew the boom | Horizontal slider, bottom right | `TURRET_MAX` ±2.35 rad, `TURRET_GAIN` 3.4, `TURRET_SLEW` 1.15 rad/s | Boom angle relative to the machine, so driving carries the whole assembly round |
| Swing | Not a control | `CHAIN` 4.2 m, `SWING_G` 29.0, `BALL_DRAG` 0.16 | **Nothing aims the ball.** It is a free point mass on an inextensible chain; you move it by moving the machine |

The lag the player leads is a consequence of the chain, not a tuned constant. UNKNOWN: the
period is not recorded anywhere for the basement build. The 2.09 s / 0.52 s figures in
`NOTES.md` are from v0.3.0 and do not apply.

## Systems

### The structure

Owns `columns`, `walls`, `columns_down`, `walls_down`, `rubble`. A `GRID_X` 4 by `GRID_Z` 3
grid of columns at `BAY` 8.6 m centres, with infill walls between some of them, inside a
`DECK_W` 38.0 by `DECK_D` 33.0 room under a `CEILING` 4.6 m soffit. Keyed on (place, level)
through `SimUtil.hash2`, so the same basement is the same basement every time - asserted by
`test_the_same_basement_is_the_same_every_time`.

Columns have `COLUMN_HP` 78.0 and are worth `COLUMN_RUBBLE` 120; walls have `WALL_HP` 40.0
and `WALL_RUBBLE` 35. **Walls are worth score and almost no support** (`WALL_CAPACITY` 0.22
against `COLUMN_CAPACITY` 1.0), which is the trade the gauge teaches without a tooltip, and
which `test_a_wall_is_easier_than_a_column_and_worth_less` asserts.

### Damage is speed

Owns nothing; reads `ball_speed()`. Below `HIT_MIN_SPEED` 3.2 m/s the ball clunks and does
nothing; at and above `HIT_FULL_SPEED` 11.0 it does the full `HIT_DAMAGE` 60.0, with
`HIT_COOLDOWN` 0.16 s between contacts. This is the claim the whole control scheme rests on
and it has two tests: `test_speed_is_what_does_the_damage` (design) and the NUDGER golden,
which creeps at a quarter throttle for a full minute and lands **one contact, zero columns,
zero rubble**.

### Support and the collapse

Owns `integrity` (1.0 → 0.0), `collapsing`, `escape_left`. Integrity is the fraction of the
original support capacity still standing. At `COLLAPSE_AT` 0.7 the slab lets go, `collapsing`
goes true and `escape_left` starts at `ESCAPE_SECONDS` 13.0. Shown as a gauge anchored centre-
top. Tests: `test_the_gauge_only_falls_when_something_falls`,
`test_the_collapse_starts_when_the_support_goes`.

### The way out

Reaching the ramp (`RAMP_W` 7.0, `RAMP_DEPTH` 5.0) while `collapsing` wins and pays
`ESCAPE_BONUS_PER_SECOND` 40 per second left, plus `TOTAL_TEARDOWN_BONUS` 400 for having
taken every column. The clock running out is `crushed()` and a loss. The ramp only counts
once the slab is coming down (`test_the_ramp_only_counts_once_it_is_coming_down`), and
`_blocks_ramp` refuses to place a wall across the mouth, because a level that is
unfinishable in a way the player cannot see is the worst kind of unfair.

**This is the decision the game is made of**, and the golden pair proves it is real: GREEDY
and WRECKER share every line of code and differ in one boolean.

### Level progression

`next_site()` keeps the score and nothing else. `LEVEL_HP_STEP` 1.14 makes columns tougher
and `LEVEL_ESCAPE_STEP` 0.94 tightens the escape, with
`test_the_escape_tightens_but_never_becomes_impossible` as the floor under it.

## Content ladder

**There is no content ladder.** Sites are procedural variations of one room on the two
constants above, forever. There are no named levels, no landmarks, no differentiated
targets, no unlocks and no salvage or upgrades. `NOTES.md` lists all of that as not built,
deliberately, before the core is known to be fun. UNKNOWN how many sites were ever intended.

## Presentation

- **Camera:** chase, behind the machine and looking along its own forward. Sim works in a 2D
  plane (x across, y into the room), mapped to world (x, height, -y) so depth runs along -Z.
  `run_smoke.gd` asserts the camera is behind and facing in. UNKNOWN: no FOV arithmetic for
  portrait is recorded anywhere.
- **World:** built entirely in code in `src/game/main.gd` (1,059 lines); `main.tscn` is four
  lines, one node with the script. Columns, walls, debris and slab are MultiMesh pools
  (24 / 24 / 240 / 48) with a `GPUParticles3D` dust emitter.
- **Light and sky:** a real captured environment - `abandoned_parking_1k.hdr` as a
  `PanoramaSkyMaterial`, with ambient and reflected light both sourced from the sky.
- **HUD:** a support gauge anchored centre-top (two `ColorRect`s), a rubble readout at 60 px,
  a status label and a banner. Left stick and right slew slider at the bottom.
- **Shell:** none. No menus template, no title screen, no settings screen, no pause.
- **Fonts:** none self-hosted. Everything is the Godot default at an overridden size, which
  `POLISH.md` does not pass.
- **Audio:** **none at all.** No sound of any kind is loaded or played.

## Assets

| Need | File | Source | Licence |
|---|---|---|---|
| Environment / sky / ambient light | `assets/abandoned_parking_1k.hdr` | UNKNOWN (unrecorded; the name matches a Poly Haven HDRI) | UNKNOWN - not recorded in the repo |
| Concrete normal | `assets/concrete_normal.webp` | UNKNOWN | UNKNOWN |
| Concrete roughness | `assets/concrete_rough.webp` | UNKNOWN | UNKNOWN |

**There is no credits file and no licence record in this repo**, which `ASSETS.md` requires.
That is a real gap and it is recorded here rather than filled in with a guess.

## Tests and tools

Complete and genuinely strong - this is the healthiest part of the repo.

- **Golden** (`test/test_golden.gd`): four whole-run goldens at level 2, one per policy, each
  failing for a different reason. Measured and committed:

  | policy | rubble | columns down | integrity | outcome |
  |---|---|---|---|---|
  | PASSIVE - touches nothing | 0 | 0 | 1.0 | still standing at 60 s, 0 hits |
  | NUDGER - creeps at a quarter throttle | 0 | 0 | 1.0 | 1 contact in 60 s; speed is the damage |
  | GREEDY - wrecks well, never leaves | 1030 | 8 | 0.329 | **crushed**, all of it lost |
  | WRECKER - wrecks well, gets out | 879 | 4 | 0.675 | **won**, out with 9.99 s to spare |

  GREEDY banks more rubble than WRECKER and loses anyway. What the escape buys is not more
  rubble, it is keeping the rubble you have.
- **Design tests** (`test/test_tuning.gd`, 13): the player can get out; the escape tightens
  but never becomes impossible; speed does the damage; a column takes a few good hits; a wall
  is easier and worth less; the ball can be swung faster than the machine drives; the deck is
  bigger than the swing; the grid fits the room; the ramp is wide enough to drive through; a
  pivot is quick but not free; the ball cannot reach across the room.
- **Sim tests** (`test/test_sim.gd`, 24) and util tests (8).
- **Smoke** (`test/run_smoke.gd`): boots the real scene, ~40 assertions, including the
  screen-right camera assertion that catches inverted steering.
- **Probe** (`test/run_probe.gd`): balance readings over levels 1-4. Prints; cannot fail.
- **Size guard** (`scripts/check_size.gd`) against `size-budget.json` (31,154,417 bytes,
  ±10%), failing in both directions.
- **Replay scenarios: none.** `test/replays/` does not exist in this repo. `playtest/SKILL.md`
  names five every game keeps (`idle`, `boundary`, `fail`, `shop`, plus one first-minute) and
  this repo has none of them, so there is nothing to film.
- **Counts:** `NOTES.md` records 57 pure tests / 4,567 assertions / 40 smoke assertions, but
  that figure is from the v0.3.0 game. UNVERIFIED - Godot could not be run to re-count.

## Polish budget

Measured against `POLISH.md`, honestly. This game is **not** near the ship gate.

| Line | State |
|---|---|
| Audio | **Not started.** No sound at all |
| Self-hosted type, one display + one text family | **Not started.** Godot default only |
| A shell: title, settings, pause, erase progress | **Not started** |
| End-of-site summary (haul, seconds saved, columns) | **Not started.** A banner only |
| Haptics | **Not started** |
| Launch-to-quit pass on the phone | **Never done for this build** |
| Perf percentiles at start and after ten minutes | **Never measured** |
| Store listing, privacy policy, release keystore | `PRIVACY.md` added 2026-09-12; no keystore, no listing |
| Determinism, size guard, build stamp, changelog, CI | **Done** |

## Milestones

**A record of what exists, reconstructed from the twelve commits and the changelog. These
were not written in advance and were not worked through in this order on purpose.**

### Phase 1: first playable - complete, shipped as 0.4.2

- [x] **M1 Scaffold** (`d70b2d4`) - template copied, CI, size guard, build stamp, changelog.
- [x] **M2 The simulation** (`a9973de`) - a rig, a swinging ball, a street to take down.
      Proved by the first goldens.
- [x] **M3 Renderer, HUD and screenshot tool** (`bd8d4d0`).
- [x] **M4 Fix the end-of-street freeze** (`668c85c`) - shipped as a hard stop; his
      screenshot named the cause. Released 0.1.1.
- [x] **M5 Rotate the crane to aim** (`1d8d222`, `3ae93e4`) - his ask #1. Turret slews to the
      thumb; a bot that ignores the crane now scores zero. Released 0.2.0, 0.2.1 (dial, and
      the stretch-mode hit-test fix, his ask #2).
- [x] **M6 Controlled collapse** (`02f3560`) - his ask #4, the genre change. One condemned
      building, fixed swings, bays, lean, clean bonus. Released 0.3.0. **Superseded.**
- [x] **M7 Down in the basement** (`82754b9`) - replaced M6 entirely: a parking level, drive a
      machine, a real chain, support gauge, collapse and escape. Released 0.4.0. *This is the
      game today.* UNKNOWN what prompted it - there is no note from Gideon after 2026-09-09
      and no entry in `NOTES.md` explaining the change.
- [x] **M8 Fix the controls** (`569c551`) - his ask #5. World-relative driving, a real
      pendulum, a slider instead of a dial. Released 0.4.1.
- [x] **M9 Drive it like tracks** (`8aafacc`) - pivot on the spot, then go. Released 0.4.2.
- [x] **M10 Audit fixes** (`6db325d`, 2026-09-12) - APK export guards (`exclude_filter`,
      `build/.gdignore`) and the `shot.gd` state argument.

### Phase 2: content and meta - not started

Taken from `NOTES.md`'s "known gaps", which is the only forward-looking source in the repo.
No milestone here has a design behind it yet.

- [ ] **The building visibly falls.** Bays currently stop being drawn and debris comes off
      the whole height. `NOTES.md` calls this the single biggest thing the game is missing
      and the reason for going native: pre-fractured slabs becoming rigid bodies on collapse.
      **Physics may only ever be cosmetic.**
- [ ] **Audio.** Named as the easiest sound design of any game here.
- [ ] **End-of-site summary**: the haul, the seconds saved, the columns taken.
- [ ] **Differentiated targets.** Every column is currently worth the same, so "which one
      next" is only ever a support question.
- [ ] **The yard**: salvage, a longer boom, a heavier ball. Deliberately not built before the
      core is known to be fun.

### Phase 3: polish and store - not started

- [ ] The `POLISH.md` table above, line by line.
- [ ] A release keystore and a Play listing. Direct APK from a GitHub Release for now.

## Second month

UNKNOWN. No source in this repo or in the playtest log says what this game becomes when it
is working. The honest statement of where it stands is that it has a proven core decision
(one more column, or leave) that **no human has played yet**.

## Open decisions and unknowns

Things a future session must not read as settled.

1. **Gideon has never played the basement game.** Every quote in the playtest log is about
   the runner or the crane runner. Everything about how v0.4.x FEELS is unverified: whether
   the support gauge is readable while driving, whether the escape clock bites or nags,
   whether a pivot-then-go machine is satisfying to drive. **Play it before tuning it.**
2. **Why M6 became M7 is unrecorded.** The move from the above-ground demolition game to the
   basement has no note from him and no entry in `NOTES.md`. It is the one change on this
   project not traceable to a measurement or a quote.
3. **`CLAUDE.md` and `NOTES.md` describe the superseded v0.3.0 game** and need rewriting
   against the shipped code. Their measured numbers are of a game that no longer exists.
4. **Asset provenance and licences are unrecorded** for all three files in `assets/`.
5. **No replay scenarios exist**, so `/playtest` has nothing to film here.
6. **CI has no `play` job** - this repo predates it by sixteen minutes.
7. **The save lives in the presentation layer** (`main.gd`, `user://wrecking-crew.save`),
   which `INDEX.md` rule 2 permits, but there is no pure `state → Dictionary → state` pair
   and no round-trip test, which rule 2 does require.
