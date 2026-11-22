-- A REAL CHOICE AND A FULL HOLD (0475), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, small. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/near-choice/after-0475.sql
-- Set `since` below to the deploy time (as deployed) or the lighting time of near_choice_enabled (the 30-minute after-check).
-- Expect, AS DEPLOYED (dark): head 20260818000475; knobs near_choice_enabled false, per_harbour 3, similar_pct 50, turn_seconds 300,
-- topup_below_pct 50, topup_coin_pct 25, topup_goods 4, hours_played 2, ships_below 3; every hunk's mark present (true); `knobs_fn` true;
-- `horizon` = before's `horizon_now` (dark: 0472's rule).
-- LIT (only after the owner lights it; read 30 minutes on), against before-0475.sql's baseline over 30 minutes dark:
--   `per_company` (distinct sale harbours a company used) UP from the baseline; `two_goods` (arrivals that sold two goods or more) above 0
--   and its share of `arrivals` up; `horizon` = before's `horizon_lit` (companies founded under 2 hours ago with under 3 ships), not the
--   Trading count; `beat_ms` the beat (the card read is a little more work: rollback if over 2 s).
-- ROLLBACK if `two_goods` stays 0 while `arrivals` > 20, if a refused BUY shows in `failed_buys` beyond a handful (the second good's line
-- halting a queue), or the beat is red: near_choice_enabled false (owner).
-- Reads: the catalog, world_config by key, events SOLD of 30 minutes (events_trades_window), about 20 human companies (one stable call
-- each, public.first_hour_near_seconds: a players row, a count of ships, a mark), human BUY orders failed since, the beat's ring of 5 minutes (public.arrivals_beats).
begin transaction read only;
with since as (select now() - interval '30 minutes' as t),
s as (
  select e.player_id, e.payload ->> 'port' as port, e.payload ->> 'fleet' as fleet, e.payload ->> 'good' as good, date_trunc('minute', e.created_at) as m
    from public.events e join public.players p on p.id = e.player_id
   where e.kind = 'SOLD' and e.created_at > (select t from since) and not p.is_npc
), arr as (select s.player_id, s.fleet, s.port, s.m, count(distinct s.good) as goods from s group by 1, 2, 3, 4)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'near\_choice\_%'),
  'knobs_fn', to_regprocedure('public.near_choice_knobs()') is not null,
  'marks', (select jsonb_object_agg(f.fn || ' ' || f.mark, position(f.mark in pg_get_functiondef(to_regprocedure(f.fn))) > 0) from (values
              ('world.best_sales(uuid,uuid)', '0475 (A REAL CHOICE'), ('world.best_sales(uuid,uuid)', '0475 (lit): a good bought here'),
              ('world.best_sales(uuid,uuid)', '0475 (near_choice_enabled): A REAL CHOICE'),
              ('public.first_hour_near_seconds(uuid)', '0475 (near_choice_enabled)')) f(fn, mark)),
  'sales', (select count(*) from s),
  'harbours', (select count(distinct s.port) from s),
  'per_company', (select round(avg(n), 2) from (select count(distinct s.port) as n from s group by s.player_id) q),
  'arrivals', (select count(*) from arr),
  'two_goods', (select count(*) from arr where arr.goods >= 2),
  'horizon', (select count(*) from public.players p where not p.is_npc and public.first_hour_near_seconds(p.id) is not null),
  'failed_buys', (select count(*) from public.orders o join public.players p on p.id = o.player_id
                   where not p.is_npc and o.status = 'failed' and o.verb = 'BUY' and o.issued_at > (select t from since)),
  'beat_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'));
rollback;
