-- EACH LEVEL OPENS SOMETHING (0468), AFTER. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/level-unlocks/after-0468.sql
-- Expect, DARK (as deployed): head 0468; switch false; trading_steps 17 (trade_routes 5, fleet_ships 4, yard_fee 8); every hunk new 1;
-- every human's `routes_bonus`, `ships_bonus` and `fee_off` 0. LIT (only after the owner lights it): each human's bonuses are the steps
-- at her Trading mark. `over`: humans who hold more routes than the cap would be with the switch off (read it BEFORE turning the switch
-- off: they keep them, and the route trigger refuses the next until they are under). Expect [] dark.
-- Reads: the catalog, world_config by key, level_perks, and for about 19 human companies their mark, their route count and three
-- stable readings (public.level_perk, public.standing_route_max_for). No volatile function is called; player_progress is not read.
begin transaction read only;
with hum as (
  select p.id, coalesce((select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'trading'), 1) as mark,
         public.level_perk(p.id, 'trade_routes') as routes_bonus, public.level_perk(p.id, 'fleet_ships') as ships_bonus,
         public.level_perk(p.id, 'yard_fee') as fee_off, public.standing_route_max_for(p.id) as route_cap,
         (select count(*) from public.standing_routes r where r.player_id = p.id) as routes
    from public.players p where not p.is_npc
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select value from public.world_config where key = 'level_unlocks_enabled'),
  'trading_steps', (select jsonb_object_agg(x.perk, x.n) from (select k.perk, count(*) as n from public.level_perks k where k.skill = 'trading' group by 1) x),
  'hunks_new', (select jsonb_object_agg(f.fn, position(f.mark in pg_get_functiondef(to_regprocedure(f.fn))) > 0) from (values
                  ('public.level_perk(uuid,text)', '0468:'), ('public.level_benefits(text,integer)', '0468:'), ('public.standing_route_max_for(uuid)', '0468:'),
                  ('public.fleet_room_caps(uuid)', '0468:'), ('public.hull_order_price(uuid,uuid,text)', '0468:')) f(fn, mark)),
  'humans', (select jsonb_agg(jsonb_build_object('mark', h.mark, 'routes_bonus', h.routes_bonus, 'ships_bonus', h.ships_bonus, 'fee_off', h.fee_off,
                                                 'route_cap', h.route_cap, 'routes', h.routes) order by h.mark desc) from hum h),
  'over', (select coalesce(jsonb_agg(jsonb_build_object('routes', h.routes, 'dark_cap', h.route_cap - h.routes_bonus::int)), '[]'::jsonb)
             from hum h where h.routes > h.route_cap - h.routes_bonus::int));
rollback;
