# 2026-11-05 - A capital draws on its nation (migration 0307)

Migration `supabase/migrations/20260818000307_a_capital_draws_on_its_nation.sql` · proof `scripts/db/proofs/17_crown_call.sql`
· mutation harness `scripts/ops/harness/crown-call/proof-0307.mjs`. Prod head when cut: 0306. **Not deployed** (PR only). Alters live play: 30-minute after-check below.

## The order
Step 2 of the REVIEW at the top of `docs/CITY_CONVOYS.md`: before funding its cities, a capital may draw on its nation's rich cities. Reuse `CROWN_CALL`, no second mechanism. Owner-approved 2026-11-05; the rule below is decided by default, every number a knob.

## What was built (one authority per concept)
| Concept | The one place |
|---|---|
| The share of a donor's surplus one run may take | knob `crown_call_share`, 0.10. 0 = 0306's behaviour |
| What a donor keeps | knob `crown_call_cover`, 20 reserves above its aid target (see "The bid") |
| What a harbour can be called for | `public.crown_call_room(port)`, STABLE, server-only |
| Who calls, how much, from whom | `public.crown_call(short)`, server-only: two `treasury_post` rows, kind `CROWN_CALL`, moved, nothing minted |
| A harbour's lock, not waited for | `public.treasury_try_lock(port)`: the key of `public.treasury_lock`, asserted the same |
| Who is short | still `public.crown_aid`, 4 hunks: the roster is read once, its locks taken, the call made, then the aid pays out as 0306 did |

**The rule.** Per capital with a short city: what its cities need, less its surplus, is called from the harbours of its nation, the largest room first, each once. Room is `floor(least(share × above, above − cover × reserve))`, never under 0, where `above` = purse − `city_aid_target`.

Unchanged: `city_day`, `capital_pays`, `treasury_lock`, `city_surplus`, `treasury_reserve`, `city_bid_factor`, `mint_guard`, every switch. `crown_aid`'s answer gains `called` and `donors`; `city_day` still passes on only `aided` and `aid`, so those two live in the flows (the after-check reads them there).

Decided by default:
- **Surplus is counted above the aid target, not above the reserve.** The target is at or above the reserve, so a donor still never goes under its reserve; it also means a city the crown would top up is never drained in the same run. The brief said "`city_surplus`-style".
- **A capital under its own reserve calls that too.** The aid pays only above the reserve, so otherwise the cities would be short by exactly that. Three capitals were under theirs at the second read below (IST, AMS, LON). When no city of its realm is short, it calls nothing.
- **The cover knob is new, not in the brief.** It is what makes "a donor near its reserve must not drop what it pays players" hold through the hour, not only at the moment of the call. Set to 0 and only the share limits a call.
- **Largest room first** is richest surplus first, except where the cover cuts a donor's room.
- **A busy donor waits till next hour.** The next richest pays this hour.

## Callers and locks (read on prod, 2026-11-05)
- The only caller chain is `tick_city` -> `city_day` -> `crown_aid`. pg_cron `byeharu-voyage:city`, `37 * * * *`. No quay. `lock_timeout` 2 s; `deadlock_timeout` 1 s. A lock failure lands in the `day` block of `tick_city`, which rolls the whole day back and reports it, so a new wait on a donor would risk the hour's aid and crown tax. Hence the try-lock.
- **Before 0307,** the aid took a city, its capital, the next city, and so on.
- **With 0307,** those same locks in that same order are taken first, all of them. Then the first donor is touched. A donor is never waited for, and after that point the run takes no lock it can wait on: `treasury_post` with no player takes none, and `CROWN_CALL` and `CROWN_AID` are moved kinds, so `mint_guard` does not take the gate (0268), and `stats_live_add` is a plain INSERT.
- **Beat (0265, 0267):** house first, then harbour, many acts in one transaction. If a beat waits on a donor this run holds, this run never waits on the beat after that, so no cycle.
- **`capital_pays` (0234):** realm harbour, then capital. It can hold a donor and wait on a capital this run holds; this run then fails the try-lock on that donor and passes over it. No cycle.
- **The hold is not new in practice.** The coupons step of the same `tick_city` already locks every harbour with a share due, 236 of 246, and this run's seven donors were all among them (read at 02:47 UTC). `treasury_try_lock` on a lock this transaction holds answers true.

## The hourly run time
`tick_city` took 8.0 to 9.8 s over the last 12 runs. Nothing else limits it but the hour. One read of purse, target, reserve and capital for all 246 harbours could not be told from `select 1` through the CLI (3.7 s against 3.6 to 4.3 s, two reads each): under the noise, so roughly 100 ms or less. A run adds one such read per calling capital, at most 10, plus 2 rows per donor: expect well under a second. Not measured as a run.

## Prod reads before writing (pure SELECTs from a file, 2026-11-05, head 0306)
Two reads, first-run simulation with the rule exactly as built (query below).

**Second read, 02:59 UTC:**

| Capital | Purse | Surplus | Short cities | Needed | Shortfall | Called | Top donor (purse, reserve) |
|---|---:|---:|---:|---:|---:|---:|---|
| IST | 30,880 | -68,231 | 25 | 1,212,437 | 1,280,668 | **1,280,668** | VLL (244.3 M, 7,860) |
| AMS | 28,837 | -54,302 | 14 | 715,453 | 769,755 | **769,755** | COP (1.28 B, 323,550) |
| KAR | 4,872 | 4,221 | 15 | 634,509 | 630,288 | **630,288** | BSR (50.3 M, 9,999) |
| LON | 922 | -47,405 | 13 | 557,334 | 604,739 | **604,739** | DUB (76.6 M, 0) |
| MRS | 82,805 | 70,952 | 12 | 504,133 | 433,181 | **433,181** | GOA (3.36 B, 135,849) |
| GUA | 290,214 | 258,918 | 15 | 644,770 | 385,852 | **385,852** | MAL (476.1 M, 10,581) |
| BUS | 164,280 | 164,280 | 10 | 361,020 | 196,740 | **7,356** | THA 4,586 (95,867, 0), JAF 2,770 (77,708, 0) |
| LIS | 325.4 M | 325.3 M | 13 | 598,782 | 0 | 0 | none needed |
| SAK | 261.5 M | 261.5 M | 17 | 770,575 | 0 | 0 | none needed |
| SVQ | 480.3 M | 480.1 M | 11 | 520,501 | 0 | 0 | none needed |
| **All** | | | | | | **4,111,839** | |

- **First read, 02:47 UTC (11:47 KST):** 4,408,784 d. in all, with the same seven nations and the same top donor in each. So expect **roughly 4 to 4.5 M d. once**, moved, not made, and read again just before deploy (check 4). Purses move hard within the hour, so the real figure at :37 will differ.
- **One donor pays in six of the seven nations.** The share cap binds only in BUS, which holds little anywhere, as the REVIEW said: it stays short by about 189,000 d. Every other realm's cities are funded in full.
- **Hourly figure after the first run: not estimated.** It depends on sales. 0306's aid moved 1.7 M d. in its last pre-floor hour.

## The bid: could a donor's fall?
**No, from the call itself, by construction.** `city_bid_factor` is 1 while the purse is at or above the reserve. A harbour with any room is above its target, which is at or above its reserve, and it ends the call at least `cover × reserve` above that target.

**Through the following hour:** the reserve is 3 game days of sale payouts and a game day is 60 s, so 20 reserves is about one real hour of payouts. So a called donor holds about an hour's payouts over its reserve even with no income. The rule refuses to go lower. On the numbers: the donors keep at least 3,960 reserves above their reserve (COP, the tightest with a reserve), or hold a zero reserve (DUB, THA, JAF, bid 1 by definition). In the 12 minutes after the 02:37 roll, sale payouts were 16,126 d. at BSR, 45,104 at MAL, 45,231 at GOA, 81,256 at DUB and 182,843 at COP, against purses of 50 M to 3.4 B; none at VLL or THA; JAF was not read.

**Repeated runs:** a donor gives at most 10 % of its room a run, so hourly calls shrink it toward its line, never past it. A rich donor's drain is bounded by the realm's need, about a million a run against hundreds of millions. When it thins, the next richest takes over.

## PROD CHECKS (pure SELECTs from a file, one statement per file, before deploy)
1. Head: `select max(version) from supabase_migrations.schema_migrations` -> `20260818000306`.
2. The body the hunks were cut against: `select md5(replace(pg_get_functiondef('public.crown_aid(uuid)'::regprocedure), E'\r', ''))` -> `a71826a38065ce8f61fb6019b4e59985`. The local world at 0306, where all 4 hunks were applied, gives this same hash.
3. Names free: `select to_regprocedure('public.crown_call(jsonb)') is null and to_regprocedure('public.crown_call_room(uuid)') is null and to_regprocedure('public.treasury_try_lock(uuid)') is null, (select count(*) from public.world_config where key in ('crown_call_share', 'crown_call_cover')), (select count(*) from public.ports where code like 'QY_'), (select count(*) from public.nations where code = 'QX7')` -> true, 0, 0, 0.
4. First run (every function called is `s`; re-run it just before deploy and compare with the table):
```sql
with c as (
  select t.port_id, p.code, t.reserve, public.treasury_balance(t.port_id) as bal, public.city_capital(t.port_id) as cap, public.city_aid_target(t.port_id) as target
    from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
), need as (
  select cap, count(*) as short_n, sum(target - bal)::bigint as need from c where cap is not null and cap <> port_id and bal < target group by 1
), gap as (
  select k.port_id as cap, k.code as cap_code, k.bal as cap_bal, k.bal - k.reserve as cap_surplus, n.short_n, n.need, greatest(0, n.need - (k.bal - k.reserve))::bigint as gap
    from need n join c k on k.port_id = n.cap
), d as (
  select c.cap, c.code, c.bal, c.reserve, c.target,
         greatest(0, floor(least(0.10 * (c.bal - c.target), (c.bal - c.target) - 20 * c.reserve)))::bigint as room
    from c where c.cap is not null and c.cap <> c.port_id
), o as (
  select d.*, g.gap, coalesce(sum(d.room) over (partition by d.cap order by d.room desc, d.code rows between unbounded preceding and 1 preceding), 0) as before
    from d join gap g on g.cap = d.cap where d.room > 0
), x as (
  select o.*, least(o.room, greatest(0, o.gap - o.before))::bigint as call from o
)
select g.cap_code, g.cap_bal, g.cap_surplus, g.short_n, g.need, g.gap,
       coalesce((select sum(x.call) from x where x.cap = g.cap), 0) as called,
       (select jsonb_agg(jsonb_build_array(x.code, x.bal, x.reserve, x.call) order by x.call desc) from x where x.cap = g.cap and x.call > 0) as donors,
       (select count(*) from x where x.cap = g.cap and x.bal - x.call < x.reserve) as donors_under_reserve
  from gap g order by 7 desc, 1
```

## The 30-minute after-check
Deploy, then wait for the first `:37` run; the window is the 30 minutes after it. Run this once at about :40 (first run) and once at about :07 (30 minutes later): the same file, a pure SELECT. `treasury_flows` keeps the last run until the next `:37` rolls it; `:07`'s merchant gifts can add `CROWN_CALL` rows of their own, so read `call_gross` at :40 for the run's figure. Baseline before the deploy: read it once, just before, with this same file.
```sql
with c as (
  select t.port_id, t.reserve, public.treasury_balance(t.port_id) as bal, public.city_capital(t.port_id) as cap
    from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
), k as (select distinct c.cap from c where c.cap is not null)
select now() as at,
  (select coalesce(sum(f.ducats) filter (where f.ducats > 0), 0) from public.treasury_flows f where f.kind = 'CROWN_CALL') as call_gross,
  (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.kind = 'CROWN_CALL') as call_net,
  (select count(*) filter (where f.ducats < 0) from public.treasury_flows f where f.kind = 'CROWN_CALL') as called_from,
  (select max(f.created_at) from public.treasury_flows f where f.kind = 'CROWN_CALL') as call_at,
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
Good: `call_at` is the new `:37`; `call_net` = 0; `aid_net` = 0; `call_gross` about 4 to 4.5 M on the first run; `cities_under_50k` falls sharply right after, then climbs back as the hour's sales drain the purses; `capitals_under_own_reserve` falls; `bid_under_1` does not rise; `city_broke_30m` does not rise.

**Bad, roll back:** `call_net` or `aid_net` not 0; a donor's purse under its reserve from a call; a `tick_city` run over about 15 s or a `day` error (the job's `cron.job_run_details`; the `day` error itself is not stored, so a missing `:37` in `aid_at` is the sign); or `bid_under_1` jumps.

## Forward rollback (owner only, a NEW migration at prod head + 1)
```sql
update public.world_config set value = '0' where key = 'crown_call_share';
```
With its self-assert on the value. The next `:37` run is then 0306's rule, proved by the "knob 0" scenes. The functions stay. Gold already moved stays where it went: it was moved, not made.

## Tests
- **Red first** (`BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/crown-call/proof-0307.mjs`, cached world at 0306, 291 of 291 restored, no from-zero replay). 16 broken files, each failing its self-assert: no call at all (the bug itself); the call 1 d. over; a capital under its reserve not made whole; gold burned; gold minted; a donor called to its whole purse; a donor judged from its reserve, not its target; the share cap ignored; the cover ignored; the poorest first; a busy donor called anyway; a donor outside the realm; knob 0 still calling; the try-lock on another key; a hunk against another body; a hunk that does not reverse. Writing them found a real gap in the first draft of the assert: the outside-the-realm break passed, so the probe gained a richest harbour outside the nation, and a thin-donor scene was added for the whole-purse break.
- **Green:** the real file, 1.5 s on PGlite. Self-assert, on a probe nation of 8 rolled-back harbours and 1 outside it (no real city, no real game step): the shortfall called exactly, 93,900 d., and the capital ends exactly at its reserve; a rich capital calls nothing; a second pass moves nothing; richest room first; every donor held to its share, 50,000 and 30,000 d., the rest left short; a capital 6,777 under its reserve made whole first; cover: a donor stops exactly 20 reserves above its target; a busy donor passed over for the next; a donor near its line gives only its 200 d.; in every scene no donor under its reserve or target, every donor's bid 1, sum of purses unchanged; knob 0 equal to 0306's own body (a `pg_temp` copy of the pre-image) in 3 scenes, flow by flow and purse by purse; 4 hunks reverse; grants of `crown_aid` unmoved; every other function and `world_config` row unmoved; new functions server-only; nothing of the probe survives.
- **Proof 17** (`node scripts/db/proof.mjs 17_`, 5/5 markers, 2.1 s): the REAL `city_day` over the whole local world at both shares, rolled back: share 0 calls nothing; the shortfall called exactly; the answer's `aided` / `aid` equal its flows; every purse in the world summed, moved 0; the donor unhurt. Proof 16: 5/5. Proof 03 (grants): 12/12.
- eslint on the harness clean.

## Not verified
- Nothing ran on prod: no call has happened. The table is a simulation from two snapshots, not a run.
- **The lock design has not been run under two real sessions.** PGlite has one connection, so "a busy donor is passed over" is proved by a stand-in try-lock that answers false, and the no-deadlock argument above is by reading the code, not by a test.
- The self-assert's real time on prod (budget 45 s; 1.5 s on PGlite, with 26 passes).
- The added run time of the real job: bounded above by reads, not measured.
- Whether this lowers `E_CITY_BROKE`: the after-check will show it. A city holding 50,000 d. covers a few sales at most.
- The size of the hourly call after the first run, and how fast the top donors thin.
- The real-Postgres path (`disposable-chain`): CI runs it on this PR.
