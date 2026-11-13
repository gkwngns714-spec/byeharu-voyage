# 2026-11-12 — two small fixes: the read-only guard reads the first statement; a landing is waited for ten voyage-days

Test and ops files only. No client code, no migration, no knob. Nothing was run against production.

## 1. The read-only guard counted bytes

**What happened.** 2026-11-12 04:49 UTC, the 30-minute after-check of 0353 on prod:
`scripts/ops/harness/combat-log/after-check.sh` stopped at step b with `REFUSING: …/after.sql is not read only`. Its guard
was `head -c 400 "$f" | grep -qi "begin transaction read only"`. `after.sql` is a read-only prod check; its header
comment is long, and its `begin transaction read only` starts at byte 708. The lead ran the remaining files by hand.

**The same pattern, everywhere it was** (every `*.sh` under `scripts/ops` read):

| script | was |
|---|---|
| `harness/combat-log/after-check.sh` | `head -c 400` |
| `harness/raid/after-check.sh` | `head -c 40` (on the query it writes itself) |
| `harness/raid/pq.sh`, `harness/sim/pq.sh`, `harness/arrfast/pq.sh` | `head -c 40` |

`health.sh`, `bv-deploy.sh` and `diag/*.sh` send no file (inline queries; `health.sh` and `diag` pass the CLI's
`--read-only`): unchanged.

**The rule now, and its one home.** The repo already had the honest reader: `tests/harness.guard.spec.ts` tokenises every
harness SQL file (comments gone, every string and dollar-quoted literal one word, a `do` body read as code) and holds a
prod check to "first statement `begin transaction read only`, last `commit` or `rollback`, no write verb". That reader
moved, unchanged, into **`scripts/ops/harness/read-only.mjs`** (types in `read-only.d.mts`); the spec imports it, and the
five scripts ask it: `node …/read-only.mjs <file> || exit 3`. One reader, two callers, no third copy.

`readOnlyVerdict(text)`, with `\r` dropped first:
1. the FIRST statement is `begin transaction read only` (also `start transaction read only`, `begin read only`; any case,
   any header length);
2. the LAST statement is `commit` or `rollback`;
3. no statement holds `insert, update, delete, merge, truncate, create, alter, drop, grant, revoke, copy, refresh, call,
   perform, execute` or `explain analyze`. A hunk literal full of those words is data.

Not judged by the script: volatility (it needs the whole chain; the spec reads it on the tree, `volatility.sql` asks prod).

One behaviour is stricter than before: a file whose transaction is never closed, or that holds a write verb inside the
wrapper, was let through by the byte count and is refused now. Every prod check in the tree already passes it (the spec's
tree test).

**Proof (local, `tests/harness.guard.spec.ts`, 7 passed; was 4).** Three new tests:
- the judge: a 600+ byte CRLF header with mixed case passes; `update …` first refuses though the words stand in its
  first 40 bytes; the words in a comment or a literal are not a statement; a plain `begin` and an unclosed file refuse;
  a write or `explain analyze` inside the wrapper refuses; a hunk of write words passes;
- the scripts: every `*.sh` under `scripts/ops` that sends a file (`db query --linked … -f`) asks `read-only.mjs` on a
  line before it, none judges "read only" with `head -c`; the five senders are named;
- the command line: `after.sql`, `../two-sides/golden.sql` and `after-lit.sql` (the three the 0353 after-check sends)
  exit 0, and `after.sql`'s wrapper is past byte 400; `cost.sql` (a scene) and a missing file exit 3 with `REFUSING:`.
Also by hand: the query `raid/after-check.sh` writes for itself (its heredoc) passes the judge.

## 2. A landing was waited for 300 s; the sea can hold her longer

**The arithmetic, from the chain** (the live bodies at head 0352, dumped from the cached local PGlite world):
- `time_compression` 960: a voyage-day is 24 × 3600 / 960 = **90 real seconds**. A near trip (Lisbon to Setubal or Porto, whichever `findCarry` picks) is a fraction of a voyage-day; Setubal is about
  0.1 voyage-days.
- Every voyage-day is rolled once (`voyage.hazard_roll`): p = the sea's `hazard_base` × the leg's `hazard_mult`, capped at
  `hazard_p_max` = 0.06.
- The cost of a roll is one table, **`voyage.day_delay_hours`** (`supabase/migrations/20260818000125_a_merchant_docks_the_moment_she_arrives.sql`,
  never re-cut; read through `voyage.day_delay_for` since 0154, which only shortens a calm by a skill): STORM +36 h
  (135 s); CALM +`round((1 + 3 × magnitude) × 24, 2)` h = 24 to 96 h (90 to 360 s); FAIR_WIND gives back at most what
  was already lost.
- **The days grow with the delay**: `voyage.arrival_at` and `voyage.settle` roll every day up to
  `ceil((sim-hours + delay) / 24)` (`voyage.total_days`). A day a calm adds is rolled too.

**So the true worst case is not 6 minutes: there is none.** One roll costs at most 4 voyage-days: a near trip lands at
most 0.1 + 4 = 4.1 days = **369 s** after she sails (a full one-day hop: 450 s). A second calm on an added day: up to
8.1 days = **729 s**. A third: 12.1 days. A 480 s wait covers every single delay and no double one.

How often, with every day rolled at the 0.06 ceiling and every event a calm (20,000,000 simulated 0.1-day trips, 30 s of
slack for the arrivals beat and the page's read; the real seas roll lower and not every event is a calm):

| later than | share of trips |
|---|---|
| 300 s (the old wait) | 2.5 in 100 |
| 480 s (PR #600's wait) | 4.9 in 1,000 |
| 720 s | 1.0 in 1,000 |
| 900 s (the new wait) | 3.7 in 10,000 |
| 1,200 s | 0.7 in 10,000 |

**The fix.** `tests/arrivalWait.fixture.ts`, one home:
- `LANDS_WITHIN_MS = 900_000`: ten voyage-days, which is any two delays of any size on a trip of up to a day (810 s) and
  a day of margin. Paid only by a failing run: the spec goes on the moment the card stands.
- `LANDING_TEST_TIMEOUT_MS` = the wait + 300 s for everything else in the test.
- `arrivalCard(page, where)`: waits for the card; when it does not come, the error says how long it waited, what the
  page said about the voyage at that moment (the Trade status line, a fleet row, the fleet strip, the queue's passage
  line), and what the Fleets page says (opened then: the test has failed). A fleet still "to" a harbour is the sea; a
  fleet lying in port is a card that never came.

Specs changed: `tests/arrival.card.spec.ts` (the sale test, both sizes), `tests/reputation.spec.ts` (all four),
`tests/drive.map.spec.ts` (its 300 s poll for "she lies at the harbour"; its message now says the value is her row).

Looked at and left:
- `tests/arrival.card.spec.ts`'s raid test and `tests/fight.log.page.spec.ts`: the raid world's pinned 30-second passage,
  whose one day's roll is the raid. No calm or storm can delay it.
- `tests/drive.routes.spec.ts`: waits 420 s for a LAP (two passages), not one landing. The same sea applies to it; it is
  outside this order (a wait over 300 s, and not an arrival) and is the next candidate if it goes red.
- `tests/trade.loop.spec.ts`, `tests/trade.orderEstimate.spec.ts`, `tests/map.shipFullPath.spec.ts`: they send a trip and
  wait for the departure only.
- `tests/trade.flow.spec.ts` is not on main (PR #600, its own `LANDS_WITHIN_MS = 480_000`). After #600 merges it should
  import `LANDS_WITHIN_MS` and `arrivalCard` from the fixture. (Its failure message reads the status line before the
  wait begins, so it prints the line as it stood when she sailed, not when the wait ran out.)

## Decided by default
- The wait is 900 s, not #600's 480 s: chosen from the arithmetic above, since two delays on one hop are possible.
- The script guard also refuses an unclosed transaction and a write verb inside the wrapper (the spec's whole rule, not
  only its first clause): one rule in both places.
- `drive.map.spec.ts` was changed and type-checked but not run here: a local run overwrites tracked screenshots under
  `docs/`.

## Checks (local, headless, `vite preview` on localhost:4937)
- `tsc -b`: clean. `eslint` on the changed files: clean. `vite build`: built.
- One Playwright run, one worker, **33 of 33 passed** (6.9 min): `harness.guard` 7, `arrival.card` 3, `reputation` 4,
  `sections` 8, `duplication` 11. Every landing in this run came in undelayed (the trips went to Porto).
- No tracked screenshot changed.
