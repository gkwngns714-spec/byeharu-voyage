-- 0364 PROD CHECK (after), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/fight-rings/after.sql
-- Wanted: new_times 1; made 4 (three functions and the index); doors 2 (both registered); client_fns 2 (authenticated may call the two doors and not the card); anon_fns 0;
-- stable 3; attack false; battles 0; no_house {"on": false, "fights": []} (the read as this session, which has no house: world.fights is STABLE, see volatility.sql);
-- head 0364. With attacks dark and no battle row, no player sees a ring: nothing on the map changed.
begin transaction read only;
with h(new) as (values ($h$      ('world',       'battle',                'uuid'),
      -- 0364: every battle being fought, for the map's rings, and any battle's log for a watcher. Reads.
      ('world',       'fights',                ''),
      ('world',       'fight',                 'uuid'),
$h$::text)),
d as (select replace(pg_get_functiondef(to_regprocedure('public.client_rpc_entry_points()')), chr(13), '') as def),
f(fn) as (values ('public.fight_card(uuid,uuid)'), ('world.fights()'), ('world.fight(uuid)'))
select (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_times,
       (select count(*) from f where to_regprocedure(f.fn) is not null) + (case when to_regclass('public.battles_ended') is null then 0 else 1 end) as made,
       (select count(*) from public.client_rpc_entry_points() e where e.fn in (to_regprocedure('world.fights()'), to_regprocedure('world.fight(uuid)'))) as doors,
       (select count(*) from f where has_function_privilege('authenticated', to_regprocedure(f.fn), 'execute')) as client_fns,
       (select count(*) from f where has_function_privilege('anon', to_regprocedure(f.fn), 'execute')) as anon_fns,
       (select count(*) from f join pg_proc p on p.oid = to_regprocedure(f.fn) where p.provolatile = 's') as stable,
       public.attack_on() as attack,
       (select count(*) from (select 1 from public.battles limit 5) q) as battles,
       world.fights() as no_house,
       md5(d.def) as registry,
       (select max(version) from supabase_migrations.schema_migrations) as head
  from h, d;
commit;
