-- 0337 PROD CHECK BEFORE, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/captain-sheet/before.sql
-- Nothing is called but the catalog (to_regprocedure, pg_get_functiondef, pg_proc) and plain SELECTs; every type is cast. No game function runs.
-- Wanted: head 20260818000335 or 20260818000336 (the number before 0337); fn_absent true; registry_anchor_times 1 and registry_row_present false; levels_bite true; readers all 's' or 'i';
--         sibling_acl {postgres=X/postgres,authenticated=X/postgres}; captain_xp_rows and seated_humans printed for the dev-log.
begin transaction read only;
with h(old) as (values ($h$      ('world',       'navy_ship_card',        'uuid'),
$h$))
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'fn_absent', to_regprocedure('world.captain_stats(text)') is null,
  'registry_anchor_times', (select (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old)
                              from h cross join lateral (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def) d),
  'registry_row_present', position('captain_stats' in pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) > 0,
  'levels_bite', (select c.value::text from public.world_config c where c.key = 'levels_bite'),
  'crew_bite', (select c.value::text from public.world_config c where c.key = 'crew_bite'),
  'combat_bite', (select c.value::text from public.world_config c where c.key = 'combat_bite'),
  'skills_bite', (select c.value::text from public.world_config c where c.key = 'skills_bite'),
  'readers', (select jsonb_object_agg(p.oid::regprocedure::text, p.provolatile::text) from pg_proc p
               where p.oid in ('public.crew_terms(uuid,timestamp with time zone)'::regprocedure, 'public.crew_pct(uuid,uuid,text,uuid,timestamp with time zone)'::regprocedure,
                               'public.captain_level(uuid,text)'::regprocedure, 'public.trait_effect_words(text,numeric,text)'::regprocedure, 'world.skill_pct(uuid,uuid,text)'::regprocedure,
                               'public.combat_bite_on()'::regprocedure, 'public.skills_bite_on()'::regprocedure, 'public.current_player_id()'::regprocedure)),
  'sibling_acl', (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.levels()'::regprocedure),
  'sibling_vol', (select p.provolatile::text from pg_proc p where p.oid = 'world.levels()'::regprocedure),
  'captain_xp_rows', (select count(*) from public.captain_xp),
  'seated_humans', (select count(*) from public.captain_seats cs join public.player_officers po on po.id = cs.player_officer_id join public.players pl on pl.id = po.player_id where not pl.is_npc),
  'signings_of_humans', (select count(*) from public.player_officers po join public.players pl on pl.id = po.player_id where not pl.is_npc)
) as checks
from h;
commit;
