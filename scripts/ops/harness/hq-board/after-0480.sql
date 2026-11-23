-- THE HQ BOARD FROM THE SERVER (0480), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/hq-board/after-0480.sql
-- Expect, AS DEPLOYED (dark): head 20260818000480; knobs hq_board_enabled false, hq_board_fleets 4, hq_board_budget_ms 2000,
-- hq_board_runs 3, hq_board_request_floor_s 900, hq_board_idle_coin 20000, hq_board_build_below 2, hq_board_danger_warn 4;
-- `registered` true; `client_reach` false; `stable` true (all four functions STABLE); `hunked` true; `door` {"on": false} while dark.
-- THE COST OF ONE BOARD for a real company: the company with the most idle fleets (ties: the newest), her identity set for this
-- transaction alone (set_config, local: nothing is written), public.hq_board_for timed (the board's body: it answers dark too, so the
-- cost is read before the switch is lit). `board_ms` the wall time, `served_ms` the board's own `ms`, `moves` by kind, `unpriced` the idle
-- fleets past hq_board_fleets or the budget. Expect board_ms under about hq_board_budget_ms + 2,500 (the last best_sales' own budget).
-- LIT (read 30 minutes after lighting): `door` is {"on": true, ...} for her; the same cost figures; the gate green.
-- ROLLBACK if `client_reach` true, `stable` false, board_ms over 6,000, or the gate goes red: hq_board_enabled false (owner); the
-- client then draws v1's board.
-- Reads: world_config by key, the catalog, players (companies), their fleets and queued orders, ONE public.hq_board_for (STABLE: it
-- calls world.best_sales for at most hq_board_fleets fleets and only STABLE readers) and world.hq_board (STABLE). No function that
-- writes is called. ROLLBACK: nothing to roll back (read only; the transaction ends with rollback).
begin transaction read only;
with hu as materialized (
  select p.id, p.auth_uid, p.created_at from public.players p where not p.is_npc
), idle as materialized (
  select hu.id as player_id, hu.auth_uid, hu.created_at as founded, count(*) as n
    from hu join public.fleets f on f.player_id = hu.id
   where f.status = 'DOCKED' and f.port_id is not null
     and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active'))
   group by hu.id, hu.auth_uid, hu.created_at
), who as materialized (
  select i.*, set_config('request.jwt.claim.sub', i.auth_uid::text, true) as a,
         set_config('request.jwt.claims', json_build_object('sub', i.auth_uid)::text, true) as b
    from idle i order by i.n desc, i.founded desc limit 1
), t0 as materialized (
  select who.*, clock_timestamp() as t0 from who
), hb as materialized (
  select t0.*, public.hq_board_for(t0.player_id) as r, clock_timestamp() as t1 from t0
), door as materialized (
  select world.hq_board() as r from hb
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'hq\_board\_%'),
  'registered', exists (select 1 from public.client_rpc_entry_points() e
                         where e.schema_name = 'world' and e.function_name = 'hq_board' and e.fn is not null),
  'client_reach', has_function_privilege('anon', 'world.hq_board()', 'execute')
                  or has_function_privilege('authenticated', 'public.hq_board_for(uuid)', 'execute')
                  or has_function_privilege('authenticated', 'public.hq_course_risk(text[])', 'execute')
                  or has_function_privilege('authenticated', 'public.hq_sea_level(uuid)', 'execute'),
  'stable', (select bool_and(p.provolatile = 's') from pg_proc p
              where p.oid in ('world.hq_board()'::regprocedure, 'public.hq_board_for(uuid)'::regprocedure,
                              'public.hq_course_risk(text[])'::regprocedure, 'public.hq_sea_level(uuid)'::regprocedure)),
  'hunked', position('''hq_board''' in pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) > 0,
  'door', (select case when door.r ->> 'on' = 'false' then door.r else door.r - 'moves' end from door),
  'company_idle', (select hb.n from hb),
  'board_ms', (select round(extract(epoch from hb.t1 - hb.t0) * 1000) from hb),
  'served_ms', (select hb.r -> 'ms' from hb),
  'moves', (select coalesce(jsonb_object_agg(z.k, z.n), '{}'::jsonb)
              from (select m ->> 'kind' as k, count(*) as n from hb cross join jsonb_array_elements(hb.r -> 'moves') m group by 1) z),
  'top', (select (hb.r #> '{moves,0}') - 'act' from hb),
  'unpriced', (select jsonb_array_length(hb.r -> 'unpriced') from hb),
  'rate', (select hb.r -> 'rate' from hb),
  'threats', (select hb.r -> 'threats' from hb));
rollback;
