# 2026-10-18 — the circulation watch after 0172/0173, and 0174 (a city's people pay for what came from afar)

**The owner (2026-10-17 ~23:50 UTC):** *"Cities are powerful … and then make the economy circulate."* A city must
never go broke under normal trade. 0172 (00:32 UTC) topped every purse up to 2 M (capitals 10 M). 0173 (00:55)
priced a sale by the sea it crossed, up to 600×. The 0173 agent flagged the risk: merchants' planned loop profit
rose × 24 against ~660 M of city purses. This page watches prod and records what it found.

## 1. Method (prod, READ-ONLY)

- Every probe is `begin transaction read only; … rollback;` through `supabase db query --linked`.
- It calls only functions whose `pg_proc.provolatile` is `s`: `city_bid_factor`, `city_standing`,
  `treasury_balance`, `world.game_day`, `city_capital`, `city_surplus`. Each was checked before the first call.
  No volatile function was called. No EXPLAIN ANALYZE was run on anything volatile.
- **One reading** (scratch `watch.sql`) records:
  - per harbour: rolled purse, live purse (`port_treasury.ducats` + this hour's `treasury_flows`), reserve,
    `city_bid_factor`, standing purse, and the hour's flows by kind;
  - the merchants (`players` ⋈ `npc_houses`): purses, capital, how many are above 2× capital and by how much;
  - the players' purses;
  - the laps closed in the last hour;
  - `E_CITY_BROKE` refusals;
  - the arrivals sweep (`cron.job_run_details`, job 1 `byeharu-voyage:arrivals`, last hour).
- **Where refusals are logged.** A refusal is never written alone. A merchant's refused line goes into
  `standing_route_laps.skipped` (jsonb: port, line, verb, code, sentence) of the lap it belongs to, and is
  visible only once that lap closes. It carries no timestamp of its own, so refusals are bucketed by lap
  close (per half hour) and split by when the lap STARTED: after the grant (00:32:44), after the first lit
  roll (00:37), after 0173 (00:55). A player's refusal is the RPC's error and is not stored at all.
- `treasury_flows` holds only the flows not yet rolled. The `:37` roll (`tick_city`) moves them into
  `treasury_daybook` and the purse, so "the last hour's flows" is the flows table read just before `:37`.

## 2. Readings

"Other in − out" is every kind except BUY and SELL. Row 00:58 counts refusals in every lap that closed in the
hour. From 01:12 it counts only refusals in laps that started after the grant.

| UTC | last roll | city purses (live) | capitals | below reserve / thin / below standing | lowest city (live) | merchants | houses > 2× cap / over it | players | BUY in | SELL out | other in − out | E_CITY_BROKE (laps started after the grant) | arrivals avg / p95 / max s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 00:58 | 00:37 | 659.52 M | 231.30 M | 0 / 0 / 92 | 1.49 M (SLV) | 39.54 M | 76 / 8.60 M | 0.21 M | 6.77 M | -7.30 M | 0.36 M | 111 | 3.09 / 5.03 / 10.25 |
| 01:12 | 00:37 | 656.85 M | 231.86 M | 0 / 0 / 106 | 0.68 M (CLL) | 42.21 M | 70 / 9.44 M | 0.21 M | 10.80 M | -15.32 M | 1.68 M | 0 | 2.99 / 4.65 / 10.25 |
| 01:20 | 00:37 | 653.66 M | 231.77 M | 1 / 0 / 116 | 0.23 M (CLL) | 45.40 M | 89 / 11.66 M | 0.21 M | 13.54 M | -21.60 M | 2.05 M | 0 | 3.02 / 4.64 / 10.25 |
| 01:35 | 00:37 | 648.05 M | 231.87 M | 2 / 0 / 130 | 0.05 M (ACA) | 51.02 M | 122 / 15.70 M | 0.21 M | 16.76 M | -31.18 M | 2.79 M | 0 | 3.02 / 4.44 / 10.25 |
| 01:41 | 01:37 | 647.40 M | 230.59 M | 0 / 2 / 113 | 0.54 M (ACA) | 52.26 M | 141 / 16.30 M | 0.21 M | 0.60 M | -1.72 M | 0.67 M | 0 | 2.93 / 4.36 / 10.25 |

### What one hour looked like (00:37 → 01:37, rolled)

| | 00:37 | 01:37 | change |
|---|---|---|---|
| city purses | 659.7 M | 647.9 M | **−11.8 M** |
| merchant purses | 39.5 M | 52.3 M | **+12.7 M** |
| players | 0.21 M | 0.21 M | 0 |

- **The hour's city flows:**
  - BUY +16.8 M against SELL −31.2 M;
  - TAX +1.5 M, SHARE +1.38 M (one batch at the `:07` reconcile), WAGES +0.50 M, DONATION +0.16 M,
    PROVISION / REPAIR / TOW +0.15 M;
  - NPC_REFOUND −0.87 M, DIVIDEND −0.04 M.
- **The drain was rising:**
  - 4.6 M/h measured at 01:12;
  - 8.4 M/h at 01:20;
  - 11.8 M/h over the full hour.
  - More of 0173's long loops were landing: 29 post-0173 laps had closed at 01:12, 484 at 01:41 (max net +392 k).
- **Callao (CLL)** went 2.00 M → 0.68 M (01:12) → 0.23 M (01:20, under its 244 k reserve) → 0.17 M (01:35).
  - One merchant (Hermanos Tapia, fleet *Ruta Sofala*) sold Mace and Bird-of-Paradise Plumes there at ~27 k/t
    that she had bought at ~1.2 k/t: three lines of ~590 k at 01:07.
  - Profit 570 k on a 596 k line; tax 85 k back.
- **Acapulco (ACA)** went 2.00 M → 0.05 M (01:35).
- **The bid factor stayed 1 at both** while their live purses emptied. It read the ROLLED purse, so nothing
  slowed the drain inside the hour.
- **At the 01:37 roll** CROWN_AID topped both up to their reserves from their capitals:
  - CLL +500 k from AYU;
  - ACA +505 k.
  - The reserves had jumped with the haul, because the reserve is 3× the SELL day: CLL 244 k → 669 k,
    ACA 146 k → 542 k. So both now bid 0.62 / 0.55.
- **EARNINGS:** +0.68 M world-wide at the first day step.
- **Refusals, by lap close (half hour, UTC):**

| 23:00 | 23:30 | 00:00 | 00:30 | 01:00 | 01:30 |
|---|---|---|---|---|---|
| 180 | 188 | 69 | 32 | 30 | 1 |

  - In laps that started after 00:32:44, after 00:37 and after 00:55: **0, 0, 0**. Every refusal logged since
    the grant came from a stop made before it.
  - The near-misses (Callao, Acapulco) were caught by the 01:37 crown aid with minutes to spare.

### Where the money went (the distance premium)

- Every SELL flow between the 00:37 roll and 01:24 was matched to its event and its `port_goods` row (1,814 of
  1,814; scratch `prem.sql`, read-only).
- Cities paid **27.45 M** for cargo:
  - the base, Σ round(total / haul): **17.23 M**;
  - the distance premium, Σ total − base: **10.23 M (37 %)**, all of it to merchants (no player sold far).
- The purse's base share (17.2 M) against BUY taken in (~16 M) is the own-trade swing the 2 M / 10 M purses
  were sized for. **The premium is the one-way transfer.**
- A city sells its own goods at the maker's price (haul 1) and buys a far good at up to 600×. Each long haul
  therefore moves city money to the trader. The return paths that hour were 10× too small: TAX 1.5 M, SHARE
  1.38 M, DONATION 0.16 M.

### The return path's capacity (shares)

- 29.5 M of shares are offered world-wide at today's works levels: 80,011 shares over 952 works, level mean
  1.10, max 5.
- `npc_invest` took at most 50 houses an hour, one stake each, at the `:07` reconcile.
- The houses above the cap grew 76 → 141 in 43 minutes. The 50-a-hour door left most of them holding.

## 3. Projection

- **Total city money is falling steadily while merchant money climbs.** This is one of the two triggers.
  - −11.8 M in the first full hour, and the rate was still rising as post-0173 loops landed.
  - At 12 M/h the purses lose ~290 M a day. The 0173 planner figure (861 fleets × ~575 k a loop) is far above that.
- **Individual far ports empty inside an hour**, faster than the hourly roll can react: Callao 2.0 M → 0.17 M in
  58 minutes, Acapulco 2.0 M → 0.05 M. Each was saved only by CROWN_AID at `:37`.
  - A capital holds 10 M and gives only what it holds above its own reserve. With several of its cities
    draining at once, a capital empties within hours.
  - After that, `E_CITY_BROKE` is the only brake.

## 4. The fix — migration 0174 (`osn-circulation`)

The shape of (1) was the coordinator's (01:25 UTC): "the premium is paid by the city's people, not its purse".

1. **The base and the premium.**
   - `public.cargo_haul(port, good)` is the one reader of the stored haul a sale is priced with
     (`port_goods.haul`, ≥ 1).
   - In `cmd.do_sell` (the one SELL body), the city's PURSE pays the base, round(total / haul).
   - The premium, total − base, is posted first as `IMPORT_DEMAND` (+) through `treasury_post`. Then the SELL
     (−total) pays the seller in full.
   - The empty-purse rule judges the BASE: a partial fill shrinks to the steps the purse's share covers, and
     `E_CITY_BROKE` fires only when the purse cannot pay one step's base.
   - At a maker (haul 1) nothing changes.
   - The distance factor is untouched (`haul_at`, `haul_rows`, `port_goods.haul`, `mid_from_terms`).
2. **The reserve counts what the purse paid.** `city_sell_outflow` sizes the reserve (3 ×) from SELL net of
   IMPORT_DEMAND. A far city's reserve no longer balloons with the haul, the way CLL's 244 k → 669 k did.
3. **The bid reads the live purse.** `city_bid_factor` now reads `treasury_balance` (rolled + this hour's
   flows) against the rolled reserve.
   - Measured on prod with EXPLAIN ANALYZE of the stable reads over 4,760 calls: 0.224 ms a call as it was, about
     0.30 ms live (+0.07 ms).
   - The arrivals sweep averages 2.9–3.1 s against a 10 s budget.
4. **Merchants give back every hour.** `npc_invest_max_per_hour` 50 → 1000: every house above
   `npc_invest_above` × capital invests (or gives, 0145) at the hourly reconcile.
   - Measured locally (PGlite, a lit head-0174 world, merchants and influence on, N houses credited 2× capital):

     | houses | invested | gave | time |
     |---|---|---|---|
     | 50 | 50 | 2 | 194 ms |
     | 200 | 200 | 22 | 507 ms |
     | 821 | 821 | 189 | 2,456 ms |

   - 0114's 60 s deadline (`npc_upkeep_spent`) still defers what an hour cannot fit.
5. **The client.** The Town Hall's "Yesterday" shows *Paid by its people* (`src/features/map/CityTownHall.tsx`).

**Why this, and not the return paths alone.** The premium was 10.2 M in 47 minutes. TAX + SHARE + DONATION
together were 3.0 M in the hour, and the shares on offer are 29.5 M in all. No setting of the share knobs closes a
gap that size. Making the premium the townsfolk's leaves each purse with exactly the trade it was sized for.

## 5. The money supply after 0174 (stated; the owner decides on a sink)

- **Minted:**
  - IMPORT_DEMAND, ≈ the premium: ~13 M an hour at today's rate (10.23 M in 47 minutes), and rising as long
    loops land;
  - EARNINGS (0172), ~0.7 M at a day step;
  - FOUNDING of new houses.
- **Where it lands:**
  - The sellers' purses: today all merchants, since no player sold far in the window.
  - From them it returns to cities as TAX (≈ 15 % of the profit at a 3 % column × 5), SHARE and DONATION, and
    through services (PROVISION, REPAIR, WAGES).
  - Players' purses are flat (0.21 M).
- **Existing sinks:** none destroy money. Wages, repairs, provisions, builds, tuition, tow and hire are all paid
  INTO the harbour (0122; WAGES go to the harbour the voyage makes). The two stated leaks of ECONOMY_LOOP §1.2
  are ≈ 0.
- **So total money grows without bound** by roughly the premium, ~300 M a real day at the present rate,
  against ~700 M today.
  - Once the 29.5 M of offered shares are bought, merchant purses grow by the premium less tax.
  - Prices do not read the world's money (`world.quote` reads stock, affinity, spread, tax and the bid
    factor), so nothing in play inflates. The number itself grows.

### NOT the owner's — confirm

- (1) The premium is minted as townsfolk demand, not taken from the purse.
- (2) The reserve counts the purse's net outflow. (3) The live bid. (4) 1000 an hour.
- **No sink is built.** Options for the owner:
  - (a) a ceiling on a merchant's purse, above which the surplus is given to the cities of her loop;
  - (b) the premium paid only while a city is under its standing purse;
  - (c) a share of the premium kept by the city (the townsfolk pay the city, not all of it to the seller);
  - (d) merchants spend their surplus on bigger hulls (S18 yards).

## 6. Verify (run once each, worktree `~/dev/bv-circ` off main `11b8a9e`, real `npm ci`, the main clone's `node_modules/.cache` copied, no `.env.local`)

- **Hunks against prod.**
  - `cmd.do_sell`, `city_sell_outflow` and `city_bid_factor` were re-dumped from prod at head 0173 with
    `pg_get_functiondef` (read-only).
  - Each of the 7 hunks occurs exactly once, and the three bodies reverse to the dumps (scratch check on the LF
    file).
- **Cached-prefix build** (`BYEHARU_PREFIX_CACHE=required npm run build`):
  - restored 128/166, applied 38 including 0174;
  - world-guard ok;
  - `tsc -b` + vite built (10 m 25 s, most of it the 38 files the copied cache lacked).
- **The 0174 receipt**, applied to the head-0173 snapshot, dark (fresh chain) and lit (`city_treasury_switch(true)`
  first), 389–489 ms. Both said: *"sold 10 t for 181744: people paid 179373, purse 2371 (haul 76.65); a purse
  of the base 2274 bought all 10 t (total 174323); one ducat short of a step's base refused E_CITY_BROKE; the
  bid at half the reserve (live) is 0.75 … city_sell_outflow is SELL net of IMPORT_DEMAND at 238 harbours …
  bodies reverse … no client door moved."*
- **`npx eslint .`** clean. **`npx tsc -b`** clean. **`db:check-versions`**: 166 distinct, no collisions.

## 7. Not done

- No merge, no `db push`, no production write.
- Deploy per `docs/DEPLOY_RUNBOOK.md` with the clock unwound. The probe sells on a docked fleet inside a
  rolled-back sub-block.

## 8. The rest of the watch (after the fix was built; 0174 not deployed)

(filled in as the watch continues)
