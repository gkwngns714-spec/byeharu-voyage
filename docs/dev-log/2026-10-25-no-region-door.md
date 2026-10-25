# 2026-10-25 — There is no region door (owner row 204, migration 0218)

> The owner, 2026-10-25: *"remove the region door, let me sail anywhere"* (docs/OWNER_REQUESTS.md row 204).

Branch `osn-no-region-door`, migration `supabase/migrations/20260818000218_there_is_no_region_door.sql`
(renumbers to the prod head + 1 at push; written against main's chain plus 0217, PR #295, which re-cuts only
`public.city_treasury_switch(boolean)` and touches none of the four bodies sliced here).

## 1. What the door was, and where it is cut

The diagnosis is docs/COMMAND_REDESIGN.md §1a row 1: each region asked an exploration level,
`1 + floor(sailed nm from Lisbon / 2,500)`, capped at 5, and a Lisbon starter at level 1 reached 111 of 237
harbours. Every place the level gated something, and what 0218 does to it:

| where | what it did | 0218 |
|---|---|---|
| `public.passage_gate` (0107:264-276, 0112 hunk 1, kept dark by 0216 hunk 2) | refused `E_REGION_CLOSED` when `regions.min_exploration_level > public.exploration_reach(player)` | block CUT (3 hunks: the three declared figures, the header comment, the block). Dark, the gate is the leg's length alone; lit, `public.sea_gate` as 0216 wrote it. |
| `voyage.reach_passage` (0188:177, 0205 hunk 1's `door` CTE, 0216 hunk 3) | asked the gate once a region with no miles, and shut every harbour of a shut region in the Dijkstra | CTE CUT (3 hunks): `v_open` is all true dark; lit, 0216's zone reading of `v_open` is untouched. The dark passage table no longer calls `passage_gate` at all. |
| `public.route_requirement` (0108:80-106) | served `requires.exploration` = the dearest region a lane calls at | key CUT (2 hunks): a lane asks `{navigation}` alone |
| `world.route_board` (0108 hunks 2-3, 0109, 0110 hunks 2 and 4, 0112 hunk 2) | `closed` and the ordering read `exploration > v_exp` | navigation alone (3 hunks); `v_exp` and its `exploration_reach` read gone |
| `public.exploration_reach(uuid)` (0112:115) | the door's reading of her level | DROPPED |
| `public.regions.min_exploration_level` (0107:122) | the door's data | COLUMN DROPPED |
| `world_config.region_level_nm_step`, `region_level_max` (0107:113-117) | the derivation's knobs | DELETED |
| `src/lib/i18n/dict/codes.ts:51,203` | the sentence for `E_REGION_CLOSED` | removed (en, ko) |
| `src/features/routes/RoutesScreen.tsx:274-280, 335` and `dict/routes.ts` `needsExp`, `navExp` | "needs exploration N", "Nav N · Exp N" | `shutBecause` says navigation or nothing; the Asks row prints `Navigation {nav}` (`asksNav`) |
| `src/lib/rpc/types.ts:2205` | `requires: { navigation; exploration }` | `{ navigation }` |
| `tests/rpc.surface.spec.ts:2050` | asserted `requires.exploration >= 1` | asserts the keys are exactly `['navigation']` |
| docs/COMMAND_REDESIGN.md default 4, docs/SEA_CONDITIONS_AND_REGIONS.md S2b note | "the region door stays / goes at the flip" | marked superseded by row 204 |

Grep after the change (`E_REGION_CLOSED|min_exploration_level|exploration_reach|needsExp|navExp`) hits only
applied migrations (history: 0107, 0108, 0112, 0205, 0215, 0216), 0218 itself, and the docs that record the change.

**What is kept, on purpose.** The EXPLORATION track itself (0069: fame, level, ports reached, nm sailed) drives
rank, the You tab and the captains (0160/0162); only its use as a door is cut. The 1,700 nm leg
(`public.passage_reach_nm`, 0188) and `E_LEG_TOO_FAR`. Supplies and endurance (`voyage.sail_refusal`). Money. The
sea conditions (0215/0216), dark. The route board's `regions` count (informational). Merchants were already exempt at
the door (0107 d4); their lanes no longer show as shut for exploration to a viewer.

**Decided by default.** The column and the knobs go with the door rather than staying as dead data: nothing reads them
once the four bodies are re-cut (asserted over every live body in `cmd`, `voyage`, `world`, `public`, `npc`). The
route board's `closed` now means "its longest leg asks a navigation above yours"; `shutBecause` on the Routes tab
prints that or nothing.

## 2. The self-assert (own probe rows, rolled back)

Probe `00000000-0218-4000-8000-000000000001`, "Casa 0218", a barca at Lisbon, exploration 1 (asserted). Pre-images
under `pg_temp` (`passage_gate_old_0218`, `reach_passage_old_0218` calling it, `route_requirement_old_0218`,
`route_board_old_0218` calling that). From Lisbon: the passage table loses no harbour and no mile against its
pre-image and gains harbours, every one of them in a region whose former level was above 1; a harbour of the former
TOP level is reached by legs, the old gate says `E_REGION_CLOSED` needing that level (positive control), the new gate
answers null with no miles and with the passage's longest leg, the sail door says neither `E_REGION_CLOSED` nor
`E_LEG_TOO_FAR`; a 999,999 nm leg is still `E_LEG_TOO_FAR`; a merchant is exempt before and after. For every human of
the world, from where her first fleet lies: nothing lost, nothing longer. The route board: same lanes, `requires` is
`{navigation}` on every row, no lane shut now that was open before, both shut and open lanes present, `closed` equals
the navigation rule. Timed 6 + 6 calls of `reach_passage` and of `passage_gate` in one session. Then, after the drops:
no live body names the door; the column, the function and the knobs are gone; the walls hold; the registry is unmoved.

## 3. Measured (local PGlite, the chain restored from the prefix cache)

Chain: 209 files, 208 restored from the prefix cache, 0218 applied on top (self-assert 7.1 s). Also run with 0217
staged untracked beside it (210 files; the deploy order): same result, 0218 applied in 19.7 s all told.

- **A Lisbon starter** (exploration 1, a barca, founding navigation) **reaches 217 of 237 harbours; it was 111.** With
  0217's eight new harbours: **222 of 245** (was 114; +108 gained, every one in a region whose former level was above 1).
- **Still unreached, 20, all by the leg rule** (no chain of legs at or under 1,700 nm from anywhere she can reach):
  `ACA ARI BUV CLL CON COQ GYE HNL HOB HUA MTY MZT NAV PAI PAN REA SDG SFR SYD VLP` — the Pacific coast of the
  Americas, Hawaii, Sydney and Hobart. This is COMMAND_REDESIGN §1a row 2 ("leg reach"), untouched by this slice.
- **The former top level opens:** AMB (Amboina, former level 5) is reached on a 1,677.4 nm longest leg; the old gate
  says `E_REGION_CLOSED` needing 5 (positive control), the new gate answers null with no miles and with that leg, the
  sail door says neither `E_REGION_CLOSED` nor `E_LEG_TOO_FAR`; a 999,999 nm leg is still `E_LEG_TOO_FAR`.
- **Every human of the local world** (13): 1,080 passages gained, none lost, none longer.
- **Route board** for the probe: 400 lanes (the cap), 0 shut, `requires` = `{navigation}` on every row, no lane shut
  now that was open before.
- **Hot functions, 6 calls each in one session:** `reach_passage` from Lisbon old/new **178.5 / 155.7 ms** (calls 4-6:
  181.7 / 158.7) — faster, since the dark table no longer asks the gate once a region; `passage_gate` (no miles, AMB)
  old/new **0.83 / 0.17 ms**. No generic-plan cliff.
- The world-image build with 0217 staged untracked failed on WORLD DRIFT (0217's eight harbours and ten goods against
  main's data/*.json) — 0217's own branch carries that data; not this slice. The committed branch builds green.

## 4. Gates run locally

- `npx tsc -b` 0 · `npx eslint .` 0 · `npm run build` 0 (the world image is built from this chain, 0218 applied inside it).
- `tests/duplication.spec.ts` + `tests/i18n.keys.spec.ts`: 14 passed (the 0218 tag, the supersede header, the dictionaries).
- `tests/rpc.surface.spec.ts` (touched): 30 passed, 12.4 s, against the built world.
- Not run here: browser specs (no `vite preview` on this busy PC) — `tests/map.regions.spec.ts` is the chart's region
  tint and names no level or door; no proof under scripts/db/proofs mentions regions or the door. CI runs the rest.
- 0217 (PR #295) overlap: none — it re-cuts only `public.city_treasury_switch(boolean)` and seeds ports, goods and sea
  rows; none of the four bodies sliced here.

## PROD CHECKS FOR THE MAIN SESSION

Read-only. Each block is ONE statement with no trailing semicolon and no dollar-quoting, so it runs as
`npx --yes supabase@2.120.0 db query --linked "<block>"`. The only functions used are built-ins
(`length`, `replace`, `chr`, `pg_get_functiondef`, `now`, `left`), all stable or immutable; no game function is
called. Expected answers are for the state BEFORE 0218 is pushed.

1. The head is 0217 and 0218 is not applied. Expect `20260818000217`.

```sql
select max(version) as head from supabase_migrations.schema_migrations
```

2. The door's data is there to drop. Expect `1`.

```sql
select count(*) as col from information_schema.columns where table_schema = 'public' and table_name = 'regions' and column_name = 'min_exploration_level'
```

3. The two knobs exist. Expect 2 rows: `region_level_max 5`, `region_level_nm_step 2500`.

```sql
select key, value from public.world_config where key in ('region_level_max', 'region_level_nm_step') order by key
```

4. The function to drop exists, once. Expect `1`.

```sql
select count(*) as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'exploration_reach'
```

5. Nothing but the four bodies names the door (the catalog scan the self-assert repeats after the cut). Expect exactly
   these four: `public.passage_gate`, `public.route_requirement`, `voyage.reach_passage`, `world.route_board`.

```sql
select n.nspname || '.' || p.proname as fn from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('cmd', 'voyage', 'world', 'public', 'npc') and (p.prosrc like '%E_REGION_CLOSED%' or p.prosrc like '%min_exploration_level%' or p.prosrc like '%exploration_reach%') order by 1
```

6. No view depends on the column (the DROP COLUMN would fail on one). Expect 0 rows.

```sql
select distinct c.relname from pg_depend d join pg_rewrite rw on rw.oid = d.objid join pg_class c on c.oid = rw.ev_class join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid where d.refobjid = 'public.regions'::regclass and a.attname = 'min_exploration_level'
```

7. The sea switch is dark (0218 is cut for the dark gate; the self-assert refuses to run lit). Expect `false` or no row.

```sql
select value from public.world_config where key = 'sea_conditions_bite'
```

8. The probe company is free. Expect `0`.

```sql
select count(*) from public.players where auth_uid = '00000000-0218-4000-8000-000000000001' or company_name = 'Casa 0218'
```

9. Each hunk's pre-image occurs exactly once in the live body. Eleven blocks, each expect `1`. The key is one plain
   line of the hunk; `chr(13)` strips a CR the way the migration does.

`public.passage_gate` hunk 1 (the declared figures):

```sql
select (length(d) - length(replace(d, '  v_region  text;', ''))) / length('  v_region  text;') as occurs from (select replace(pg_get_functiondef('public.passage_gate(uuid,uuid,numeric,uuid,jsonb)'::regprocedure), chr(13), '') as d) x
```

`public.passage_gate` hunk 2 (the header comment):

```sql
select (length(d) - length(replace(d, '--   the DESTINATION''s region against her EXPLORATION level.', ''))) / length('--   the DESTINATION''s region against her EXPLORATION level.') as occurs from (select replace(pg_get_functiondef('public.passage_gate(uuid,uuid,numeric,uuid,jsonb)'::regprocedure), chr(13), '') as d) x
```

`public.passage_gate` hunk 3 (the door block):

```sql
select (length(d) - length(replace(d, '    select r.name, r.min_exploration_level into v_region, v_need', ''))) / length('    select r.name, r.min_exploration_level into v_region, v_need') as occurs from (select replace(pg_get_functiondef('public.passage_gate(uuid,uuid,numeric,uuid,jsonb)'::regprocedure), chr(13), '') as d) x
```

`voyage.reach_passage` hunk 1 (the header comment):

```sql
select (length(d) - length(replace(d, '-- (public.passage_gate''s region check, asked of passage_gate).', ''))) / length('-- (public.passage_gate''s region check, asked of passage_gate).') as occurs from (select replace(pg_get_functiondef('voyage.reach_passage(uuid,uuid,uuid)'::regprocedure), chr(13), '') as d) x
```

`voyage.reach_passage` hunk 2 (0205's door CTE):

```sql
select (length(d) - length(replace(d, '  with door as materialized (', ''))) / length('  with door as materialized (') as occurs from (select replace(pg_get_functiondef('voyage.reach_passage(uuid,uuid,uuid)'::regprocedure), chr(13), '') as d) x
```

`voyage.reach_passage` hunk 3 (0216's note on the door):

```sql
select (length(d) - length(replace(d, '    -- harbour: 0205''s one-door-a-region shortcut holds for the region door, not for the sea', ''))) / length('    -- harbour: 0205''s one-door-a-region shortcut holds for the region door, not for the sea') as occurs from (select replace(pg_get_functiondef('voyage.reach_passage(uuid,uuid,uuid)'::regprocedure), chr(13), '') as d) x
```

`public.route_requirement` hunk 1 (the comment):

```sql
select (length(d) - length(replace(d, '  -- 0106''s course_nm per stop and 0107''s min_exploration_level per region.', ''))) / length('  -- 0106''s course_nm per stop and 0107''s min_exploration_level per region.') as occurs from (select replace(pg_get_functiondef('public.route_requirement(uuid)'::regprocedure), chr(13), '') as d) x
```

`public.route_requirement` hunk 2 (the key):

```sql
select (length(d) - length(replace(d, '      ''exploration'', coalesce((', ''))) / length('      ''exploration'', coalesce((') as occurs from (select replace(pg_get_functiondef('public.route_requirement(uuid)'::regprocedure), chr(13), '') as d) x
```

`world.route_board` hunk 1 (the declaration):

```sql
select (length(d) - length(replace(d, '  v_exp   int;     -- 0108: ...and her EXPLORATION level', ''))) / length('  v_exp   int;     -- 0108: ...and her EXPLORATION level') as occurs from (select replace(pg_get_functiondef('world.route_board()'::regprocedure), chr(13), '') as d) x
```

`world.route_board` hunk 2 (the reading):

```sql
select (length(d) - length(replace(d, '  v_exp := public.exploration_reach(v_me);', ''))) / length('  v_exp := public.exploration_reach(v_me);') as occurs from (select replace(pg_get_functiondef('world.route_board()'::regprocedure), chr(13), '') as d) x
```

`world.route_board` hunk 3 (`within` and the order): this line occurs TWICE in the live body by design (once in `within`,
once in the window's order), and the hunk carries both in one piece. Expect `2`.

```sql
select (length(d) - length(replace(d, 'or coalesce((r.requires->>''exploration'')::int, 1) > v_exp) ', ''))) / length('or coalesce((r.requires->>''exploration'')::int, 1) > v_exp) ') as occurs from (select replace(pg_get_functiondef('world.route_board()'::regprocedure), chr(13), '') as d) x
```

10. The harbours behind the door today, by former level (informational; the self-assert's receipt names what a
    Lisbon starter reaches after). Expect 5 rows, level 1 the smallest group of the shut ones.

```sql
select r.min_exploration_level as lvl, count(*) as harbours from public.ports p join public.regions r on r.id = p.region_id where p.kind = 'HARBOUR' group by 1 order by 1
```

11. The lock the file takes (`alter table public.regions drop column`, lock_timeout 5 s): who holds `regions`?
    Expect no row older than a few seconds.

```sql
select a.pid, a.state, now() - a.xact_start as open_for, l.mode, left(a.query, 80) as query from pg_locks l join pg_class c on c.oid = l.relation join pg_stat_activity a on a.pid = l.pid where c.relname = 'regions' and a.pid <> pg_backend_pid() order by a.xact_start
```

After the push, the receipt line `0218 self-assert ok: THERE IS NO REGION DOOR …` and the `0218 probe:` notice carry the
prod reach figures; checks 2, 3, 4 then read `0`, no rows, `0`, and check 5 reads no rows.
