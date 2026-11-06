-- 0330 PROD CHECK, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-danger/before.sql
-- Every function read here is STABLE or IMMUTABLE (pg_get_functiondef, to_regclass, to_regprocedure, replace, length). No game function is called.
-- Wanted: every `times` 1; seas 51; sea_danger_fn null; pressure_table null; old_mix 1; knobs 0; piracy_readers exactly voyage.sea_mix(uuid) and voyage.settle(uuid,timestamp with time zone); head 0329 (0328 until W12 lands).
with h(fn, ord, old) as (values
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)'::regprocedure, 1, $h$  values (p_fleet, v_player, p_segments, v_total, v_profile, p_at,
$h$),
  ('voyage.hazard_roll(uuid,integer)'::regprocedure, 1, $h$    from voyage.sea_mix(v_sea) m
$h$),
  ('voyage.settle(uuid,timestamp with time zone)'::regprocedure, 1, $h$      select coalesce(s2.piracy_index, 0) * 40 * (0.5 + h.magnitude) into v_raider
        from public.seas s2 where s2.id = (voyage.leg_at_day(v.id, d)->>'sea_id')::uuid;
$h$),
  ('voyage.risk_quote(uuid)'::regprocedure, 1, $h$    select (voyage.leg_at_day(p_voyage, g.d)->>'sea_id')::uuid as sea, h.p_hazard as p
      from generate_series(1, voyage.total_days(p_voyage)) g(d)
$h$),
  ('voyage.risk_quote(uuid)'::regprocedure, 2, $h$    select x.sea, coalesce((select m.share from voyage.sea_mix(x.sea) m where m.kind_code = 'PIRATES'), 0) as share
      from (select distinct d.sea from d) x
$h$),
  ('voyage.risk_quote(uuid)'::regprocedure, 3, $h$    from d join s on s.sea = d.sea
$h$),
  ('voyage.waters_ahead(uuid)'::regprocedure, 1, $h$  v_to     numeric[] := '{}';
$h$),
  ('voyage.waters_ahead(uuid)'::regprocedure, 2, $h$      v_to   := v_to   || v_acc;
$h$),
  ('voyage.waters_ahead(uuid)'::regprocedure, 3, $h$      'mix',    (select jsonb_object_agg(m.kind_code, m.share) from voyage.sea_mix(s.id) m),
$h$)
), t as (
  select h.fn::text as fn, h.ord, (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as times
    from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as def) d
)
select jsonb_build_object(
  'times', (select jsonb_agg(jsonb_build_array(t.fn, t.ord, t.times) order by t.fn, t.ord) from t),
  'seas', (select count(*) from public.seas),
  'sea_danger_fn', to_regprocedure('voyage.sea_danger(uuid,timestamp with time zone)')::text,
  'pressure_table', to_regclass('public.sea_pressure')::text,
  'old_mix', (select count(*) from pg_proc p where p.oid = to_regprocedure('voyage.sea_mix(uuid)')),
  'knobs', (select count(*) from public.world_config c where c.key in ('sea_pressure_decay', 'sea_danger_bands')),
  'piracy_readers', (select jsonb_agg(p.oid::regprocedure::text order by 1) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%piracy_index%'),
  'head', (select max(version) from supabase_migrations.schema_migrations)
) as check_0330
