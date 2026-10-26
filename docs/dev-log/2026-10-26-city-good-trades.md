# 2026-10-26 — Who bought what: a city's trades of one good (owner row 211)

**Branch `osn-city-good-trades`: migration `20260818000227_a_city_remembers_who_traded_there.sql` (renumbers to
the prod head + 1 at deploy; its tags are `0227`) + the client. NOT merged, NOT deployed.**

**The owner, verbatim (docs/OWNER_REQUESTS.md row 211):**

> *"i want to see who bought what when pressed a city - clicking trade goods."*

## 1. Why no existing read could answer — read from prod, not guessed

- A trade is a `BOUGHT` / `SOLD` event (0007). On prod the ONLY bodies that write them are `cmd.do_buy` and
  `cmd.do_sell` (`pg_proc` search, 2026-10-26); every other path (`cmd.run_manifest`, `cmd.execute_order`,
  the merchants' laps) calls those two. The payload carried `fleet, good (NAME), qty, avg_price, total…` —
  **no city**. A fleet moves on, so "where" was lost.
- The city's side of a trade, a `SELL` / `BUY` row in `public.treasury_flows`, names the harbour — but
  `tick_city` rolls flows into the daybook and deletes them hourly (prod: oldest flow 00:37 at 01:26).
- The Stats rollups (0214 `stats_city_good`) keep sums per slot, no names.
- Prod 2026-10-26 01:26 UTC: 216,606 events / 101 MB; 29,510 trades (39 by players since August, the rest
  by merchants — `npc_compact` keeps a merchant's events about 6 hours).

## 2. What 0227 does

| Part | What |
|---|---|
| The event names its city | `cmd.do_buy` and `cmd.do_sell` gain one payload key, `port` = the harbour's **code** — the key and spelling every other event already uses for a city (FOUNDED, TRAINED, ENROLLED; `src/features/ledger/headline.ts` reads it as a code). One hunk each, sliced from the live body, asserted to occur once and to reverse; ACL / volatility / definer / config unmoved. |
| One index | `events_trades_port_good` on `(payload->>'port', payload->>'good', created_at desc) where kind in ('SOLD','BOUGHT')`. |
| One read | `world.city_good_trades(p_port uuid, p_good uuid, p_limit int default 50) returns jsonb`, `stable`, security definer, `search_path = public, pg_temp`, granted to `authenticated` only. The last 7 days, newest first, at most `limit` (clamped 1…200): `at, company, merchant, own, side (bought/sold — the company's side), qty, price (avg_price), total`. Unknown port or good → `E_NO_SUCH_GOOD`. |
| The registry | `public.client_rpc_entry_points()` gains `('world', 'city_good_trades', 'uuid, uuid, int')` — one hunk. |

**Not backfilled.** Events written before the deploy carry no city and are not listed; events are append-only
and are not rewritten. Merchants trade constantly and their events live ~6 h, so the lists fill within hours
of the deploy; a player's trades before the deploy stay unplaced.

### Decided by default (the owner may reverse each)

- **Names are shown** — players' and merchants' company names. The owner's word (row 211) outranks the older
  "never show a rival's books" reading. The read gives the trade only: **no purse, no fleet, no position**.
- **Not gated by investment.** Any signed-in player sees any city's list (the owner asked for it on a city
  press, with no stake condition). `anon` cannot call it.
- **7 days, 50 rows.** A merchant's events are compacted after ~6 h anyway, so in practice a busy pair's 50
  newest trades are minutes old.

### Why the index (measured on prod, read-only)

`explain analyze` of the shape without the city (a plain SELECT on `events`, nothing volatile): a good's last
50 trades over 7 days was a backward scan of `events_created_at` filtering **127,533 rows, 239 ms**; with the
city as a further filter, a quiet pair would scan the whole week. The partial index holds only the trades
(~30 k rows; a few MB). It is built plainly (a migration is one transaction, so not `CONCURRENTLY`): it reads
the heap once — a full parallel seq scan of `events` measured **475 ms** cold — and holds inserts into
`events` until the migration commits (the self-assert after it is a handful of ms; see §4).

## 3. The client

- `src/lib/rpc`: `worldCityGoodTrades` in the catalog (`catalog.ts`), `CityGoodTrade` / `CityGoodTrades` in
  `types.ts`, `worldCityGoodTrades(port, good, limit = 50)` in `index.ts`. The local (PGlite) backend calls it
  from the catalog like every other read.
- **Where the press lives.** Every press on a city's good opens one of three trays: PORT's read-only
  `PriceTray` (the city Info face when no fleet is there, and the MAP's city panel — both through
  `src/live/PortPrices.tsx`), the quay's `TradeTray` (`src/live/PortTrade.tsx`, a fleet docked), and the desk's
  trade doorway `src/features/command/markets/DeskTrade.tsx` (the Markets face, and Trade › Here —
  `HereMarket.tsx`, #315, merged from main). The Stats → Cities detail rows (`src/features/stats/CityDetail.tsx`)
  are not pressable. All three now render ONE component, `src/live/CityGoodTrades.tsx`: a caption **Trades**, then a `Row` per trade — the company's full
  name (wraps, never cut; the full name is also the hover title), tagged `you` / `merchant`; line 2
  "**Bought 5 · 12 🪙 each**"; the value "**5 min ago**" (the one `formatRelative`, the shell's clock). Yours
  is gold. Empty: "No trades in 7 days." A failed read shows nothing (the tray is true without it). The quay
  re-asks on the fleet's version, so a trade she just made appears.
- Words (`src/lib/i18n/dict/trade.ts`), EN / KO: Trades / 거래 · Bought / 구매 · Sold / 판매 ·
  `{side} {qty} · {price} each` / `{side} {qty}개 · 개당 {price}` · you / 나 · merchant / 상인 ·
  No trades in 7 days. / 7일간 거래 없음.

## 4. Proof run here (Windows, cached PGlite chain, headless; never from zero)

- **Migration, cached preamble prefix (216 restored) + 0226 + 0227, self-asserts only:**
  `0227 self-assert ok: A CITY REMEMBERS WHO TRADED THERE. do_buy / do_sell / the registry re-cut by one hunk
  each, each reversed; registry +1; walls 0; index valid. Probe at Lisbon, anise: a sale of 10 and a purchase of
  5, both events naming LIS, both listed as the probe's own (2 row(s) in the list), newest first; limit 1 → 1
  row; an unknown good refused. world.city_good_trades × 6 = [1.00, 0.00, 1.00, 0.00, 0.00, 0.00] ms. Rolled back.`
- `npx tsc -b` 0; eslint on every touched file 0; `npm run build` 0 with no `.env.local` (world image: 217 of
  218 restored, 1 applied).
- `tests/i18n.keys`, `tests/i18n.ko`, `tests/duplication`: 14 passed, 2 skipped.
- `vite preview --port 4195` on `localhost`: `tests/city.goodTrades.spec.ts` **1 passed** — at 390 × 844 buy a
  lot of Aniseed at Lisbon, press Aniseed again: the first row reads "Casa de Aveiro · you — Bought 10 · 15.1 🪙
  each — just now", no sideways scroll; at 1280 the same press shows the same row, no sideways scroll.

**FOUND, NOT MINE — a latent hour-of-day flake in 0226's self-assert.** Applied between 01:00 and 01:59 UTC, 0226
fails: `0226 self-assert FAIL: the day folded day 2026-10-24 o 10.00 h 13.00 l 10.00 c 13.00 n 4`. Its probe plants
two hours at `date_trunc('hour', now()) - 26 h` and `+ 1 h`; in hour 01 those straddle UTC midnight, so the day
row it checks folds 4 points, not 8 (0226:612–652). Production applied it at another hour and is unaffected; any
from-zero or prefix-miss apply (CI's chain jobs) that runs 0226 in hour 01 UTC will be red. 0226 is applied and
must not be edited; the fix belongs in a forward migration or in the proof's clock. Here the apply was re-run at
02:00 UTC and was green.

## 5. PROD CHECKS FOR THE MAIN SESSION

Read-only. One statement per block, no trailing semicolons. Every block is a pure SELECT (or a plain
`explain` without ANALYZE) — no `cmd.*`, no `tick_*`, nothing volatile.

**(1) Not applied yet** — expect 0, 0, 0 and the head before this file

```sql
select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'world' and p.proname = 'city_good_trades') as read_exists, (select count(*) from pg_class c where c.relname = 'events_trades_port_good') as index_exists, (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'city_good_trades') as registered, (select max(version) from supabase_migrations.schema_migrations) as head
```

**(2) Hunk 1 of `cmd.do_buy` occurs once** — expect 1

```sql
select (length(d) - length(replace(d, h, ''))) / length(h) as do_buy_hunk_1 from (select replace(pg_get_functiondef('cmd.do_buy(uuid,jsonb)'::regprocedure), chr(13), '') as d, '    public.emit_event(f.player_id, ''BOUGHT'', jsonb_build_object(' || chr(10) || '      ''fleet'', f.name,' as h) z
```

**(3) Hunk 1 of `cmd.do_sell` occurs once** — expect 1

```sql
select (length(d) - length(replace(d, h, ''))) / length(h) as do_sell_hunk_1 from (select replace(pg_get_functiondef('cmd.do_sell(uuid,jsonb)'::regprocedure), chr(13), '') as d, '    public.emit_event(f.player_id, ''SOLD'', jsonb_build_object(' || chr(10) || '      ''fleet'', f.name,' as h) z
```

**(4) Hunk 1 of the registry occurs once** — expect 1

```sql
select (length(d) - length(replace(d, h, ''))) / length(h) as registry_hunk_1 from (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), chr(13), '') as d, '      (''cmd'',         ''watch_price'',           ''uuid, uuid'')' || chr(10) || '    ) as t(s, f, a)' as h) z
```

**(5) Good names are unique** (the payload names the good) — expect goods = distinct_names

```sql
select count(*) as goods, count(distinct name) as distinct_names from public.goods
```

**(6) The table the index is built over** — the size of the build

```sql
select count(*) as events, count(*) filter (where kind in ('SOLD', 'BOUGHT')) as trades, count(*) filter (where kind in ('SOLD', 'BOUGHT') and payload ? 'port') as trades_with_port, pg_size_pretty(pg_total_relation_size('public.events')) as size from public.events
```

**(7) The plan without the index** — a backward scan of `events_created_at` with a filter

```sql
explain select e.id from public.events e where e.kind in ('SOLD', 'BOUGHT') and e.payload->>'good' = 'Wine' and e.created_at > now() - interval '7 days' order by e.created_at desc limit 50
```

**After the deploy** — the new trades name their city, and the read's plan uses the index (expect
`events_trades_port_good`)

```sql
select e.kind, e.payload->>'port' as port, e.payload->>'good' as good, e.created_at from public.events e where e.kind in ('SOLD', 'BOUGHT') order by e.created_at desc limit 5
```

```sql
explain select e.id from public.events e where e.kind in ('SOLD', 'BOUGHT') and e.payload->>'port' = 'LIS' and e.payload->>'good' = 'Wine' and e.created_at > now() - interval '7 days' order by e.created_at desc limit 50
```

### Results, run read-only against prod 2026-10-26 01:3x UTC (head 0226)

| Check | Result |
|---|---|
| (1) | read_exists 0 · index_exists 0 · registered 0 · head 20260818000226 |
| (2) do_buy hunk | 1 |
| (3) do_sell hunk | 1 |
| (4) registry hunk | 1 |
| (5) | goods 565 · distinct_names 565 |
| (6) | events 221,351 · trades 30,186 · trades_with_port 0 · 103 MB |
| (7) | `Limit → Index Scan Backward using events_created_at`, `Filter: kind = ANY ('{SOLD,BOUGHT}') AND payload->>'good' = 'Wine'` (est. cost 5,739); measured earlier with ANALYZE on the same plain SELECT: 127,533 rows removed by the filter, 239 ms |
