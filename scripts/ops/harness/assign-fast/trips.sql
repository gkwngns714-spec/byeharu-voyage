-- ONE TRIP A HARBOUR: HOW MANY LEGS, AND WHAT OUT AND BACK COST. A PROD CHECK: read-only, ONE statement, about 1 to 2 s on prod. Not in a minute's first ten seconds.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/assign-fast/trips.sql
-- Twelve fixed harbours from where the newest docked company fleet lies (her identity for this transaction alone): `legs` of the way out (over 1: the pathfinder was
--   asked), out_ms (the miles alone), back_ms (priced). The same harbours each run, so two runs compare: assign-fast/split.sql's are her cards', which move.
-- Expect (locally): a direct trip 3 to 8 ms, one with a harbour between 40 to 100: almost all of it one voyage.reach_passage. Nothing is written.
begin transaction read only;
with who as materialized (
  select f.player_id as pl, f.id as fl, f.port_id as po, pt.code,
         set_config('request.jwt.claim.sub', p.auth_uid::text, true) as a, set_config('request.jwt.claims', json_build_object('sub', p.auth_uid)::text, true) as b
    from public.fleets f join public.players p on p.id = f.player_id join public.ports pt on pt.id = f.port_id and pt.kind = 'HARBOUR'
   where f.status = 'DOCKED' and not p.is_npc and exists (select 1 from public.ships s where s.fleet_id = f.id)
   order by p.created_at desc, f.created_at, f.id limit 1
), d as materialized (select p.id, p.code from public.ports p, who where p.kind = 'HARBOUR' and p.id <> who.po and p.code in ('SET', 'CAD', 'SVQ', 'OPO', 'LPA', 'AMS', 'GEN', 'VEN', 'IST', 'ALX', 'CAP', 'LUA')
), x as materialized (
  select d.code, clock_timestamp() as t0, public.job_trip(who.fl, who.po, array[d.code], false) as o, clock_timestamp() as t1,
         public.job_trip(who.fl, d.id, array[who.code], true) as b, clock_timestamp() as t2
    from who, d)
select json_build_object('from', (select code from who), 'trips', (select json_agg(json_build_object('to', x.code, 'legs', coalesce(x.o->'legs', x.o->'shut'->'code'),
  'out_ms', round((extract(epoch from x.t1 - x.t0) * 1000)::numeric, 1), 'back_legs', coalesce(x.b->'legs', x.b->'shut'->'code'),
  'back_ms', round((extract(epoch from x.t2 - x.t1) * 1000)::numeric, 1)) order by x.code) from x)) as trips;
rollback;
