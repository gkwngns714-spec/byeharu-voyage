# 2026-10-26 — Every list can be sorted: filters and sorts on every Stats face (owner row 228, `osn-stats-filters`, migration 0244)

> *"also create filter for all parts in stats, for example in cities such as by area (continents), or by richest, etc"*
> (2026-10-26, docs/OWNER_REQUESTS.md row 228.)

Server + client, one slice. `supabase/migrations/20260818000244_every_list_can_be_sorted.sql` (prod head is 0240 at
writing; the deploy renumbers to head + 1, `_0244` suffixes and the probe uuid go with it).

## What the owner sees

One bar on every face: a row of chips that scrolls sideways (one on at a time, "All" first, plus on/off toggles), then
pickers and a Sort picker. Each face remembers its choice in this browser.

| face | filters | sorts |
|---|---|---|
| Cities | area (Europe, Africa, Middle East, India, SE Asia, East Asia, Americas, Oceania), country, "My cities" | richest (purse), most traded 24 h, most invested, biggest stock, name |
| Markets | kind (the good's category), rarity | movers (biggest move either way), rose most, fell most, most traded, price, name |
| Merchants | country (new list: every company) | richest (cash now), best day, most laps, biggest fleet, name |
| Overview | the money by kind: all / new / burned / moved | — |
| Me | best sales; the captains' board by country (ranks kept) | best sales: profit, newest, biggest sale |

The count in each heading is the filtered count; an empty result says "Nothing matches.". On Markets, the risers,
fallers and most traded are cut from the filtered goods.

## Decided by default (the owner may reverse)

- **Area = a fixed grouping of the 25 authored regions**, in ONE server function `public.region_area(text)`: the
  Atlantic Isles and the Aegean, Anatolia & Black Sea count as **Europe**; Levant & Egypt and Arabia & the Gulf as the
  **Middle East**; the Maghreb, West Africa and East Africa as **Africa**; Western India and Eastern India, Ceylon &
  Burma as **India**; the four American regions as **Americas**.
- **"Most invested"** = Σ paid in by every investor in that city (city_shares.paid). **"My cities"** = I hold shares.
- **"Biggest stock"** = Σ units in the city's market **as of the last count** (summing 139k port_goods rows costs
  130–330 ms, too slow for a read asked every second). It is blank until the first count after deploy (≤ 15 min).
- **Merchants' list** is every company (821 on prod), first 60 shown with "Show all". A merchant's purse is her cash
  now; a company the world keeps, not a player's purse.
- Sort ties break on the name. An unknown figure (no price, no move, no stock yet) sorts last.

## The pieces

- `src/components/ui/FilterBar.tsx` — the one primitive: `chips` (one-of), `toggles`, `picks` (native selects for long
  lists), `sort`. It decides nothing. MoneyLog (owner 227, #337) can adopt it: its chips + "mine" are a `chips` + a
  `toggles`.
- `src/components/ui/filterState.ts` — `useFilterChoice(list, defaults)`: key `byeharu-voyage.filter.v1:<list>`,
  read/write in try/catch, a stored value never trusted (only the defaults' keys, only strings; `oneOf` drops a value
  the list no longer offers).
- `src/features/stats/statsFilters.ts` — the pure filters and sorts (areas, cities, merchants).
- Server, 0244: `public.region_area(text)` (new, IMMUTABLE, revoked from clients); `world.stats_cities` ×2 hunks (each
  row + `region`, `area`, `invested`, `mine`, `stock`); `public.stats_fold_day` ×1 hunk (the count keeps `stock` on the
  city's day); `world.stats_merchants` ×3 hunks (`list`: `[name, nation, purse, fleets, day, laps]`, richest first; the
  24 h of laps read once into `v_d` for both the board and the list).

## Self-assert (probe rows only, all rolled back)

(a) the six hunks reverse; ACL / volatility / definer / config unmoved; registry; walls 0. (b) every region in exactly
one area; IBE europe, JAP east_asia, PAC americas, an unknown code none. (c) a probe Lisbon city row past every real
slot: after the fold its `stock` = round(Σ port_goods.stock at Lisbon). (d) a probe company (probe JWT subject) with
shares at Lisbon reads Lisbon `mine` true, `invested` ≥ its 777, `area` europe, `region` IBE; another harbour `mine`
false; every row has the fields. (e) a probe merchant company (purse 4,321, one roster fleet) is in `list` once.
No growing table counted against a remembered figure, no DELETE, no `set role`, no hour.

Local, cached-prefix apply: `0244 self-assert ok … Rolled back.` (96 ms).

## PROD CHECKS (read-only, pure SELECTs, one statement per block; run by me on 2026-10-26; pasted results)

No function was called. Each hunk was also checked against the live bodies (`pg_get_functiondef`, LF-normalised) at
head 0238 and again at head 0240: every hunk occurs exactly once; the three bodies are unchanged between 0238 and 0240.

```sql
select max(version) as head, (select string_agg(p.oid::regprocedure::text || '=' || p.provolatile::text, ', ' order by 1) from pg_proc p where p.oid in ('world.stats_cities()'::regprocedure, 'world.stats_merchants()'::regprocedure, 'public.stats_fold_day(bigint)'::regprocedure)) as vol, to_regprocedure('public.region_area(text)') is null as no_region_area from supabase_migrations.schema_migrations
```
`head 20260818000240 · world.stats_cities()=s, world.stats_merchants()=s, stats_fold_day(bigint)=v · no_region_area true`

```sql
select string_agg(r.code, ',' order by r.code) as region_codes, count(*) as regions, (select count(*) from public.ports p where p.kind = 'HARBOUR' and p.region_id is null) as harbours_without_region from public.regions r
```
`ADR,AEG,ARA,ATL,BAL,BRI,CAR,CHI,EAS,EST,FRA,IBE,JAP,KOR,LEV,MAG,NOR,OCE,PAC,SCA,SOU,STH,WES,WIA,WST · 25 · 0` — the
same 25 codes region_area maps; every harbour has a region.

```sql
select clock_timestamp() as t0, (select count(*) from (select x.port_id, sum(x.paid) from public.city_shares x group by x.port_id) s) as invested_cities, (select count(*) from public.ports p join public.regions r on r.id = p.region_id where p.kind = 'HARBOUR') as harbours, clock_timestamp() as t1
```
`232 invested cities · 246 harbours · 39 ms (cold)`; the shares sum alone, warm: **1.5–2.1 ms** a read.

```sql
select clock_timestamp() as t0, (select count(*) from (select pl.company_name, n.code, pl.ducats, coalesce(f.n, 0) from public.npc_houses h join public.players pl on pl.id = h.player_id left join public.nations n on n.id = pl.nation_id left join (select nf.player_id, count(*)::int as n from public.npc_fleets nf group by nf.player_id) f on f.player_id = h.player_id) q) as houses, (select length(jsonb_agg(jsonb_build_array(pl.company_name, n.code, pl.ducats, 0, 0, 0))::text) from public.npc_houses h join public.players pl on pl.id = h.player_id left join public.nations n on n.id = pl.nation_id) as list_bytes, clock_timestamp() as t1
```
`821 houses · list ≈ 37 KB of JSON · 14 ms` — the merchants' list adds ~14 ms and ~37 KB (before gzip) to a read asked
every second while the Merchants face is open.

```sql
select clock_timestamp() as t0, (select sum(q.s) from (select pr.id, (select coalesce(round(sum(pg.stock)), 0)::bigint from public.port_goods pg where pg.port_id = pr.id) as s from public.ports pr where pr.kind = 'HARBOUR') q) as fold_units, clock_timestamp() as t1
```
`223,722,007 units · 837 ms` — the fold's added cost, **once a count** (every 15 minutes), not per read.

## Proof

`npx tsc -b` clean; eslint on every touched file clean; `npm run build` (no `.env.local`) green.
On `vite preview --port 4222` (localhost): `tests/stats.filters.spec.ts` 3/3 (Cities: Europe → only `data-area=europe`;
Richest → first purse ≥ second; remembered across faces; no sideways scroll at 390 px; the pure readers),
`tests/stats.tab.spec.ts` 3/3, `tests/rpc.stats.spec.ts` 6/6.

ROLLBACK (forward): put each hunk's OLD text back (verbatim in the migration) and drop `public.region_area(text)`; the
client reads every new field as optional.
