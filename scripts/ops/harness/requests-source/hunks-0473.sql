-- REQUESTS SAY WHERE TO BUY (0473), THE HUNKS' PRE-IMAGE ON PRODUCTION. A PROD CHECK for the lead: read-only, ONE statement, catalog only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/requests-source/hunks-0473.sql
-- Before the deploy: each line below is a distinctive line of one of 0473's twelve hunks' OLD text; want every count 1 (and `done` 0:
-- 0473 not applied). The self-assert refuses the whole file anyway if a hunk is not once; this says so before the push.
begin transaction read only;
with b as (
  select replace(pg_get_functiondef('public.hold_request_post(uuid,timestamp with time zone)'::regprocedure), E'\r', '') as post,
         replace(pg_get_functiondef('world.contracts(uuid)'::regprocedure), E'\r', '') as rd,
         replace(pg_get_functiondef('world.houses_week()'::regprocedure), E'\r', '') as wk
), n(name, body, needle) as (
  select 'post_1', post, '  v_base  numeric;' from b union all
  select 'post_2', post, '    select distinct s.good_id from public.port_specialties s join public.ports p2 on p2.id = s.port_id and p2.kind = ''HARBOUR'' where s.port_id <> p_port' from b union all
  select 'post_3', post, '  if v_good is null then' from b union all
  select 'post_4', post, '  v_u    := voyage.rng(p_port, v_day, ''hold:'' || v_seq::text || '':hours'');' from b union all
  select 'post_5', post, 'premium_ducats, expires_day, status, escrow, size)' from b union all
  select 'post_6', post, '''open'', case when v_lit then v_bud else 0 end, ''hold'')' from b union all
  select 'read_1', rd, '''total'', case when c.size = ''hold'' then round(floor(c.premium_ducats / c.premium_per_unit) * (q.bid + c.premium_per_unit))::bigint end,' from b union all
  select 'read_2', rd, '       cross join lateral world.price(c.port_id, c.good_id) q   -- 0311' from b union all
  select 'week_1', wk, '  v_ahead jsonb;' from b union all
  select 'week_2', wk, '  select w.net into v_net from public.houses_week w where w.week = v_week and w.player_id = v_me;' from b union all
  select 'week_3', wk, '                        from public.houses_week w where w.week = v_week) q' from b union all
  select 'week_4', wk, '''on_board'', v_pos <= v_size, ''ahead'', v_ahead);' from b
)
select jsonb_build_object(
  'hunks', (select jsonb_object_agg(n.name, (length(n.body) - length(replace(n.body, n.needle, ''))) / length(n.needle)) from n),   -- want every one 1
  'done', (select count(*) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'trade_contracts' and c.column_name = 'source_port_id'),   -- want 0
  'head', (select max(version) from supabase_migrations.schema_migrations));   -- want 20260818000471 or 20260818000472
rollback;
