-- 0380 PROD CHECK (before the deploy), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-company/before.sql
-- Wanted: head is the migration before 0380 in the deploy order; old_times 1 and new_times 0 (the live world.snapshot is the body the hunk was cut against, and
-- 0380 is not in); pirate_power_volatility 's'; pirate_powers 1; knob false. now_md5 is the live body's hash: keep it, after.sql's without_hunk_md5 must equal it.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as old_times,
       (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_times,
       md5(d.def) as now_md5,
       (select p.provolatile from pg_proc p where p.oid = 'public.pirate_power(uuid)'::regprocedure) as pirate_power_volatility,
       (select count(*) from public.great_powers g where g.pirate) as pirate_powers,
       (select c.value from public.world_config c where c.key = 'pirates_joinable') as knob
  from (select replace(pg_get_functiondef('world.snapshot()'::regprocedure), E'\r', '') as def) d,
       (select $h$        'joinable', public.nation_joinable(n.id)) order by n.code), '[]'::jsonb)   -- 0028 WIND; GP1: one of the great powers; 0338: one a company may sail for
$h$ as old,
               $h$        'joinable', public.nation_joinable(n.id),                                  -- 0028 WIND; GP1: one of the great powers; 0338: one a company may sail for
        'pirate', public.pirate_power(n.id)) order by n.code), '[]'::jsonb)        -- 0380: THE PIRATE POWER, named once, so the picker can say what the skull costs
$h$ as new) h;
commit;
