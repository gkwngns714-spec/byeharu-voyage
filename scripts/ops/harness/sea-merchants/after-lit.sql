-- 0397 / 0399 PROD CHECK (the merchants' window), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/after-lit.sql
-- Run it ONCE BEFORE sea_conditions_bite_npc is lit (the baseline), then at +5, +15 and +30 minutes. Run volatility.sql first. What to read:
--   loops_closed            merchant loops with a leg her hull cannot hold. Lit it FALLS as each merchant reaches her lap start (the planner moves her); it need
--                           not reach 0 inside 30 minutes (a Pacific lap is hours). It must never rise.
--   closed_and_buying       such loops that still carry a BUY line. Lit: falls to 0 as each is planned (a closed loop is written with no BUY).
--   laid_up                 merchants waiting in port (0181). WANTED: no more than the baseline + the "no sailable loop that pays" figure of the simulation
--                           (docs/dev-log/2026-11-13-merchants-under-the-sea-rule.md); a jump past it is the rollback signal.
--   no_buy                  merchant routes with no BUY line at all (ballast). Read against the baseline the same way.
--   replanned_30m           merchant routes written in the last 30 minutes (the planner at work).
--   refused_at_the_door     merchant orders refused E_SEA_CLOSED in the last hour. WANTED 0, always: the door never judges a merchant.
--   courses_not_remembered  merchant courses the memo does not hold (sampled live: correct, slower). Grows only if new courses are founded.
--   beats                   the arrivals beat over the last 30 minutes: WANTED errors 0, avg_ms <= 3000, p95_ms < 5000, and no worse than the baseline.
-- ROLLBACK: update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc' (owner): every plan after it is the old planner's.
begin transaction read only;
with loops as (
  select nf.fleet_id, nf.route_id, f.status, sr.paused_reason, sr.updated_at,
         public.npc_loop_sea_shut(nf.fleet_id, (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord)
                                                  from public.standing_route_stops st where st.route_id = nf.route_id)) as shut,
         exists (select 1 from public.standing_route_lines l where l.route_id = nf.route_id and l.kind = 'BUY') as buys
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.standing_routes sr on sr.id = nf.route_id
   where nf.route_id is not null
)
select now() as read_at,
       (select value from public.world_config where key = 'sea_conditions_bite_npc') as switch_merchants,
       (select value from public.world_config where key = 'sea_conditions_bite') as switch_players,
       (select count(*) from loops) as merchant_loops,
       (select count(*) from loops where shut) as loops_closed,
       (select count(*) from loops where shut and status <> 'DOCKED') as closed_at_sea,
       (select count(*) from loops where shut and buys) as closed_and_buying,
       (select count(*) from loops where paused_reason = 'laid_up') as laid_up,
       (select count(*) from loops where paused_reason is not null and paused_reason <> 'laid_up') as paused_otherwise,
       (select count(*) from loops where not buys) as no_buy,
       (select count(*) from loops where updated_at >= now() - interval '30 minutes') as replanned_30m,
       (select count(*) from public.orders o join public.players p on p.id = o.player_id and p.is_npc
         where o.error_code = 'E_SEA_CLOSED' and o.issued_at >= now() - interval '1 hour') as refused_at_the_door,
       (select count(*) from public.standing_route_stops st join loops l on l.route_id = st.route_id
         where not exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(st.course::text))) as courses_not_remembered,
       (select jsonb_build_object('n', count(*), 'avg_ms', round(avg(b.ms)::numeric, 1), 'p95_ms', round((percentile_cont(0.95) within group (order by b.ms))::numeric, 1),
                                  'errors', count(*) filter (where b.error is not null))
          from public.arrivals_beats b where b.at >= now() - interval '30 minutes') as beats;
commit;
