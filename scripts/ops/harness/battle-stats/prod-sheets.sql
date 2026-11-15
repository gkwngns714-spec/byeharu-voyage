-- 0450 PROD READ, ONCE, BEFORE THE PR: the 100 newest closed RAIDs fought tick by tick, as frozen (sheet a / b, a_flee, the stances the timeline was
-- run under, how it ended), each hull's level and the crew her class needs as they are now (what 0450 will freeze), and the knobs the fight reads.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/battle-stats/prod-sheets.sql > sheets.json
-- Run scripts/ops/harness/db-health/gate.sql first (gate_ok true). One statement, read only; public.battles (RAID rows are kept 48 h) by its newest
-- 100, index probes of ships / ship_xp for their ~300 hulls. Stable functions only (public.fleet_kind, public.level_in_force). The timelines' events
-- are NOT read (the replay re-runs them: scripts/ops/harness/battle-stats/replay.mjs).
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'head', (select max(m.version) from supabase_migrations.schema_migrations m),
  'knobs', (select jsonb_object_agg(k.key, k.value) from public.world_config k
             where k.key ~ '^(fight_|raid_flee|tick_|ship_level_|peace_after)' or k.key in ('levels_bite', 'npc_ship_level', 'npc_ship_level_enabled', 'armour_turns_pct', 'fleet_speed_by_kind')),
  'battles', (select jsonb_agg(jsonb_build_object(
                'id', b.id, 'started_at', b.started_at, 'a', b.sheet -> 'a', 'b', b.sheet -> 'b', 'a_flee', b.sheet -> 'a_flee', 'acts', b.sheet -> 'acts',
                'ai', b.ticks -> 'ai', 'out', b.ticks ->> 'out', 'n', b.ticks -> 'n', 'fled', b.result -> 'fled',
                'def_kind', (select public.fleet_kind(bs.fleet_id) from public.battle_sides bs where bs.battle_id = b.id and bs.side = 'DEFENDER' and bs.how = 'OPENED'),
                'cards', (select jsonb_object_agg(s.id, jsonb_build_object('lv', case when sx.xp > 0 then public.level_in_force(sx.xp) else 1 end,
                                                                           'crew_need', c.crew_required, 'cls', c.name))
                            from jsonb_array_elements(coalesce(b.sheet -> 'a', '[]'::jsonb) || coalesce(b.sheet -> 'b', '[]'::jsonb)) h
                            join public.ships s on s.id = (h ->> 'id')::uuid
                            join public.ship_classes c on c.id = s.class_id
                            left join public.ship_xp sx on sx.ship_id = s.id))
                order by b.started_at desc)
                from (select x.* from public.battles x
                       where x.kind = 'RAID' and x.ticks is not null and x.ticks <> 'null'::jsonb and x.status <> 'FIGHTING'
                       order by x.started_at desc limit 100) b)
) as r;
commit;
