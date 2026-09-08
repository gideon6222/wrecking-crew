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

## What is measured, as of 2026-09-08

Over six streets, each policy playing the whole street:

| policy | mean rubble | floors | flattened |
|---|---|---|---|
| `passive` — never touches the screen | 8 | 0.0 | 0.0 |
| `dodger` — survives, never aims | 138 | 4.2 | 2.0 |
| `wrecker` — plays it | 268 | 7.7 | 4.0 |

The gap that matters is the last two rows: aiming earns about twice what merely surviving
does. `test_golden.gd` asserts that ratio over six streets so it cannot quietly close.

Other measured numbers worth not re-deriving:

- Swing period **2.76 s**, so the lag the player leads is about **0.69 s**.
- Reach ceiling **7.56** from the centre line against a kerb at **5.20**.
- A quarter-period load peaks at **4.19**; a half-period load at **6.76**. Both connect,
  which is what makes the first minute forgiving and the tenth minute worth practising.
- APK **27.11 MB**, budget recorded with ±10%.
- 51 pure tests / 25,930 assertions in about a second; 25 smoke assertions.

## Three things that were built, measured, and removed or changed

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
   10. Capped at 18 m/s; later streets get harder by growing the skyline instead.

## Known gaps / next, roughly in order

1. **He has not played it.** Everything about how it FEELS is unverified — whether the lag
   is discoverable, whether the load-then-turn technique is findable without being told,
   and whether a barricade reads as "swing through it" or as "get out of the way".
2. **The art is a first pass and is the weakest part.** It went through four passes and
   landed on flat-shaded boxes with a cool atmosphere against warm concrete. It reads
   clearly and it is not yet *gritty*, which is what he asked for on Coreward. The most
   likely wins, in order: a normal map on the concrete from ambientCG (the one import that
   has ever paid off twice), real rubble geometry left in the street where a building came
   down, and floors that break into pieces rather than vanishing.
3. **No audio at all.** An action with no sound reads as not having happened. A wrecking
   ball is the easiest sound design in any of these games — one impact with pitch and
   filter jitter, a low engine bed, and a rising creak as the swing loads.
4. **No yard.** The persistent half of the loop does not exist: no salvage, no shop, no
   upgrades, no collection. The design calls for a landmark per street that is lost forever
   if the building is flattened the wrong way, which is the reward whose value does not
   decay. Deliberately not built before the core is known to be fun.
5. **No end-of-street screen.** Finishing a street currently just ends the run. It wants
   the haul, the buildings flattened, and a reason to go again.
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
