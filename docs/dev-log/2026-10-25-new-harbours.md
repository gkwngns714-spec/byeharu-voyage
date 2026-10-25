# 2026-10-25 — eight new harbours: the Russian north, Australia, New Zealand, the northern United States (migration 0217 at writing, `osn-new-harbours`)

Owner row 186 (2026-10-20): *"There aren't a single city on top of Russia. Can there be like 2 more? Also 2 more in
autrailia and in new zeland. Also 2 on top of USA."*

One migration, `20260818000217_the_far_north_australasia_and_new_england_have_harbours.sql`, built by the existing
generators from the data. No switch is lit. Prod head at writing: 0216. **Renumber to prod head + 1 at push.**

## 1. The eight, and why these (decided by default; the owner may reverse any)

Already on the map: Arkhangelsk and Vardo (Russian/Norwegian north), Sydney and Hobart, Boston and New York.

| Code | Harbour | Where | Founder / ruler | Roadstead zone (0215) | Goods |
|---|---|---|---|---|---|
| MEZ | Mezen | White Sea, the Mezen mouth | Muscovy (ruler, no holder) | WHI, title 3, wave 10 | stockfish, halibut, eiderdown, whale-bone stays |
| PUS | Pustozersk | Pechora delta, Barents Sea | Muscovy (ruler, no holder) | BAR, title 3, wave 12 | gyrfalcons, Russia leather, narwhal horn, angelica root |
| DAR | Darwin | Timor Sea | none (like Sydney) | TIM, title 7, wave 16 | trepang, pandanus mats, wax, kangaroo skins |
| FRE | Fremantle | Swan River, Indian Ocean | none | IND-S, title 5, wave 44 | sandalwood, wattle bark, sperm oil, **jarrah** |
| AUK | Auckland | Hauraki Gulf, South Pacific | none | STH-AM, title 8, wave 12 (see §6) | **kauri spars, kauri gum, NZ flax, kumara** |
| WLG | Wellington | Cook Strait, Tasman Sea | none | TAS, title 8, wave 56 | **NZ flax, pounamu, kumara**, sperm oil |
| PTL | Portland (Maine) | Casco Bay, North Atlantic | none (like Boston) | NOR-AM, title 4, wave 12 | cod, maple sugar, **mast pine, beaver pelts** |
| AST | Astoria (Oregon) | Columbia mouth, North Pacific | none (like Monterey) | NRT-AM, title 8, wave 12 | **beaver pelts, Douglas fir, dentalium shell**, pine pitch |

**Bold** = one of the ten new goods (data/goods.json; Korean names in `src/lib/i18n/names/goods.ts`). Every harbour is a
small one (tier 3: four goods, size 2), like Hobart. "On top of Russia": the Siberian coast east of 60° E is closed ice
since 0040 (`scripts/sea-grid.mjs` ICE), so the two sit on the open Arctic shore between Arkhangelsk and the ice.
"On top of USA": one on each coast, north of Boston and north of San Francisco.

**Anachronisms, said.** Darwin (1869), Fremantle (1829), Auckland and Wellington (1840) and Astoria (1811) are towns of a
later age, like Sydney (1788) and Hobart (1804) before them. Each note names what was there in the age of sail: the
Makassan trepang coast (Marege', from about 1700), the Swan River Vlamingh charted in 1697, the Maori harbours of the
islands Tasman sighted in 1642, the Chinook market at the Columbia. Mezen, Pustozersk (1499) and Portland (Falmouth,
1633) are of the era.

**Coordinates.** wikidata.org is not reachable from the container this was built in, so `scripts/fetch-coords.mjs`
could not run. The coordinates are the places' well-known Wikidata/enwiki values, typed; the five whose Wikidata id
I could not confirm carry `"wikidata": null` (Mezen, Pustozersk, Fremantle, Portland, Astoria), the enwiki title
beside it. **Main session: run `node scripts/fetch-coords.mjs` once on a networked machine and compare** (any move
under 0.005° changes nothing in the database, which rounds to 0.01°). `scripts/check-ports.mjs` passes (NZ's
bounding box added).

**Kola was the first choice, and it was swapped for Mezen — said so it is not hidden.** With Kola in the world, proof
05's `BALANCE_DISTANCE_PAYS` went red: 12.71 % for the long legs against 13.91 % for the short. Measured route by route
(the proof's own d = 1 loop, dumped): only Amsterdam's offer list changed — two Kola routes (sea charts 15.97 %,
Rhenish wine 5.82 %, both 1,609 nm) displaced Reykjavik and Trondheim — and that one change moved the proof's median
cut from 1,413.9 to 1,422.8 nm, which re-sorts routes between the halves. **The proof sits on a 0.47-point margin on
main today (13.47 vs 13.00).** That is a fragile guard, and a balance finding for the owner: the distance premium the
first-voyage pool shows is 1.04×. Mezen was the brief's other named White Sea harbour; with it every proof reads
exactly as on main (13.47 vs 13.00). The proof was not touched.

## 2. How the file is made: three parts, each from the one path

1. **(growth)** `node scripts/build-world-growth.mjs 20260818000217 the_far_north_australasia_and_new_england_have_harbours`
   against the applied chain. Two fixes to the generator, both of which any future growth needs:
   - **0208's price level.** The database holds a good's base value × `goods_price_level` (0.2); the generator compared
     and wrote the raw data figure, so it saw all 555 goods as "changed" and would have priced the new goods at five
     times their neighbours. The scaling is now ONE helper, `goodsAtPriceLevel` (scripts/lib/world-derive.mjs), used by
     both the generator and the world guard (which carried the only other copy).
   - **The market step is three short statements.** The single `insert … on conflict` priced every pair of the world
     (`world.demand_for` and three depth calls on ~139,000 rows) only for the conflict to discard ~132,000: **72.6 s as
     one statement** on native PostgreSQL 16. Now: affinity derived into a temp table (9.9 s), the missing pairs
     inserted (2.3 s), the moved pairs updated (0.3 s). Same arithmetic.
2. **(sea)** `node scripts/build-sea-migration.mjs` with its new switch **`ADDS_PLACES_ONLY`**. Re-measuring every
   pair, as 0091 did, would move the existing distances: today's pathfinder (smoothed since 0091) reads a mean of
   −2.53 nm against the applied table (98 % of pairs under 0.5 %, Coquimbo → Makassar 9,167 → 8,651). That is a
   movement change for its own slice, not a side effect of eight towns. With the switch on, the generator emits only
   the new places' rows and their keys in every existing row (existing distances asserted unchanged to the tenth), and
   refuses if the raster, the membership patch or any existing roadstead moved. It also emits **48 merchant courses**
   (each new harbour to and from its 3 nearest existing harbours by sea, the pathfinder's own course): 0203's
   `npc_known_legs` offers a merchant only legs a loop has held or `npc_courses` remembers, so without them no house
   could ever plan a new harbour. No house is founded; the planner decides whether a loop through them pays.
3. **(cities)** the per-harbour rows six systems after 0090 seeded once over the harbours of their day. Found by
   measurement, not memory: every foreign key to `public.ports` on the grown chain, small harbours' coverage against
   the eight's — `port_treasury` 121/121 vs 0/8, `city_works` 121/121 vs 0/8, `port_allegiance` 121/121 vs 0/8,
   `port_language` 121/121 vs 0/8, `sea_leg_asks` 121/121 vs 0/8 — plus `port_goods.haul` (0173), which the world
   guard holds to `world.haul_rows()`. Each is landed by its own rule:
   - **purse** (0122/0172): the row, its reserve, and — in a world whose cities were seeded (prod) — the seed. The
     seed expression lived only inside `public.city_treasury_switch`; it **moves** into `public.city_seed_amount(port)`
     and the switch calls it (one hunk, occurs once, reverses to its pre-image, ACL/volatility/definer/config
     unchanged), so the switch and a harbour born after it read one rule. A new harbour is no capital: 2,000,000 each,
     16,000,000 in all, as one SEED flow each. On a world never seeded (CI) nothing is posted; the switch seeds them
     with the rest when it is lit. Both branches tested.
   - **works** (0123): the four at level 0, 0123's statement.
   - **flag** (0143, 0187): measured over all 238 — a great power's foundation flies its founder, every other harbour
     has no holder; the founder is the ruler. Mezen and Pustozersk: ruled by Muscovy, no holder. None is a home city.
   - **tongue** (0156): from `data/captains.generated.json` (regenerated: 246 harbours; no captain's languages moved).
   - **leg asks** (0215): `public.sea_leg_asks_derive()` filtered to the legs touching the eight (3,872 rows).
   - **hauls** (0173): every row back to `world.haul_rows()`.

Client: nothing in the client lists harbours by hand — labels, flags and the city Info tab read the snapshot,
`world.allegiance`, `world.town_hall` and `world.stats_city`. Changed: Korean names (`names/ports.ts`, `names/goods.ts`),
`data/region-tint.json` (rebuilt by `scripts/build-region-tint.mjs`: the tint is nearest-harbour-by-water, and New
Zealand is a new country with a harbour), and three test pins moved deliberately with dated comments
(`tests/map.landfall.spec.ts`: 238 → 246 harbours, 80 → 81 in drawn water, 52 → 53 moved — Fremantle, 0.43 nm;
`tests/map.marks.spec.ts`: 238 → 246 harbours), each re-measured by the spec itself.

**The seam, found by CI.** Auckland (174.76° E) and Wellington (174.78° E) are the first harbours near the
antimeridian, and the continuous chart (2026-10-14) draws a harbour once in every copy of the sheet its box touches.
At the world view the box crosses ±180°, so CI measured **248 marks for 246 harbours** (run 40195840956). The two
map specs now count the claim by harbour (246 distinct codes), pin the marks (248) and name the doubled pair (AUK,
WLG); the marks spec's zoom probe takes a dot drawn once (a seam copy's anchor is copy-local, run 40196400409); and
`tests/map.wrap.spec.ts` reads the tapped harbour's name from `deriveWorld()` instead of the frozen 214-harbour
fixture, which never carried the 0090 or 0217 harbours (it tapped Astoria, run 40197017998). No product code moved:
the chart was already right.

## 3. What changes in live play

- **1,950 existing market rows** (18 goods) change affinity: a maker of their good is now within reach. Their stock
  resets to the new target — what every growth since 0041 has done. Most: sperm oil 236, maple sugar 198, kangaroo
  skins 198, wattle bark 194, stockfish 169, pine pitch 158, narwhal horn 152.
- **1,269 existing market rows** take a shorter haul (0173: the good has a nearer maker), so the price there falls
  toward the maker's: haul factor median ×0.970, mean ×0.963, at most ×0.799. Sperm oil 236, wattle bark 214, maple
  sugar 197, cod 178, sandalwood 147.
- 6,900 new market rows (8 harbours × 565 goods + 10 goods × 238 harbours), 32 offers, 8 × 3 buildings, 8 purses
  (16,000,000 seeded on prod), 32 works, 8 flags, 8 tongues, 3,872 leg asks, 48 merchant courses, 8 reach rows.
- **Unchanged:** every player row, every existing roadstead and distance, the raster, the sea zones, the passage gate
  (0216, dark), every switch.

## 4. Measured (native PostgreSQL 16.15, the chain 0001–0216 applied from zero on this container)

- The whole file applies in **36–40 s**. Heaviest statements: growth self-assert 15.8 s (reads), affinity derivation
  9.9 s (temp table), cities self-assert 6.1 s, leg asks 3.0 s, haul diff 3.0 s, new market rows 2.3 s. Nothing
  near the minutes-long statement that cost 0215 its push connection. `lock_timeout` 5 s as 0214–0216.
- Receipts: `0217 self-assert ok: THE WORLD EQUALS THE DATA` (246 harbours, 565 goods, 1,380 offers, 138,990 market
  rows), `0217 (sea) self-assert ok` (260 places; a bent distance seen, then restored), `0217 (cities) self-assert ok`.
- **World guard** (`scripts/db/world-guard.mjs`) green on the result: every table it holds equals the data, the
  captains generator re-run equals the file and the database (246 harbour languages), every haul equals
  `world.haul_rows()`.
- **All 12 proofs green** (`scripts/db/proofs/*.sql`, with `installProofCourses` and the market fixture, as
  `npm run db:proof` runs them). Proof 05: median first voyage 18.0 %; distance pays 13.47 % vs 13.00 % — identical to
  main.
- Prod-shaped branch: on a chain whose cities were seeded **before** the growth (the switch lit at 0216), the eight are
  seeded 2,000,000 each and the self-assert holds them to `city_seed_amount`.
- `npx tsc -b` clean, `npx eslint .` clean, `tests/duplication.spec.ts` + `tests/sections.spec.ts` 18/18,
  `tests/map.landfall.spec.ts` pure table green.
- How it was run without the 2-hour PGlite build: the generators were pointed at the native database through a
  module-resolution shim for `@electric-sql/pglite` (outside the repo, not committed). CI's own from-zero and
  prefix-cache runs are the proof that counts.

## 5. Not verified here

- The browser specs (map marks, Korean sweep) — no world image was built (2+ hours). CI runs them.
- The paired prod-shaped NPC simulation — the main session's measurement, §PROD CHECKS.
- The coordinates against Wikidata (§1).

## 6. A finding for the owner (not changed here): Auckland's zone

`data/sea-zones.json` cuts the South Pacific raster sea with the box **STH-AM "Pacific Americas, south coast": lat > −45,
lon ≥ −90**. "lon ≥ −90" was meant as "east of the Galápagos meridian, toward Chile", but it also takes in all STH water
at positive longitudes — so Auckland's roadstead (175.1° E) reads as the *Pacific Americas, south coast* (title 8,
wave 12). Reaching it still crosses the Tasman (56) or the open Pacific (70), so no hull gets there cheaply; only the
harbour's own zone name and wave read oddly. The fix is a `lon_max` on that box, a 0215 data change with its own
re-derivation of `sea_zone_cells` and `sea_leg_asks` — a slice of its own.

## PROD CHECKS FOR THE MAIN SESSION

Run before the push, read-only. Every call below is to a function whose `provolatile` is `s` or `i` (measured:
`pg_get_functiondef`, `to_regprocedure`, `voyage.water_roadstead` s, `public.harbour_zone` s, `public.sea_zone_at` s,
`public.city_standing` s, `public.city_sell_outflow` s, `public.wc_int`/`wc_num` s, `voyage.gc_distance_nm` i).

```sql
begin transaction read only;

-- 1. the head is 0216 (renumber this file to head + 1 if not)
select max(version) from supabase_migrations.schema_migrations;                         -- expect 20260818000216

-- 2. THE ONE HUNK occurs exactly once in the live switch body (and its new text not at all)
with d as (select replace(pg_get_functiondef('public.city_treasury_switch(boolean)'::regprocedure), E'\r', '') as def)
select (length(def) - length(replace(def,
$h$                    greatest(public.city_standing(p.id), public.wc_int('city_seed_min'),   -- 0172: its standing purse
                             round(public.wc_num('city_seed_days') * public.city_sell_outflow(p.id)))::bigint as s
$h$, ''))) / length(
$h$                    greatest(public.city_standing(p.id), public.wc_int('city_seed_min'),   -- 0172: its standing purse
                             round(public.wc_num('city_seed_days') * public.city_sell_outflow(p.id)))::bigint as s
$h$) as old_hunk_occurs,                                                                  -- expect 1
       position('city_seed_amount' in def) as new_hunk_at                                -- expect 0
  from d;
select p.proacl, p.provolatile, p.prosecdef, p.proconfig
  from pg_proc p where p.oid = 'public.city_treasury_switch(boolean)'::regprocedure;     -- record; the file restores/asserts them

-- 3. nothing this file creates exists yet
select to_regprocedure('public.city_seed_amount(uuid)');                                  -- expect null
select count(*) from public.ports where code in ('AST','AUK','DAR','FRE','MEZ','PTL','PUS','WLG');   -- expect 0
select count(*) from public.goods where code in ('jarrah','kauri-timber','kauri-gum','harakeke','pounamu',
  'kumara','mast-pine','beaver-pelts','douglas-fir','dentalium');                         -- expect 0

-- 4. the preconditions the three parts read
select to_regprocedure('public.sea_leg_asks_derive(uuid)') is not null as asks,
       to_regprocedure('world.haul_rows()') is not null as haul,
       to_regprocedure('public.furnish_harbours()') is not null as furnish,
       to_regprocedure('world.market_depth_at(integer,numeric,numeric)') is not null as depth,
       to_regprocedure('world.demand_for(uuid,uuid)') is not null as demand,
       to_regprocedure('voyage.segments_from_course(jsonb)') is not null as segs,
       to_regclass('public.npc_courses') is not null as courses,
       to_regclass('public.port_language') is not null as tongue;                        -- expect all true
select count(*) from public.ports where kind = 'HARBOUR';                                -- expect 238
select count(*) from public.ports;                                                        -- expect 252
select count(*), min(cnt), max(cnt) from (select (select count(*) from jsonb_object_keys(reaches)) cnt
  from public.sea_reaches) x;                                                             -- expect 252, 251, 251
select md5(cells) from public.sea_raster where id = 1;           -- expect 38831e3f0611c86ba46ff0dcfa56b0fb (the chain's)
select md5(string_agg(md5(reaches::text), '' order by code)) from public.sea_reaches;
                                                                 -- expect ef8e8289037eca914c9e67fa7e5b2814 (the chain's)
select count(*) from public.sea_leg_asks;                                                 -- expect 56644 (238²)
select key, value from public.world_config where key in ('goods_price_level','affinity_curve','affinity_home',
  'affinity_producer','affinity_reach_nm','affinity_span','market_depth','city_purse_city','city_seed_min',
  'city_seed_days','city_treasury_enabled','sea_conditions_bite');
  -- expect goods_price_level 0.2; affinity 0.88 / 1.00 / 0.93 / 9500 / 0.76 (else the growth's knob reconcile
  -- UPDATEs fire — read them before pushing); city_purse_city 2000000; sea_conditions_bite false

-- 5. the seeded-world branch: prod's cities were seeded, so the eight will be posted 2,000,000 each
select exists (select 1 from public.treasury_flows where kind = 'SEED')
    or exists (select 1 from public.treasury_daybook where kind = 'SEED') as seeded;     -- expect true
select greatest(public.wc_int('city_purse_city'), public.wc_int('city_seed_min'));        -- expect 2000000

-- 6. the roadsteads the file seeds equal what the one SQL rule answers on prod
select v.code, w.lat, w.lon, round(w.nm, 2) as snap_nm, public.sea_zone_at(w.lat, w.lon) as zone
  from (values ('AST', 46.19, -123.83), ('AUK', -36.85, 174.76), ('DAR', -12.44, 130.84), ('FRE', -32.05, 115.75),
               ('MEZ', 65.85, 44.23), ('PTL', 43.66, -70.26), ('PUS', 67.53, 52.64), ('WLG', -41.29, 174.78)) v(code, lat, lon)
 cross join lateral voyage.water_roadstead(v.lat, v.lon) w order by 1;
  -- expect AST 46.125 -124.125 12.87 NRT-AM · AUK -36.625 175.125 22.16 STH-AM · DAR -12.375 130.625 13.20 TIM
  --        FRE -32.125 115.625 7.79 IND-S · MEZ 66.375 43.875 32.68 WHI · PTL 43.375 -70.125 18.09 NOR-AM
  --        PUS 68.375 51.625 55.65 BAR · WLG -41.375 174.625 8.65 TAS

-- 7. no code collision with a sea place, and Muscovy is a minor (so Mezen/Pustozersk get no holder)
select code from public.ports where kind = 'SEA_PLACE' and code in ('AST','AUK','DAR','FRE','MEZ','PTL','PUS','WLG');  -- expect none
select count(*) from public.great_powers gp join public.nations n on n.id = gp.nation_id where n.code = 'RUS';           -- expect 0

-- 8. the size of what moves (equal to the chain's: affinity and haul are pure functions of the roster and the sea)
select count(*) from public.port_goods;                                                   -- expect 132090 before; 138990 after
select count(*) from public.npc_courses;                                                  -- record; +48 after

rollback;
```

**After the push** (still read-only): `select count(*) from public.ports where kind = 'HARBOUR'` = 246;
`select count(*) from public.sea_leg_asks` = 60516 (246²); each new harbour's `public.treasury_balance(id)` = 2000000;
`world.snapshot()->'ports'` carries the eight with a roadstead.

**What the main session must measure with its paired prod-shaped sim before deploying** (the same pair it ran for
0215/0216: a prod-shaped world without and with this file, same seed, same clock):
- **arrivals**: average arrival handling ≤ 3 s, and not worse than the paired run without 0217. The eight add 48
  candidate legs to `npc_known_legs` and 3,872 rows to `sea_leg_asks`; the planner's per-port candidate set grows only
  at the 24 neighbours (each gains 2 legs).
- **laps**: the count of laps closing at ≤ 0 net must not be worse than the paired run. Watch especially the houses at
  the neighbours of the eight (Arkhangelsk, Vardo, Kupang, Dili, Sydney, Hobart, Boston, New York, Quebec, Monterey,
  San Francisco …): their candidate legs grow, and the 1,950 reset stocks and 1,269 shorter hauls move what their
  loops earn.
- the market-drift tick time and `world.trade_routes` from Lisbon/Amsterdam (rows +6,900 = +5.2 %).
- the after-check at +30 min: `tick_city` ran clean (the eight purses roll), `tick_market_drift` touched the new rows,
  no `E_*` spike in the order log.
