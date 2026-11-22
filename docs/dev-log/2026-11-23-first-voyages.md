# 2026-11-23 — First voyages (0476, dark: `first_voyages_enabled`)

Roadmap 2026-11-23 slice 8; playable 2026-11-22 §6 findings 4 and 12. Migration `20260818000476_first_voyages.sql`, proof 179,
harness `scripts/ops/harness/first-voyages/`, client `src/live/FirstVoyageLine.tsx` (one line under the goal card).

## What it is

A new company (founded under 7 real days ago) is offered five starter jobs, in order. Each pays once, from her capital's purse
(the gift's payer, `public.capital_pays`: no new gold), plus Reputation:

| # | Step | Met when | Pays |
|---|---|---|---|
| 1 | deliver | a request delivered (a `PREMIUM` ledger row) | 2,000 + 20 Rep |
| 2 | profit | 10,000 of trade profit (`ledger_is_trade`, 0474) | 3,000 + 30 Rep |
| 3 | trading | Trading 3 (her paid mark, `house_level_marks`) | 3,000 + 30 Rep |
| 4 | captain | a captain hired at the Inn (`player_officers`) | 3,000 + 30 Rep |
| 5 | hull | two ships, counting a hull on order (0465) | 5,000 + 50 Rep |

16,000 coin and 160 Reputation in all (about a third of the second hull's 48,557-52,000). Every figure is in one knob,
`first_voyages_steps`; a step is cut to `first_voyages_ducats_max` (5,000) / `first_voyages_reputation_max` (50).

The deliver step names THE job: of the open hold jobs with a source (0466 / 0473), the one whose trip from her capital to its
source and on to its harbour is shortest for a Barca, with twice that trip inside the time the job stands. Its line, "Deliver 40 Lead
to Lisbon · Buy at Bristol · 19m", is a press that plans that trip on the Map (the request board's own "Buy at" press, #800).

## Decided by default (the owner may reverse)

- **Order**: deliver, profit, Trading 3, captain, second hull (the brief listed hull third; it is the long goal, so last, as the
  roadmap's (e)). Each condition reads what she has done since founding, so a step already met pays the moment it is reached.
- **"Take a hire job"** = hire a captain at the Inn (no other hire job exists).
- **Deliver** counts any delivered request (a city's request is out of a newcomer's reach; a hold job's bonus is the same `PREMIUM`).
- **Who**: companies founded under `first_voyages_days` (7). An older company is never offered it (no back-pay of five rewards).
- **When paid**: when she next reads the chain (the read pays, as `world.contracts` winds its board): no job runs over every company.
  The client asks it whenever her purse moves.
- **Realm cannot pay**: the step waits (`waiting`, "Pay waits"), nothing written; it is paid on a later read.
- **Not trade**: `VOYAGE_REWARD` is a moved word, not in `ledger_is_trade`, so Rank Week and the gift's worth do not count it.
- **The slice 7 sighting step** (roadmap (d)) is not in the chain: slice 7 is not built. The named reward (a captain, a fitting, a flag)
  is left out: coin and Reputation only, as the brief asks.
- **Client**: one line under the goal card, drawn only while the chain is open (dark or done: nothing). The goal card itself is not
  touched (another builder is redoing it, #813).

## Numbers

Measured in CI (proof 179, PGlite): see the PR body.
