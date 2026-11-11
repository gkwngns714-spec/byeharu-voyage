# 2026-11-11 — R1: every success earns Reputation (0352, owner row 317)

Slice R1 of `docs/REPUTATION.md`: the book, the one writer, the earn hooks, the read and the three places a player sees
it. Nothing is spent yet (R2). Built on the local PGlite world at head 0350 (the cached prefix); **no production read or
write was made**, and the PROD CHECK files have not been run.

## What was built

**Migration `20260818000352_every_success_earns_reputation.sql`** (one DO block, `statement_timeout` 45 s,
`lock_timeout` 5 s, fails above 45 s):

- Tables `reputation_kinds` (12 kinds), `reputation_balance`, `reputation_book` (+ the once-index). RLS on, no client
  privilege. The book is append-only (`public.forbid_mutation`) and a chain: `reputation_book_chains` (before insert,
  one primary-key probe) and `reputation_reconciles` (deferred constraint trigger on both tables, two probes). Nothing
  sums the book.
- `public.reputation_credit` (the one writer), `reputation_sale`, `reputation_arrival`, `reputation_request`,
  `reputation_built`, `reputation_card` (STABLE). No client may call any of them.
- 14 knobs: `reputation_on` true, `rep_profit_per_point` 250, `rep_sale_max` 120, `rep_nm_per_point` 100,
  `rep_miles_max` 40, `rep_per_fight_point` 2, `rep_landfall` 25, `rep_request_per_point` 250, `rep_request_min` 5,
  `rep_request_max` 100, `rep_built` 100, `rep_day_cap` 600, and `rep_lap` 10, `rep_battle` 40 (seeded, read by nothing).
- Five hunks, sliced from the live bodies (`pg_get_functiondef` at head 0350, LF), each OLD text found once, each
  reversing: `cmd.do_sell`, `voyage.settle`, `cmd.run_fulfil`, `cmd.do_build`, `world.player()`. Both droppable hooks
  (`run_fulfil`, `do_build`) sliced cleanly and were kept.

**Client:** the top bar's figure (`src/app/TopBar.tsx`, `data-testid="reputation"`, left of the purse, from 640 px up), the arrival
card's one new line (`src/app/ArrivalCard.tsx`, `+26 Reputation` / `평판 +26`), the You tab's card with the balance and
`Today 1 / 600` / `오늘 1 / 600` (`src/features/you/YouScreen.tsx`), the type (`src/lib/rpc/types.ts`), the words
(`dict/shell.ts`, `dict/feed.ts`), one row in `docs/WORDS.md`.

**Proof** `scripts/db/proofs/55_reputation.sql` (8 markers), **spec** `tests/reputation.spec.ts` (390 and 1280, EN and
KO), **PROD CHECK** files under `scripts/ops/harness/reputation/` (generated from the migration's own hunks by
`gen-checks.mjs`).

## Where the build leaves the design (the code was followed, the intent kept)

| # | The design said | Built | Why |
|---|---|---|---|
| 1 | `cmd.do_build`: one hunk after the `HULL_LAID_DOWN` emit | the hunk stands after `v_ship := public.commission_ship(...)` | the once-key is `built:<ship id>` and the ship has no id until she is commissioned, two statements later |
| 2 | `request`: no once-key | key `request:<contract id>`: once a contract a house | a contract is delivered in parts (0311), `request` is outside the day's cap and has a floor of 5; without a key a house landing one tun at a time earns 5 a tun |
| 3 | helpers `reputation_sale`, `reputation_arrival`, `reputation_card` | two more: `reputation_request`, `reputation_built` | each hook stays one line and no amount stands inside a door (section 1.7: every number is a knob read in a helper) |
| 4 | knobs as listed | four more: `rep_miles_max`, `rep_request_per_point`, `rep_request_min`, `rep_request_max` | the miles cap had no name; the request's 250 / 5 / 100 had no knob |
| 5 | `reputation_credit` step 4 reads the key, step 5 locks | the key is read again under the lock | two settlements of one house at one instant both pass the first read; the second would die on the unique index inside `voyage.settle` |
| 6 | one trigger `reputation_reconciles` | two triggers of that name, one on each table | a trigger belongs to one table |
| 7 | `E_NOT_ENOUGH_REPUTATION` "with figures" | `cmd.refuse` + `cmd.figures(have, need, 'reputation')` | `cmd.figures` takes a lower-case unit name |
| 8 | pirates "evaded 10, driven off 30" | `floor(voyage_xp_tracks.combat × rep_per_fight_point)` | the same figures today (`xp_evaded_points` 5, `xp_driven_off_points` 15), read through the one reading, not written down twice |
| 9 | miles and landfall at "arrival at a port" | a harbour or a sea place (any `dest_port_id`); pirates are paid in open water too | the design did not say; a sea place is an arrival with a code. Decided by default |
| 10 | "OLD against NEW `do_sell` on 200 probe merchant sales, printed as a notice" | in the migration's self-assert, 100 OLD + 100 NEW interleaved, bounded to 6 s, and it never gates | printed in CI's chains and at the deploy; whatever stops it (a refusal) is printed instead |
| 11 | "a real probe sale through `cmd.do_sell`" in the self-assert | kept; where the city's purse is lit or the economy is closed and the door refuses the empty-pursed probe, the refusal is printed and the sale is left to proof 55 | prod's switches cannot be read from here, and a deploy must not die on a probe's refusal |
| 12 | the top bar figure at every width | from 640 px up (`sm`); on a phone Reputation stands on the You tab and on the arrival card | at 390 px the date, the hour, the Korea clock and the purse leave 17 px: a figure there cut the game hour off, and `tests/shell.kstClock.spec.ts` (390 px: "the game hour is cut off") went red with it. The owner may prefer to drop something else from the phone bar |
| 13 | `rpc.surface` spec | not changed | the slice adds no client entry point; the spec passes as it is |

Things seen and left as designed:
- The sale cap is per sale (120), so a lot split into several sales can earn more than one sale of the whole lot; the
  day's cap (600) bounds it.
- A new house has no report to its starting port, so its first return home pays a landfall (25) as well.
- A sale that lands on a later read than its arrival is not on the card (the card's own rule for sales); its Reputation
  is then not on the card either, and is on the top bar.

## Measured (local PGlite, cached prefix at 0350, this PC)

| What | Figure |
|---|---|
| The migration, self-assert included | 651 to 686 ms a run (6 runs) |
| `cmd.do_sell`, merchant at a gain, OLD vs NEW, 100 + 100 interleaved | 1.70 / 1.70, 1.63 / 1.72, 1.84 / 1.67, 1.72 / 1.78, 1.61 / 1.67 ms a sale: no difference above the noise |
| A human sale through the door (first call in the session, a point booked) | 14 to 15 ms |
| `reputation_arrival` on a stub voyage (miles + a first landfall) | 2 to 5 ms |
| A real human arrival settled by the read (`world.fleets()`, proof 55) | 47 ms in all |
| A starter barca's real speed (risk 12): Lisbon to CID, 1,606.2 nm laden | 8.5 real minutes: **189 nm a real minute** (the design assumed 230 to 290, measured on other hulls) |

**The first session, on a probe** (proof 55: a new house takes the most profitable trade the quay names within 1,700
nm, 80 tuns of raw silk to CID): sale 63 (profit 15,865 in two halves) + miles 16 + landfall 25 = **104 Reputation**.
The design's worked example was 28 + 12 + 25 = 65; the self-assert reproduces that exactly on a stub (7,200 of profit,
1,200 nm). The browser spec's new company (it sails to Porto with cork, at a loss of 24) earned 25 + 1 mile = 26.

## Checks run

- `tsc -b`, `eslint`, `vite build` (the world image built from the cached prefix): clean.
- The migration on the cached prefix: green 6 times; once more in a world with `city_treasury_enabled` and
  `economy_closed` set (the door refused the probe, printed, and the file still applied).
- Proof 55 alone: 8 of 8 markers.
- `tests/reputation.spec.ts`: 4 of 4 (390 and 1280, EN and KO), headless, a preview on port 47352. At 390 px in Korean the game hour is
  cut in the top bar on main already (the bar's Korean words are wider); the spec holds that line in English only.
- `tests/sections.spec.ts`, `tests/duplication.spec.ts`, `tests/words.spec.ts`, `tests/i18n.keys.spec.ts`,
  `tests/i18n.ko.spec.ts`: 26 of 26. `tests/rpc.surface.spec.ts`: 29 of 29. `arrival.card`, `shell.kstClock`,
  `you.design`, `fleets.you.grow`: 20 of 20 (the first build, with the figure in the phone bar, failed `shell.kstClock` at 390 px: deviation 12).
- The four PROD CHECK files were run on the local world (before: 5 hunks once each, nothing made; after: 5 new texts
  once, 3 tables, 12 kinds, 8 functions, 0 client functions, 4 triggers, 14 knobs).

## Not proven

- **Nothing was read on prod.** `before-hunks.sql` must read 1 for each OLD text on the live bodies before the deploy.
- The migration's run time on prod (budget 45 s; here 0.7 s). Its probe sale may be refused there and printed.
- A merchant sale's cost on real Postgres and on prod: the notice prints it in `disposable-chain` and at the deploy.
- `arrivals_beats` before and after (the two beat files): a merchant's arrival runs no new statement, by reading the
  body (the hunk is inside 0127's players-only block), not by a measurement on prod.
- The from-zero chain and the full proof run: CI's.
- Whether a phone should show Reputation in its top bar at the cost of another fact there: not decided here (deviation 12).
- The KO word 평판 is the designer's (risk 8).

## After the merge with main at 0351 (2026-11-12)

- `origin/main` (0351, #583, #584, #586) merged in as a merge commit, no conflict. 0351 touches none of the five bodies: on the
  world at head 0351 each OLD hunk text is found once (`before-hunks.sql` run locally), the migration applied green 3 more
  times (0.6 s; OLD / NEW merchant sale 1.46 / 1.60, 1.56 / 1.57, 1.62 / 1.44 ms), proof 55 gave 8 of 8, and the PROD CHECK
  files regenerated byte for byte.
- **The goal card carries the balance** (`src/features/command/levels/GoalCard.tsx`): its second line reads
  `Reputation 26` / `평판 26` (after `Opens: ...` when that line is shown). It reads the store's own `world.player()` balance,
  so there is no second call, and its 44 px height is unchanged (`tests/goal.card.spec.ts` green). This is the phone's place
  for the figure the top bar cannot hold (deviation 12); `tests/reputation.spec.ts` holds it.
- On the merged build: `reputation`, `arrival.card`, `shell.kstClock`, `you.design`, `goal.card`, `sections`, `duplication`,
  `words`, `i18n.keys`, `rpc.surface`: 74 of 74, then `reputation` again with the goal-card check: 4 of 4.
