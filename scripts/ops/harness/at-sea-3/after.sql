-- 0426 PROD CHECK, BEFORE and AFTER the deploy (+30 min and +3 h), read-only, ONE statement, stable functions only:
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/at-sea-3/after.sql
-- One row, one jsonb column `r`. Run scripts/ops/harness/db-health/gate.sql first (gate_ok true).
-- Reads npc_fleets (~900) with their fleets and routes by key, cargo_ships (~370) with their fleets and each one's newest LOADED row through
-- convoy_cargo's (fleet_id, id) index, for the merchants moved in the last three hours (a handful) their newest NPC_REHOMED event through events' (player_id, created_at) index, and
-- the beat's ring. No big table is scanned. npc_fleets.rehomed_at is read through to_jsonb so the same file runs before 0426 (no column: null).
-- BEFORE, wanted: head 20260818000425; applied false; old_hunk 1, new_hunk 0; knobs npc_min_return_pct 5, convoy_load_max 250000,
--   convoy_loads_per_run 20, no npc_rehome_* knob. Write `merchants` and `cargo` down: they are the "before" of the after-check.
-- AFTER, wanted: head 20260818000426; applied true; old_hunk 0, new_hunk 1; knobs 2, 100000, 30, npc_rehome_per_run 4 (an owner's own value is
--   left by 0426 and named in its receipt); the gate green.
-- READING after the deploy: merchants.rehomed_30m grows by at most 4 a minute while the ~45 eligible are asked (each within 30 minutes), then a
--   few an hour; merchants.laid_up falls from ~103 toward ~50-70 within the hour; merchants.at_sea rises from ~732 toward ~770-790 (the moved
--   sail at once; 2 % keeps parcels 5 % dropped). moves (the newest NPC_REHOMED payloads) every passage_net above 0. cargo.loads_largest_1h at
--   most 100000 after the next :37 city run; cargo.at_sea rises over hours as loaded ships come home and their realms reload in 100,000 shares
--   (expected ~150-200 of 361). beat.mean_ms under 1,000.
begin transaction read only;
with body as (
  select replace(pg_get_functiondef('public.waiting_ask_plan(uuid)'::regprocedure), E'\r', '') as def
), m as (
  select case
           when ro.k > public.wc_int('npc_fleet_max') then 'dark'
           when f.status = 'SAILING' then 'at_sea'
           when sr.paused_reason = 'laid_up' then 'laid_up'
           when sr.paused_reason is not null then 'paused'
           when f.status <> 'DOCKED' then 'other'
           when sr.hold_until > now() then 'resting'
           when f.ready_at > now() then 'port_time'
           when sr.lap_id is not null then 'mid_lap'
           else 'due' end as st,
         nf.refused, (to_jsonb(nf)->>'rehomed_at')::timestamptz as rehomed_at
    from public.npc_tend_roster() ro
    join public.npc_fleets nf on nf.fleet_id = ro.fleet_id
    join public.fleets f on f.id = nf.fleet_id
    join public.standing_routes sr on sr.id = nf.route_id
), c as (
  select x.laid_up_at, f.status, f.port_id, x.home_port_id,
         (select a.aboard from public.cargo_ship_aboard(x.fleet_id) a) as aboard,
         l.created_at as last_at, l.ducats as last_d
    from public.cargo_ships x join public.fleets f on f.id = x.fleet_id
    left join lateral (select b.created_at, b.ducats from public.convoy_cargo b where b.fleet_id = x.fleet_id and b.stage = 'LOADED' order by b.id desc limit 1) l on true
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'applied', to_regprocedure('public.npc_rehome(uuid)') is not null,
  'old_hunk', (select (length(b.def) - length(replace(b.def, E'  if coalesce((v_res->>''planned'')::int, 0) = 0 or coalesce((v_res->>''waiting'')::int, 0) > 0 then\n    return 0;', '')))
                      / length(E'  if coalesce((v_res->>''planned'')::int, 0) = 0 or coalesce((v_res->>''waiting'')::int, 0) > 0 then\n    return 0;') from body b),
  'new_hunk', (select (length(b.def) - length(replace(b.def, E'    -- 0426: NOTHING FROM HER HARBOUR PAYS', ''))) / length(E'    -- 0426: NOTHING FROM HER HARBOUR PAYS') from body b),
  'knobs', (select jsonb_object_agg(w.key, w.value) from public.world_config w
             where w.key in ('npc_min_return_pct', 'convoy_load_max', 'convoy_loads_per_run', 'npc_rehome_per_run', 'npc_rehome_after_refused',
                             'npc_rehome_after_hours', 'npc_rehome_purse_min', 'npc_rehome_candidates', 'npc_buyers_per_good', 'npc_ask_job_ms')),
  'merchants', (select jsonb_build_object('n', count(*), 'at_sea', count(*) filter (where m.st = 'at_sea'),
                                          'in_port', count(*) filter (where m.st not in ('at_sea', 'dark')),
                                          'laid_up', count(*) filter (where m.st = 'laid_up'),
                                          'laid_up_4plus', count(*) filter (where m.st = 'laid_up' and m.refused >= 4),
                                          'rehomed_30m', count(*) filter (where m.rehomed_at > now() - interval '30 minutes'),
                                          'rehomed_3h', count(*) filter (where m.rehomed_at > now() - interval '3 hours'),
                                          'why', (select jsonb_object_agg(z.st, z.k) from (select m2.st, count(*) as k from m m2 group by m2.st) z)) from m),
  'moves', (select jsonb_agg(e.payload order by e.created_at desc)
              from (select nf.player_id from public.npc_fleets nf
                     where (to_jsonb(nf)->>'rehomed_at')::timestamptz > now() - interval '3 hours'
                     order by (to_jsonb(nf)->>'rehomed_at')::timestamptz desc limit 12) z
              cross join lateral (select e0.payload, e0.created_at from public.events e0
                                   where e0.player_id = z.player_id and e0.kind = 'NPC_REHOMED' order by e0.created_at desc limit 1) e),
  'cargo', (select jsonb_build_object('n', count(*), 'at_sea', count(*) filter (where c.status = 'SAILING'),
                                      'at_sea_funds', count(*) filter (where c.status = 'SAILING' and c.aboard > 0),
                                      'aboard', coalesce(sum(c.aboard), 0),
                                      'home_idle', count(*) filter (where c.laid_up_at is null and c.status = 'DOCKED' and c.port_id = c.home_port_id and c.aboard is null),
                                      'laid_up', count(*) filter (where c.laid_up_at is not null),
                                      'loads_1h', count(*) filter (where c.last_at > now() - interval '1 hour'),
                                      'loads_largest_1h', max(c.last_d) filter (where c.last_at > now() - interval '1 hour'))
              from c),
  'beat', (select jsonb_build_object('beats', count(*), 'mean_ms', round(avg(a.ms)), 'p95_ms', round(percentile_cont(0.95) within group (order by a.ms)::numeric))
             from public.arrivals_beats a where a.at > now() - interval '30 minutes')
) as r;
commit;
