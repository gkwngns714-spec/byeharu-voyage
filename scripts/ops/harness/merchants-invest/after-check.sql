-- 0313 AFTER-CHECK. One pure SELECT, read-only. Run after the first two :07 hours past the deploy, then at 24 h:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/merchants-invest/after-check.sql
-- PASS: failed 0, deferred 0; companies_ms not above its week (8,000-17,000); hold_max_ms under ~130; buyers about 15-25 an hour;
--       share_gold no more than ~4.2 M an hour; level_above_max 0; merchants_paused about 35, all laid_up (2026-11-05, before the deploy).
-- FAIL: forward rollback, owner only: update public.world_config set value = '0' where key in ('npc_invest_day_cap', 'works_open_shares');
with r as (
  select at, ms, receipt -> 'ms' ->> 'companies' as companies_ms,
         receipt #>> '{merchant_upkeep,tend,invested}' as bought,
         receipt #>> '{merchant_upkeep,tend,donated}' as gave,
         receipt #>> '{merchant_upkeep,tend,failed}' as failed,
         receipt #>> '{merchant_upkeep,tend,deferred}' as deferred,
         receipt #>> '{quay,companies,hold_max_ms}' as hold_max_ms
    from public.reconcile_runs order by at desc limit 4
), s as (
  select date_trunc('hour', l.created_at) as h, sum(-l.ducats_delta) as gold, count(*) as buys, count(distinct l.player_id) as houses
    from public.ledger l where l.kind = 'SHARE' and l.created_at > now() - interval '6 hours' group by 1
)
select (select jsonb_agg(to_jsonb(r) order by r.at desc) from r) as hours,
       (select jsonb_agg(to_jsonb(s) order by s.h desc) from s) as share_gold,
       (select count(*) from public.city_works w where w.level > public.wc_int('works_level_max')) as level_above_max,
       (select count(*) from public.city_works w where w.subscribed > 0 and w.level >= public.wc_int('works_level_max')) as lots_open,
       (select sum(s2.paid) from public.city_shares s2) as shares_paid,
       (select sum(t.ducats) from public.port_treasury t) as purses,
       (select count(*) from public.port_treasury t where t.ducats < 50000) as purses_under_floor,
       (select count(*) from public.standing_routes sr join public.npc_fleets nf on nf.route_id = sr.id where sr.paused_reason is not null) as merchants_paused,
       (select jsonb_object_agg(x.paused_reason, x.n) from (select sr.paused_reason, count(*) as n from public.standing_routes sr join public.npc_fleets nf on nf.route_id = sr.id
                                                              where sr.paused_reason is not null group by 1) x) as paused_why;
