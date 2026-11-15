-- 0451 PROD CHECK, BEFORE AND AFTER the deploy: THE DISTRIBUTION of the world's own fleets by kind, hulls and class, and what the pictures draw.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/npc-ladder/dist.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true). One statement, read only.
-- Reads public.fleet_census() (0448: THE one reading of every fleet's kind, state and ships; nothing is counted a second way here), the hulls
-- of the ~550 pirate, navy and cargo fleets by key, the three live bodies 0451 re-cuts (catalog) and the beat's ring. No big table is scanned.
-- BEFORE, wanted: applied false; hunks_once {1, 1, 1}; roster_squadrons 8 (the eight 0451 makes Dread), roster_dread 0; dist: NAVY one line
--   `galion*1`, CARGO one line `navire*1`, PIRATE six lines (brigantin, fusta, xebec, xebec*2, galeoncete*1+xebec*3, korsan*1+xebec*3);
--   looks: no flagship anywhere.
-- AFTER (an hour or more on), wanted: applied true; roster_dread 8; dist: NAVY four shapes a country (its own line's classes), CARGO three,
--   PIRATE with `kalyon*1+xebec*3` (up to 8) and `brigantin*1` / `xebec*2` among 0339's; looks: flagships in every kind; `fleets` by kind the
--   same as before (0451 adds and removes no fleet; a kind's ships change with its hulls); beat < 1,000 ms.
begin transaction read only;
with c as (
  select x.fleet_id, x.kind, x.state, x.ships from public.fleet_census() x where x.kind in ('NAVY', 'PIRATE', 'CARGO') and x.counted
), h as (
  select c.fleet_id, c.kind, c.state, c.ships,
         (select string_agg(z.code || '*' || z.n, '+' order by z.code)
            from (select k.code, count(*) as n from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = c.fleet_id group by k.code) z) as hulls,
         (select max(cp.size) from public.ships s join public.ship_classes k on k.id = s.class_id join public.class_profile cp on cp.class_code = k.code where s.fleet_id = c.fleet_id) as lead
    from c
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'applied', to_regclass('public.npc_ladder') is not null,
  'hunks_once', jsonb_build_object(
    'tick_pirates', (select (length(q.d) - length(replace(q.d, q.t, ''))) / length(q.t)
                       from (select replace(pg_get_functiondef('public.tick_pirates(timestamp with time zone)'::regprocedure), E'\r', '') as d,
                                    'jsonb_build_object(''purses'', public.pirate_purse_step(p_now)) else ''{}''::jsonb end' || E'\n' as t) q),
    'pirate_reborn', (select (length(q.d) - length(replace(q.d, q.t, ''))) / length(q.t)
                        from (select replace(pg_get_functiondef('public.pirate_reborn(uuid,timestamp with time zone)'::regprocedure), E'\r', '') as d,
                                     E'  perform public.fleet_mend(p_fleet);\n  perform public.fleet_book_refit(p_fleet, ' as t) q),
    'cargo_hull', (select (length(q.d) - length(replace(q.d, q.t, ''))) / length(q.t)
                     from (select replace(pg_get_functiondef('public.cargo_hull(uuid)'::regprocedure), E'\r', '') as d,
                                  E'begin\n  select x.* into s from public.ships x where x.fleet_id = p_fleet and x.is_flagship;\n' as t) q)),
  'roster_squadrons', (select count(*) from public.pirate_roster_hulls a
                        where a.class in ('galeoncete', 'korsan') and a.ord % 1000 % 18 = 6
                          and exists (select 1 from public.pirate_roster_hulls x where x.ord = a.ord and x.class = 'xebec' and x.n = 3)),
  'roster_dread', (select count(*) from public.pirate_roster_hulls a where a.class = 'kalyon'),
  'fleets', (select jsonb_object_agg(z.kind, z.v) from (select h.kind, jsonb_build_object('fleets', count(*), 'ships', sum(h.ships)) as v from h group by 1) z),
  'dist', (select jsonb_agg(to_jsonb(z) order by z.kind, z.fleets desc, z.hulls)
             from (select h.kind, h.hulls, count(*) as fleets, count(*) filter (where h.state = 'sea') as sea, count(*) filter (where h.state = 'port') as port,
                          count(*) filter (where h.state = 'wrecked') as wrecked, count(*) filter (where h.state = 'laid_up') as laid_up, count(*) filter (where h.state = 'battle') as battle
                     from h group by 1, 2) z),
  'looks', (select jsonb_agg(to_jsonb(z) order by z.kind, z.look, z.ships)
              from (select h.kind, case when h.lead >= 5 then '4 flagship' when h.lead >= 3 then '3 frigate' when h.lead = 2 then '2 brig' else '1 sloop' end as look, h.ships, count(*) as fleets
                      from h group by 1, 2, 3) z),
  'beat', (select jsonb_build_object('mean_ms', round(avg(a.ms)), 'n', count(*)) from public.arrivals_beats a where a.at > now() - interval '5 minutes')
) as r;
commit;
