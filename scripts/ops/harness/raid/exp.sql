begin transaction read only;
with r as (
  select ve.voyage_id, ve.day_index, ve.resolved_at, v.fleet_id, ve.payload p
    from public.voyage_events ve join public.voyages v on v.id = ve.voyage_id
   where ve.kind = 'PIRATES'),
fl as (select distinct fleet_id from r)
select json_build_object(
 'at', now(),
 'raids', (select json_agg(json_build_object('voyage', r.voyage_id, 'day', r.day_index, 'at', r.resolved_at, 'fleet', r.fleet_id,
            'npc', pl.is_npc, 'raider', (r.p->>'raider')::numeric, 'escort', (r.p->>'escort')::numeric, 'outcome', r.p->>'outcome',
            'crew_before', (r.p->>'crew_before')::numeric, 'crew_lost', (r.p->>'crew_lost')::numeric, 'base_loss', (r.p->>'base_loss')::numeric,
            'lit', r.p ? 'rounds', 'fight', r.p->'fight') order by r.resolved_at)
            from r join public.voyages v on v.id = r.voyage_id join public.players pl on pl.id = v.player_id),
 'fleets', (select json_agg(json_build_object('id', fl.fleet_id,
            'escort_lit', voyage.escort_score(fl.fleet_id),
            'escort_dark', (select coalesce(sum(c.guns + sh.crew * 0.02 + c.tier * 3), 0) from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = fl.fleet_id),
            'ships', (select json_agg(json_build_object('id', s.id, 'name', s.name, 'class', c.code, 'tier', c.tier, 'hull', s.durability, 'maxd', c.durability,
                        'crew', s.crew, 'crew_required', c.crew_required, 'guns', c.guns, 'st', world.ship_stats(s.id),
                        'gear', (select coalesce(json_agg(distinct ik.name), '[]'::json) from public.fitted_units fu
                                  join public.item_use iu on iu.item_code = fu.item_code and iu.trigger = 'PIRATES'
                                  join public.item_kinds ik on ik.code = fu.item_code where fu.ship_id = s.id))
                        order by s.is_flagship desc, s.created_at, s.id)
                       from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = fl.fleet_id)))
            from fl));
rollback;
