-- 0437 PROD CHECK, BEFORE the deploy: every hunk 0437 cuts occurs EXACTLY ONCE in the live body it cuts, and public.cargo_ship_state is not there yet.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/cargo-home/hunks.sql
-- Run scripts/ops/harness/db-health/gate.sql first. ONE statement, read-only: the catalog only (pg_get_functiondef of five functions), no game table.
-- WANTED: ok true, every `n` 1, state_fn false. (0432's hunk of public.stats_fleets_count is disjoint from 0437's: both stand.)
begin transaction read only;
with h (fn, ord, old) as (values
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1, $h$  v_home  jsonb;
begin
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2, $h$  v_left := coalesce(v_left, 0);
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 3, $h$      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: idle, she may be due a new home. Off at her capital: IDLE
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 4, $h$    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
$h$),
  ('world.cargo_ship_card(uuid)', 1, $h$  w record;
begin
$h$),
  ('world.cargo_ship_card(uuid)', 2, $h$    'funds', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
$h$),
  ('world.cargo_ship_card(uuid)', 3, $h$                      where l.circuit_id = c.circuit_id and l.ord > c.leg order by l.ord limit 5) x),
    'stops_left', (select count(*) from public.cargo_circuit_legs l where l.circuit_id = c.circuit_id and l.ord > c.leg),
$h$),
  ('world.stats_fleet(uuid)', 1, $h$      'aboard', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
$h$),
  ('public.stats_fleet_list_rows(text,timestamp with time zone)', 1, $h$from public.cargo_ships c where p_kind = 'CARGO'),
$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 1, $h$           from public.cargo_ships c
           join public.fleets f on f.id = c.fleet_id
$h$)
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'state_fn', to_regprocedure('public.cargo_ship_state(uuid)') is not null,
  'hunks', (select jsonb_agg(jsonb_build_object('fn', x.fn, 'ord', x.ord, 'n', x.n) order by x.fn, x.ord) from (
              select h.fn, h.ord, (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as n
                from h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'', '') as def) d) x),
  'ok', (select bool_and((length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) = 1)
           from h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'', '') as def) d)
        and to_regprocedure('public.cargo_ship_state(uuid)') is null
) as r;
commit;
