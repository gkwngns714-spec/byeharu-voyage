# 2026-11-11 — R2: a captain's skill is raised with Reputation (0355, owner row 317)

Slice R2 of `docs/REPUTATION.md` (sections 1.4, 1.6, 3 and 6): the spending half of Reputation. A step per captain per
skill, bought with Reputation, worth +4 % of that skill's own value, capped by her grade. Built on branch
`captain-skills`, which stands on R1's branch (`reputation`, 0352). Built on the local PGlite world (the cached prefix at
0352); **no production read or write was made**, and the PROD CHECK files have not been run on prod.

## What was built

**Migration `20260818000355_a_captain_skill_is_raised_with_reputation.sql`** (one DO block, `statement_timeout` 45 s,
`lock_timeout` 5 s, fails above 45 s):

- Table `public.captain_trait_rank (player_officer_id, trait, rank >= 1)`, RLS on, no client privilege. A row exists
  only once a player buys a step: a merchant's captain never has one.
- `public.captain_grades.max_rank`: C 3, B 5, A 7, S 10 (`data/captains.json` and `scripts/db/world-guard.mjs` hold it).
- `public.captain_rank_mult(rank)` = `1 + rank × captain_skill_rank_pct / 100` (sql, STABLE): the one arithmetic.
- Four hunks on `public.crew_terms`, sliced from the live body (`pg_get_functiondef` at head 0352, LF), each found once
  and reversing: in each arm a left join on the table's primary key and one factor,
  `case when tr.rank is null then 1 else public.captain_rank_mult(tr.rank) end`. Dark, only her job's row is joined.
- `public.captain_skill_next(player, code, trait)`: the one reading the door refuses by and the sheet prints.
- The door `cmd.captain_skill_up(code, trait)` → `public.captain_skill_up_for(player, code, trait)`: spends through
  `public.reputation_credit(player, 'skill', -cost, …)` (still the one place the balance falls), writes the row, emits
  `CAPTAIN_SKILL`. Refusals: `E_NOT_SIGNED_IN`, `E_NOT_SIGNED`, `E_TRAIT_NOT_KNOWN`, `E_TRAIT_IDLE`, `E_NOT_IN_PORT`,
  `E_TOP_RANK`, `E_NOT_IN_USE`, `E_NOT_ENOUGH_REPUTATION` (with figures).
- The read `world.captain_skills(code)` (STABLE, to authenticated only, as `world.levels()`).
- Knobs `rep_skill_base` 50 and `captain_skill_rank_pct` 4.
- One hunk on `public.client_rpc_entry_points()`, +2 rows.

**The registry hunk and 0354.** 0353 (fight-log) anchors its registry rows on the `pirate_ship_card` line and 0354
(fleet-room) on the `ship_moves` line. This file anchors on 0162's own line, `('cmd', 'promote_captain', 'text'),`, which
neither of them moves, and puts its two rows after it. So the hunk's OLD text is found once whether 0353 and 0354 have
been applied or not, and in either order.

**Client:** a new block in the captain's card, `src/live/CaptainSkills.tsx` (read `src/live/useCaptainSkills.ts`), placed
in `CaptainSheet` (`src/live/YourCaptains.tsx`) under the promotion and above the list of the skills she uses. One row a
skill she knows:

    Navigator · 2 / 5 · +8 %          [ Upgrade · 300 ]
    항해사 · 2 / 5 · +8 %             [ 강화 · 300 ]

The button is greyed when the server's `can` is false, and the server's own sentence stands under it (in Korean, the
code's entry in the refusal dictionary with the figures served). Heading **Captain skills / 선장 스킬**. The card's old
heading "Traits / 특성" reads **Skills / 스킬** (`Skills · 2 / 3`, `Use skills`, `Skills change in port only.`). History
has a sentence for the new event (`Richard Chancellor: Navigator 2 · 150 Reputation.`). `catalog.ts`, `types.ts`,
`index.ts`, `dict/books.ts`, `dict/codes.ts`, `dict/history.ts`, `docs/WORDS.md` (4 rows).

**Proof** `scripts/db/proofs/58_captain_skills.sql` (8 markers), **spec** `tests/captain.skills.spec.ts` with
`tests/captainSkills.fixture.ts` (390 and 1280, EN and KO), the `rpc.surface` pin, **PROD CHECK** files under
`scripts/ops/harness/captain-skills/`.

## Where the build leaves the design (the code was followed, the intent kept)

The four `crew_terms` hunk texts in `docs/REPUTATION.md` section 3 were checked against the live body at head 0352:
**all four match the live text exactly and each occurs once.** The deviations are elsewhere:

| # | The design said | Built | Why |
|---|---|---|---|
| 1 | four functions created | a fifth, `public.captain_skill_next` | the door and the read must refuse by one rule (as `public.promotion_next` does for a promotion); otherwise `can` / `why` and the door are two copies |
| 2 | `E_TRAIT_IDLE` when `trait_in_use` is false, or dark and not her job | dark: not her job, or her job's effect is not live (`trait_in_use`). Lit: idle only when every effect of the skill is a ship effect and `combat_bite` is off | `crew_effects.live` is the DARK arm's filter: only speed, hold, spread and crew_saved are `live`. Lit, `public.crew_terms` counts every skill she uses, storm, supplies and the goods traders included, and a Gunner's or Boarder's is read while `combat_bite` is on. By `trait_in_use` alone a lit world would refuse 21 of the 25 skills that do work |
| 3 | seven refusals | an eighth, `E_NOT_IN_USE`, when `reputation_on` is false | `public.reputation_credit` books nothing while the switch is off; without the refusal a step would be given for nothing. The door also raises if the spend booked is not the cost |
| 4 | the read `{reputation, skills: [{trait, word, rank, max, pct_now, cost, in_use, can, why}]}` | also `code`, and on each skill `why_code` and `figures` | the client prints a refusal in Korean from its code and figures (`codes` dictionary), as every other refusal |
| 5 | event `{officer, name, trait, rank, cost}` | also `word` (the skill's served word beside its code) | History composes its sentence from the payload alone, with no second read |
| 6 | parity for every fleet | for every fleet that has a seated captain (498 here) | both arms inner-join `captain_seats`, so a fleet with none has no term in either body; each such call would still cost three knob reads on prod |
| 7 | "two captains past 25 %" | three navigators, each at her grade's ceiling | two S navigators at step 10 reach 24.5 %, under the cap. Three add up to 29.6 % lit and `crew_pct` reads 25 % |
| 8 | `SKILL_FIGHT_BYTES`: fights "different with one" | the fights and the side the fight reads (`voyage.fleet_hulls`) are byte-equal with no step; a Gunner at her ceiling moves that side's accuracy and reach and nothing else; how many of the 30 fights change is printed, not required | a hull's stat is served rounded and one step of a 7.5 % Gunner is +0.3 points: at her ceiling (step 7) the flagship went accuracy 66 → 67, reach 78 → 80, and none of 30 (nor of 120) seeded fights changed. A control that needs a lucky roll is not a control |
| 9 | hot-path bound "the faster of two passes" | OLD is timed before the re-cut and NEW after it, two passes each, on 60 merchant fleets with a captain (speed + flagship hold) and 200 `world.spread_effective` quotes; each pass stops at 1 s; printed, never raised | the readers call `public.crew_terms` by name, so OLD and NEW cannot be alternated without a second copy of every reader; the passes are bounded so the file stays inside 45 s on prod |
| 10 | `E_TOP_RANK`: "Navigator is 3 of 3: a B captain reaches 5." | the same, with "an A captain" / "an S captain", and at the top grade "Navigator is 10 of 10." | grammar; and an S captain has no next grade |
| 11 | KO row `항해사 · 2 / 5 · +8 %` | a Korean word for each of the 25 skills (`books.skill_<CODE>`, read by `src/live/skillWords.ts`), used on the skill rows, on the card's own list and in History | no Korean job word existed: the server's English word was printed in both languages. The Codex and the Inn still print the served word (not this slice) |
| 12 | a skill is raised when a rule reads it | a skill she knows but does not use now can be raised too (`in_use` says whether a rule reads the skill, not whether she uses it) | she can choose it in port at any time and steps are never lost; ashore is allowed by the design for the same reason |
| 13 | rollback: reverse the four hunks | `scripts/ops/harness/captain-skills/rollback-draft.sql` also closes the door (`E_NOT_IN_USE`) | with the term gone a step would do nothing, and the door would still sell it |
| 14 | — | `refusalWords` moved out of `src/components/ui/Note.tsx` into `src/components/ui/refusalWords.ts` | the reason under a greyed button is not a Note; the rule (the code's Korean entry with its figures) stays one |

Things seen and left as they are:
- The sheet's speed line words a part to one decimal (`public.trait_effect_words`): 6.5 × 1.04 = 6.76 reads `+6.8% speed`.
  The row's own `+4 %` is exact, and the term is exact (proof 58).
- One step of a small skill can be less than a hull stat's rounding (deviation 8): a Gunner's first step may change no
  served figure of her ship. The fleet effects (speed, hold, prices) are fractions and always move.
- The row prints `+8 %` with a space, as the design's text has it; the server's lines on the same card print `+9% speed`.
- `world.captain_skills` asks `public.captain_skill_next` once a known skill (4 to 10 calls). It is read when a card
  opens and on the world's beat while it stays open, never by a job.

## The parity

`OLD = NEW public.crew_terms` at one instant, as text, for all **498** fleets with a seated captain, in the world's own
switches (`crew_bite` true here). The other arm is held by the probe (her term × 1.08 exactly and every other term of the
fleet byte-equal, lit and dark) and by proof 58 `SKILL_MERCHANT_EQUAL`: **3,348** answers (every merchant fleet × speed,
hold, spread, crew_saved; 498 fleets with a term above 0) read what they read before a player bought 41 steps.

## Measured (local PGlite, cached prefix at 0352, this PC)

| What | Figure |
|---|---|
| The migration, self-assert included | 826 to 862 ms a run (5 runs on the final text; 828 to 857 ms on 3 earlier ones) |
| Hot path, merchant speed + hold on 60 fleets, OLD / NEW (the faster of two passes) | 48 / 43, 47 / 43, 47 / 42, 50 / 43, 49 / 45 ms: within the bound each run |
| Hot path, 200 `world.spread_effective` quotes, OLD / NEW | 52 / 49, 50 / 50, 49 / 49, 52 / 48, 53 / 51 ms: within the bound each run |
| Proof 58 alone | 8 of 8 markers in 2.7 s |

PGlite's clock ticks in whole milliseconds, so the hot-path figures are whole numbers; the bound is
NEW ≤ OLD × 1.05 + 10 ms and was met on every run. Real Postgres prints its own in `disposable-chain` and at the deploy.

**A first upgrade, on a probe** (proof 58, `SKILL_FIRST_UPGRADE`: ELCANO, an S navigator at 9 %, through
`cmd.captain_skill_up` as `authenticated`): Reputation 35,800 → 35,750; her speed term 9 → 9.36; the fleet's speed
15.0288 → 15.0784 kn (a navire and a barca; the figure differs a little each run with the second hull's roll, the ratio
does not); purse and ledger untouched; one `CAPTAIN_SKILL` event; the sheet row `Navigator · 1 / 10 · +4 % [ Upgrade · 150 ]`.
At step 3 (× 1.12): speed 15.0288 → 15.1777 kn, the flagship's hold 1,302 → 1,314 tons, a spread at Lisbon 0.018200 → 0.017984.

**On the glass** (`tests/captain.skills.spec.ts`: Richard Chancellor, a B navigator at 6.5 %, 260 Reputation):
`Navigator · 0 / 5 · +0 % [ Upgrade · 50 ]` → `1 / 5 · +4 % [ Upgrade · 150 ]` → `2 / 5 · +8 % [ Upgrade · 300 ]`, greyed,
with `Needs 300 Reputation: you have 60.` under it; Korean `항해사 · 2 / 5 · +8 % [ 강화 · 300 ]` with
`평판 부족. (60 / 300 평판)`; Reputation 260 → 210 → 60 in the block and in the top bar; her speed line
`+6.5% speed` → `+6.8% speed` → `+7% speed`.

## Checks run

- `tsc -b`, `eslint .`, `vite build` (the world image built from the cached prefix, 337 files, certified): clean.
- The migration on the cached prefix: green 9 times (the last 6 on the final text), never from zero.
- The world guard on the built world: equal to `data/*.json` with `max_rank` in the grades.
- Proof 58 alone: 8 of 8 markers (run 3 times).
- `tests/captain.skills.spec.ts`: 4 of 4 (390 and 1280, EN and KO), headless, a preview on `localhost:47355`, run 3 times.
- `captains.sheet`, `captains.roster`, `fleets.you.grow`, `you.design` (the specs that open the captain's card or the You
  tab): 23 of 23. `rpc.surface` (29), `i18n.ko`, `i18n.keys`, `words`, `sections`, `duplication`, `harness.guard`,
  `captains.catalogue`: 67 of 67.
- The PROD CHECK files were run on the local world after the file (`after.sql`: 5 new texts once, 1 table, the four
  ceilings, 5 functions, 2 for the client, 0 for anon, s/s/s/s, 2 registry rows, the 2 knobs; `switches.sql`: 4 rows;
  `steps.sql` and the two beat files answer). `rollback-draft.sql` was applied after the file on the local world: the body
  no longer reads a step, the door answers `E_NOT_IN_USE`, its receipt printed.
- One mistake, stopped: after the last edits to the migration's header the world image was stale, and
  `tests/rpc.surface.spec.ts` began applying the chain from zero in its own process. It was stopped (its process tree
  only), the image was rebuilt from the cached prefix, and the spec then passed in under a minute. It ran for about 20 minutes before it was seen; nothing outside this
  worktree's own private cache copy could have been touched.
- Not run locally: the from-zero replay, the full `db:proof`, `db.chain`, `db.image`, the layout sweeps and the rest of
  the browser suite (CI's).

## The 30-minute after-check (it alters live play once a player spends)

1. Before the deploy: `switches.sql` (keep the four values), `before-crew-terms.sql` (5 rows, every `old_times` 1,
   `new_times` 0, `made` 0), `before-beats.sql` (keep the row).
2. Deploy. Read the two notices: the cost line (both "within the bound") and the receipt.
3. At once: `after.sql` (5 rows, every `new_times` 1, `tables` 1, `ceilings` C:3,B:5,A:7,S:10, `fns` 5, `client_fns` 2,
   `anon_fns` 0, `volatility` s/s/s/s, `registry` 2, the two knobs).
4. 30 minutes later: `after-beats.sql` against the kept row (n > 0, errors 0, avg ≤ 3,000 ms, p95 < 5,000 ms, no worse
   than before), and `steps.sql` (every step bought: `held` ≥ `rank`, `paid` = −`cost`, `merchant` false; no row is right
   too).
5. Rollback, forward only: `reputation_on` false stops every spend at once (and every earn); the file
   `rollback-draft.sql` puts `public.crew_terms` back and closes the door (copy it under the next number, delete its
   first line). Steps bought are kept and read as nothing.

## Not proven

- **Nothing was read on prod.** `crew_bite` there is unknown: both arms are built and proved, and `switches.sql` reads it
  (with `levels_bite`, `combat_bite` and `reputation_on`) before the deploy. If it is false, only a captain's job can be raised.
- `before-crew-terms.sql` must read 1 for each OLD text on prod's live bodies. Here each was found once at head 0352.
- The migration's run time on prod (budget 45 s; here under a second). The parity calls `public.crew_terms` twice a
  fleet with a seated captain (about 1,000 calls); `wc_num` was measured at 2.7 ms a call inside it on prod
  (`2026-11-07-a-captain-has-a-sheet.md`), so about 10 to 15 s is expected there. Not measured.
- The hot-path bound on real Postgres and on prod: printed in `disposable-chain` and at the deploy, never raised.
- `world.captain_skills` on prod: 4 to 10 calls of the one reading; not priced there.
- 0353 and 0354 are not in this branch's chain. Neither touches `public.crew_terms`; the registry hunk is anchored off
  both of theirs (above). The proof's fights call `voyage.fight(seed, day, fleet, raiders)`, which 0353 cuts by a hunk and
  keeps the signature of; proof 58 has not been run on a chain that holds 0353.
- The from-zero chain, the full proof run and the full Acceptance suite: CI's. Touching `src/components/ui/` selects
  every browser spec on the PR.
- The Korean words 선장 스킬, 스킬, 강화 and the 25 job words (항해사, 도선사, 보급관, 의사, 화물장, 사무장, 포수,
  백병대장, and `… 상인` for the goods traders) are the builder's: the owner sees them on the screenshots.

## After the news law (2026-11-12)

`tests/news.lint.spec.ts` asks every migration from 0347 on for one `public.news_update(` call. 0355 now posts its row,
`'Captain skills'` / `'선장 스킬'`, outside the rolled-back probe (the guard refuses a world without
`public.news_update(text,text,text)`; nothing counts the news table). Re-applied on the cached prefix 3 times (841 to
884 ms), the image rebuilt, proof 54 4 of 4, proof 58 8 of 8, `sections` and `duplication` green. `news.lint` is green
for 0355 and still red for 0352 on this branch: R1's own news call had not landed on `origin/reputation` (head 8c2b9bd3)
when this was pushed, so **the merge of `origin/reputation` into `captain-skills` is still owed**.
