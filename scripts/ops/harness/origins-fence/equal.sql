-- 0336 PROD CHECK, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/origins-fence/equal.sql
-- The two shapes of the lit read, 0324's and 0336's, written out as queries and asked of every great power on LIVE data, whatever the switch says (it is false, so the function itself answers the capital today).
-- Every function called is STABLE (public.crown_call_room, public.port_nation, public.wc_int); no row is written. COST: the old shape asks crown_call_room of every harbour for each realm, so ten realms take what ten
-- old reads take (about 0.3 to 1 s each); the new shape takes a fraction of that.
-- Wanted: realms 10; unequal 0 (the two arrays are the same for every realm); empty is how many realms have no city with room and a course (their origin would be the capital); rosters are the codes, in order.
select jsonb_build_object(
  'realms', count(*),
  'unequal', count(*) filter (where r.old_ids is distinct from r.new_ids),
  'empty', count(*) filter (where r.new_ids is null),
  'rosters', jsonb_object_agg(r.code, (select jsonb_agg(p.code order by o.n) from unnest(r.new_ids) with ordinality o(id, n) join public.ports p on p.id = o.id))
) as checks
  from (select n.code,
               (
        select array_agg(y.id order by y.room desc, y.code)
          from (select h.id, h.code, x.room
                  from public.ports h
                 cross join lateral (select public.crown_call_room(h.id) as room) x
                 where h.kind = 'HARBOUR' and public.port_nation(h.id) = g.nation_id and x.room > 0
                   and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)
                 order by x.room desc, h.code
                 limit public.wc_int('convoy_rich_ports')) y
               ) as old_ids,
               (
        select array_agg(y.id order by y.room desc, y.code)
          from (select h.id, h.code, x.room
                  from (select p.id, p.code from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) = g.nation_id offset 0) h
                 cross join lateral (select public.crown_call_room(h.id) as room) x
                 where x.room > 0
                   and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)
                 order by x.room desc, h.code
                 limit public.wc_int('convoy_rich_ports')) y
               ) as new_ids
          from public.great_powers g join public.nations n on n.id = g.nation_id) r;
