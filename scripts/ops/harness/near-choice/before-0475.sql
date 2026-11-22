-- A REAL CHOICE AND A FULL HOLD (0475), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/near-choice/before-0475.sql
-- Expect: head 20260818000474 (0474, #799, deployed first); knobs {} (none of the nine); each of the five hunks' OLD text once (old 1) and
-- its NEW mark absent (new 0) in the live body; first_hour_enabled true (lit on prod: the near rule this slice ends differently).
-- The BASELINE for the lit window (the same figures after-0475.sql reads, over the last 30 minutes, dark):
--   `sales`       human SOLD events; `harbours` the distinct harbours they sold at; `per_company` the average distinct sale harbours a company
--                 used (finding 8: one harbour, ping-pong); `two_goods` the arrivals (a fleet, a harbour, a minute) that sold two goods or
--                 more (finding 13: one good a load); `arrivals` all of them.
--   `horizon_now` the human companies with a near horizon by 0472's rule (Trading under first_hour_trading_below); `horizon_lit` those
--                 that would have one lit (founded under 2 hours ago and under 3 ships).
-- Reads: the catalog (pg_get_functiondef of two functions: stable), world_config by key, events SOLD of 30 minutes (events_trades_window: a
-- range), about 20 human companies (their Trading mark, one count of ships each). No game function is called.
begin transaction read only;
with h(fn, old, new) as (values
  ('world.best_sales(uuid,uuid)', '  v_near_s  numeric := public.first_hour_near_seconds(public.current_player_id());' || chr(10), '0475 (A REAL CHOICE'),
  ('world.best_sales(uuid,uuid)', '           v_short or (exists (select 1 from pool) and not exists (select 1 from c))' || chr(10) || '      into v_best, v_far, v_short;' || chr(10), '0475 (lit): a good bought here'),
  ('world.best_sales(uuid,uuid)', '    v_out := v_out || jsonb_build_array(jsonb_build_object(' || chr(10), '0475 (lit): the good''s paying sales'),
  ('world.best_sales(uuid,uuid)', '  return jsonb_build_object(''port'', v_port.code, ''goods'', v_out, ''cut'', v_cut,' || chr(10), '0475 (near_choice_enabled): A REAL CHOICE'),
  ('public.first_hour_near_seconds(uuid)',
   '                     and coalesce((select m.level from public.house_level_marks m where m.player_id = p_player and m.track = ''trading''), 1)' || chr(10)
   || '                         < public.wc_num(''first_hour_trading_below'')' || chr(10), '0475 (near_choice_enabled)')
), d as (
  select h.fn, h.old, h.new, case when to_regprocedure(h.fn) is null then null else replace(pg_get_functiondef(to_regprocedure(h.fn)), E'\r', '') end as def from h
), since as (select now() - interval '30 minutes' as t),
s as (
  select e.player_id, e.payload ->> 'port' as port, e.payload ->> 'fleet' as fleet, e.payload ->> 'good' as good, date_trunc('minute', e.created_at) as m
    from public.events e join public.players p on p.id = e.player_id
   where e.kind = 'SOLD' and e.created_at > (select t from since) and not p.is_npc
), arr as (select s.player_id, s.fleet, s.port, s.m, count(distinct s.good) as goods from s group by 1, 2, 3, 4),
hum as (
  select p.id, p.created_at,
         coalesce((select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'trading'), 1) as trading,
         (select count(*) from public.ships x where x.player_id = p.id) as ships
    from public.players p where not p.is_npc
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'near\_choice\_%'),
  'kept', (select jsonb_object_agg(c.key, c.value) from public.world_config c
            where c.key in ('first_hour_enabled', 'first_hour_trading_below', 'first_hour_trip_hours')),
  'hunks', (select jsonb_agg(jsonb_build_object('fn', d.fn,
                     'old', (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old),
                     'new', (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new))) from d),
  'sales', (select count(*) from s),
  'harbours', (select count(distinct s.port) from s),
  'per_company', (select round(avg(n), 2) from (select count(distinct s.port) as n from s group by s.player_id) q),
  'arrivals', (select count(*) from arr),
  'two_goods', (select count(*) from arr where arr.goods >= 2),
  'horizon_now', (select count(*) from hum where hum.trading < (select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'first_hour_trading_below')),
  'horizon_lit', (select count(*) from hum where hum.created_at > now() - interval '2 hours' and hum.ships < 3));
rollback;
