# 2026-11-05 - A broke city is short (migration 0306)

Branch `reserve-floor` · migration `supabase/migrations/20260818000306_a_broke_city_is_short.sql` · proof `scripts/db/proofs/16_reserve_floor.sql`
· mutation harness `scripts/ops/harness/reserve-floor/proof-0306.mjs`. Prod head when cut: 0305. **Not deployed** (PR only). Alters live play: 30-minute after-check below.

## The order
Step 1 of the REVIEW at the top of `docs/CITY_CONVOYS.md`: a broke city must count as short. The reserve is 3 days of a city's own recent sale payouts, so a broke city's reserve is near zero and `CROWN_AID` does not top it up.

## The callers (read on prod, 2026-11-05): why the floor is NOT in `treasury_reserve`
The brief was `greatest(floor, today's value)` in the one place the reserve is computed, unless that changes what a player's sale pays or locks a capital's surplus. It does both, so the brief's fallback applies: **only the aid decision uses the floor.**

| Reader of the reserve | What it does | With the floor inside `treasury_reserve` |
|---|---|---|
| `city_bid_factor` -> `world.price_terms`, `world.quote_terms`, every price | the bid falls linearly to `city_bid_floor` (0.5) as the purse falls under the reserve; reserve 0 means factor 1 | **a sale pays less at 121 harbours today, mean -29 %, worst -50 %** (the very cities that need cargo) |
| `city_surplus` -> `capital_pays` (merchant gifts, `CROWN_CALL`), `insurance_claim`, `voyage.forced_home`, coupons in `tick_city`, `city_can_spend` -> `tick_contracts` | "the one figure every spender reads" | 50,000 d. of every purse locked; 6 of the 10 working capitals have a reserve under the floor, so their surplus falls |
| `city_day` CROWN_AID, capital's term | the capital gives only `city_surplus(capital)` | locks the capital's own surplus |
| `tick_city` build step | `greatest(reserve, city_standing)` | changes what a city builds |
| `world.town_hall`, `stats_watch` | print the reserve, "Under reserve" | numbers move |
| `city_treasury_switch` | sets the reserve, and judges the circulation at switch-on | off the path today |

`E_CITY_BROKE` paths (`treasury_post`, `cmd.do_sell`) read the live purse, not the reserve: unaffected either way, except that a city with more gold refuses less.

## What was built (one authority per concept)
| Concept | The one place |
|---|---|
| The floor | knob `treasury_reserve_floor`, 50,000 d. (decided by default; owner approved the plan). 0 = today's rule |
| The level the crown tops a city up to | `public.city_aid_target(port)` = `greatest(rolled reserve, floor)`, STABLE, server-only |
| Who is short, who pays, how much | `public.crown_aid(p_only_capital)`, the aid loop of `city_day` **moved** (not copied), server-only. `p_only_capital` narrows a pass to one realm: the probe's; the live call passes null (as `npc_tend_houses` does, 0234) |
| The hourly call | `public.city_day`, 5 hunks, answers the same `aided` and `aid` keys |

The loop was moved because `docs/OPS_HEALTH.md` section 4 forbids a self-assert from running a real game step: with the loop inside `city_day`, the migration could not test it without aiding real cities. It is also the one place step 3 (cargo ships) will replace.

Unchanged: `treasury_reserve`, `port_treasury.reserve`, `city_bid_factor`, `city_surplus`, `treasury_post`, `mint_guard`, every switch. A capital still gives only above its own reserve. `CROWN_AID` stays two `treasury_post` rows, moved, nothing minted.

Decided by default:
- A capital's own purse is judged by its own reserve, as today, not the floor: the brief forbids locking its surplus. So a capital with a tiny reserve can still give down to that reserve, under 50,000 d. (today too). 4 capitals hold under 50,000 d.
- "Under reserve" on the Stats Watch and the hall's reserve figure are unchanged: they still mean the reserve.

## Prod reads before writing (pure SELECTs, 2026-11-05 01:58 UTC, 21 minutes after the 01:37 aid)
Facts: `tick_city` runs hourly at :37, so CROWN_AID does too. Last run: 1,738,021 d. to 81 cities. 246 harbours; 23 nations, of which only the 10 great powers hold harbours, so **10 working capitals**. 10 harbours have no capital (AUK, DAR, FRE, HNL, MEZ, POR, PTL, PUS, SAL, WLG) and get no aid, today or after this. 56 harbours have reserve 0; 124 have a reserve of 1 to 49,999; 154 non-capital harbours hold under 50,000 d., of which 38 have reserve 0 and 67 already "meet" their reserve.

**First run, estimated.** Simulated in one SELECT from the snapshot with `crown_aid`'s exact rule: harbours in code order, each capital's surplus used up in turn.

| Capital | Purse | Own reserve | Surplus | Gives today | Short today | Gives with floor | Short with floor | Extra gold | Capital after |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| AMS | 247,880 | 52,932 | 194,948 | 194,948 | 8 | 194,948 | 13 | 0 | 52,932 |
| BUS | 2,618 | 273 | 2,345 | 2,345 | 4 | 2,345 | 12 | 0 | 273 |
| GUA | 124,399 | 22,521 | 101,878 | 101,878 | 5 | 101,878 | 14 | 0 | 22,521 |
| IST | 507,442 | 42,420 | 465,022 | 465,022 | 22 | 465,022 | 28 | 0 | 42,420 |
| KAR | 1,300 | 990 | 310 | 310 | 6 | 310 | 13 | 0 | 990 |
| LIS | 325,917,903 | 172,890 | 325,745,013 | 399,403 | 9 | 918,477 | 18 | **519,074** | 324,999,426 |
| LON | 6,575 | 5,946 | 629 | 629 | 13 | 629 | 17 | 0 | 5,946 |
| MRS | 11,505 | 27,825 | -16,320 | 0 | 8 | 0 | 12 | 0 | 11,505 |
| SAK | 262,406,117 | 71,220 | 262,334,897 | 375,569 | 13 | 958,837 | 22 | **583,268** | 261,447,280 |
| SVQ | 480,917,516 | 274,353 | 480,643,163 | 407,823 | 9 | 699,322 | 15 | **291,499** | 480,218,194 |
| **All** | | | | **1,947,927** | | **3,341,768** | | **1,393,841** | |

- **At this snapshot the floor moves about 1.39 M d. once**, all of it from LIS, SAK and SVQ, on top of about 1.95 M the old rule would give at that moment. No gold is made.
- **No capital goes under its own reserve.** Every capital ends at or above it; MRS is already under and gives nothing, as today.
- **Seven of the ten realms get no more gold.** Their capitals already give all they have. There, more cities count as short, so the same gold goes further down the code list less evenly: the first cities take up to 50,000 d. each and later ones may get less than today (IST aids 11 cities, not 13; AMS 5, not 6; GUA 3, not 4). The floor alone does not help them; that is step 2 of the plan.
- After the first run, the extra each hour is only what floored cities paid out since. Not estimated: it depends on sales.
- **The figure moves with the hour.** A second read at about 02:12 UTC gave 966,340 d. extra (LIS 362,578, SAK 295,920, SVQ 307,615, GUA 227) with the same result for every capital. So expect roughly 1 to 1.4 M, read again just before deploy (check 4).

The query is in PROD CHECKS below (`first run`).

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
1. Head: `select max(version) from supabase_migrations.schema_migrations` -> `20260818000305`.
2. The body the hunks were cut against: `select md5(replace(pg_get_functiondef('public.city_day(timestamptz)'::regprocedure), E'\r', ''))` -> `f914180a29f19f0e1393bb0d8a2bb24e`. All 5 hunks were checked once each against that body.
3. Names free: `select to_regprocedure('public.city_aid_target(uuid)') is null and to_regprocedure('public.crown_aid(uuid)') is null, (select count(*) from public.world_config where key = 'treasury_reserve_floor'), (select count(*) from public.ports where code like 'QX_'), (select count(*) from public.nations where code = 'QX6')` -> true, 0, 0, 0.
4. First run (every function called is `s`; re-run it just before deploy and compare with the table):
```sql
with c as (
  select t.port_id, p.code, t.reserve, public.treasury_balance(t.port_id) as bal, public.city_capital(t.port_id) as cap
    from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
), caps as (
  select distinct c.cap, k.code as cap_code, k.bal as cap_bal, k.reserve as cap_res, k.bal - k.reserve as cap_surplus
    from c join c k on k.port_id = c.cap where c.cap is not null
), f as (select unnest(array[0, 50000]) as floor_d),
need as (
  select f.floor_d, c.cap, c.code, greatest(f.floor_d, c.reserve) - c.bal as need
    from f cross join c
   where c.cap is not null and c.cap <> c.port_id and greatest(f.floor_d, c.reserve) > 0 and c.bal < greatest(f.floor_d, c.reserve)
), given as (
  select n.*, least(n.need, greatest(0, k.cap_surplus - coalesce(sum(n.need) over (partition by n.floor_d, n.cap order by n.code rows between unbounded preceding and 1 preceding), 0))) as give
    from need n join caps k on k.cap = n.cap
)
select k.cap_code, k.cap_bal, k.cap_res, k.cap_surplus,
       coalesce(sum(g.give) filter (where g.floor_d = 0), 0) as give_today,
       coalesce(sum(g.give) filter (where g.floor_d = 50000), 0) as give_floor,
       k.cap_bal - coalesce(sum(g.give) filter (where g.floor_d = 50000), 0) as cap_after
  from caps k left join given g on g.cap = k.cap group by 1, 2, 3, 4 order by 1
```

## The 30-minute after-check
Deploy, then wait for the first `:37` run; the window is the 30 minutes after it. Run this once at about :40 and once at about :07 (the same file; a pure SELECT, literal 50,000 until read from the knob). Baseline, 2026-11-05 02:09 UTC, floor not in: last aid 1,738,021 d. to 81 cities, net 0, 116 cities under 50,000, 2 capitals under their own reserve, 69 harbours bid under 1, 1,763 SELL orders and 136 `E_CITY_BROKE` in 30 minutes.
```sql
with c as (
  select t.port_id, t.reserve, public.treasury_balance(t.port_id) as bal, public.city_capital(t.port_id) as cap
    from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
), k as (select distinct c.cap from c where c.cap is not null)
select now() as at,
  (select coalesce(sum(f.ducats) filter (where f.ducats > 0), 0) from public.treasury_flows f where f.kind = 'CROWN_AID') as last_aid,
  (select count(*) filter (where f.ducats > 0) from public.treasury_flows f where f.kind = 'CROWN_AID') as last_aided,
  (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.kind = 'CROWN_AID') as aid_net,
  (select max(f.created_at) from public.treasury_flows f where f.kind = 'CROWN_AID') as aid_at,
  (select count(*) from c where c.cap <> c.port_id and c.bal < 50000) as cities_under_50k,
  (select count(*) from c join k on k.cap = c.port_id where c.bal < c.reserve) as capitals_under_own_reserve,
  (select count(*) from c where public.city_bid_factor(c.port_id) < 1) as bid_under_1,
  (select count(*) from public.orders o where o.verb = 'SELL' and o.issued_at > now() - interval '30 minutes') as sells_30m,
  (select count(*) from public.orders o where o.error_code = 'E_CITY_BROKE' and o.issued_at > now() - interval '30 minutes') as city_broke_30m
```
Good: `aid_at` is the new `:37`; `aid_net` = 0; `last_aid` about 3.3 M or more on the first run (the table, plus what the hour drained), then lower; `cities_under_50k` falls, by up to 55 (the cities the LIS, SAK and SVQ realms can fund); `capitals_under_own_reserve` not above 2 plus any capital sales push under (the aid cannot); `bid_under_1` does not rise; `city_broke_30m` does not rise.

**Bad, roll back:** `aid_net` not 0; a capital's purse falls below its reserve by CROWN_AID (`last_aid` far above the table); `tick_city` reports a `day` error; or `bid_under_1` jumps.

## Forward rollback (owner only, a NEW migration at prod head + 1)
```sql
update public.world_config set value = '0' where key = 'treasury_reserve_floor';
```
With its self-assert on the value. The next `:37` run is then today's rule, proved by the "floor 0" tests. The functions stay. Gold already moved stays where it went: it was moved, not made.

## Tests
- **Red first** (`BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/reserve-floor/proof-0306.mjs`, cached world at 0305, 290 of 290 restored, no from-zero replay). Eight broken files, each failing its self-assert for the intended reason:
  the floor ignored (the bug itself); the floor put in `treasury_reserve` (a sale pays less: "another function moved"); a capital giving its whole purse ("did not stop exactly at its reserve"); the capital not paying, so gold minted ("the sum of purses moved"); floor 0 not today, by 1 d.; a top-up overshooting by 1 d.; a hunk cut against a different body; a hunk that does not reverse.
- **Green:** the real file, 250 ms, on PGlite. Self-assert, on a probe realm of 5 rolled-back harbours (no real city, no real game step): a broke city with zero outflow reads short and gets exactly 49,000 d.; floor 0 equals today's rule city by city (2 aided, 50,800 d.; the zero-reserve city nothing); capital stops exactly at its reserve; a capital under it gives nothing and is not aided; realm's sum of purses unchanged in all four passes; a second pass gives nothing; bid, surplus and reserve the same at both floors; 5 hunks reverse to the pre-image; grants and settings of `city_day` unmoved; every other function and world_config row unmoved; new functions server-only; nothing of the probe survives.
- **Proof 16** (`node scripts/db/proof.mjs 16_`, 5/5 markers, 0.9 s): the REAL `city_day` over the whole local world, both floors, rolled back: floor 0 = today; exact top-up; the answer's `aided` / `aid` are numbers equal to its flows; every purse in the world summed, moved 0; bid, surplus, reserve unmoved. Proof 03 (grants): 12/12.
- `BYEHARU_PREFIX_CACHE=required npm run build` ran to the end (0306 applied over the restored prefix); eslint on the harness clean. All 5 hunks checked against the prod body.

## Not verified
- Nothing ran on prod: no aid with the floor has happened. The table is a simulation from one snapshot, not a run.
- The self-assert's real time on prod (budget 45 s; 250 ms on PGlite, whose world has no sales). The probes do five 246-harbour candidate reads there, against prod's live flows.
- Whether this lowers `E_CITY_BROKE`: the after-check will show it. A floor of 50,000 d. covers a few sales at most.
- The size of the hourly extra after the first run.
- The real-Postgres path (`disposable-chain`): CI runs it on this PR.
