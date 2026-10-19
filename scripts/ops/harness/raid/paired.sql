begin transaction read only;
-- the PAIRED after-check: every PIRATES day in the window, its recorded outcome against DESIGN B.6's table on the
-- SAME day (the dark escort from its fleet's hulls, the day's own raider strength)
with w as (select timestamptz '2026-10-18 20:50+00' a, timestamptz '2026-10-18 21:20+00' b),
d as (
  select ve.payload p, v.fleet_id,
         (select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0) from public.ships sh join public.ship_classes c on c.id = sh.class_id
           where sh.fleet_id = v.fleet_id) as esc_dark
    from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id, w
   where ve.kind = 'PIRATES' and ve.resolved_at >= w.a and ve.resolved_at < w.b),
t as (
  select d.*, (d.p->>'raider')::numeric r,
         case when (d.p->>'raider')::numeric <= 0 then 'EVADED'
              when d.esc_dark / (d.p->>'raider')::numeric >= 2.0 then 'EVADED'
              when d.esc_dark / (d.p->>'raider')::numeric >= 1.2 then 'DRIVEN_OFF'
              when d.esc_dark / (d.p->>'raider')::numeric >= 0.7 then 'RANSOM'
              when d.esc_dark / (d.p->>'raider')::numeric >= 0.3 then 'PLUNDERED' else 'STRIPPED' end as table_outcome
    from d)
select json_build_object(
  'n', count(*),
  'lost_pct', round(100.0 * count(*) filter (where p->>'outcome' in ('PLUNDERED', 'STRIPPED')) / nullif(count(*), 0), 1),
  'lost_pct_table', round(100.0 * count(*) filter (where table_outcome in ('PLUNDERED', 'STRIPPED')) / nullif(count(*), 0), 1),
  'crew_pct', round(100.0 * avg((p->>'crew_lost')::numeric / nullif((p->>'crew_before')::numeric, 0)), 2),
  'crew_pct_table', round(100.0 * avg((select sum(sh.crew - floor(sh.crew * (1 - case table_outcome when 'DRIVEN_OFF' then 0.02 when 'PLUNDERED' then 0.10
                                                                                   when 'STRIPPED' then 0.30 else 0 end)))
                                         from public.ships sh where sh.fleet_id = t.fleet_id) / nullif((select sum(sh.crew) from public.ships sh where sh.fleet_id = t.fleet_id), 0)), 2))
  from t;
rollback;
