-- COMBAT SPEED (0424): THE AFTER CHECK. Read-only, ONE statement, static (no function called). Run once right after the deploy and once ~30 minutes
-- later (the owner's after-check for a change to live play), after db-health/gate.sql:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/combat-speed/after.sql
-- WANTED:
--   knob = {"NAVY": 4.5, "PIRATE": 4.5};
--   departed_since: navy and pirate voyages that LEFT after the switch have a median first-segment speed at least 3 x the merchants' median
--     (ratio_navy, ratio_pirate >= 3); a player's (COMPANY) voyages left at the speeds they always did (no kind multiplier exists for them);
--   at_sea: the combat voyages that were at sea at the switch (left before it) carry their later segments at 4.5 x (their first and last
--     segment knots differ by that factor when the switch fell on their first segment);
--   arrivals_per_min by kind among the voyages at sea now (sum of 1 / passage minutes): NAVY + PIRATE together under ~2 a minute (bound 1.8).
-- The switch time is the knob's updated_at.
begin transaction read only;
with sw as (
  select wc.updated_at as at, wc.value as knob from public.world_config wc where wc.key = 'fleet_speed_by_kind'
), v as (
  select case when exists (select 1 from public.cargo_ships x where x.fleet_id = v.fleet_id) then 'CARGO_SHIP'
              when exists (select 1 from public.npc_fleets x where x.fleet_id = v.fleet_id) then 'MERCHANT'
              when exists (select 1 from public.navy_ships x where x.fleet_id = v.fleet_id) then 'NAVY'
              when exists (select 1 from public.pirate_ships x where x.fleet_id = v.fleet_id) then 'PIRATE' else 'COMPANY' end as k,
         (v.speed_profile ->> 0)::numeric as kn0,
         (v.speed_profile ->> (jsonb_array_length(v.speed_profile) - 1))::numeric as kn_last,
         v.departed_at >= (select at from sw) as since,
         extract(epoch from v.eta - v.departed_at) / 60.0 as mins
    from public.voyages v where v.status = 'SAILING'
), m as (
  select k, since, count(*) as n,
         round((percentile_cont(0.5) within group (order by kn0))::numeric, 2) as kn0_median,
         round((percentile_cont(0.5) within group (order by kn_last / nullif(kn0, 0)))::numeric, 2) as last_over_first,
         round((percentile_cont(0.5) within group (order by mins))::numeric, 1) as mins_median,
         round(sum(1.0 / greatest(mins, 0.5))::numeric, 2) as arrivals_per_min
    from v group by 1, 2
)
select jsonb_build_object(
  'switch_at', (select at from sw), 'knob', (select knob from sw),
  'by_kind', (select jsonb_object_agg(k || case when since then ':left_since' else ':left_before' end,
                                      jsonb_build_object('n', n, 'kn0_median', kn0_median, 'last_over_first', last_over_first, 'mins_median', mins_median,
                                                         'arrivals_per_min', arrivals_per_min)) from m),
  'ratio_navy', (select round((select percentile_cont(0.5) within group (order by kn0) from v where k = 'NAVY' and since)::numeric
                              / nullif((select percentile_cont(0.5) within group (order by kn0) from v where k = 'MERCHANT')::numeric, 0), 2)),
  'ratio_pirate', (select round((select percentile_cont(0.5) within group (order by kn0) from v where k = 'PIRATE' and since)::numeric
                                / nullif((select percentile_cont(0.5) within group (order by kn0) from v where k = 'MERCHANT')::numeric, 0), 2)),
  'combat_arrivals_per_min', (select round(sum(1.0 / greatest(mins, 0.5))::numeric, 2) from v where k in ('NAVY', 'PIRATE'))
) as after;
commit;
