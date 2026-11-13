-- 0367 PROD CHECK (before), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/armada/before.sql
-- Run it BEFORE the deploy. It needs nothing of 0367. It answers:
--   hunks        each of the six lines 0367 cuts, and how many times it stands in the LIVE body today. Wanted: 1 in every row (0367 refuses itself otherwise, and nothing is applied).
--   speed_header how many times the header of voyage.fleet_speed_at stands in its live definition. Wanted: 1.
--   applied      whether 0367 is there already. Wanted: false.
--   switches     the owner's knobs an armada depends on, as they are: fleet_room_bite, fleet_max, fleet_hard_max, combat_bite, attack_enabled, standing_routes_enabled.
--   companies    human companies by how many fleets they hold. A company of two or more could form an armada the minute 0367 lands; docs/FLEETS_AND_SLOTS.md read every human
--                company at exactly one fleet on 2026-10-25.
--   at_sea       voyages sailing now (each rolls one more primary-key probe a day after the deploy; none changes its days).
begin transaction read only;
with h (fn, ord, old) as (values
    ('voyage.hazard_roll(uuid,integer)', 1, $h$  v_leg := voyage.leg_at_day(p_voyage, p_day);
  v_sea := (v_leg->>'sea_id')::uuid;
$h$),
    ('voyage.settle(uuid,timestamp with time zone)', 1, $h$  v_leg     jsonb;     -- 0339: the day's frozen segment, read once for its danger and its raider
$h$),
    ('voyage.settle(uuid,timestamp with time zone)', 2, $h$      v_fight := case when public.combat_bite_on() then voyage.fight(v.id, d, p_fleet, v_raider) end;
$h$),
    ('cmd.do_sail(uuid,jsonb)', 1, $h$  select * into f from public.fleets where id = p_fleet;

  -- the gates that need no distance, first (status, crew, flagship, and the berth facts)
$h$),
    ('cmd.divert(uuid,uuid,jsonb,jsonb)', 1, $h$  -- Catch up first: an act must not reason about a stale position (D.2).
  perform voyage.settle(p_fleet, v_now);
$h$),
    ('public.client_rpc_entry_points()', 1, $h$      ('cmd',         'rename_fleet',          'uuid, text'),
$h$)
)
select jsonb_build_object(
  'hunks', (select jsonb_agg(jsonb_build_object('fn', h.fn, 'hunk', h.ord,
                     'times', (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old)) order by h.fn, h.ord)
              from h cross join lateral (select replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '') as def) d),
  'speed_header', (select (length(d.def) - length(replace(d.def, 'CREATE OR REPLACE FUNCTION voyage.fleet_speed_at(', ''))) / length('CREATE OR REPLACE FUNCTION voyage.fleet_speed_at(')
                     from (select replace(pg_get_functiondef('voyage.fleet_speed_at(uuid,numeric)'::regprocedure), E'\r', '') as def) d),
  'applied', to_regclass('public.armadas') is not null,
  'switches', (select jsonb_object_agg(c.key, c.value) from public.world_config c
                where c.key in ('fleet_room_bite', 'fleet_max', 'fleet_hard_max', 'combat_bite', 'attack_enabled', 'standing_routes_enabled')),
  'companies', (select jsonb_object_agg(x.fleets, x.houses) from (
                  select n.fleets, count(*) as houses
                    from (select p.id, (select count(*) from public.fleets f where f.player_id = p.id) as fleets from public.players p where not p.is_npc) n
                   group by n.fleets) x),
  'at_sea', (select count(*) from public.voyages v where v.status = 'SAILING')) as before_0367;
commit;
