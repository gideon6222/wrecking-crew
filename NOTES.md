# Notes — Wrecking Crew

Decisions specific to this game, and what to do next in it. General lessons belong in
`C:\dev\gamedev-notes`, not here.

## Why this game

The first real game on the Godot stack, chosen from two proposals on 2026-09-08. It is in
the hyper-casual runner family like Coreward and Candle Gift, but the control scheme is
the thing that is new: **you never place the tool, you only push it.**

That is a direct answer to the most useful sentence found while rebuilding Candle Gift —
a strategy guide saying *"sometimes you need to start moving well before an obstacle is in
reach"*. In that game it was a consequence of a trailing formation. Here it is the entire
control scheme.

It is also the pitch that most needs to be native: hundreds of physics debris chunks under
real shadowed lighting is precisely the ceiling the WebView was imposing.

## The crane rewrite, 2026-09-08

Gideon's note on the first build: *"it would be more fun if the main goal was to rotate the
crane part to hit the buildings, especially as we add things to aim for."* He was right, and
the reason is worth keeping: in the first build aiming WAS the whole game and yet you could
not see yourself aim. The ball was driven by the rig's lateral acceleration, so the only
feedback on your aim was whether you hit something.

Now the turret slews to where the thumb drags, the ball trails the boom as an underdamped
spring, and reach comes from how fast the ball is travelling round rather than from where the
boom points. The lag survives - it is what you lead - but it is legible.

**What the rewrite unambiguously bought:** a policy that never touches the crane now scores
**exactly zero**. Under the old scheme the same policy scored 138 against the aiming policy's
268, because a ball driven by the rig's own movement swung into things by accident. There is
no accident available any more. That zero is pinned in `test_golden.gd` and it is the single
most valuable number in this repo.

**The open design problem, stated plainly.** Reach rises monotonically with swing speed and
*nothing anywhere punishes swinging flat out*, so maximum swing is never wrong. Measured over
six streets: a bot that reads the street and picks targets scores 310; a bot that ignores the
street entirely and just waves the crane on the ball's own period scores 317. They are level.

That was chased hard before settling. A sweep of the aiming bot's switch timing across eleven
values never beat the waving bot - best was 0.87x - so it is not a bot bug this time. Thinning
the street made it *worse*, not better (at 0.16 density the waving bot wins 1.74x), which kills
the obvious explanation. The real property is that there is no cost to a wild swing.

**The fix is what Gideon said next: "especially as we add things to aim for."** Targets that
are worth different amounts turn a sweep that hits everything into a sweep that hits the wrong
things. Until they exist, waving is a legitimate strategy and the game is a rhythm game with a
crane on it. Do not paper over this with a test that enshrines it.

## What is measured, as of 2026-09-08

Over six streets, each policy playing the whole street:

| policy | mean rubble | floors | flattened |
|---|---|---|---|
| `passive` — touches nothing | 0 | 0.0 | 0.0 |
| `dodger` — presses the lane pads, never the crane | **0** | 0.0 | 0.0 |
| `weaver` — waves the crane, ignores the street | 317 | 10.5 | 4.5 |
| `wrecker` — reads the street and picks targets | 310 | 9.0 | 5.0 |

Other measured numbers worth not re-deriving:

- Ball period **2.09 s**, so the lag the player leads is about **0.52 s**.
- At rest the ball reaches **2.96** from the rig; a kerb needs **4.15**. That gap is the
  design: pointing is not hitting, the ball has to be travelling.
- Reach ceiling **9.93** from the outer lane against a kerb at **5.20**.
- Radius must not saturate. At a gain of 1.75 with a cap of 11 the radius sat pinned at the
  cap for most of a sweep, the ball blanketed a band twice the width of the street, and
  waving beat aiming by 1.24x. The cap has to be somewhere the ball rarely reaches.
- APK **27.11 MB**, budget recorded with ±10%.
- 61 pure tests / 22,046 assertions in about a second; 36 smoke assertions.

## Four things that were built, measured, and removed or changed

Kept here so they are not rediscovered as good ideas.

1. **The height rule.** The ball rises as it swings out, so it could only damage a building
   it was not sailing over. It has no middle setting: with two-floor buildings it never
   fired once, and with one-floor shopfronts it made the whole of street one immune to the
   only tool in the game. The full reasoning is in `sim.gd`. The choice it was meant to
   create — how hard to swing, not just when — is still worth having, but as a cost rather
   than a gate, and on the HUD.
2. **A faster pendulum.** `SWING_G` 34 instead of 26 puts more turning points on a street,
   which sounds like more chances to connect. It measured **24% worse** for the aiming bot,
   because a faster swing needs tighter timing and therefore rewards the policy that
   ignores the street and weaves on the beat. That is the wrong game.
3. **Uncapped speed.** Speed compounding 5% a street outran the ball's fixed lag by street
   10. Capped — at 18 m/s under the old boom, and lowered to 16.5 when the crane rewrite
   made the boom shorter, because the window a building is aimable in is
   `(BOOM + depth) / speed` and shortening the tool lowers the speed the ladder may reach.
   The design test found that on its own, twice.
4. **The whole first control scheme**, on Gideon's note. Kept in git and described above.
   Everything measured about it is still true; it was replaced because you could not see
   yourself aim, which no amount of tuning would have fixed.

## Known gaps / next, roughly in order

1. **Differentiated targets.** The open problem above. Until some buildings are worth more
   than others, sweeping blindly is as good as aiming and the main control is not really
   being used for what it is for. This is the next thing to build, not the art.
2. **He has not played the crane.** Whether the slew feels like a crane or like a laggy
   cursor, whether the lane pads are reachable without looking, and whether the ball is
   findable on screen when it swings behind the rig.
3. **The art is a first pass and is the weakest part.** It went through four passes and
   landed on flat-shaded boxes with a cool atmosphere against warm concrete. It reads
   clearly and it is not yet *gritty*, which is what he asked for on Coreward. The most
   likely wins, in order: a normal map on the concrete from ambientCG (the one import that
   has ever paid off twice), real rubble geometry left in the street where a building came
   down, and floors that break into pieces rather than vanishing.
4. **No audio at all.** An action with no sound reads as not having happened. A wrecking
   ball is the easiest sound design in any of these games — one impact with pitch and
   filter jitter, a low engine bed, and a rising creak as the swing loads.
5. **No yard.** The persistent half of the loop does not exist: no salvage, no shop, no
   upgrades, no collection. The design calls for a landmark per street that is lost forever
   if the building is flattened the wrong way, which is the reward whose value does not
   decay. Deliberately not built before the core is known to be fun.
6. **The rig is one mesh set.** Upgrades should change how it looks in play, which is the
   thing he asked for by name on Coreward.
7. **No release keystore and no Play listing.** Direct APK from a GitHub Release is the
   path for now. See `godot-template`'s notes for what Play needs.

## Things this repo does that the template does not

Worth folding back into `godot-template` when convenient:

- `test/policies.gd` — scripted players as a first-class file rather than a closure inside
  the golden.
- `test/run_probe.gd` — a balance probe that prints and cannot fail.
- `scripts/shot.gd` — a deterministic screenshot at a chosen second.
- `TestHarness.FLOAT_EPS` — a golden over floats cannot use exact equality.
- The smoke test's **screen-right assertion**, which is the only thing that catches
  inverted steering on a chase camera.
