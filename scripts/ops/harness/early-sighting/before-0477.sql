-- EARLY SIGHTING (0477), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/early-sighting/before-0477.sql
-- Expect: head 20260818000476; knobs {} (none of the eight); table false; fn_absent true; each of the four hunks' OLD text once (old 1)
-- and its new marker absent (new 0): voyage.depart, public.tick_pirates, public.battle_npc_joins, public.client_rpc_entry_points.
-- The fight as prod runs it (`lit`): attack_enabled, raid_orders_enabled, pirates_bite, city_treasury_enabled true; tick_fight_kinds
-- with RAID; raid_company_title_min 3; ransom_share and insurance_keep_pct as the card will say them.
-- The BASELINE for the lit window:
--   `pirates_at_work`   pirate fleets not laid up; `raiders` of them at rung 1 (public.npc_rung_of: one small hull), `raiders_free` free
--                       to sight now (not busy, afloat, in no battle, no open bounty): the pool the sighting draws from.
--   `companies`         human companies; `eligible` of them at Trading 3 or more (their paid mark) with a title under Master: the
--                       companies a lit switch would set at their next near trip with cargo.
-- Reads: the catalog (four pg_get_functiondef), world_config by key, pirate_ships / fleets / ships / battle_sides / pirate_bounties for
-- the pirates (about 100 rows), players (humans) with house_level_marks; public.npc_rung_of and public.title_level are stable. No
-- function that writes is called.
begin transaction read only;
with h(fn, old, new) as (values
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', '    perform voyage.hostile_freeze(v_voyage, v_player, p_at);', 'early_sighting_plan'),
  ('public.tick_pirates(timestamp with time zone)', '         -- 0445: LAST, the one ship of this run that may trade takes her step', 'early_sighting_step'),
  ('public.battle_npc_joins(timestamp with time zone)',
   '              where x.status = ''FIGHTING'' and x.kind = ''RAID'' and x.ticks is not null and x.resolves_at > p_now', 'early_sightings'),
  ('public.client_rpc_entry_points()', '      (''world'',       ''first_voyages'',         ''''),', '''early_sighting''')
), d as (select h.fn, h.old, h.new, replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def from h),
pir as (
  select n.fleet_id, public.npc_rung_of(n.fleet_id) as rung,
         f.busy_until is null and f.status in ('DOCKED', 'ANCHORED', 'SAILING')
           and exists (select 1 from public.ships s where s.fleet_id = n.fleet_id and s.durability > 0)
           and not exists (select 1 from public.pirate_bounties b where b.fleet_id = n.fleet_id and b.closed_at is null)
           and not exists (select 1 from public.battle_sides bs join public.battles bt on bt.id = bs.battle_id
                            where bs.fleet_id = n.fleet_id and bt.status = 'FIGHTING') as free
    from public.pirate_ships n join public.fleets f on f.id = n.fleet_id
   where n.laid_up_at is null
),
co as (
  select p.id, coalesce((select m.level from public.house_level_marks m where m.player_id = p.id and m.track = 'trading'), 1) as trading
    from public.players p where not p.is_npc
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'early\_sighting\_%'),
  'table', to_regclass('public.early_sightings') is not null,
  'fn_absent', to_regprocedure('world.early_sighting()') is null and to_regprocedure('public.early_sighting_step(timestamp with time zone)') is null,
  'hunks', (select jsonb_object_agg(d.fn, jsonb_build_object(
                     'old', (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old),
                     'new', (length(d.def) - length(replace(d.def, d.new, ''))) / length(d.new))) from d),
  'lit', (select jsonb_object_agg(c.key, c.value) from public.world_config c
           where c.key in ('attack_enabled', 'raid_orders_enabled', 'pirates_bite', 'city_treasury_enabled', 'tick_fight_kinds',
                           'raid_company_title_min', 'ransom_share', 'insurance_keep_pct', 'raid_companies_enabled')),
  'pirates_at_work', (select count(*) from pir),
  'raiders', (select count(*) from pir where pir.rung <= 1),
  'raiders_free', (select count(*) from pir where pir.rung <= 1 and pir.free),
  'rungs', (select jsonb_object_agg(coalesce(q.rung::text, 'none'), q.n) from (select pir.rung, count(*) as n from pir group by pir.rung) q),
  'companies', (select count(*) from co),
  'eligible', (select count(*) from co where co.trading >= 3
                 and coalesce(public.title_level(co.id), 1) < coalesce((select (c.value #>> '{}')::int from public.world_config c where c.key = 'raid_company_title_min'), 3)));
rollback;
