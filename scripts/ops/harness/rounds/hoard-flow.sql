-- FOR THE LEAD (read-only): what came into and went out of the pirates' purses in the last 24 hours, by kind, with the hoard and the day's room.
begin transaction read only;
select public.pirate_hoard() as hoard, public.pirate_spend_room(now()) as room_left, (select json_agg(json_build_array(q.kind, q.into_purses, q.out_of_purses) order by q.kind)
  from (select f.kind, sum(f.ducats) filter (where f.ducats > 0) as into_purses, sum(f.ducats) filter (where f.ducats < 0) as out_of_purses
          from public.treasury_flows f where f.created_at > now() - interval '24 hours'
           and f.port_id in (select a.port_id from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id where g.pirate) group by f.kind) q) as flows;
rollback;
