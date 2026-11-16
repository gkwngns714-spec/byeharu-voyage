-- 0452 PROD CHECK, AFTER the deploy: the escorts re-rated as each lies in harbour.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/escort-refit/after.sql
-- One row, one jsonb column `r`. One statement, read only: one function's body, the navy's ~48 rows, their hulls and rung rows, the ladder's
-- three-row clock. Stable functions only (public.npc_hulls_sig).
-- WANTED: head 0452; applied true; `due` falling to [] as the four escorts at sea come into harbour (the four in harbour at the deploy within
--   minutes); each re-rated escort still `escorting` (mission ESCORT, escort_of set) with `has` = `wants` and a fresh `rated_at`;
--   `navy_rated_10m` at most 20 (two a minute); `unpaid` 0 as before.
begin transaction read only;
with nv as (
  select na.code, n.ord, n.fleet_id, n.mission, n.escort_of is not null as escorting, n.unpaid_since is not null as unpaid, f.status,
         (select string_agg(h.code || '*' || h.n, '+' order by h.code)
            from (select k.code, count(*) as n from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = n.fleet_id group by k.code) h) as has,
         public.npc_hulls_sig(n.fleet_id) as wants,
         (select g.rated_at from public.npc_fleet_rungs g where g.fleet_id = n.fleet_id) as rated_at
    from public.navy_ships n join public.fleets f on f.id = n.fleet_id join public.nations na on na.id = n.nation_id
   where n.laid_up_at is null
)
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'applied', position('-- 0452: not escort_of' in pg_get_functiondef('public.npc_ladder_refit(uuid,timestamp with time zone)'::regprocedure)) > 0,
  'navy', (select count(*) from nv),
  'due', (select coalesce(jsonb_agg(jsonb_build_object('code', v.code, 'ord', v.ord, 'status', v.status, 'escorting', v.escorting, 'has', v.has, 'wants', v.wants) order by v.code), '[]'::jsonb)
            from nv v where v.has is distinct from v.wants),
  'escorts', (select jsonb_agg(jsonb_build_object('code', v.code, 'ord', v.ord, 'mission', v.mission, 'status', v.status, 'has', v.has, 'wants', v.wants, 'rated_at', v.rated_at) order by v.code)
                from nv v where v.escorting),
  'navy_rated_10m', (select count(*) from nv v where v.rated_at > now() - interval '10 minutes'),
  'unpaid', (select count(*) from nv v where v.unpaid),
  'clock', (select jsonb_agg(to_jsonb(c) order by c.kind) from public.npc_ladder_clock c)
) as r;
commit;
