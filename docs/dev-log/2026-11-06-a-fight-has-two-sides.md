# A fight has two sides (migration 0320, slice W5, owner rows 283, 288)

`docs/WORLD_POWERS.md` sections 2.5, 2.6. No fight changes. Nothing can attack anything yet: no verb, no job, no client door. The owner answered "not for now" on pirate players attacking player merchants; no player attack of any kind is built.

## What was built
- `public.fight_sides(seed, round, a, b, opts)`: the engine. Real hulls on both sides, numbers only, `hull_lost` for both by ship id. `a` is the side set upon, `b` the side that closes.
- `public.fight_volley(...)`: one side's guns in one round. Both sides call the same rule.
- `voyage.raider_hulls(strength)`: the one reader of `fight_raider_class` and `ship_classes` in a fight.
- `voyage.fight_resolve`: now a skin. Same arguments, same answer, all the words.

The engine names no table. The self-assert reads its source and allows only `public.wc`, `public.wc_num`, `public.armour_soak`, `public.fight_volley` and `voyage.rng`.

## Decided by default
1. **A raid is one squadron hull, not whole xebecs.** The doc says "build xebecs". A raid's strength is fractional and its hull is one pool. Whole hulls would waste overkill on a sunk hull and silence her guns, which is a different fight, so parity would be impossible. `raider_hulls` returns one hull with every figure scaled and a `shots` count. A hull fires `shots` shots of attack / shots each; a real hull has no `shots`, so one. Reverse it by building several hulls in the builder, and accept that raids change.
2. **There is no switch.** Section 2.5 has none, and keeping two fight bodies behind a knob would be two authorities. "Dark" here means the two-sided path has no caller and the one live path is proved byte-identical. If a switch is wanted, the rollback below is the same thing.
3. **The old body lives whole in proof 28**, not as hunks, because the whole function is replaced. The proof checks it by digest, puts it back, and fights with it. That text is the forward rollback.
4. **Only `a` may slip away, only `b` breaks off.** That is today's fight, and the doc says nothing else about the fight changes. W10 can widen it.
5. **A shot on side `b` picks its target on a new stream**, `fight:<round>:you:<n>:at`. `voyage.rng` is keyed, so no other number moves.
6. **Sizing up is an option of the engine** (`opts {a_score, b_score}`), so a broken knob on a fleet that stands off raises exactly as before.

## Proof of no change
| Where | What | Result |
|---|---|---|
| 0320 self-assert | Old body (pg_temp copy of the live one) against the skin as text: 0202's 960-day probe plus 120 days of a convoy (Gunner, Boarder, gear, a hurt hull, a wreck) | 1,080 of 1,080 equal, on the mini world and on a real image |
| Proof 28 | 1,200 fights of 200 made-up fleets; 1,680 with 14 knob values moved | all equal |
| Proof 28 | The refusals (no ships, broken knob, broken class) | same words |
| Proof 28 | A real company's fleet through `voyage.fight`, 240 days, skin against old body | equal; old body back by digest, skin back after it |
| `proof-0320.mjs` | 20 mutations of the file | all red, the real file green |
| Prod, before | `scripts/ops/harness/two-sides/golden.sql`, the 1,080 fights on prod's real secret and knobs | digest `89ee59988714e9794df244ef70883257`; EVADED 94, DRIVEN_OFF 67, RANSOM 164, PLUNDERED 755 |

**Prod, after the deploy:** run `golden.sql` again. The digest must be the same text. This is the strongest check there is: prod's own secret, prod's own knobs, read-only.

The first run of the parity probe was red: 986 of 1,080 fights changed, because the volley keyed its streams by the day instead of the round. It is why the volley takes both `p_day` and `p_g`. The probe caught it on its first run.

## What moves, on no live state
- A raider class with no guns (`fight_raider_class` is `xebec`): the old body "hit" for nothing, and the engine does not fire. An armed class is word for word (proof 28: `nau`, `galion`).
- `fight_raider_break` above 1, so a sunk squadron fights on: the old body kept shooting it, and the engine stops. Exactly 1 is word for word.
- A broken class and an empty fleet at once: the class is named first, not the fleet.

## Cost
Alone on PGlite, 1,000 fights: old 235 ms, new 442 ms, about 0.2 ms more a fight. Not measured on prod. `golden.sql` on prod ran 1,080 old fights in about 4 s. A fight runs only on a PIRATES day, so this is expected not to show in the beat; the after-check reads it.

## Real hulls on both sides (`sim.mjs --sides`, 500 fights each)
Prod's class figures, whole hulls, level 1, no captain, no gear, random seeds. **This is one sample, not a balance claim.** W5 owes only that the sim runs on the core.

| Closing | On | Plundered | Ransom | Driven off | Evaded | Her hull lost | Theirs |
|---|---|---|---|---|---|---|---|
| 1 xebec | navire | 0.0 | 0.0 | 22.0 | 78.0 | 0.5 | 17.5 |
| 2 xebecs | navire | 0.0 | 23.4 | 33.8 | 42.8 | 2.2 | 13.7 |
| 1 nau | navire | 0.0 | 77.4 | 18.6 | 4.0 | 8.1 | 10.7 |
| 2 galion | navire | 100.0 | 0.0 | 0.0 | 0.0 | 47.0 | 2.0 |
| 1 xebec | galion | 0.0 | 0.0 | 9.0 | 91.0 | 0.1 | 26.6 |
| 2 xebecs | galion | 0.0 | 0.0 | 32.6 | 67.4 | 0.6 | 18.1 |
| 1 nau | galion | 0.0 | 0.0 | 52.2 | 47.8 | 1.7 | 15.5 |
| 2 galion | galion | 99.2 | 0.0 | 0.8 | 0.0 | 28.2 | 7.2 |

Worth knowing for W10: side `b` breaks off at 15 % of its hull lost, so a small attacker almost always leaves.

## Not verified
- `sim.mjs`'s raid replay itself: it needs `prod-raids.json` and an image, neither kept here. It calls `voyage.fight_resolve`, so it runs through the skin. Only `--sides` was run.
- Whether proof 28 passes on the head chain: this machine keeps no chain past 0096. It was run whole on a kept world image at 0301, and on CI.
- A PIRATES day through `voyage.settle` with the new body, compared with the old. `voyage.fight` is compared; `voyage.settle` is unchanged and existing proofs fight through it.

## Rollback (forward, a NEW migration, owner only)
Put back the pre-image held in `scripts/db/proofs/28_fight_sides.sql` (digest `8fc074d4f0a09332b321eb55a600c2fc`), then drop `voyage.raider_hulls`, `public.fight_sides`, `public.fight_volley`. Nothing else reads them.

## Order
0320 follows 0318 (#514) and 0319 (#513). Neither touches `voyage.fight_resolve`, `voyage.fight`, `voyage.escort_score`, `public.armour_soak`, `voyage.rng`, `world.ship_stats` or a fight knob (read in both PRs' diffs, 2026-11-06). 0319's only mention of a fight is a comment; its probe calls `voyage.settle`, which reaches the same answers.
