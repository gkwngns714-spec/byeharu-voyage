-- 0420 PROD CHECK, BEFORE the deploy AND AGAIN AFTER IT (before.sql and after.sql are one text), read-only, ONE statement. Calls only stable functions.
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/drift-15/before.sql
-- It reads the catalog, world_config, the 268 harbours and ONE port_goods row a harbour (by its primary key): no scan of port_goods.
-- BEFORE, wanted: head 20260818000418 or 419; spread 50; slot_seconds 300; time_compression 192; hunks {1: 1, 2: 1} (each old text once in the
--   live public.clock_set); due_now 5 or 6 harbours (268 / 50); behind: a harbour's first row up to 10 slots behind (50 minutes at 300 s).
-- AFTER, wanted: head 20260818000420; spread 15 with a description starting '0420:'; hunks {1: 0, 2: 0}; new_texts {1: 1, 2: 1}; due_now 17 or 18.
--   Read again 16 minutes or more after the deploy: behind is 0 to 3 for every harbour (no harbour more than 3 slots, 15 minutes, behind;
--   one stepped by a player's quay read since may be 0). rows_due_now about 10,400 (156,621 / 15).
begin transaction read only;
with hk(ord, old, new) as (values
  (1, E'--   same way); the drift job''s spread (x f); the economy''s rates per real time (/ f) and its half-lives (x f); and the clock''s anchor.\n',
      E'-- 0420: NOT the drift job''s spread (drift_spread_runs): it is a pace in real minutes'),
  (2, E'  update public.world_config wc\n     set value = to_jsonb(greatest(1, round((wc.value #>> ''{}'')::numeric * v_f))::int), updated_at = now()\n   where wc.key = ''drift_spread_runs'';\n',
      E'  -- 0420: drift_spread_runs is not moved here')
), body as (select replace(pg_get_functiondef('public.clock_set(integer,timestamp with time zone)'::regprocedure), E'\r', '') as def),
firsts as (
  select po.id, (select pg.drift_slot from public.port_goods pg where pg.port_id = po.id order by pg.good_id limit 1) as slot
    from public.ports po)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'spread', (select wc.value from public.world_config wc where wc.key = 'drift_spread_runs'),
  'spread_note', (select left(wc.description, 60) from public.world_config wc where wc.key = 'drift_spread_runs'),
  'slot_seconds', (select wc.value from public.world_config wc where wc.key = 'drift_slot_seconds'),
  'time_compression', (select wc.value from public.world_config wc where wc.key = 'time_compression'),
  'hunks', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.old, ''))) / length(hk.old)) from hk, body b),
  'new_texts', (select jsonb_object_agg(hk.ord, (length(b.def) - length(replace(b.def, hk.new, ''))) / length(hk.new)) from hk, body b),
  'ports', (select count(*) from public.ports),
  'port_goods_est', (select c.reltuples::bigint from pg_class c where c.oid = 'public.port_goods'::regclass),
  'due_now', (select count(*) from public.drift_ports_due(now())),
  'rows_due_now', (select count(*) from public.drift_ports_due(now()) d join public.port_goods pg on pg.port_id = d.id),
  'slot_now', public.drift_slot_of(now()),
  'behind', (select jsonb_object_agg(b.k, b.n) from (select public.drift_slot_of(now()) - f.slot as k, count(*) as n from firsts f group by 1) b),
  'drift_job', (select jsonb_build_object('schedule', j.schedule, 'active', j.active) from cron.job j where j.jobname = 'byeharu-voyage:drift')
) as r;
commit;
