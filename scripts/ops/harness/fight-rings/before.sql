-- 0364 PROD CHECK (before), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/fight-rings/before.sql
-- Wanted: 2 rows (the registry, public.navy_fight), each old_times 1 and new_times 0; made 0 (no function, table or index of 0364 yet);
-- needs 4 (0357 is deployed: world.battle, public.battle_log, public.battle_fight and battles.sheet are there); attack false; battles 0 (no battle was ever opened on prod);
-- navy and raids: what is lit now (expected true and true: the navy hunts and the fight at sea bites, so rings will show from the deploy);
-- head = the migration before this one (0363 if every open file went first). Keep `body` (each cut body's md5) for the dev-log.
-- Only the catalog, three knobs and whether a battle row exists are read.
begin transaction read only;
with h(fn, old, new) as (values
  ('public.client_rpc_entry_points()'::text, $h$      ('world',       'battle',                'uuid'),
$h$::text, $h$      ('world',       'battle',                'uuid'),
      -- 0364: every battle being fought, for the map's rings, and any battle's log for a watcher. Reads.
      ('world',       'fights',                ''),
      ('world',       'fight',                 'uuid'),
$h$::text),
  ('public.navy_fight(uuid,uuid,timestamp with time zone)', $h$  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;
$h$, $h$  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;
  perform public.navy_fight_keep(p_navy, p_pirate, v_a, v_b, v_f, p_now);   -- 0364: the fight's log and its place, kept for the map (it never raises and moves nothing of the fight)
$h$)),
d as (select h.*, replace(pg_get_functiondef(to_regprocedure(h.fn)), chr(13), '') as def from h)
select d.fn,
       (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old) - (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new) as old_times,
       (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new) as new_times,
       (select count(*) from unnest(array['public.fight_card(uuid,uuid)', 'world.fights()', 'world.fight(uuid)', 'public.navy_fight_keep(uuid,uuid,jsonb,jsonb,jsonb,timestamp with time zone)']) f where to_regprocedure(f) is not null)
         + (case when to_regclass('public.battles_ended') is null then 0 else 1 end) + (case when to_regclass('public.navy_fight_log') is null then 0 else 1 end) as made,
       (select count(*) from unnest(array['world.battle(uuid)', 'public.battle_log(jsonb,jsonb,text)', 'public.battle_fight(uuid,integer)']) f where to_regprocedure(f) is not null)
         + (select count(*) from pg_attribute a where a.attrelid = to_regclass('public.battles') and a.attname = 'sheet' and not a.attisdropped) as needs,
       public.attack_on() as attack,
       public.navy_hunts_on() as navy,
       public.combat_bite_on() as raids,
       (select count(*) from (select 1 from public.battles limit 5) q) as battles,
       md5(d.def) as body,
       (select max(version) from supabase_migrations.schema_migrations) as head
  from d order by d.fn;
commit;
