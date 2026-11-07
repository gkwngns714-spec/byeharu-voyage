-- 0336 PLAN of the shape before (0324), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/origins-fence/plan-old.sql
-- A plain EXPLAIN: the statement is PLANNED and NOT RUN (never EXPLAIN ANALYZE on prod, CLAUDE.md), so no function is called. The plan is for ESP, the biggest realm, with the switch's lit arm written out as a query.
-- Wanted: the old shape filters crown_call_room(id) > 0 on the scan of ports, in the same node as port_nation(id) = ...; the new shape filters port_nation(id) on the inner scan of ports and crown_call_room(h.id) > 0 on the Subquery Scan above it.
begin transaction read only;
explain
select array_agg(y.id order by y.room desc, y.code)
  from (select h.id, h.code, x.room
          from public.ports h
         cross join lateral (select public.crown_call_room(h.id) as room) x
         where h.kind = 'HARBOUR' and public.port_nation(h.id) = (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP') and x.room > 0
           and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)
         order by x.room desc, h.code
         limit public.wc_int('convoy_rich_ports')) y;
commit;
