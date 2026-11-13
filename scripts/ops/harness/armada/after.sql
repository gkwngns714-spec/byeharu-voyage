-- 0367 PROD CHECK (after), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/armada/after.sql
-- Run it right AFTER the deploy, and again at the end of the 30-minute window. Every function it calls is STABLE (volatility.sql). It answers:
--   knobs          armada_enabled true, armada_fleet_max 6, armada_raid_scale 1.
--   tables         the four tables are there, each with row level security. Wanted: 4.
--   doors          the read and the four doors a client may call, each granted to authenticated and to nobody else. Wanted: 5 and 0.
--   registry       the same five in public.client_rpc_entry_points. Wanted: 5.
--   read           world.armadas() for nobody: {on: true, max: 6, raid_scale: 1, armadas: []}.
--   speed_moved    fleets in no armada whose speed is not the old formula's (voyage.fleet_speed_alone_at IS the old body), read in this one snapshot. Wanted: 0.
--   armadas, fleets_in, voyages, fights   what players have made since: armadas formed, fleets in them, voyages sailed in one, raid days fought as one.
--   news           the UPDATE row. Wanted: 1.
begin transaction read only;
select jsonb_build_object(
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key in ('armada_enabled', 'armada_fleet_max', 'armada_raid_scale')),
  'tables', (select count(*) from pg_class c where c.oid in ('public.armadas'::regclass, 'public.armada_fleets'::regclass, 'public.armada_voyages'::regclass, 'public.armada_fights'::regclass) and c.relrowsecurity),
  'doors', (select count(*) from unnest(array['world.armadas()', 'cmd.armada_form(jsonb,text)', 'cmd.armada_disband(uuid)', 'cmd.armada_sail(uuid,text,jsonb,boolean,boolean)',
                                               'cmd.preview_armada_sail(uuid,text,jsonb,boolean)']) f
             where has_function_privilege('authenticated', f::regprocedure, 'execute') and not has_function_privilege('anon', f::regprocedure, 'execute')),
  'server_only_open', (select count(*) from unnest(array['public.armada_form_for(uuid,jsonb,text)', 'public.armada_disband_for(uuid,uuid)', 'public.armada_sail_for(uuid,uuid,text,jsonb,boolean)',
                                               'voyage.armada_fight(uuid,integer,uuid,uuid,numeric)', 'voyage.armada_side(uuid)', 'voyage.fleet_speed_alone_at(uuid,numeric)',
                                               'public.armada_of(uuid)', 'public.armada_on()']) f
             where has_function_privilege('authenticated', f::regprocedure, 'execute') or has_function_privilege('anon', f::regprocedure, 'execute')),
  'registry', (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('armadas', 'armada_form', 'armada_disband', 'armada_sail', 'preview_armada_sail') and e.fn is not null),
  'read', world.armadas(),
  'speed_moved', (select count(*) from public.fleets f
                   where exists (select 1 from public.ships s where s.fleet_id = f.id)
                     and not exists (select 1 from public.armada_fleets af where af.fleet_id = f.id)
                     and voyage.fleet_speed_at(f.id, null) is distinct from voyage.fleet_speed_alone_at(f.id, null)),
  'armadas', (select count(*) from public.armadas),
  'fleets_in', (select count(*) from public.armada_fleets),
  'voyages', (select count(*) from public.armada_voyages),
  'fights', (select count(*) from public.armada_fights),
  'news', (select count(*) from public.world_news n where n.key = 'update:0367')) as after_0367;
commit;
