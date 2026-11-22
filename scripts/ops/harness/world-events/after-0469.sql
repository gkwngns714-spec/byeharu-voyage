-- WORLD EVENTS (0469), AFTER. A PROD CHECK: read-only, ONE statement, small. Run once after the deploy, and once after the owner lights it.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/world-events/after-0469.sql
-- Reads: catalog, world_config by key, buff_kinds (4 rows), the event rows of active_buffs (at most a handful), world_news by kind (EVENT_*,
-- a few rows an hour lit) and two stable reads (world.world_events: a handful of rows; world.spread of the harbours holding an event).
-- Expect, DARK (as deployed): head 0469; world_events_enabled false; kinds BLOCKADE, FAIR, FAMINE, FESTIVAL with FAIR alone on the calendar;
--   no event row; no EVENT_ news; world.world_events = {"on": false}; the read stable and executable by authenticated alone; the tick and
--   the want, toll and switch readers private.
-- Expect, LIT (one buff-calendar run later, within the hour at chance 0.5): at most world_event_max (3) event rows with ends_at ahead;
--   each named one has an EVENT_<kind> news row posted at the same instant; a running blockade's harbour quotes a cut 0.20 over its
--   own; world.world_events lists them. About 0.5 events an hour.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'world_events_enabled'),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'world_event%'),
  'kinds', (select jsonb_agg(jsonb_build_object('code', k.code, 'effect', k.effect, 'mag', k.magnitude_pct, 'cats', k.categories,
                                                'calendar', k.season_seconds is not null) order by k.code) from public.buff_kinds k),
  'events', (select coalesce(jsonb_agg(jsonb_build_object('kind', ab.kind_code, 'port', p.code, 'starts_at', ab.starts_at, 'ends_at', ab.ends_at,
                                                          'cut', case when ab.kind_code = 'BLOCKADE' then round(world.spread(p.id), 4) end)
                                       order by ab.starts_at), '[]'::jsonb)
               from public.active_buffs ab join public.ports p on p.id = ab.subject_id where ab.source like 'event:%'),
  'news', (select jsonb_object_agg(x.kind, x.n) from (select w.kind, count(*) as n from public.world_news w where w.kind like 'EVENT_%' group by 1) x),
  'read', world.world_events(),
  'read_stable', (select p.provolatile = 's' and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
                    from pg_proc p where p.oid = to_regprocedure('world.world_events()')),
  'private', (select bool_and(not has_function_privilege('authenticated', to_regprocedure(f), 'execute'))
                from unnest(array['public.tick_world_events(timestamp with time zone)', 'public.event_want(uuid,uuid)', 'public.world_event_toll(uuid)',
                                  'public.world_events_on()', 'public.want_mult_of(numeric)']) f),
  'job', (select jsonb_build_object('schedule', j.schedule, 'active', j.active) from cron.job j where j.jobname = 'byeharu-voyage:buff-calendar'));
rollback;
