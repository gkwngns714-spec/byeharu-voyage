-- 0437 PROD CHECK, BEFORE the deploy: the self-assert probe's SELECTIONS, read-only (CLAUDE.md: a migration's selections run read-only on prod first).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/cargo-home/probe-select.sql
-- ONE statement; stable functions only (public.realm_capital, public.port_nation, public.cargo_circuit_plan: one walk of the course graph per city tried,
-- at most 6). Reads great_powers, nations, cargo_fleet_sizes (~11), ports by kind, npc_courses by port, cargo_ships by nation (its ords).
-- WANTED: nation PRT (or the crown with the largest share), a city whose course home exists (plan true), next_ord = its highest ord + 1.
begin transaction read only;
with n as (
  select g.nation_id, x.code, public.realm_capital(g.nation_id) as cap
    from public.great_powers g join public.nations x on x.id = g.nation_id join public.cargo_fleet_sizes s on s.nation_id = g.nation_id
   where not g.pirate and public.realm_capital(g.nation_id) is not null
   order by (x.code = 'PRT') desc, s.ships desc, x.code
   limit 1
), c as (
  select p.id, p.code from n cross join public.ports p
   where p.kind = 'HARBOUR' and p.id <> n.cap and public.port_nation(p.id) = n.nation_id
     and exists (select 1 from public.npc_courses k where k.from_port = p.id or k.to_port = p.id)
   order by p.code limit 6
)
select jsonb_build_object(
  'nation', (select n.code from n),
  'capital', (select p.code from n join public.ports p on p.id = n.cap),
  'share', (select s.ships from n join public.cargo_fleet_sizes s on s.nation_id = n.nation_id),
  'next_ord', (select greatest(coalesce(max(x.ord), 0) + 1, 2) from n join public.cargo_ships x on x.nation_id = n.nation_id),
  'cities', (select jsonb_agg(jsonb_build_object('code', c.code, 'plan', public.cargo_circuit_plan(n.nation_id, c.id, n.cap) #> '{legs,0}' is not null) order by c.code)
               from c cross join n)
) as r;
commit;
