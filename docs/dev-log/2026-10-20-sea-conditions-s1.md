# 2026-10-20 — the seas have conditions, slice S1 (migration 0215 at writing, `osn-sea-s1`)

**The design:** docs/SEA_CONDITIONS_AND_REGIONS.md (PR #271, merged). The owner, 2026-10-20: *"lets start by applying the
design you've created first, then consider adding more."* Every default of its §7 is accepted (title = the lower of
Trading and Exploration capped at 11; the region gate retired with S2; merchants on wave only; 24 far traders later;
capital 20,000 d. weekly with the docked-fleet rule; six starting powers; the numbers as written). Ice-breaking,
breakthrough and rowing are NOT built (the stat seam is one base row in `world.ship_stats` and one column).

**Version.** 0215 at writing (0212 insurance and 0213 haul cap are open ahead; 0214 is the stats tab). Prod head
**0211** when the pre-images were read (every hunk occurs exactly once on the live bodies, LF-normalised). Renumber to the
prod head + 1 at push. Not deployed: this PR does not push, merge or flip anything. **Dark:** `sea_conditions_bite`
is false; `public.sea_gate` answers null; no gate is re-cut here (S2).

## 1. What landed (one authority per concept — the design's §1 table)

| Concept | Home | Note |
|---|---|---|
| Zone requirements | `public.sea_zones` (64) + `public.sea_zone_boxes` (67) + `public.title_names` (11) | data, `data/sea-zones.json`, held by the world guard both directions. The doc's prose says 61 zones; its table has 64 rows and the table is what is built. Boxes are a child table (NOR-MAC has three boxes, STH-OPEN spans two seas), half-open `[min, max)`, one REST box per raster sea (asserted). |
| Which zone is this water | `public.sea_zone_at(lat, lon)` reading `public.sea_zone_cells` | the 0040 raster answered as zones, one byte a cell, DERIVED from `sea_cells` + the boxes at apply (1,036,800 cells). Decided by default over "sea_at then the boxes per call": the leg-asks derivation samples ~4 million points and the merchant planner (S3) will sample ~100 a leg; a byte read is the only shape that keeps both cheap. `public.sea_cell_row/col` is the one cell address for the zone readers; the self-assert holds the two rasters to the same sea at every roadstead and on 2,000 sampled cells. |
| A harbour's zone | `public.harbour_zone(port)` at its roadstead | not `ports.sea_id` |
| A course's zones | `public.course_zones(course)` | every vertex + a sample every `sea_sample_nm` (30) per straight segment, lon the short way (`voyage.lon_lerp`). Positive control: a two-vertex Lisbon → Havana line — vertices name NOR-EU and GCO only, sampled it crosses NOR-MAC, NOR-MID, NOR-AM. **The design's Bristol → Cape Coast claim was wrong:** read on prod, that course hugs the coast (never west of 17.6° W) and its vertices already name every zone it crosses (NOR-EU, NOR-MAC, NOR-DOL, GUL); it is asserted for what it is. |
| A leg's ask without a course | `public.sea_leg_asks` (238² rows) by `public.sea_leg_asks_derive()` | straight line between roadsteads + the destination's zone; a 300-row re-derivation is asserted equal |
| The hull's stat | `ship_classes.wave`, derived `12 × size + rig + role` | asserted for all 103 classes (prod has 103, not the doc's 101); `scripts/lib/world-derive.mjs waveResistance` is the same rule for the data file and the guard; one base row in each branch of `world.ship_stats` |
| What gear adds | `item_effects` 'wave' rows (65) | `scripts/build-gear.mjs WAVE_BY_BASE` by (base type, grade), applied last so no ladder multiplies it; the three live G1s carry theirs in `data/fittings.json`, asserted against the table; `--sql-0215` pasted |
| The fleet's figure | `public.fleet_wave(fleet)` | floor(avg); nau + 2 barcas = 21 (probe) |
| The title | `public.title_level(player)`, `public.title_names` | derived; `players.title_level` DROPPED (stored 1 for every house; read only by `world.player()`, re-cut) |
| The rule | `public.sea_refusal(title, wave, zones[])` | the only comparison; `E_SEA_CLOSED` with figures `{zone, zone_name, needs_title, title, needs_wave, wave}` |
| The gatherer | `public.sea_gate(player, fleet, dest, course)` | null while dark, null for nobody; a merchant's title is null (wave only) |
| Served | `world.sea_conditions()` (registered + granted), `world.fleets().wave`, `world.ship_view().wave`, `world.player().title_level/title_name` | client: `worldSeaConditions` in the catalogue, types `SeaConditions`, `FleetShip.wave?`, `FleetView.wave?`, `PlayerHouse.title_name?` |
| Knobs | `sea_conditions_bite` false, `sea_sample_nm` 30, `title_max` 11 | `sea_conditions_bite_npc` comes with S3, the capital knobs with S6 |

**Re-cut by hunks** (each asserted to occur once and to reverse, ACL/volatility/definer/config unmoved):
`world.ship_stats` (2), `world.ship_view` (1), `world.fleets` (1), `world.player` (1), `public.client_rpc_entry_points` (1).

## 2. What changes while dark (honest list)

- `world.player().title_level` now serves the DERIVED title: on prod every house read 1; JOOHOON HA (trading 3,
  exploration 4) will read **3**; the other 16 stay 1. No screen reads it (only `src/lib/rpc/types.ts` names it).
  `title_name` is new.
- `world.fleets()` / `world.ship_view()` gain the additive key `wave`; `world.ship_stats()` gains `wave`. The ten old
  stats are asserted unchanged to the digit on every hull of the world.
- No SAIL, plan, route-save or desk answer changes: no gate is touched in S1.

## 3. Read-only on prod before the PR (2026-10-20, head 0211)

- 103 classes, every one with a profile; the derivation gives 6 8 12 13 14 15 18 24 25 26 27 30 36 39 42 48 49 51 53 54
  60 61 63 66 72 73 75 (barca 12, carlat 26, nau 39, galeao 51, indiaman 63, carraca 75, sjb 53, goldenhind 27).
- The nine families hold 65 items (Anchor 8, Sheet Anchor 7, Storm Canvas 7, Planking 12, Sheathing 9, Bilge Pumps 8,
  Ballast 10, Doubled Frames 2, Raised Forecastle 2); 68 hulls carry a wave piece (all copper sheathing, +2).
- All 238 harbours' roadsteads resolve a sea in the raster; classified with the authored boxes they fall exactly into the
  design's §2 table (every zone's harbour list matches, e.g. NOR-MAC = ANG CID GOR LPA PON SAI TEN; NOR-ICE = NUU REY;
  HNL = NRT-OPEN; HAG = PHI).
- Bristol → Cape Coast exists in `npc_courses` (10 points, 3,756 nm) and in three merchant loops.
- The 17 humans: `min(trading, exploration)` is 1 for 16 and 3 for JOOHOON HA; every stored `title_level` is 1.
- The straight line Lisbon → Havana samples 123 cells of NOR, 3 of GCO and 1 land cell (the Bahamas).
- Knobs for the probe: `fleet_ship_max` 8, `ship_max` 8, `fleet_ship_base` 2 (+ SEAMANSHIP 5 → room for 3 hulls).
- `item_effects_stat_check` is the constraint's name; `world_config` is keyed on `key`.

## 4. Measured (local PGlite, the chain restored from the prefix cache and 0215 applied on it)

- **First cut: 787 s** for 0215 in PGlite. The zone raster took 10.6 s; the rest was `sea_leg_asks_derive()` — a
  per-sample join to `sea_zone_cells` and to `sea_zones`, run TWICE (the self-assert re-derived every pair to compare
  300 rows). **Second cut: 105 s** (raster 16 s, the derivation ~80 s): the whole raster is read once as one 1 MB
  bytea and a sample is one `get_byte`; the distinct zone bytes per pair are joined to `sea_zones` once; the
  re-derivation check takes `p_from` and re-derives Lisbon's 238 legs only. PGlite is wasm; native PostgreSQL is
  expected several times faster (measured at push).
- The receipt (PGlite world: 908 hulls, 13 humans): 647,214 water cells of 1,036,800, every one zoned; 56,644 leg
  asks; 65 wave rows; the ten old stats unchanged on every hull; 238 harbours resolve; Lisbon → Havana sampled
  crosses {GCO, NOR-AM, NOR-EU, NOR-MAC, NOR-MID}, its vertices alone {GCO, NOR-EU}; the prod course Bristol → Cape
  Coast (10 vertices) crosses {ENG, GUL, NOR-DOL, NOR-EU, NOR-MAC}; the rule, the probe (21), the dark/lit gate, the
  walls — all as the header promises.
- Hot readers, 8 calls each in one session (PGlite's clock is coarse; prod's receipt is the measurement that counts):
  `world.ship_stats` old vs new within noise (0.1–0.7 ms); `course_zones` of the Lisbon → Havana line 5.1 ms (first 3
  5.7, last 3 4.3 — no generic-plan cliff); `fleet_wave` 1.6 ms; `title_level` 0.6 ms.
- `node scripts/db/proof.mjs 03_grant`: 12/12 PASS (RLS on all 111 tables, 0 client write grants, the registry
  executable). World guard: equal, with the positive controls seen. `tsc -b` clean. `tests/duplication.spec.ts`
  10/10.

## 5. Not verified here

- The migration has not run on prod (no db push by order): the self-assert's probe (new house, three hulls, the switch
  flipped inside a rolled-back sub-transaction) runs at push.
- CI's disposable-Supabase job is the first real PostgreSQL to run the raster derivation; PGlite's timing is the only
  measurement until then.
- No browser build: no screen changed (the catalogue, types and a wrapper only). `tsc -b` passes.


## 6. Re-verified on top of 0213 (2026-10-20, the cloud routine, after the rebase)

**The branch.** `osn-sea-s1` contains `origin/main` (main's head `e681828` is a docs-only work-queue commit after
`ca4fe6f`; nothing in `supabase/` differs). **The WIP commit `5278abe` is KEPT:** 0213 appended
`('world', 'insurance', '')` as the last row of `public.client_rpc_entry_points()`, so 0215's hunk there had to re-anchor
on that row instead of `price_why`. That is exactly what the WIP did, and it is right: on the chain applied through 0213 the new
OLD text occurs once. None of the five bodies 0215 re-cuts (`world.ship_stats` ×2, `world.ship_view`, `world.fleets`,
`world.player`, `public.client_rpc_entry_points`) is one 0212/0213 re-cut apart from the registry. 0215 touches no
`voyage.settle`, raid body or `npc_tend`.

**How it was checked.** The whole chain 0001 → 0213 was applied locally in PGlite (`scripts/db/apply-chain.mjs`, on disk, 93 min of
wasm). On that world: every 0215 hunk occurs exactly once (the read-only query in §8, run as written), every 0216
hunk occurs exactly once, and all the 0215 preconditions in §8 are true. Then 0215 and 0216 were applied statement by statement in one
transaction each (§7). Both self-asserts printed their receipts:
- `0215 self-assert ok: THE SEAS HAVE CONDITIONS (dark). 64 zones, 67 boxes, 11 titles; the zone raster and 56644 leg asks
  derived; every class's wave is the derivation; 65 wave rows; 908 hulls: ten stats unchanged, wave = class + mounted (59
  carry a wave piece); 238 harbours resolve a zone of their raster sea; Lisbon → Havana sampled crosses
  {GCO,NOR-AM,NOR-EU,NOR-MAC,NOR-MID} …`
- `0216 self-assert ok: THE PASSAGE GATE READS THE SEA (dark). Seven bodies re-cut and reversed (three re-signed, ACL and
  config restored). DARK: 580 gate / door / sail answers equal their pre-images for the probe and 13 human(s) (140 refused
  E_REGION_CLOSED, the dark door exercised); reach_passage from Lisbon equal 6 × 6, the humans' tables equal, the good
  board's passages equal. LIT (rolled back): Funchal clear, Las Palmas E_SEA_CLOSED at Macaronesia …`

**One change to 0215 (decided by default):** `public.sea_leg_asks` is now created WITHOUT its two foreign keys to `ports`.
They are added by an `alter table` right after the fill, with the same names PostgreSQL would have given them
(`sea_leg_asks_from_port_fkey`, `sea_leg_asks_to_port_fkey`). Declared in the CREATE, they took SHARE ROW EXCLUSIVE on
the hot `ports` table before the ~112 s derivation, and held it to commit. Every write to `ports` (the inn's `crew_pool` tick, a
crew hire) would have waited the whole time. Measured: 120 s → 7.6 s. Nothing else in the file moved; the self-assert
is unchanged and passes.

**Specs.** `tests/duplication.spec.ts` 10/10 (after the change). `tsc -b` clean on both branches. `tests/rpc.surface.spec.ts` /
`tests/rpc.issueLines.spec.ts` were NOT finished locally: they build their own world from zero and the run was stopped at the
30-minute limit. CI runs them (acceptance shards, green on `5278abe`).

## 7. Locks on the hot tables (local PGlite, measured; native PostgreSQL is expected to be several times faster)

Method: each file split into its top-level statements, run inside ONE transaction. After every statement the session's
own `pg_locks` is read, and the first moment each (table, mode) appears is recorded. "Held" is from that moment to COMMIT.
Locks taken inside the self-asserts' rolled-back probe sub-transactions (RowExclusive on the probe's own fleets / ships /
voyages rows) are released when the probe rolls back. They are not visible here and last at most the probe's
statement (§ below); RowExclusive never blocks another writer's DML.

| Table | 0215 longest lock (after the fix) | blocks live play? | 0216 longest lock |
|---|---|---|---|
| fleets | AccessShare 7.5 s | no (blocks only DDL) | none |
| voyages | none | — | none |
| ships | AccessShare 7.6 s | no | none |
| port_goods | none | — | none |
| standing_route_* | none (read only if prod had no Bristol → Cape Coast course) | — | none |
| **players** | **AccessExclusive 7.5 s** (`drop column title_level`, held through the self-assert) | **yes: every read of `players` waits** | AccessShare 23.0 s (no) |
| ship_classes | AccessExclusive 7.6 s (`add column wave`) | yes, for readers of hull classes | none |
| item_effects | AccessExclusive 7.5 s (the CHECK widened) | yes, for readers of gear effects | none |
| ports | ShareRowExclusive 7.6 s (was **120 s** before the fix); AccessShare 129.5 s | writes wait 7.6 s | AccessShare 23.0 s (no) |
| world_config | RowExclusive 145 s (the three new keys) | no (only DDL) | AccessShare 23.0 s (no) |

Total: 0215 146 s (raster 16 s, `sea_leg_asks` derivation 112 s, self-assert 7.5 s); 0216 23.4 s (all of it its
self-assert; no DML-blocking lock at all). The last ~7.5 s of 0215, with `players`, `ship_classes` and `item_effects`
exclusively locked, is the only window players would feel. Both files set `lock_timeout` 5 s, so a busy table
makes the push fail cleanly instead of queueing behind it. Push 0215 at a quiet moment and expect a short stall of every
RPC. The prod receipt's timing is the measurement that counts.

**Not breaking, noted for S2's lit window:** `world.trade_routes` calls `voyage.sail_refusal(p_fleet, port, null, nm)` with 4
arguments. After 0216 that resolves to the new 5-argument signature through its default (checked locally: it answers). So lit, the trade
board judges a lane by the destination's zone without the course.

## 8. PROD CHECKS FOR THE MAIN SESSION

Run each block as written (`npx --yes supabase@2.120.0 db query --linked "<block>"`, or `-f` on a file). Every block is a
`begin transaction read only … rollback`, SELECTs only. The only functions called are `pg_get_functiondef`,
`to_regprocedure`, `to_regclass`, `replace`, `length` and `current_setting` (all stable or immutable).
**Changed after the failed push (§10):** the hunks (8a, 8c) and 8d are unchanged. 8b gains one row (the server version, for
`bit_count`). The speed-up re-cut no function body that a hunk anchors on, so the 8a/8c results read on prod still hold. No game function is called. Each was run
on the local world at the matching head, and every row came out as expected.

### 8a. Before pushing 0215 (prod head 0213): the hunks. Expect every row `occurs = 1` and `new_already_there = 0`.

```sql
begin transaction read only;
-- 0215: every OLD hunk must occur EXACTLY once in the live body (LF-normalised). Expect every row occurs = 1.
with h(fn, n, old, new) as (values
('world.ship_stats(uuid)', 1,
$h$('sighting',   c.sighting::numeric)) b(stat, base)
      left join d on d.stat = b.stat$h$,
$h$('sighting',   c.sighting::numeric),
                                ('wave',       c.wave::numeric)) b(stat, base)   -- 0215: + wave resistance, summed as the rest
      left join d on d.stat = b.stat$h$),
('world.ship_stats(uuid)', 2,
$h$('sighting',   c.sighting::numeric)) b(stat, base)
    left join d on d.stat = b.stat$h$,
$h$('sighting',   c.sighting::numeric),
                              ('wave',       c.wave::numeric)) b(stat, base)   -- 0215: + wave resistance, summed as the rest
    left join d on d.stat = b.stat$h$),
('world.ship_view(uuid)', 1,
$h$           'sighting', x.st->'sighting',
$h$,
$h$           'sighting', x.st->'sighting',
           'wave', x.st->'wave',   -- 0215: her wave resistance (world.ship_stats, the one computation)
$h$),
('world.fleets()', 1,
$h$    'free_hold', public.fleet_free_hold(f.id),
$h$,
$h$    'free_hold', public.fleet_free_hold(f.id),
    'wave', public.fleet_wave(f.id),   -- 0215: the fleet's wave resistance, the average of her hulls' (public.fleet_wave)
$h$),
('world.player()', 1,
$h$      'title_level',   v_row.title_level,
$h$,
$h$      'title_level',   public.title_level(v_id),   -- 0215: DERIVED (the lower of Trading and Exploration, capped title_max); the column is gone
      'title_name',    (select t.name from public.title_names t where t.level = public.title_level(v_id)),
$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'insurance',             '')
    ) as t(s, f, a)$h$,
$h$      ('world',       'insurance',             ''),
      -- 0215: the sea conditions — every zone's asks, the caller's title, her fleets' wave (docs/SEA_CONDITIONS_AND_REGIONS.md S1).
      ('world',       'sea_conditions',        '')
    ) as t(s, f, a)$h$)
)
select h.fn, h.n,
       (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as occurs,
       (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_already_there
  from h
  cross join lateral (select replace(pg_get_functiondef(to_regprocedure(h.fn)), E'\r', '') as def) d
 order by h.fn, h.n;
rollback;
```

### 8b. Before pushing 0215: the self-assert's preconditions. Expect every row `ok = true`. The query sorts any false row first.

```sql
begin transaction read only;
-- 0215 preconditions (run at prod head 0213). Every row's `ok` must be true.
select * from (
select 'head is 0213 (nothing landed since)', max(version) = '20260818000213', max(version)
  from supabase_migrations.schema_migrations
union all
select 'no 0215 object exists yet', to_regclass('public.sea_zones') is null and to_regclass('public.sea_zone_boxes') is null
       and to_regclass('public.sea_zone_cells') is null and to_regclass('public.sea_leg_asks') is null
       and to_regclass('public.title_names') is null and to_regprocedure('public.sea_gate(uuid,uuid,uuid,jsonb)') is null,
       null
union all
select 'knobs absent (sea_conditions_bite, sea_sample_nm, title_max)',
       not exists (select 1 from public.world_config where key in ('sea_conditions_bite', 'sea_sample_nm', 'title_max')),
       (select string_agg(key, ',') from public.world_config where key in ('sea_conditions_bite', 'sea_sample_nm', 'title_max'))
union all
select 'players.title_level exists; ship_classes.wave does not',
       exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'players' and column_name = 'title_level')
       and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ship_classes' and column_name = 'wave'),
       null
union all
select 'players.title_level read by no view/index/constraint (drop column cannot cascade)',
       not exists (select 1 from pg_depend d join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
                    where d.refobjid = 'public.players'::regclass and a.attname = 'title_level'
                      and (d.classid in ('pg_rewrite'::regclass, 'pg_class'::regclass, 'pg_trigger'::regclass, 'pg_policy'::regclass)
                           or (d.classid = 'pg_constraint'::regclass
                               and (select c.conrelid <> 'public.players'::regclass or cardinality(c.conkey) <> 1
                                      from pg_constraint c where c.oid = d.objid)))),
       null
union all
select 'only world.player() names title_level in a function body (it is re-cut)',
       (select array_agg(n.nspname || '.' || p.proname order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where p.prosrc like '%title_level%' and n.nspname in ('public', 'world', 'cmd', 'voyage')) = array['world.player'],
       (select string_agg(n.nspname || '.' || p.proname, ',') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where p.prosrc like '%title_level%' and n.nspname in ('public', 'world', 'cmd', 'voyage'))
union all
select 'every class has a profile (103 at writing); barca/carlat/nau derive 12/26/39',
       (select count(*) from public.ship_classes) = (select count(*) from public.ship_classes c join public.class_profile cp on cp.class_code = c.code)
       and (select count(*) from public.ship_classes) >= 100
       and (select string_agg((12 * cp.size + case c.rig when 'square' then 3 when 'mixed' then 1 when 'lateen' then 0 when 'oared' then -6 end
                               + case cp.role when 'explorer' then 2 else 0 end)::text, '/' order by c.code)
              from public.ship_classes c join public.class_profile cp on cp.class_code = c.code where c.code in ('barca', 'carlat', 'nau')) = '12/26/39',
       (select count(*)::text from public.ship_classes)
union all
select 'the nine gear families hold exactly the 65 items 0215 inserts wave rows for; none has a wave row',
       (select count(*) from public.item_profile where base_type in ('Anchor', 'Sheet Anchor', 'Storm Canvas', 'Planking', 'Sheathing', 'Bilge Pumps', 'Ballast', 'Doubled Frames', 'Raised Forecastle')) = 65
       and not exists (select 1 from public.item_effects where stat = 'wave')
       and exists (select 1 from pg_constraint where conname = 'item_effects_stat_check' and conrelid = 'public.item_effects'::regclass),
       (select count(*)::text from public.item_profile where base_type in ('Anchor', 'Sheet Anchor', 'Storm Canvas', 'Planking', 'Sheathing', 'Bilge Pumps', 'Ballast', 'Doubled Frames', 'Raised Forecastle'))
union all
select 'harbours: >= 200, every one with a sea_reaches roadstead (238 at writing)',
       (select count(*) from public.ports where kind = 'HARBOUR') >= 200
       and not exists (select 1 from public.ports p where p.kind = 'HARBOUR' and not exists (select 1 from public.sea_reaches sr where sr.port_id = p.id)),
       (select count(*)::text from public.ports where kind = 'HARBOUR')
union all
select 'the named harbours exist (LIS PON HAV CPT HNL HAG PAR BRS CAP OPO)',
       (select count(*) from public.ports where code in ('LIS', 'PON', 'HAV', 'CPT', 'HNL', 'HAG', 'PAR', 'BRS', 'CAP', 'OPO')) = 10, null
union all
select 'probe needs: SEAMANSHIP, classes barca + nau, new_house + commission_ship',
       exists (select 1 from public.skills where code = 'SEAMANSHIP')
       and (select count(*) from public.ship_classes where code in ('barca', 'nau')) = 2
       and exists (select 1 from pg_proc where proname = 'new_house' and pronamespace = 'public'::regnamespace)
       and exists (select 1 from pg_proc where proname = 'commission_ship' and pronamespace = 'public'::regnamespace),
       null
union all
select 'server is PostgreSQL 14+ (the water-mask check calls bit_count(bit))',
       current_setting('server_version_num')::int >= 140000, current_setting('server_version_num')
union all
select 'no probe leftovers (auth uid 0215, Casa 0215)',
       not exists (select 1 from public.players where auth_uid = '00000000-0215-4000-8000-000000000001' or company_name like '%0215%'), null
) t(chk, ok, seen)
order by ok nulls first, chk;
rollback;
```

### 8c. Before pushing 0216 (after S1 landed): the hunks. Expect every row `occurs = 1`, `new_already_there = 0`. (0215 re-cuts
none of these seven bodies, so this also reads true at head 0213.)

```sql
begin transaction read only;
-- 0216: every OLD hunk must occur EXACTLY once in the live body (LF-normalised). Expect every row occurs = 1.
with h(fn, n, old, new) as (values
('public.passage_gate(uuid,numeric,uuid)', 1,
$h$CREATE OR REPLACE FUNCTION public.passage_gate(p_player uuid, p_nm numeric, p_dest uuid)
$h$,
$h$CREATE OR REPLACE FUNCTION public.passage_gate(p_player uuid, p_fleet uuid, p_nm numeric, p_dest uuid, p_course jsonb DEFAULT NULL::jsonb)
$h$),
('public.passage_gate(uuid,numeric,uuid)', 2,
$h$  if p_dest is not null then
    select r.name, r.min_exploration_level into v_region, v_need
$h$,
$h$  -- 0216 (docs/SEA_CONDITIONS_AND_REGIONS.md, S2): WHILE THE SEA CONDITIONS BITE, the destination's waters and the
  -- course's are asked of the one rule (public.sea_gate: her title, her fleet's wave resistance, the zones) and the
  -- 0107 region door below is never read — the zone table is the one authority for "is this place open to her".
  -- Dark, the body below is the pre-image to the character (the region door goes with its column in the slice
  -- after the switch is lit).
  if public.sea_conditions_on() then
    return public.sea_gate(p_player, p_fleet, p_dest, p_course);
  end if;

  if p_dest is not null then
    select r.name, r.min_exploration_level into v_region, v_need
$h$),
('voyage.sail_refusal(uuid,uuid,jsonb,numeric)', 1,
$h$CREATE OR REPLACE FUNCTION voyage.sail_refusal(p_fleet uuid, p_dest uuid, p_dest_point jsonb, p_nm numeric)
$h$,
$h$CREATE OR REPLACE FUNCTION voyage.sail_refusal(p_fleet uuid, p_dest uuid, p_dest_point jsonb, p_nm numeric, p_course jsonb DEFAULT NULL::jsonb)
$h$),
('voyage.sail_refusal(uuid,uuid,jsonb,numeric)', 2,
$h$  v_gate := public.passage_gate(f.player_id, p_nm, p_dest);
$h$,
$h$  v_gate := public.passage_gate(f.player_id, f.id, p_nm, p_dest, p_course);   -- 0216: her fleet and her course, for the sea
$h$),
('cmd.do_sail(uuid,jsonb)', 1,
$h$  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, v_nm);
$h$,
$h$  v_gate := voyage.sail_refusal(p_fleet, v_dest, v_point, v_nm, v_course);   -- 0216: + the course (the sea conditions judge it)
$h$),
('cmd.standing_route_save_for(uuid,uuid,text,jsonb,bigint,integer,integer)', 1,
$h$      v_gate := public.passage_gate(p_player, v_leg_nm, v_port.id);
$h$,
$h$      v_gate := public.passage_gate(p_player, sr.fleet_id, v_leg_nm, v_port.id, s->'course');   -- 0216: + her fleet (none until assigned) and the leg's course
$h$),
('cmd.issue_lines(uuid,jsonb,integer)', 1,
$h$    v_gate := public.passage_gate(v_player, v_nm, v_dest);
$h$,
$h$    v_gate := public.passage_gate(v_player, p_fleet, v_nm, v_dest, v_lpath);   -- 0216: + the fleet and the course
$h$),
('voyage.reach_passage(uuid,uuid)', 1,
$h$CREATE OR REPLACE FUNCTION voyage.reach_passage(p_player uuid, p_from uuid)
$h$,
$h$CREATE OR REPLACE FUNCTION voyage.reach_passage(p_player uuid, p_fleet uuid, p_from uuid)
$h$),
('voyage.reach_passage(uuid,uuid)', 2,
$h$  v_path  text[];
begin
$h$,
$h$  v_path  text[];
  ok      boolean[];   -- 0216: lit, edge i → j is open when public.sea_leg_asks allows it for her title and her fleet's wave
  v_title int;
  v_wave  numeric;
begin
$h$),
('voyage.reach_passage(uuid,uuid)', 3,
$h$    select h.region_id, public.passage_gate(p_player, null, h.id) is null as open
$h$,
$h$    select h.region_id, public.passage_gate(p_player, p_fleet, null, h.id, null) is null as open   -- 0216: lit, the harbour's own zone
$h$),
('voyage.reach_passage(uuid,uuid)', 4,
$h$  if coalesce(array_length(d, 1), 0) <> v_n * v_n then
    raise exception 'voyage.reach_passage: % harbours but % sailed distances — a harbour has no sea_reaches row', v_n, coalesce(array_length(d, 1), 0);
  end if;
$h$,
$h$  if coalesce(array_length(d, 1), 0) <> v_n * v_n then
    raise exception 'voyage.reach_passage: % harbours but % sailed distances — a harbour has no sea_reaches row', v_n, coalesce(array_length(d, 1), 0);
  end if;
  -- 0216: THE SEA, ONCE A CALL. Lit, her title and her fleet's wave are read once and every edge is open or shut by
  -- public.sea_leg_asks (the straight line between the two roadsteads and the destination's zone — the one derivation,
  -- the same figures public.sea_refusal compares); a side she has no figure for (a merchant's title, an empty fleet's
  -- wave) is not asked, as the rule itself skips it. Dark, `ok` stays null and every edge is as before.
  if public.sea_conditions_on() then
    v_title := public.title_level(p_player);
    v_wave  := public.fleet_wave(p_fleet);
    select array_agg(coalesce((v_title is null or s.title_min <= v_title) and (v_wave is null or s.wave_min <= v_wave), true) order by a.i, b.j)
      into ok
      from unnest(v_ids) with ordinality a(id, i)
     cross join unnest(v_ids) with ordinality b(id, j)
      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = b.id;
    -- and a HARBOUR is open by its own zone (the self row of sea_leg_asks is exactly that), not by its region's first
    -- harbour: 0205's one-door-a-region shortcut holds for the region door, not for the sea (Funchal is home water in
    -- a region whose first harbour by code is the Azores).
    select array_agg(a.id = p_from or coalesce((v_title is null or s.title_min <= v_title) and (v_wave is null or s.wave_min <= v_wave), true) order by a.i)
      into v_open
      from unnest(v_ids) with ordinality a(id, i)
      left join public.sea_leg_asks s on s.from_port = a.id and s.to_port = a.id;
  end if;
$h$),
('voyage.reach_passage(uuid,uuid)', 5,
$h$      if not done[j] and v_open[j] then
$h$,
$h$      if not done[j] and v_open[j] and (ok is null or ok[(u - 1) * v_n + j]) then   -- 0216
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 1,
$h$    from voyage.reach_passage(v_player, v_origin) r;
$h$,
$h$    from voyage.reach_passage(v_player, p_fleet, v_origin) r;   -- 0216: + her fleet (the sea conditions)
$h$),
('world.good_board(uuid,uuid,uuid,numeric)', 2,
$h$     cross join lateral voyage.reach_passage(v_player, s.id) r
$h$,
$h$     cross join lateral voyage.reach_passage(v_player, p_fleet, s.id) r   -- 0216
$h$)
)
select h.fn, h.n,
       (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as occurs,
       (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_already_there
  from h
  cross join lateral (select replace(pg_get_functiondef(to_regprocedure(h.fn)), E'\r', '') as def) d
 order by h.fn, h.n;
rollback;
```

### 8d. Before pushing 0216: the self-assert's preconditions. Expect every row `ok = true`.

```sql
begin transaction read only;
-- 0216 preconditions (run at prod head 0215, i.e. after 0215 landed). Every row's `ok` must be true.
select * from (
select 'head is S1 (0215, or the number S1 was renumbered to at push)', max(version) >= '20260818000214', max(version)
  from supabase_migrations.schema_migrations
union all
select 'sea switch dark', (select value from public.world_config where key = 'sea_conditions_bite') = 'false'::jsonb, null
union all
select 'the seven old signatures exist, the three new ones do not',
       to_regprocedure('public.passage_gate(uuid,numeric,uuid)') is not null
       and to_regprocedure('voyage.sail_refusal(uuid,uuid,jsonb,numeric)') is not null
       and to_regprocedure('cmd.do_sail(uuid,jsonb)') is not null
       and to_regprocedure('cmd.standing_route_save_for(uuid,uuid,text,jsonb,bigint,integer,integer)') is not null
       and to_regprocedure('cmd.issue_lines(uuid,jsonb,integer)') is not null
       and to_regprocedure('voyage.reach_passage(uuid,uuid)') is not null
       and to_regprocedure('world.good_board(uuid,uuid,uuid,numeric)') is not null
       and to_regprocedure('public.passage_gate(uuid,uuid,numeric,uuid,jsonb)') is null
       and to_regprocedure('voyage.sail_refusal(uuid,uuid,jsonb,numeric,jsonb)') is null
       and to_regprocedure('voyage.reach_passage(uuid,uuid,uuid)') is null,
       null
union all
-- world.trade_routes calls voyage.sail_refusal with 4 arguments: it resolves to the new 5-argument signature by its default (course null)
select 'no caller of the three changed signatures beyond the re-cut bodies and world.trade_routes',
       (select array_agg(distinct n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'world', 'cmd', 'voyage')
           and (p.prosrc ~ 'passage_gate\(' or p.prosrc ~ 'sail_refusal\(' or p.prosrc ~ 'reach_passage\(')
           and p.proname not in ('passage_gate', 'sail_refusal', 'reach_passage'))
       <@ array['cmd.do_sail', 'cmd.issue_lines', 'cmd.standing_route_save_for', 'world.good_board', 'world.trade_routes']::text[],
       (select string_agg(distinct n.nspname || '.' || p.proname, ',')
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'world', 'cmd', 'voyage')
           and (p.prosrc ~ 'passage_gate\(' or p.prosrc ~ 'sail_refusal\(' or p.prosrc ~ 'reach_passage\(')
           and p.proname not in ('passage_gate', 'sail_refusal', 'reach_passage'))
union all
select 'the named harbours exist (LIS HAV HNL LPA FNC OPO CAD SAF SVQ SET TEN AGA)',
       (select count(*) from public.ports where code in ('LIS', 'HAV', 'HNL', 'LPA', 'FNC', 'OPO', 'CAD', 'SAF', 'SVQ', 'SET', 'TEN', 'AGA')) = 12, null
union all
select 'probe needs: NAVIGATION + SEAMANSHIP, classes barca nau carraca',
       (select count(*) from public.skills where code in ('NAVIGATION', 'SEAMANSHIP')) = 2
       and (select count(*) from public.ship_classes where code in ('barca', 'nau', 'carraca')) = 3, null
union all
select 'no probe leftovers (auth uid 0216, Casa/Comptoir 0216)',
       not exists (select 1 from public.players where auth_uid = '00000000-0216-4000-8000-000000000001'
                                                 or company_name in ('Casa 0216', 'Comptoir 0216')), null
) t(chk, ok, seen)
order by ok nulls first, chk;
rollback;
```

## 9. Summary (2026-10-20, the cloud routine)

- **#275 (S1, `osn-sea-s1`)**: every check green on `5278abe` (build, select, pglite-gate ×3, disposable-chain against main's
  0213 snapshot on real PostgreSQL, acceptance shards ×6, npc-on-world, acceptance). This commit (the FK move + this log)
  re-runs them; see the PR comment for the state on the new head.
- **#276 (S2, `osn-sea-s2`)**: rebased onto the new S1 (one commit, 0216 unchanged). Everything green except `disposable-chain`.
  That red is the expected one: "no usable applied-chain snapshot for this chain — refusing to rebuild from zero on a PR". It turns green
  once S1 is on main.
- **Locks**: §7. Longest on a hot table: `players` AccessExclusive 7.5 s (0215); `ports` writes 7.6 s (down from 120 s).
  0216 holds nothing that blocks play.
- **Not verified**: the migrations have not run on prod (no push by order). The CI disposable-chain timing of 0215 on real
  PostgreSQL was not read (the log download was refused by the sandbox proxy). The two rpc specs did not finish locally (CI ran
  them). PGlite's wall-clock is wasm, not prod. The lock method cannot see locks inside the rolled-back probes (they are
  RowExclusive on probe rows only).

## 10. The failed prod push, and the speed-up (2026-10-20, the cloud routine)

**What happened.** ~08:55 UTC the main session pushed 0215 to prod (head 0213). Every §8 precheck had passed. The push
failed with `DbPushApplyError: Error: Connection terminated unexpectedly  At statement: 23`. Statement 23 (0-based) is
the DO block that counted water cells against zoned cells with a 1,036,800-row cross join of `get_byte` pairs. Prod
rolled back to 0213. Nothing of 0215 is on prod.

**The cause, as far as it can be seen from here.** The server closed the connection; it did not report a timeout or an
error. So the exact trigger (a pooler or server limit on one long transaction, or memory) cannot be read from this
container. What is certain is that the file did far too much per-cell and per-sample work in one transaction. Measured on
native PostgreSQL 16 (local, below), the work before the self-assert took 82 s, and prod's compute is slower than this
machine.

**How it was measured.** A local PostgreSQL 16 cluster (no Supabase, nothing linked) with the REAL sea raster of 0040
(720 rows, 647,226 water cells), the 51 seas with their raster ordinals, `voyage.gc_distance_nm` and `voyage.lon_lerp`
copied from 0002 and 0088, and 238 harbours placed on random water cells (seeded). The world was not built from zero.
0215 was run from its first statement through the `sea_leg_asks` fill in one transaction, statement by statement with
`\timing`. (Later edits to the raster by 0046–0091 move a few cells. They do not change the cost.)

| Step | Before | After | How |
|---|---:|---:|---|
| zone raster build | 6.7 s | 0.85 s | The old build asked the boxes once per CELL: 1,036,800 sub-queries in a plpgsql loop. The new one splits the chart into BANDS at every row and column where a box bound can change the answer (each cut ±1). It asks the boxes once per (row band, column band, sea), at the band's first cell, with the same tests. Each row is then 1,440 reads of one dense array. |
| water vs zoned (statement 23) | 3.6 s | 0.2 s | 720 row-by-row comparisons of bit-string "water masks" (each byte's 8 bits OR-ed into one). This is stronger than the old check: it compares the POSITIONS, not just the totals. Controls: one cell zeroed, the last cell, a neighbour. |
| band cuts re-asked | — | ~1 s | NEW: every cell on and beside a cut (98,400) is asked of the box rule directly. A band that is off by one fails here. |
| `sea_leg_asks` derivation | 71.6 s | 2.3 s | `voyage.lon_lerp` cannot be inlined (its scalar sub-select costs ~6 µs a call × 5 million samples = 30 s). The planner also re-computed each pair's great circle per sample and sorted 4 million rows to disk. Now the pairs are materialised, the zone bytes are made distinct inside each pair, and lon_lerp's arithmetic is written out. The self-assert holds it to the authority: every leg out of Lisbon equals what `public.course_zones` (which calls `voyage.lon_lerp`) gives for the same two-vertex line. |
| **everything up to the fill** | **82 s** | **4.8 s** | |

**Same answers.** On the fixture, the new raster equals the old one byte for byte on all 720 rows, and the new 56,644
leg asks equal the old derivation's rows exactly (md5 of the sorted dumps). Negative controls were run on the fixture.
A cell flipped on a band cut fails "cells on the band cuts disagree". A water cell zeroed fails "a water cell answers no
zone". A Lisbon leg's stored wave bumped by 1 fails "differ from the stored asks" against `course_zones`.

**The rest of the file (estimated, not measured here).** The hunks, the 65 gear rows, the column changes and the
self-assert took ~18 s in PGlite (§7). Native PostgreSQL should be a few seconds. The new Lisbon-vs-`course_zones` check
adds ~1.5 s. **Estimate for the whole 0215 on prod: well under 60 s** if prod is up to ~3× slower than this machine. The
prod receipt's timings are the measurement that counts.

**Locks.** Nothing new touches a live table. The new statements write only `sea_zone_cells` (new) and temp tables. The
`ports` foreign keys of `sea_leg_asks` are still added after the fill. Because the whole file is now ~20× shorter, every
lock in §7 is held for seconds, not minutes.

**Kept as it was.** `statement_timeout` 20 min and `lock_timeout` 5 s, set locally at the top, as 0207–0213 do. No new
`set` was added. The hunks, the probe and every other self-assert line are unchanged.

**0216 on top.** Its hunks anchor on seven bodies that 0215 does not re-cut, and it reads only `sea_leg_asks`, whose
shape did not change. §8c/§8d are unchanged. `osn-sea-s2` was rebased onto the new S1.

**For the next push.** Run §8a and §8b again (8b has the one new row), then push at a quiet moment. If the connection
drops again on a file this short, the cause is the connection itself (the pooler or the network), not the migration's
length. In that case the CLI's direct connection should be tried before anything else is changed.

## RE-SLICED ONTO 0214, 2026-10-20 ~14:20 UTC (cloud session)

0214 (the stats tab) went live at 14:05 UTC, so the prod head moved 0213 → 0214 while this PR sat
open. That broke the registry hunk, and the self-assert would have refused the push:

- The hunk anchored on `('world', 'insurance', '')` as the LAST row of
  `public.client_rpc_entry_points()`, immediately followed by `) as t(s, f, a)`.
- 0214 appended six `stats_*` rows after insurance, so that text no longer occurs in the live body.
  Checked read-only on prod: the old anchor occurred **0 times**.

The hunk is now sliced onto 0214's last row instead (`('world', 'stats_me', '')`). Verified
read-only against the deployed body, the same three things the migration asserts for itself:

| | |
|---|---|
| the OLD anchor occurs in the live body | **1** (must be 1) |
| the NEW text already present | **0** (must be 0) |
| applying it reverses to the pre-image | **true** |

Nothing else moved: the four `world.*` hunks (ship_stats ×2, ship_view, fleets, player) were sliced
at head 0211 and those bodies have not changed since, so they still occur once each.

main was also merged in (it was 6 behind, 4 ahead). Two conflicts, both the same shape — 0214 and
0215 each append to the one RPC registry — resolved by keeping both, 0214's six rows first:
`src/lib/rpc/catalog.ts` and `tests/rpc.surface.spec.ts`.

**Still to do before this deploys:** CI must go green on the merge (the earlier `disposable-chain`
pass was against a 0213 snapshot; it now has to apply 0215 on top of 0214), and §8a/§8b's prod
checks should be re-read, since they were last run at 08:53 UTC against the old head.
