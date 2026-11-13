-- 0404 PROD CHECK, BEFORE and AFTER the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/far-traders/calls-0404.sql
-- 16 rows: the harbours that lost every merchant call. arrivals_1h = merchant voyages that arrived there in the last hour; loops = merchant loops that stop
-- there; laid_up = of those loops, the ones waiting in port; houses = merchant houses homed there. BEFORE: write the rows down.
-- AFTER (an hour or more after the deploy): loops 1 or more on every row but POR (Port Royal: the pirates' own merchants serve it, 0341). arrivals_1h rises
-- only as laps close: a far trader's first loop is 400 to 2,600 nm, so read it again after six hours.
begin transaction read only;
select h.code as harbour, h.name,
       (select count(*) from public.voyages v join public.npc_fleets nf on nf.fleet_id = v.fleet_id
         where v.dest_port_id = h.id and v.status = 'ARRIVED' and v.eta >= now() - interval '1 hour' and v.eta <= now()) as arrivals_1h,
       (select count(distinct st.route_id) from public.standing_route_stops st join public.npc_fleets nf on nf.route_id = st.route_id where st.port_id = h.id) as loops,
       (select count(distinct sr.id) from public.standing_route_stops st join public.npc_fleets nf on nf.route_id = st.route_id
          join public.standing_routes sr on sr.id = st.route_id where st.port_id = h.id and sr.paused_reason = 'laid_up') as laid_up,
       (select count(*) from public.npc_houses nh where nh.home_port_id = h.id) as houses
  from public.ports h
 where h.code in ('AMB','BND','CPT','DIL','GAL','HAG','HOB','KOL','MAK','OLD','PLO','POR','STG','SYD','TER','TID')
 order by h.code;
commit;
