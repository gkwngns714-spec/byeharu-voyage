-- rollback-0414.sql: A DRAFT, NOT A MIGRATION. Forward only, owner only, as a NEW migration (prod head + 1) if 0414 must be undone.
-- THE FAST LEVERS NEED NO MIGRATION (knob or row writes, owner only):
--   * `pirates_bite` false: every pirate fleet sails home and is laid up; no raider is named; the seas' pressure empties.
--   * delete rows of public.pirate_roster (or all of them): those fleets are no longer wanted (public.pirate_ord_wanted), sail home and are laid up. Hulls remain.
--   * `pirate_pressure_max` lower (0.5 is one ship's weight; 0 is no pirate pressure at all); `pirate_spend_day_pct` back to what its description says it replaced (0.001 on the one-hour day; in any case the standing value / 2.4); `pirate_add_minutes` 1440 is the old pace.
-- THE FULL UNDO, in this order, in ONE do block with the hunk loop of 0414 run the other way (old and new swapped; each new text once, reversing to the pre-image):
--   1. the nine hunks reversed over public.pirate_ship_step, public.pirate_add, public.pirate_haunt_of, public.pirate_pressure_write, public.npc_refit_step, world.pirate_ship_card.
--      AFTER THIS a pirate wreck is 0322's again (her home alone pays): the fault of 2026-11-14 returns unless the homes hold a purse.
--   2. every roster fleet laid up at her hub first (delete the roster rows and wait for the fleets to come home); then
--      drop function public.pirate_commission_fleet, public.pirate_reborn, public.pirate_refit_pay, public.pirate_next_ord, public.pirate_ord_wanted;
--      drop table public.pirate_roster_hulls, public.pirate_roster, public.pirate_hubs; alter table public.pirate_ships drop column wrecked_at
--      (the unique key on player_id cannot return while a house owns two fleets).
--   3. the knobs: delete pirate_respawn_minutes, pirate_add_minutes, pirate_pressure_max; pirate_spend_day_pct = the standing value / 2.4 (0414 multiplied it; the value it replaced is in the description).
--   4. THE FIVE HARBOURS ARE A ONE-WAY DOOR once a fleet, a merchant or a player has called there (0338 said the same of its three). Before that: delete their rows from
--      sea_leg_asks, npc_courses, port_population, port_language, port_allegiance, city_works, port_treasury, port_buildings, port_goods, city_production, port_specialties and
--      sea_reaches, remove the five keys from every sea_reaches.reaches, delete the ports, re-derive the moved market rows (world.affinity_at without the five; world.haul_rows()),
--      and take the five out of data/ports.json, data/sea-legs.json, data/port-population.json, data/captains.json and scripts/lib/world-derive.mjs in the same PR.
begin transaction read only;   -- the draft is prose; its one statement is a pure read (tests/harness.guard.spec.ts)
select 'rollback-0414.sql is a draft: read it, do not run it' as note;
commit;
