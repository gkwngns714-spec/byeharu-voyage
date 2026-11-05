# 2026-11-05 - Insurance pays its way (migration 0314)

Branch `insurance-0316` (first numbered 0316, renumbered next after 0313; the branch keeps its name so the PR stays open) · migration `supabase/migrations/20260818000314_insurance_pays_its_way.sql` · mutation harness `scripts/ops/harness/insurance/proof-0314.mjs`. Prod head when cut: 0312. Deploys after 0313. **Not deployed** (PR only). Alters live play: after-check below. Slice W0b of `docs/WORLD_POWERS.md`.

## The order
Cities paid out 29.5 M d. in 24 h and took in 7.4 M d., cause unmeasured. Measure first; a bug is fixed at the root; a pricing choice goes to the owner as a proposal.

## The proven cause: a bug, not a price (prod, read-only, 2026-11-05 ~09:00 UTC)
**No rate changes. No premium rises.** `insurance_raid_loss`, `insurance_margin`, `insurance_keep_pct` and `endurance_margin` are untouched.

**The cities were paying for cargo the ship still had.** 0279's `voyage.settle` guard says a dry day is a forced home when `d < v_cap`. It was written for "the trailing day" that `voyage.day_ends_at` clamps at the ETA, so a ship drinking her last cask as she makes port would dock. But a CALM or STORM stacks **several** days on the ETA, not one:
- `voyage.total_days` counts the delay: `ceil((sim + delay) / 24)`;
- every boundary after the delay is pushed by it too: `d × 24 + delay`, clamped at the ETA;
- so every day with `d × 24 ≥ sim` lands on the same instant, the arrival.

A merchant carries `ceil(1.15 × sim / 24) + 1` days of stores (`public.npc_leg_days`), so 1.5 to 4 days of delay empties her casks on one of those stacked days. `d < v_cap` is still true, and she is "forced home" at the moment she enters port, usually into that same port. The whole hold is lost, the hull is hurt, and the insurer owes 90 % of a hold that had arrived.

Example: VAL to BAR, 139 nm, 7 hours' sailing, 2 days of stores. A calm of 68.69 h on day 1 makes `total_days` 4. Day 2 ends on the ETA, she is dry, 2 < 4, so she is forced "home" to BAR, her destination.

### Every claim on record
`insured_voyages` holds only about 7.6 hours (the compact job cuts it with its voyages; the "week" in the brief does not exist on prod), so this is 23,248 policies, 01:15 to 08:50 UTC. All are merchants: **no player holds a policy or made a claim.**

| Cause | Claims | Lost at cost | Owed (90 %) | Paid by cities | Short |
|---|---|---|---|---|---|
| `FORCED_HOME` | 142 | 17,155,187 | 15,439,671 | **6,572,594** (92 %) | 8,867,077 |
| `PLUNDERED` | 31 | 1,216,500 | 1,094,854 | **601,805** | 493,049 |
| `STRIPPED`, storms, shoals | 0 | | | | |
| **Premiums on the same policies** | | | | **1,901,821 in** | |

Raids alone are covered **1.74 times** by premiums (1.90 M against 1.09 M owed), about the design's margin once the 321 voyages still at sea finish.

### Were the forced homes real?
283 forced homes in the record, read from `voyage_events.resolved_at` (the day's own boundary) against `voyages.eta`:

| | Forced homes | Insured | Into her own destination |
|---|---|---|---|
| **Day boundary IS the ETA: she had arrived** | **280** | **142** | 279 |
| Boundary before the ETA: really short of port | 3 | 0 | 3 |

- The 3 real ones were 0.12 to 0.30 of a day short, each after `FOUL_WATER`, all with empty holds, no claim.
- Of the 280: 141 carried insured cargo (39,297 units), 1 uninsured cargo (12 units), 137 sailed empty and were still hurt. 32,525 hull points in all.
- **100 % of the money paid for forced homes went to ships that had arrived.**

### When it began
`stats_city.flows`, by UTC day:

| Day | Premiums in | Paid out |
|---|---|---|
| 10-24 | 2.38 M | 1.14 M |
| 10-27 | 1.57 M | 0.47 M |
| 10-29 | 0.75 M | 0.13 M |
| **10-30 (0279 live)** | 2.46 M | **5.08 M** |
| 11-02 | 11.01 M | 49.69 M |
| 11-03 | 7.97 M | 34.10 M |
| 11-04 | 7.56 M | 33.63 M |

Insurance earned every day until the day 0279 shipped. The record has gaps (10-31 is missing and 10-30 and 11-01 are part days: the count job was failing), and 0285 multiplied goods prices and 0302 multiplied purses in this span, so read the turn, not the size.

### Everything else the brief asked

| Question | Answer |
|---|---|
| Quote × actual loss | Quoted loss 1,908,880; actual raid loss 1,216,500 (0.64, 321 voyages still at sea). Dry loss 17,155,187 was never in the quote: `voyage.risk_quote` prices raids only |
| Who claims | Merchants 173 of 173. Players 0 |
| Premiums off the wrong value | No: `value` equals cargo × basis on every one of 23,276 rows |
| Stale danger number | No: `voyage.risk_quote` reads the live `voyage.hazard_roll` chance at each departure |
| Price formula | Holds on 23,275 of 23,276. The one other row was written 10-29, before 0285 multiplied stored policies; not a defect |
| Any claim paid twice | No: 0 policies with 2 claims, 0 voyages with 2 payouts, 0 over 90 % of value, 0 lost over value |
| Merchants' premiums capped | No cap in the code; only "a merchant who cannot pay sails uninsured". Highest premium 7,765 d. on a 3.47 M d. hold; 0.0598 % of value on average |
| Did the 60-second game day break a rate | **No.** Not the coupon mistake. `risk_quote`, `insurance_price`, `insure_voyage`, `insurance_claim`, `hazard_roll`, `sea_mix`, `settle` and `forced_home` read no `game_day` figure. A voyage-day is 24 sim-hours on `time_compression` 960, 90 s, and a premium is per voyage |

### By voyage length, sea, ship and cargo (same 23,248 policies)
Nothing here points to a place, ship or cargo: the dry claims follow the delays, wherever they fall.

| Passage | Policies | Premium | Quoted loss | Dry: n, owed | Raids: n, owed |
|---|---|---|---|---|---|
| < 500 nm | 7,546 | 117,909 | 115,104 | 16, 3,653,043 | 4, 45,545 |
| 500-1,000 | 6,956 | 246,241 | 245,071 | 26, 2,033,224 | 6, 353,762 |
| 1,000-2,000 | 2,791 | 180,198 | 180,552 | 29, 2,638,882 | 6, 98,892 |
| 2,000-4,000 | 3,727 | 542,774 | 546,352 | 50, 3,895,690 | 8, 169,150 |
| 4,000+ | 2,228 | 814,699 | 821,802 | 21, 3,218,832 | 7, 427,505 |

- **Sea she left by, top dry owed:** Baltic 3.60 M, Mediterranean 1.92 M, North Atlantic 1.76 M, South Atlantic 1.00 M, South Pacific 0.89 M, Caribbean 0.85 M. Top raid owed: East China Sea 0.34 M, South China Sea 0.28 M.
- **Ship:** carlat 79 dry, 9.02 M; nau 33, 4.25 M; barca 22, 1.13 M. Raids: carlat 18, 0.65 M; barca 11, 0.42 M; nau 0.
- **Cargo, top owed:** Baltic amber 2.41 M, amber 0.80 M, scroll paintings 0.73 M, clocks 0.62 M, pearls 0.57 M, velvet 0.54 M, ivory 0.52 M, gold 0.51 M. High value per ton, nothing more.

## What was built
One hunk of `voyage.settle`: `if v_end <= 0 and d < v_cap` becomes `if v_end <= 0 and v_bound < v.eta`, a day that ends before she arrives. It covers 0279's final day too, since a final day always ends on the ETA. `v` is re-read at the end of each day, so `v.eta` is current. A ship really dry at sea is forced home, claim and all, as before.

**A clamped day stays clamped.** After the fix a stacked day still rolls its hazard, and a calm there moves the ETA. Her next day cannot then fall before the new ETA: a day is clamped when `d × 24 ≥ sim`, and that does not depend on the delay.

### Decided by default (the owner may reverse)
- **A delay alone never strands her.** Once her sailing time is done, the next boundary is her arrival, so she docks even if a long calm held her out on empty casks. The other reading, cutting her mid-calm, loses the same holds on her destination's doorstep: the same drain, and then it would need the fourfold premium to pay for it.
- **A real dry day stays covered and unpriced:** 3 in 7 hours, all empty.

## Estimate (arithmetic from the same read, not a forecast)
| A day | Now | After |
|---|---|---|
| Premiums in | 7.4 M | 7.4 M |
| Paid out | 29.5 M | **about 1.9 M to 3.5 M** (raids: paid to owed, 601,805 and 1,094,854 over 7.6 h) |
| Net out of city purses | **-22.1 M** | **about +4 M to +5.5 M** |

- **The premium question in `docs/WORLD_POWERS.md` falls away:** merchants need no fourfold premium.
- **Merchants keep about 54 M d. a day of cargo at cost** that was being destroyed (17.16 M in 7.6 h), and the hull damage stops (32,525 points in that record).
- **A knock-on, not measured:** that cargo now reaches market. A sale is paid from the city's purse, so some of what insurance stops draining may leave as purchases instead, against goods the city then holds. Read purses a day after deploy, not only this line.

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
Prod head must be 0313 by then. Run after rebasing on 0313.

```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,                                                   -- 20260818000313
       md5(replace(pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure), E'\r', '')) as settle_md5,     -- e3adabaa9b4007b672b9600bb1129b16 at head 0312; a change means re-check the hunk
       position('    if v_end <= 0 and d < v_cap' in pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure)) > 0 as hunk_line;   -- true
```
```sql
select (select jsonb_object_agg(key, value) from public.world_config
         where key in ('insurance_raid_loss', 'insurance_margin', 'insurance_keep_pct', 'endurance_margin')) as knobs;   -- 0.084, 0.1, 0.1, 1.15: unchanged by this file
```
The hunk text was checked against prod's own `voyage.settle` at head 0312: each of its lines occurs once. 0313 (#496) does not touch that body.

## The 30-minute after-check (T = the deploy instant)
```sql
select count(*) filter (where ve.resolved_at >= v.eta) as forced_on_the_eta,   -- 0: this was 40 an hour
       count(*) filter (where ve.resolved_at < v.eta) as forced_at_sea,        -- 0 to 2: real ones
       count(*) filter (where v.status = 'SAILING') as still_at_sea            -- 0
  from public.voyages v join public.voyage_events ve on ve.voyage_id = v.id and ve.kind = 'FORCED_HOME'
 where ve.resolved_at > 'T';
```
```sql
select e.payload->>'cause' as cause, count(*) as n, sum((e.payload->>'paid')::numeric) as paid, sum((e.payload->>'short')::numeric) as short
  from public.events e
 where e.kind = 'INSURANCE_PAID' and e.created_at > 'T'
 group by 1;   -- FORCED_HOME: none unless forced_at_sea above says so; PLUNDERED about 4 an hour
```
```sql
select count(*) as arrived, count(*) filter (where i.voyage_id is not null) as insured
  from public.voyages v left join public.insured_voyages i on i.voyage_id = v.id
 where v.status = 'ARRIVED' and v.eta > 'T';   -- arrivals carry on as before, with about 40 more an hour
```
Also: `bash scripts/ops/health.sh`, arrival lag under 5 s, `byeharu-voyage:arrivals` succeeding. **A day later,** in Stats: `INSURANCE` above `INSURANCE_PAID`, about 7 M against about 3 M, and the purses.

**Red, and act:** any row `forced_on_the_eta`, a fleet stuck `SAILING` past its ETA, or arrivals failing: stop with the rollback below and tell the owner.

## Forward rollback (owner only, a NEW migration at prod head + 1)
Swap this file's `v_old` and `v_new`. That brings the bug back, so it is not advised unless arrivals fail. No data was changed, and past claims stay paid.

## Tests
- `BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/insurance/proof-0314.mjs`: from the cached world at head 0312 (297 of 297 restored, nothing from zero), **the real file green, 10 of 10 mutations red for the intended reason, the real file green again** (1.0 to 1.6 s an apply): the guard left at `d < v_cap`; `d + 1 < v_cap`; never forced home; forced only with no delay; `<=` for `<`; the eta before the delay; a scene not run dry; a scene with no delay; hunk drift; hunk reversal.
- **The same run with 0313 in the chain,** #496's file byte for byte (hash checked), copied in for the run only, 297 restored and 1 applied: the real file green, 10 of 10 red, the real file green. This is the order deploy will use. An apply took 1 to 37 s here: the PC was loaded by other work (the same cache restore took 2 s, then 90 s), so read 1 to 3 s as its own cost.
- **The self-assert reproduces the bug on the pre-image body:** dry on stacked day 2 of 5, her own ETA: ABORTED, hold 0, 1,800 owed. The new body on the same scene: ARRIVED, DOCKED at Funchal, hold 2,000, no hull lost, 0 owed. The same settled day by day, and after a storm's 36 hours. A real dry day at sea, with and without a calm first: forced home, 1,800 owed. A dry final day with no delay: an arrival.
- The first runs failed on my own probes, each fixed: a load inside one `or`, a comparison that included `sim` (speed is rolled per voyage), and a scene whose "at sea" day was really a stacked one. One mutation survived because it was the same rule in other arithmetic (`d < total_days - ceil(delay / 24)`); it was replaced by a truly broken one rather than the assert being bent.
- `npm run db:check-versions`, eslint on the harness.

## Not verified
- Nothing is deployed; no prod `voyage.settle` has run this code. The harness world is the chain, not prod's data.
- Prod's record holds 7.6 hours of policies, not a week. Before that, only the daily totals.
- The estimate assumes today's raid and delay rates. How much of the saved cargo returns to purses through sales is not measured.
- A calm rolled on a stacked day after she is dry is reasoned above, not run: no probe forces that roll.
- Proved against #496's 0313 as it stands now, not against main with 0313 merged: re-run the harness at the rebase. Whether the full CI suite is green: see the PR.
