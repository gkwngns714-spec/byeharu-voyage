-- 0511 PROD CHECK, after the deploy, and after the light (+30 min); read-only, ONE statement. Dark: bite false, with_terms 0. Lit: merchants_with_terms 0;
-- riots, riot_homes and storms are what players met; worst_crew_pct at most 15 and some; arrivals beat under 2 s, errors 0.
begin transaction read only;
select (select value from public.world_config where key = 'happenings_bite') as bite,
       (select count(*) from public.voyages v join public.players p on p.id = v.player_id and not p.is_npc where v.status = 'SAILING' and v.path->0 ? 'hap') as with_terms,
       (select count(*) from public.voyages v join public.players p on p.id = v.player_id and p.is_npc where v.status = 'SAILING' and v.path->0 ? 'hap') as merchants_with_terms,
       (select jsonb_object_agg(q.kind, q.n) from (select e.kind, count(*) as n from public.voyage_events e join public.voyages v on v.id = e.voyage_id and v.status = 'SAILING'
          join public.players p on p.id = v.player_id and not p.is_npc where e.kind in ('RIOT', 'RIOT_HOME', 'STORM') group by 1) q) as met,
       (select jsonb_build_object('n', count(*), 'avg_ms', round(avg(b.ms)::numeric, 1), 'errors', count(*) filter (where b.error is not null))
          from public.arrivals_beats b where b.at >= now() - interval '30 minutes') as beats;
rollback;
