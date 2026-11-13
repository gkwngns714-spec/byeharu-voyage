-- 0364 PROD CHECK (after), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/fight-rings/after.sql
-- Wanted: 2 rows (the registry, public.navy_fight), each new_times 1; made 6 (four functions, the table, the index); doors 2 (both registered);
-- client_fns 2 (authenticated may call the two doors and neither the card nor the keeper); anon_fns 0; stable 3; log_table "rls, no client"; attack false; battles 0;
-- no_house {"on": false, "fights": []} (the read as this session, which has no house: world.fights is STABLE, see volatility.sql); news 1 (this file's UPDATE row); head 0364.
-- kept: how many navy fights have been kept so far (0 right after the deploy; it rises to at most the number of navy ships as they fight, one row a ship).
-- No function of the game reads public.navy_fight_log; only world.fights does.
begin transaction read only;
with h(fn, new) as (values
  ('public.client_rpc_entry_points()'::text, $h$      ('world',       'battle',                'uuid'),
      -- 0364: every battle being fought, for the map's rings, and any battle's log for a watcher. Reads.
      ('world',       'fights',                ''),
      ('world',       'fight',                 'uuid'),
$h$::text),
  ('public.navy_fight(uuid,uuid,timestamp with time zone)', $h$  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;
  perform public.navy_fight_keep(p_navy, p_pirate, v_a, v_b, v_f, p_now);   -- 0364: the fight's log and its place, kept for the map (it never raises and moves nothing of the fight)
$h$)),
d as (select h.*, replace(pg_get_functiondef(to_regprocedure(h.fn)), chr(13), '') as def from h),
f(fn) as (values ('public.fight_card(uuid,uuid)'), ('world.fights()'), ('world.fight(uuid)'), ('public.navy_fight_keep(uuid,uuid,jsonb,jsonb,jsonb,timestamp with time zone)'))
select d.fn,
       (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new) as new_times,
       (select count(*) from f where to_regprocedure(f.fn) is not null) + (case when to_regclass('public.battles_ended') is null then 0 else 1 end)
         + (case when to_regclass('public.navy_fight_log') is null then 0 else 1 end) as made,
       (select count(*) from public.client_rpc_entry_points() e where e.fn in (to_regprocedure('world.fights()'), to_regprocedure('world.fight(uuid)'))) as doors,
       (select count(*) from f where has_function_privilege('authenticated', to_regprocedure(f.fn), 'execute')) as client_fns,
       (select count(*) from f where has_function_privilege('anon', to_regprocedure(f.fn), 'execute')) as anon_fns,
       (select count(*) from f join pg_proc p on p.oid = to_regprocedure(f.fn) where p.provolatile = 's') as stable,
       (select case when c.relrowsecurity and not has_table_privilege('anon', c.oid, 'select,insert,update,delete')
                         and not has_table_privilege('authenticated', c.oid, 'select,insert,update,delete') then 'rls, no client' else 'OPEN' end
          from pg_class c where c.oid = to_regclass('public.navy_fight_log')) as log_table,
       public.attack_on() as attack,
       (select count(*) from (select 1 from public.battles limit 5) q) as battles,
       (select count(*) from (select 1 from public.navy_fight_log limit 500) q) as kept,
       world.fights() as no_house,
       (select count(*) from public.world_news n where n.key = 'update:0364') as news,
       md5(d.def) as body,
       (select max(version) from supabase_migrations.schema_migrations) as head
  from d order by d.fn;
commit;
