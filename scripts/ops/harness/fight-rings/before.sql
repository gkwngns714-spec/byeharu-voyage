-- 0364 PROD CHECK (before), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/fight-rings/before.sql
-- Wanted: old_times 1 and new_times 0 (the registry carries 0357's world.battle row once, and not this file's two rows); made 0 (no function or index of 0364 yet);
-- needs 4 (0357 is deployed: world.battle, public.battle_log, public.battle_fight and battles.sheet are there); attack false; battles 0 (no battle was ever opened on prod);
-- head = the migration before this one (0363 if every open file went first). Keep `registry` (the body's md5) for the dev-log.
-- Only the catalog, one knob and whether a battle row exists are read.
begin transaction read only;
with h(old, new) as (values ($h$      ('world',       'battle',                'uuid'),
$h$::text, $h$      ('world',       'battle',                'uuid'),
      -- 0364: every battle being fought, for the map's rings, and any battle's log for a watcher. Reads.
      ('world',       'fights',                ''),
      ('world',       'fight',                 'uuid'),
$h$::text)),
d as (select replace(pg_get_functiondef(to_regprocedure('public.client_rpc_entry_points()')), chr(13), '') as def)
select (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old) - (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as old_times,
       (length(d.def) - length(replace(d.def, h.new, ''))) / length(h.new) as new_times,
       (select count(*) from unnest(array['public.fight_card(uuid,uuid)', 'world.fights()', 'world.fight(uuid)']) f where to_regprocedure(f) is not null)
         + (case when to_regclass('public.battles_ended') is null then 0 else 1 end) as made,
       (select count(*) from unnest(array['world.battle(uuid)', 'public.battle_log(jsonb,jsonb,text)', 'public.battle_fight(uuid,integer)']) f where to_regprocedure(f) is not null)
         + (select count(*) from pg_attribute a where a.attrelid = to_regclass('public.battles') and a.attname = 'sheet' and not a.attisdropped) as needs,
       public.attack_on() as attack,
       (select count(*) from (select 1 from public.battles limit 5) q) as battles,
       md5(d.def) as registry,
       (select max(version) from supabase_migrations.schema_migrations) as head
  from h, d;
commit;
