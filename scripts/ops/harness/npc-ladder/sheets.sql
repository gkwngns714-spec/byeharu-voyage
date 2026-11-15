-- 0451 PROD READ, ONCE, BEFORE THE PR: the 100 newest closed RAIDs fought tick by tick, as frozen (sheet a / b, a_flee, the stances the
-- timeline was run under, how it ended), the ord of the pirate fleet that opened each, and the knobs the fight reads. The input of
-- scripts/ops/harness/npc-ladder/replay.mjs (local), which re-fights them with the hulls 0451 gives those fleets.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/npc-ladder/sheets.sql > sheets.json
-- Run scripts/ops/harness/db-health/gate.sql first (gate_ok true). One statement, read only; public.battles (RAID rows are kept 48 h) by its
-- newest 100, their two opening sides by key. Stable functions only (public.fleet_kind). The timelines' events are not read.
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'knobs', (select jsonb_object_agg(k.key, k.value) from public.world_config k
             where k.key ~ '^(fight_|raid_flee|tick_|ship_level_|peace_after|flee_)' or k.key in ('levels_bite', 'npc_ship_level', 'npc_ship_level_enabled', 'armour_turns_pct')),
  'battles', (select jsonb_agg(jsonb_build_object(
                'id', b.id, 'started_at', b.started_at, 'a', b.sheet -> 'a', 'b', b.sheet -> 'b', 'a_flee', b.sheet -> 'a_flee', 'acts', b.sheet -> 'acts',
                'ai', b.ticks -> 'ai', 'out', b.ticks ->> 'out', 'n', b.ticks -> 'n', 'fled', b.result -> 'fled', 'taken', b.result #> '{raid,taken}',
                'def_kind', (select public.fleet_kind(bs.fleet_id) from public.battle_sides bs where bs.battle_id = b.id and bs.side = 'DEFENDER' and bs.how = 'OPENED'),
                'att', (select jsonb_build_object('ord', pn.ord, 'fleet', pn.fleet_id) from public.battle_sides bs join public.pirate_ships pn on pn.fleet_id = bs.fleet_id
                         where bs.battle_id = b.id and bs.side = 'ATTACKER' and bs.how = 'OPENED'))
                order by b.started_at desc)
                from (select x.* from public.battles x
                       where x.kind = 'RAID' and x.ticks is not null and x.ticks <> 'null'::jsonb and x.status <> 'FIGHTING'
                       order by x.started_at desc limit 100) b)
) as r;
commit;
