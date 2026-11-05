-- 0313 PROD CHECK, BEFORE THE PUSH. One pure SELECT, read-only; it calls only stable functions (provolatile 's').
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/merchants-invest/before.sql
-- Expect: head 20260818000312; every `hunk_*` true; maxed about 924; knobs_already_there 0; cohort_laps_ms under 100 (prod 2026-11-05: see the dev-log).
with c as materialized (select clock_timestamp() as t0),
roster as materialized (select count(*) as n from public.npc_invest_roster()),
t1 as materialized (select clock_timestamp() as t),
cohort as materialized (
  select h.player_id, (select coalesce(sum(r.dearest), 0) from (
           select max(l.spend) as dearest
             from public.npc_fleets nf
             cross join lateral (select x.bought + x.supplies + x.repairs + x.wages + x.taxes + x.insurance as spend
                                   from public.standing_route_laps x
                                  where x.route_id = nf.route_id and x.closed_at > now() - interval '3 days'
                                  order by x.lap_no desc limit 20) l
            where nf.player_id = h.player_id group by nf.route_id) r) as lap
    from public.npc_houses h where h.roster_ord % 24 = 13
),
lapsum as materialized (select count(*) as n, sum(lap) as lap from cohort),
t2 as materialized (select clock_timestamp() as t)
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (select count(*) from public.city_works w where w.level >= public.wc_int('works_level_max')) as maxed,
       (select count(*) from public.city_works) as works,
       roster.n as rostered,
       lapsum.n as cohort,
       round(extract(epoch from t1.t - c.t0) * 1000) as roster_read_ms,
       round(extract(epoch from t2.t - t1.t) * 1000) as cohort_laps_ms,
       position($h$limit public.wc_int('npc_invest_max_per_hour')$h$ in pg_get_functiondef('public.npc_invest_roster(uuid)'::regprocedure)) > 0 as hunk_roster,
       position($h$if w.subscribed + p_shares >= v_per then$h$ in pg_get_functiondef('public.invest_for(uuid,uuid,text,integer)'::regprocedure)) > 0 as hunk_invest_for,
       position($h$floor(v_left / v_stake.price)$h$ in pg_get_functiondef('public.npc_invest_one(timestamp with time zone,uuid)'::regprocedure)) > 0 as hunk_npc_invest_one,
       position($h$then 0$h$ in pg_get_functiondef('public.city_offered(uuid,text)'::regprocedure)) > 0 as hunk_city_offered,
       position($h$'share_price', case when coalesce(w.level, 0) < v_max$h$ in pg_get_functiondef('world.town_hall(uuid)'::regprocedure)) > 0 as hunk_town_hall,
       position($h$'share_price', case when coalesce(w.level, 0) < v_max$h$ in pg_get_functiondef('world.holdings()'::regprocedure)) > 0 as hunk_holdings,
       (select count(*) from public.world_config k where k.key in ('works_open_shares', 'npc_invest_day_cap', 'npc_invest_keep_laps')) as knobs_already_there
  from c, roster, t1, lapsum, t2;
