-- ATTACKS, PROD CHECK (before the light), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/attacks/before-light.sql
-- Run it just before deploying 0375 (a company may attack), AFTER 0374 is deployed (it calls 0374's public.attack_ready, the very reading 0375's guard refuses by).
-- Run cargo-at-sea.sql beside it. WANTED:
--   ready        {"ready": true, "lived": true, "why": []} and every check true: loot_rule_on, clock_sane, regard_lit, npc_levels_lit, levels_written (9 cargo hulls in 10 carry
--                their level), convoy_armed_lit, navy_lit, cargo_safe (the unarmed cargo ships at sea are at most a tenth). `why` names whatever is not.
--   attack_lit   FALSE.
--   knobs        as shipped unless the owner changed one: battle_round_seconds 60, battle_seconds 600, loot_share 0.15, ransom_share 0.08, loot_per_ship 60000,
--                loot_per_company_day 240000, loot_risk_full 0.075, loot_risk_floor 0, attack_reach_nm 240, attack_cooldown_minutes 30, regard_attack_cargo -150,
--                regard_attack_navy -250, regard_sink -100, wanted_hours 48, navy_call_ships 3, navy_hunt_per_day 0 (the hunt is its own later light), npc_refits_enabled as it is.
--   untouched    battles 0, battle_rounds 0, wanted 0, loot_rows 0 (no LOOT row in the last 7 days): nothing of an attack exists before the light.
--   doors        4: cmd.attack, cmd.preview_attack, cmd.battle_stance and world.battle are registered for the client.
--   companies    how many human companies there are and how many own a ship with guns (who can attack on day one).
--   head         the migration before 0375.
-- Every function called is STABLE. Bounded reads: cargo_ships (hundreds), battles (empty), the ledger's last 7 days by kind, the human companies' ships.
begin transaction read only;
select public.attack_ready() as ready,
       public.attack_on() as attack_lit,
       (select jsonb_object_agg(w.key, w.value)
          from public.world_config w
         where w.key in ('battle_round_seconds', 'battle_seconds', 'loot_share', 'ransom_share', 'loot_per_ship', 'loot_per_company_day', 'loot_risk_full', 'loot_risk_floor',
                         'attack_reach_nm', 'attack_cooldown_minutes', 'attack_ship_minutes', 'regard_attack_cargo', 'regard_attack_navy', 'regard_pirate', 'regard_sink',
                         'wanted_hours', 'navy_call_ships', 'navy_hunt_per_day', 'npc_refits_enabled', 'npc_ship_level', 'fight_raider_break')) as knobs,
       jsonb_build_object(
         'battles', (select count(*) from (select 1 from public.battles limit 5) q),
         'battle_rounds', (select count(*) from (select 1 from public.battle_rounds limit 5) q),
         'wanted', (select count(*) from (select 1 from public.wanted limit 5) q),
         'loot_rows', (select count(*) from (select 1 from public.ledger l where l.kind = 'LOOT' and l.created_at > now() - interval '7 days' limit 5) q)) as untouched,
       (select count(*) from public.client_rpc_entry_points() e
         where (e.schema_name, e.function_name) in (('cmd', 'attack'), ('cmd', 'preview_attack'), ('cmd', 'battle_stance'), ('world', 'battle'))) as doors,
       (select jsonb_build_object('human', count(*),
                                  'with_guns', count(*) filter (where exists (select 1 from public.ships s join public.ship_classes k on k.id = s.class_id where s.player_id = p.id and k.attack > 0)))
          from public.players p where not p.is_npc) as companies,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
