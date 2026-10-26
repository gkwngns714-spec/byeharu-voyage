# 2026-10-26 — 0238: she buys where she can sail (`osn-fix-shut-reason`, owner on the Trade card)

**The owner.** *"Best, Port Royal — Hold too full: 4.3 days of supplies, crossing needs 7.8 days. - I don't get it,
if this is a limit then i can go to city by city, short distances with lots of visiting. right? why is this a limit?"*

## 1. Why (prod, read-only, head 0235–0237)

- His Gaivota (`51b8f474…`) was sailing to Cumaná with 149 furs (178.8 of 180 t). `supply_reach` = 4.28 days, cap 883 nm.
  The board plans from Cumaná (her destination), which is right.
- From Cumaná the capped search reaches **Port Royal directly, 844.9 nm** (within the cap). Port Royal was never out of reach.
- The card was the **tea** board. Tea was not aboard, so every sell row is "buy first, then sell". `world.good_board`
  picked the buy city as the cheapest seller anywhere, without asking whether she could sail there. For tea that was
  **Guangzhou**. The only tea sellers with stock were GUA, FUZ and NIN. Every way from the Caribbean to China has a
  1,613.6 nm crossing, which needs 7.8 days of supplies. That is the same figure Tsushima showed.
- So the Port Royal row carried the crossing to Guangzhou, and the words did not say Guangzhou.

Two faults: (1) the buy city was chosen without her reach. A dearer seller within her stores was passed over, and
every sell row was shut by the leg to the cheap one. (2) A row shut by the way to the buy city read as if the sell
city were out of reach.

**For the owner, in three sentences.** Port Royal is close and was never the problem: from Cumaná you reach it in one
short leg. The card was for tea, which you did not have, so it planned "buy tea first, then sell at Port Royal". The
only tea for sale was in China, and every way to China has one long ocean crossing (7.8 days of supplies) that a
nearly full hold cannot carry, but the card did not say that the crossing was on the way to China.

## 2. What changed (migration `20260818000238_she_buys_where_she_can_sail.sql`, `world.good_board`, 4 hunks)

| Part | What |
|---|---|
| Buy city | With no city asked, the board buys at the cheapest seller whose buy row is `sailable` (every leg within her stores, the 0231 capped search). Only when no seller is sailable does the cheapest of all stand. A city asked (`p_from`) is kept. So a sell row is "Hold too full" only when no route of short legs runs through any buy city. When one exists, the row is sailable through it, with its stops listed. |
| Shut row | When the buy city's own route is past her stores, every shut sell row's `shut.figures` gains `buy_at` and `buy_at_name`. |
| Client | `reachWords` prints new `desk.holdTooFullBuy`: "Hold too full: bought at {city}, the trip has a crossing that needs {need} of supplies; you can carry {carry}" (KO "화물 과다: {city}에서 사 오는 길에 보급 {need}이 드는 횡단이 있음; 보급 최대 {carry}"). `BoardShut.figures` gains the two optional keys. `tests/planWords.spec.ts` +1 case. |

**Decided by default.**
- A sailable seller is preferred over a cheaper unsailable one at any price difference.
- A row shut while the buy city is sailable (the sell city is past her stores from there) keeps 0231's words.
- The board still uses one buy city for every sell row (as before). Within the capped sea, a city reached from where
  she sails is reached from any buy city she can reach, through that port, so one sailable buy city opens every sell
  city she could reach. Probe (b) asserts this row for row.
- Not changed: a shut row's `longest_leg` reads `{miles: 0}` (the reach CTE's `greatest(null, 0)`, from 0188). The words
  never read it for a shut row.

## 3. Measured (local PGlite, merged with main at 0237: 225/228 restored from the prefix cache, 0236–0238 applied)

```
0238 probe (a): angelica-root (1 boards tried): the pre-image buys at ARK, past her stores (cap 503 nm) — 0 of 246 sell rows sailable
0238 probe (b): now buys at TRO (the cheapest seller within her stores): 87 of 246 sell rows sailable, every one by legs within 503 nm; good_board 1123.0, 1196.0, 1073.0 ms (pre-image 1098.0, 1037.0, 1296.0 ms)
0238 probe (c): asked to buy at ARK: 223 shut sell row(s), each naming ARK (Arkhangelsk); otherwise the pre-image to the byte, e.g. {"nm": 1614, "buy_at": "ARK", "cap_nm": 503, "leg_days": 6.0, "need_days": 6.9, "carry_days": 2.1, "buy_at_name": "Arkhangelsk"}
0238 probe (d): parity: angelica-root bought at TRO, and anise aboard, = their pre-images
0238 self-assert ok: SHE BUYS WHERE SHE CAN SAIL. ... 16.9 s.
```

Timing: the board costs the same (one extra scan of the buy rows).

## 4. PROD CHECKS (read-only, pure SELECTs, one statement per block; run by me on 2026-10-26; pasted results)

Every function called has `provolatile` 's' (4b).

### 4a. Preconditions. Expect good_board's ACL, STABLE, definer, config as below.

```sql
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select p.oid::regprocedure::text || ' ' || coalesce(p.proacl::text, '') || ' ' || p.provolatile::text || ' ' || p.prosecdef::text || ' ' || coalesce(p.proconfig::text, '')
          from pg_proc p where p.oid = to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)')) as good_board
```
Result: `20260818000237`, `world.good_board(uuid,uuid,uuid,numeric) {postgres=X/postgres,authenticated=X/postgres} s true {"search_path=public, pg_temp"}`.

### 4b. Volatility. Expect `s` on every row.

```sql
select p.oid::regprocedure::text as fn, p.provolatile from pg_proc p
 where p.oid in (to_regprocedure('voyage.reach_passage(uuid,uuid,uuid,numeric)'), to_regprocedure('public.supply_reach(uuid)'),
                 to_regprocedure('public.passage_reach_nm(uuid)')) order by 1
```
Result: `passage_reach_nm(uuid) s`, `supply_reach(uuid) s`, `voyage.reach_passage(uuid,uuid,uuid,numeric) s`.

### 4c. The hunks on the LIVE body. Expect `1, 1, 0`.

```sql
select (length(gb) - length(replace(gb, 'order by (e->>''price_each'')::numeric, e->>''port'' limit 1;', ''))) / length('order by (e->>''price_each'')::numeric, e->>''port'' limit 1;') as h2,
       (length(gb) - length(replace(gb, '''shut'', (select sh.refusal from shuts sh where sh.nm = r.shut_leg and r.nm is null),', ''))) / length('''shut'', (select sh.refusal from shuts sh where sh.nm = r.shut_leg and r.nm is null),') as h3,
       (length(gb) - length(replace(gb, 'v_src_cut', ''))) / length('v_src_cut') as new_already
  from (select replace(pg_get_functiondef(to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)')), chr(13), '') as gb) d
```
Result: `1, 1, 0`. I also dumped the live body (at 0235, and again at 0237, after 0237 re-cut good_board elsewhere) and
matched all 4 hunks with a node script. Each OLD text occurs once, each NEW once after, and the result reverses to the pre-image.

### 4d. The owner's case: from Cumaná with his cap, Port Royal is one leg; every tea seller is past a 1,613.6 nm crossing.

```sql
select r.code, r.nm, r.stops, r.max_leg_nm, r.shut_leg_nm
  from voyage.reach_passage('c85b31cb-8274-4801-999d-6c40f57ddf74', '51b8f474-9c57-4e4e-b3f2-da2143c2838d',
                            (select id from public.ports where code = 'CUM'), 883.4) r
 where r.code in ('POR', 'HAV', 'GUA', 'FUZ', 'NIN', 'TSU') order by r.code
```
Result:
```
FUZ  null  null   null   1613.6
GUA  null  null   null   1613.6
HAV  1570.9 [POR] 844.9  null
NIN  null  null   null   1613.6
POR  844.9 []     844.9  null
TSU  null  null   null   1613.6
```

The board itself was read once, while she was still at sea with the furs, as the owner (read-only transaction,
`request.jwt.claims` set locally). The tea board was `basis step, bought_at GUA`. The sellers with units were GUA 103.04,
FUZ 107.78 and NIN 111.41, none sailable. Port Royal's row was shut with `{nm 1614, need_days 7.8, carry_days 4.3}`. On the
rum and tobacco boards (bought at VER and JAM), Port Royal was sailable through HAV or STA>HAV. The fleet has since
docked at Cumaná and sold the furs (cap 176,682 nm), so that board can no longer be reproduced live.

## 5. Proof run here

- Cached-prefix apply (`node scripts/db/build-image.mjs`), 0238's self-assert ok (§3).
- `npx tsc -b` 0. eslint on the 4 touched client/spec files 0. `npm run build` with no `.env.local` 0.
- On my own `vite preview --port 4215 --strictPort --host localhost`, killed afterwards: `tests/planWords.spec.ts` 13 passed
  and `tests/rpc.goodBoard.spec.ts` 4 passed. Node's `navigator.language` was forced to `en-US` by a preload, because this
  machine reports `ko-KR`.

## 6. Rollback

Forward slice: reverse the 4 good_board hunks (each OLD text is in the file verbatim). The client's new key is only read
when `buy_at` is served.
