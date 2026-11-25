-- 0536 BEST SALES, FASTER, BEFORE. A PROD CHECK: read-only, ONE statement, the gate first; the catalog and the beats alone.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/best-sales-fast/before.sql
-- Expect: head 20260818000535; bodies_off [] (each body 0536 cuts is the one it was matched on; a body listed is judged by its own hunk counts at
--   the push); new_there []; long_tx 0. Digests: the local chain, to 0535.
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'bodies_off', (select coalesce(json_agg(json_build_object('fn', w.fn, 'have', h.have)), '[]'::json)
                   from (values ('public.stores_cost(uuid,numeric,numeric)', 'e45f2f2b3aef0b5ae2da9ea3d019b7df'),
                                ('public.stores_topup(numeric,numeric,numeric,numeric,numeric,numeric)', '6cc4ab6a036c2fc40558869d3a71164d'),
                                ('voyage.reach_passage(uuid,uuid,uuid,numeric)', 'ce7f367207326f4cb88fd4296a4c2572'),
                                ('voyage.ship_speed_of(jsonb,numeric)', '1a3b3fa86bcf2b074d2b93ec70a888d2'),
                                ('voyage.stores_need_days(numeric,numeric)', '60001bcd4bbfbf33e33ed17b2b1c32f2'),
                                ('world.best_sales(uuid,uuid)', 'c91c2f8b9221166ee64f3589e77533c8'),
                                ('world.board_sell_memo(uuid,uuid,jsonb,jsonb)', 'a0e37e672f7c0ec7649961ff5d6b64b2'),
                                ('world.board_trips(uuid,jsonb,jsonb)', '79293b2b01d2ecc73d966a535327cd14'),
                                ('world.trip_leg(jsonb,jsonb,numeric,boolean,numeric)', 'de610c0cd84278994159535fbdff0c4d')) w(fn, want)
                  cross join lateral (select md5(replace(pg_get_functiondef(to_regprocedure(w.fn)), E'', '')) as have) h
                  where h.have is distinct from w.want),
  'new_there', (select coalesce(json_agg(u.s), '[]'::json) from unnest(array['public.stores_cost_of(numeric,numeric,numeric[])', 'public.stores_cost_terms(uuid)', 'public.stores_topup_of(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)', 'voyage.ship_speed_fill(numeric,numeric,numeric)', 'voyage.stores_need_days_of(numeric,numeric,numeric)', 'world.legs_rank(jsonb)', 'world.trip_arrays(jsonb,jsonb)', 'world.trip_hulls_at(jsonb,numeric[],numeric[])', 'world.trip_knobs()', 'world.trip_leg_of(numeric[],numeric[],numeric[],numeric[],numeric[],numeric[],numeric[],numeric,numeric,numeric,numeric,numeric[],numeric[],numeric,boolean,numeric)']) u(s) where to_regprocedure(u.s) is not null),
  'long_tx', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.state <> 'idle' and a.xact_start < now() - interval '4 seconds' and a.backend_type = 'client backend')) as before_0536;
rollback;
