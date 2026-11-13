-- 0380 PROD CHECK (after the deploy), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pirate-company/after.sql
-- Wanted: head 20260818000380 (or later); new_times 1 and old_times 0; without_hunk_md5 = before.sql's now_md5; volatility 's'; pirates ["PIR"]; nations 24;
-- joinable 10 (11 once 0381 is in); knob false (true once 0381 is in): 0380 itself sets no knob.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_times,
       (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) as old_times,
       md5(replace(d.def, h.new, h.old)) as without_hunk_md5,
       (select p.provolatile from pg_proc p where p.oid = 'world.snapshot()'::regprocedure) as volatility,
       (select jsonb_agg(e.value ->> 'code' order by e.value ->> 'code') from jsonb_array_elements(world.snapshot() -> 'nations') e where (e.value ->> 'pirate')::boolean) as pirates,
       (select count(*) from jsonb_array_elements(world.snapshot() -> 'nations') e) as nations,
       (select count(*) from jsonb_array_elements(world.snapshot() -> 'nations') e where (e.value ->> 'joinable')::boolean) as joinable,
       (select c.value from public.world_config c where c.key = 'pirates_joinable') as knob
  from (select replace(pg_get_functiondef('world.snapshot()'::regprocedure), E'\r', '') as def) d,
       (select $h$        'joinable', public.nation_joinable(n.id)) order by n.code), '[]'::jsonb)   -- 0028 WIND; GP1: one of the great powers; 0338: one a company may sail for
$h$ as old,
               $h$        'joinable', public.nation_joinable(n.id),                                  -- 0028 WIND; GP1: one of the great powers; 0338: one a company may sail for
        'pirate', public.pirate_power(n.id)) order by n.code), '[]'::jsonb)        -- 0380: THE PIRATE POWER, named once, so the picker can say what the skull costs
$h$ as new) h;
commit;
