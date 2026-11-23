-- EARLY SIGHTING (0477), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, small. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/early-sighting/after-0477.sql
-- `since` below is the last 30 minutes: read it 30 minutes after the deploy (as deployed) or after the owner lights early_sighting_enabled.
-- Expect, AS DEPLOYED (dark): head 20260818000477; knobs early_sighting_enabled false, trading_min 3, trip_min_seconds 240,
-- trip_max_seconds 1800, at 0.4, rung_max 1, strength 0.5, hull_floor 0.5; `registered` true; `client_reach` false; `hunked` all true
-- (each of the four bodies carries its 0477 line); `rows` {}; `events` 0.
-- LIT (read 30 minutes after lighting): `rows` by state (due, open, done, missed); `set_since` rows set in the window; `told` EARLY_SIGHTING
-- events = `rows.done`; `outcomes` of the told; `lost_max` the largest loss (a ransom: ransom_share of a cargo); `insured_paid` what
-- insurers paid back for sightings; `open_stuck` OPEN rows sighted over 10 minutes ago (0: a fight lasts about 75 s and is told the next
-- minute); `due_late` DUE rows whose time is over 10 minutes past (her trip should have been sighted or MISSED); `joined` ships that joined
-- a sighting (0); `ships_lost` sighted fleets UNABLE_TO_SAIL or with a hull at 0 (0); `strength` the guns each sighting fought at.
-- ROLLBACK if `ships_lost` > 0, `joined` > 0, `open_stuck` > 0 for two reads running, `told` <> `rows.done`, or the gate goes red:
-- early_sighting_enabled false (owner).
-- Reads: world_config by key, the catalog (registry, four bodies, privileges), public.early_sightings (one row a sighted company), their
-- battles' sides, their fleets' ships, their EARLY_SIGHTING and INSURANCE_PAID events by player. No function that writes is called.
begin transaction read only;
with since as (select now() - interval '30 minutes' as t),
es as (select * from public.early_sightings),
ev as (select e.player_id, e.kind, e.payload, e.created_at from public.events e
        where e.player_id in (select es.player_id from es) and e.kind in ('EARLY_SIGHTING', 'INSURANCE_PAID'))
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'early\_sighting\_%'),
  'registered', exists (select 1 from public.client_rpc_entry_points() e
                         where e.schema_name = 'world' and e.function_name = 'early_sighting' and e.fn is not null),
  'client_reach', has_table_privilege('authenticated', 'public.early_sightings', 'select')
                  or has_function_privilege('authenticated', 'public.early_sighting_plan(uuid,timestamp with time zone)', 'execute')
                  or has_function_privilege('authenticated', 'public.early_sighting_step(timestamp with time zone)', 'execute'),
  'hunked', jsonb_build_object(
    'depart', position('early_sighting_plan' in pg_get_functiondef('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)'::regprocedure)) > 0,
    'tick_pirates', position('early_sighting_step' in pg_get_functiondef('public.tick_pirates(timestamp with time zone)'::regprocedure)) > 0,
    'joins', position('early_sightings' in pg_get_functiondef('public.battle_npc_joins(timestamp with time zone)'::regprocedure)) > 0,
    'registry', position('early_sighting' in pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) > 0),
  'rows', (select coalesce(jsonb_object_agg(s.state, s.n), '{}'::jsonb) from (select es.state, count(*) as n from es group by es.state) s),
  'set_since', (select count(*) from es where es.planned_at > (select t from since)),
  'told', (select count(*) from ev where ev.kind = 'EARLY_SIGHTING'),
  'outcomes', (select coalesce(jsonb_object_agg(s.o, s.n), '{}'::jsonb)
                 from (select es.report ->> 'outcome' as o, count(*) as n from es where es.state = 'done' group by 1) s),
  'lost_max', (select coalesce(max((es.report ->> 'lost')::bigint), 0) from es where es.state = 'done'),
  'insured_paid', (select coalesce(sum((ev.payload ->> 'paid')::bigint), 0) from ev where ev.kind = 'INSURANCE_PAID' and ev.payload ->> 'cause' = 'EARLY_SIGHTING'),
  'open_stuck', (select count(*) from es where es.state = 'open' and es.sighted_at < now() - interval '10 minutes'),
  'due_late', (select count(*) from es where es.state = 'due' and es.due_at < now() - interval '10 minutes'),
  'tries_max', (select coalesce(max(es.tries), 0) from es),
  'joined', (select count(*) from public.battle_sides s where s.battle_id in (select es.battle_id from es where es.battle_id is not null) and s.how = 'JOINED'),
  'ships_lost', (select count(*) from es join public.fleets f on f.id = es.fleet_id
                  where es.state in ('open', 'done')
                    and (f.status = 'UNABLE_TO_SAIL' or exists (select 1 from public.ships s where s.fleet_id = f.id and s.durability <= 0))),
  'strength', (select coalesce(jsonb_object_agg(s.k, s.n), '{}'::jsonb)
                 from (select es.strength::text as k, count(*) as n from es where es.strength is not null group by 1) s));
rollback;
