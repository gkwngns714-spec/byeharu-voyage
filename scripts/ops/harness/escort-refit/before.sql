-- 0452 PROD CHECK, BEFORE the deploy: the hunks' pre-images in the live body, and the navy ships the ladder has not re-rated, as they stand.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/escort-refit/before.sql
-- One row, one jsonb column `r`. One statement, read only: one function's body (pg_get_functiondef, stable), the navy's ~48 rows, their hulls
-- and rung rows. Stable functions only (public.npc_hulls_sig, public.fleet_state_of is not needed: status and port are read off fleets).
-- WANTED: head 0451; applied false; hunk1 1, hunk2 1; `due` = the 8 escorts (ENG ESP JPN MNG MUG NLD OTT PRT), each escort_of set, none busy,
--   called, in a battle, unpaid or laid up.
begin transaction read only;
with body as (
  select replace(pg_get_functiondef('public.npc_ladder_refit(uuid,timestamp with time zone)'::regprocedure), E'\r', '') as d
), due as (
  select na.code, n.ord, (select max(x.ord) from public.navy_ships x where x.nation_id = n.nation_id and x.laid_up_at is null) as last_ord,
         n.mission, n.escort_of is not null as escorting, n.called_to is not null as called, n.battle_id is not null as in_battle,
         n.unpaid_since is not null as unpaid, f.status, f.port_id is not null as in_port, f.busy_until > now() as busy,
         (select string_agg(h.code || '*' || h.n, '+' order by h.code)
            from (select k.code, count(*) as n from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = n.fleet_id group by k.code) h) as has,
         public.npc_hulls_sig(n.fleet_id) as wants,
         (select g.hulls from public.npc_fleet_rungs g where g.fleet_id = n.fleet_id) as rated
    from public.navy_ships n join public.fleets f on f.id = n.fleet_id join public.nations na on na.id = n.nation_id
   where n.laid_up_at is null
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'applied', (select position('-- 0452: not escort_of' in b.d) > 0 from body b),
  'hunk1', (select (length(b.d) - length(replace(b.d, $h$-- wreck lying: public.pirate_reborn calls it before the mend), never busy, never on a side of a battle being fought, never a navy ship called to a
-- fight or escorting, never with goods in a hold; and only inside the minute's room (public.npc_ladder_take). Her old hulls go and
$h$, ''))) / length($h$-- wreck lying: public.pirate_reborn calls it before the mend), never busy, never on a side of a battle being fought, never a navy ship called to a
-- fight or escorting, never with goods in a hold; and only inside the minute's room (public.npc_ladder_take). Her old hulls go and
$h$) from body b),
  'hunk2', (select (length(b.d) - length(replace(b.d, $h$     or exists (select 1 from public.navy_ships n where n.fleet_id = p_fleet and (n.battle_id is not null or n.called_to is not null or n.escort_of is not null)) then
$h$, ''))) / length($h$     or exists (select 1 from public.navy_ships n where n.fleet_id = p_fleet and (n.battle_id is not null or n.called_to is not null or n.escort_of is not null)) then
$h$) from body b),
  'navy', (select count(*) from due),
  'rated_ok', (select count(*) from due d where d.has = d.wants),
  'due', (select jsonb_agg(to_jsonb(d) - 'wants' - 'rated' || jsonb_build_object('wants', d.wants) order by d.code) from due d where d.has is distinct from d.wants)
) as r;
commit;
