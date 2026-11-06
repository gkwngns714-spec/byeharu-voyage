-- 0332 PROD CHECK, read-only, one statement: supabase db query --linked -f scripts/ops/harness/crown-ships/before.sql
-- Generated from the migration's hunks. Every function read here is STABLE (pg_get_functiondef, to_regprocedure, replace). No game function is called.
-- Wanted: every `times` 1; crown_fn null; classes_with_recipe 2 before 0331 is deployed (navy_ship_class is not on prod yet), 3 after; head 0330 or 0331.
with h(fn, ord, old) as (values
  ('world.snapshot()'::regprocedure, 1, $h$        || jsonb_build_object('size', cp.size, 'role', cp.role, 'tech', cp.tech)     -- 0135: the Codex grid's filters
$h$),
  ('world.snapshot()'::regprocedure, 2, $h$      left join public.ship_lines sl on sl.code = cp.line_code),
$h$),
  ('world.building_yard(uuid)'::regprocedure, 1, $h$        -- 0165: a famous ship the company keeps already says so (public.famous_held), only then
$h$),
  ('world.building_yard(uuid)'::regprocedure, 2, $h$      left join public.ship_lines sl on sl.code = cp.line_code         -- 0130
$h$))
select jsonb_build_object(
  'hunks', (select jsonb_agg(jsonb_build_object('fn', h.fn::text, 'ord', h.ord,
                     'times', (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old)) order by h.fn::text, h.ord)
              from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as def) d),
  'crown_fn', to_regprocedure('public.crown_classes()'),
  'classes_with_recipe', (select count(*) from public.world_config c join public.hull_recipes r on r.class_code = c.value #>> '{}' where c.key in ('convoy_ship_class', 'convoy_armed_class', 'navy_ship_class')),
  'head', (select max(version) from supabase_migrations.schema_migrations)
)::text as j;
