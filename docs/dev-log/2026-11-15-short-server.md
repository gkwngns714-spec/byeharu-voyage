# 2026-11-15 — 0433: the server says have and need (row 350)

The owner, 2026-11-15: *"too much word should be shorter. for example wave 24. just tell me what i have, and what is required."*
The client was cut to have / need words by #708-#716. This slice cuts the server's own words. Branch `short-server`, migration
`20260818000433_the_server_says_have_and_need.sql`, proof 134.

## What changes

| Where | Before | After |
|---|---|---|
| Sea wall refusal (`public.sea_refusal`) | Macaronesia and the Canary Current asks title 2 and wave resistance 10 — you are title 1 and your fleet holds 12 | Macaronesia and the Canary Current closed. Title 1 / 2. |
| BUY she cannot pay for (`E_INSUFFICIENT_FUNDS`) | the purse will not cover that much Quicksilver | Money 2,000 / 3,821 |
| Room purchase (`E_INSUFFICIENT_FUNDS`) | This room costs 30000 🪙 and you have 2000 🪙. | Money 2,000 / 30,000 |
| Hold (`E_HOLD_FULL`) | more Pepper than the hold will take | Hold 120 / 150 t |
| Reach (`E_OUT_OF_REACH`) | Havana is 1,450 miles off, and you reach 300 | Range 300 / 1,450 miles |
| Reputation (`E_NOT_ENOUGH_REPUTATION`) | Needs 300 Reputation: you have 60 | Reputation 60 / 300 |
| Raid lines (`voyage.raid_report`) | Raiders: about 2 × Şebek (xebec), 81 crew. / They saw you before your lookout saw them. | Raiders: ~2 × Şebek (xebec), 81 crew. / They saw us first. |
| A round (`voyage.fight_round_line`) | Round 2 · long range — you have no guns to answer with; they hit Gaivota for 8% damage (armour turned 2%). | Round 2 · long · no guns; they hit Gaivota −8% (armour −2%). |
| Boarding | Close quarters: they come alongside — your 40 crew against their 55. They board and take what they can carry. | Boarded: crew 40 vs 55. Plundered. |
| Battle report line (`public.battle_words`) | We came alongside and were thrown back. | Thrown back. |
| Voyage day (`voyage_event_kinds`, `voyage.report_line`) | Day 3. A gale took us on the beam. We ran under bare poles and lost 12 points of hull. We buried 2 of the crew. | Day 3. Gale: hull −12. Crew −2. |
| News (`news_kinds`) | Update: Merchants leave poor harbours; cargo ships carry smaller loads on more ships | Merchants leave poor ports |
| News | Pirates took 52,000 from Casa Nova / Pepper at Lisbon +25% in an hour | Casa Nova raided: 52,000 / Pepper +25% · Lisbon |
| Best sale card (`world.best_sales`) | No money (purse 2,000; the full load needed 57,870) | Money 2,000 / 57,870, and the trip offered at 4 units for 1,908 (pays +2,565) |
| Room ladder (`world.house_room`) | Trading 3 | Trading 1 / 3 (the served `level`) |

The mechanism for refusals is ONE hunk in `cmd.refusal`, the one maker of a refusal value: when its figures are a have / need pair (or a
closed sea's), its sentence is `cmd.refusal_line(code, figures)`. Codes, figures and every other key are unmoved. A skill's refusal
(E_NEEDS_SKILL, E_SKILL_PREREQ, E_SKILL_ORDER) keeps its sentence, since it names the skill. Korean is the client's `refusalWords`, with
the same labels (`돈 5,000 / 9,000`, `보급 2.9 / 33일`).

## Decided by default

- `Update: {title}` became `{title}`: the update row is still the UPDATE kind (its own colour and filter), the word "Update" is gone.
- The six update titles over 40 letters (0375, 0413, 0422, 0423, 0425, 0426) are shortened in their own world_news rows, each matched on its
  exact old title. world_news is append-only: its trigger is lifted for that one UPDATE and put back (asserted). Six rows, by unique key.
  Titles 0427-0432 (not yet live when this was written) are their own files'.
- The best sale: `short` keeps 0351's meaning (no sale is named). New `have` / `need` are served when the best full load is beyond her
  purse; the sale then named is the most units her purse (less her stores, unless owed) pays for, re-priced through world.quote and
  world.board_sell (at most three narrowing steps), the best of those within her purse.
- Not touched: `public.battle_resolve` (0427 and 0432 cut it), `public.battle_log` (numbers only), `public.reputation_arrival` and
  `public.reputation_lap` (they book keys and amounts, no words), `voyage.settle`'s own fallback words (raid_report always gives a sentence),
  `cmd.captain_skill_next` and `public.augment_fitting_for` (their own envelopes).

## Proof and checks (local PGlite world, restored from the cached prefix at 0426 + 0433)

- 0433 self-assert ok: 43 hunks over 7 bodies, each once and reversing; no other function moved; 91 ms.
- Proof 134 (5/5): HN_REFUSAL (a real BUY refused `Money 1 / 3,821`), HN_REPORTS (120 raid days, every line short), HN_NEWS, HN_BEST_SALE
  (from SET at a purse of 2,000: 3 cards sized to her purse with have / need, 4 with a need), HN_ROOM_LEVEL.
- Proofs that pinned the old words, amended and run green locally: 28 (compares figures, not words: the old body's words are 0320's),
  31 (the BATTLE day line), 56 (its copies of 0353's hunks carry the new words), 60 (the Flee round), 91 (the sea sentence).
- Harness: `scripts/ops/harness/short-server/before.sql` / `after.sql` (one read), `rollback-0433.sql` + `rollback.mjs` (the hunks reversed
  from the migration's own text): applied, read, rolled back and read again on the local world; the read before and after matched what each
  side wants.
- Client: `tsc`, `eslint`, `vite build`; `tests/shortWords.server.spec.ts` (4/4), `tests/news.kinds.spec.ts`, `tests/news.lint.spec.ts`.
