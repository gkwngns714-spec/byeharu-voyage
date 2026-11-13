// THE SHIPPED WORLD, LIT FOR AN ATTACK SHE STARTS HERSELF — for tests/battle.live.spec.ts (owner row 324: the battle driven in a real browser before `attack_enabled` is lit).
//
// Attacks ship dark and the page has no seam to light them, so, like fightWorld.fixture.ts, this patches a COPY of the built image (tests/worldImage.fixture.ts) and leaves the
// chain alone. The difference from fightWorld: there the battle is opened by the fixture; HERE THE PAGE OPENS IT, by the real press (a cargo ship's card, Attack). So the copy is
// the world as production will be when attacks are lit, and nothing of the fight is pinned:
//   * LIT in the copy: `attack_enabled`, `convoys_enabled`, `convoy_armed_enabled` (the armed navire), `city_treasury_enabled`, `navy_enabled`, `regard_enabled`,
//     `npc_ship_level_enabled` (crown hulls at level 5, written by the real `public.crown_hull_level_fix`), and `npc_traders_enabled` with `npc_fleet_max` 0: the sea then
//     serves the crown's ships to the map (world.sea_roster is gated by that switch and by `standing_routes_enabled`) and no merchant is started;
//   * `battle_round_seconds` is 5, so a battle is 35 s (six rounds and the boarding) instead of 7 minutes;
//   * Spain's cargo ships exist (the real `public.tick_cargo_ships`), and ONE NAVY SHIP of Spain (the real `public.navy_commission`) lies at the harbour whose passage to
//     the harbour nearest the cargo ship is nearest to two and a half rounds (and never under a round and a half, nor over five and a half): the real `public.navy_call` then calls her at the press and she comes up in a LATER round by
//     her own sailing (the real `public.navy_reinforce`);
//   * THE SCENE IS LAID ON THE FIRST CALL OF A JOB THE LOCAL BACKEND PLAYS (`public.tick_arrivals` before a read of the sea's hulls, `public.tick_battles` before a read of the
//     map's fights, as fightWorld's does), because a page spec cannot know how long the boot took: one of Spain's cargo ships SAILS with 100,000 aboard (the real `public.cargo_ship_step`, hands from the quay, then slowed so
//     she is still at sea), and the page's own fleet is laid at anchor in open water near her with guns and an empty hold. Her voyage's own days, and the navy ship's, are quiet (no storm, no raid: `voyage.hazard_roll` answers a quiet day for THOSE voyages alone), so only the battle rolls. Then the job is the chain's own.
//   * once her battle is over the wrapper gives the cargo ship her speed back, once (so the spec can see the held ship arrive), and nothing else.
// `kind`:
//   'board'  her fleet is two of the strongest hulls with full complements. No roll can break her off (her 15 % is more than the two ships she fights can fire in six rounds) and
//            no boarding can go the other way; `fight_evade_per_sighting` is 0 in this copy, so the cargo ship cannot slip away before the first round. So the battle is fought to
//            the boarding under ANY world's dice. `loot_risk_floor` is 0.2 in this copy (0374: the least share of the loot a won fight pays; 0 as shipped), so gold is
//            taken even in a world whose dice let no shot of the other side land.
//   'flee'   one such hull, and `fight_flee_floor` 1 with `fight_evade_max` 1: docs/COMBAT_LOG.md 3.3, "one knob floor at 1.0 gives 5.2's rule back": a side that runs gets away
//            for certain after the round's fire. So a Flee is a break-off under ANY world's dice.
// Everything the page then shows is the chain's own reads of a real battle. SPEC_WORLD_SECRET gives the copy another world's dice (scripts/ops/harness/attacks/dice.mjs).

import type { Page } from '@playwright/test'
import { LOCAL_AUTH_UID } from '../src/lib/db/localDb'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

export const BATTLE_ROUND_SECONDS = 5
export const BATTLE_ABOARD = 100_000

const SECRET_SQL = process.env.SPEC_WORLD_SECRET
  ? `update public.world_config set value = to_jsonb('${process.env.SPEC_WORLD_SECRET.replace(/[^A-Za-z0-9_-]/g, '')}'::text) where key = 'world_secret';`
  : ''

export function battleWorld(kind: 'board' | 'flee'): Promise<Buffer> {
  return patchedWorldImage(`battle-world-${kind}`, async (pg) => {
    await pg.exec(`
      ${SECRET_SQL}
      update public.world_config set value = 'true'::jsonb
       where key in ('attack_enabled', 'convoys_enabled', 'convoy_armed_enabled', 'city_treasury_enabled', 'navy_enabled', 'regard_enabled', 'npc_ship_level_enabled');
      update public.world_config set value = '${BATTLE_ROUND_SECONDS}'::jsonb where key = 'battle_round_seconds';
      update public.world_config set value = '0'::jsonb where key = 'npc_fleet_max';
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
      ${kind === 'flee'
        ? `update public.world_config set value = '1'::jsonb where key in ('fight_flee_floor', 'fight_evade_max');`
        : `update public.world_config set value = '0'::jsonb where key = 'fight_evade_per_sighting';
           update public.world_config set value = '0.2'::jsonb where key = 'loot_risk_floor';`}
      insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
      update public.port_treasury set ducats = 50000000, reserve = 0;
      update public.ports set crew_pool = 2000;
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';

      -- ONE NAVY SHIP OF SPAIN, lying where her passage to the capital takes about two and a half rounds
      do $$
      declare
        v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'ESP');
        v_cap  uuid;
        v_n    uuid;
      begin
        v_cap := public.realm_capital(v_nat);
        insert into public.navy_realms (nation_id, ships, read_at) values (v_nat, 25, now()) on conflict (nation_id) do update set ships = 25, read_at = now();
        v_n := public.navy_commission(v_nat, 1, v_cap, public.refit_yard(v_cap), v_cap, now());
        update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_n;
      end $$;
      select public.crown_hull_level_fix();

      create table public.spec_battle (target uuid primary key, released boolean not null default false);
      alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_spec;
      create function voyage.hazard_roll(p_voyage uuid, p_day integer)
      returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
      language plpgsql stable security definer set search_path = public, pg_temp as $q$
      begin
        if exists (select 1 from public.voyages v join public.spec_battle s on s.target = v.fleet_id where v.id = p_voyage)
           or exists (select 1 from public.voyages v join public.navy_ships n on n.fleet_id = v.fleet_id where v.id = p_voyage) then
          return query select false, null::text, 0::numeric, 0::numeric;
        else
          return query select * from voyage.hazard_roll_real_spec(p_voyage, p_day);
        end if;
      end $q$;
      revoke all on table public.spec_battle from public, anon, authenticated;
      create function public.spec_battle_step(p_now timestamptz)
      returns void language plpgsql security definer set search_path = public, pg_temp as $$
      declare
        v_target uuid;
        v_fleet  uuid;
        v_player uuid;
        v_class  text := (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1);
        v_to     uuid;
        v_navy   uuid;
        v_at     uuid;
      begin
        if not exists (select 1 from public.spec_battle) then
          select f.id, f.player_id into v_fleet, v_player
            from public.fleets f join public.players p on p.id = f.player_id
           where not p.is_npc and p.auth_uid = '${LOCAL_AUTH_UID}'::uuid
           order by f.id limit 1;
          select c.fleet_id into v_target
            from public.cargo_ships c join public.nations n on n.id = c.nation_id join public.fleets f on f.id = c.fleet_id
           where n.code = 'ESP' and f.status = 'DOCKED' order by c.ord limit 1;
          if v_fleet is not null and v_target is not null then
            update public.fleets set ready_at = null where id = v_target;
            perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, ${BATTLE_ABOARD}) from public.cargo_ships c where c.fleet_id = v_target;
            perform public.cargo_ship_step(v_target, p_now);
            update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
             where vo.fleet_id = v_target and vo.status = 'SAILING';
            -- ... and already three seconds of her own sailing down her leg (300 s at a hundredth of her speed): her hull stands clear of the harbour she left, and that harbour
            -- stays the one nearest her for the whole test (half-way down the leg the nearest harbour flips to the one she is bound for, and the navy's call goes there)
            update public.voyages vo set departed_at = p_now - interval '300 seconds' where vo.fleet_id = v_target and vo.status = 'SAILING';
            perform voyage.recompute_eta(vo.id) from public.voyages vo where vo.fleet_id = v_target and vo.status = 'SAILING';
            -- her fleet: guns, full complements, an empty hold, at anchor in open water four tenths of a degree west of the harbour the cargo ship is bound for
            update public.ships s set cargo = '{}'::jsonb, class_id = k.id, durability = k.durability from public.ship_classes k where k.code = v_class and s.fleet_id = v_fleet;
            ${kind === 'board' ? `perform public.commission_ship(v_player, v_fleet, v_class, 'Santa Ana', false, true);` : ''}
            update public.ships s set crew = k.crew_max, durability = (select b.durability from public.ship_base(s.id) b) from public.ship_classes k where k.id = s.class_id and s.fleet_id = v_fleet;
            update public.fleets x set status = 'ANCHORED', port_id = null, lat = (vo.path -> -1 -> 'b' ->> 0)::numeric, lon = (vo.path -> -1 -> 'b' ->> 1)::numeric - 0.4
              from public.voyages vo where vo.fleet_id = v_target and vo.status = 'SAILING' and x.id = v_fleet;
            -- THE NAVY SHIP lies where her own passage to the harbour nearest the cargo ship (where public.navy_call sends her) takes about two and a half rounds: she comes up in a later round
            select public.harbour_nearest(p.lat::double precision, p.lon::double precision) into v_to from voyage.fleet_point(v_target, p_now) p;
            select n.fleet_id into v_navy from public.navy_ships n join public.nations x on x.id = n.nation_id where x.code = 'ESP' order by n.ord limit 1;
            select q.id into v_at
              from public.ports q cross join lateral (select public.navy_leg_seconds(v_navy, q.id, v_to) as s) l
             where q.kind = 'HARBOUR' and q.id <> v_to and l.s between ${BATTLE_ROUND_SECONDS * 1.4} and ${BATTLE_ROUND_SECONDS * 5.4}
             order by abs(l.s - ${BATTLE_ROUND_SECONDS * 2.5}), q.code limit 1;
            if v_at is null then
              raise exception 'battleWorld: no harbour lies between round 2 and round 6 of sailing from the harbour nearest the cargo ship';
            end if;
            update public.fleets f set port_id = v_at, ready_at = null where f.id = v_navy;
            update public.navy_ships n set station_port = v_at, last_port = v_at where n.fleet_id = v_navy;
            insert into public.spec_battle (target) values (v_target);
          end if;
        end if;
        -- her battle is over: the cargo ship has her speed back, once, so she is seen to arrive
        if exists (select 1 from public.spec_battle s join public.battle_sides bs on bs.fleet_id = s.target join public.battles b on b.id = bs.battle_id where not s.released and b.status <> 'FIGHTING') then
          update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric * 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
            from public.spec_battle s where vo.fleet_id = s.target and vo.status = 'SAILING';
          perform voyage.recompute_eta(vo.id) from public.voyages vo join public.spec_battle s on s.target = vo.fleet_id where vo.status = 'SAILING';
          -- ... and three seconds of sea left: an arrival is told to the map by an eta that falls AFTER its last read (world.sea_roster's own rule), never by one long past
          update public.voyages vo set departed_at = vo.departed_at + ((p_now + interval '3 seconds') - vo.eta), eta = p_now + interval '3 seconds'
            from public.spec_battle s where vo.fleet_id = s.target and vo.status = 'SAILING';
          perform voyage.recompute_eta(vo.id) from public.voyages vo join public.spec_battle s on s.target = vo.fleet_id where vo.status = 'SAILING';
          update public.spec_battle set released = true;
        end if;
      end $$;
      revoke all on function public.spec_battle_step(timestamp with time zone) from public, anon, authenticated;
      -- the two jobs the local backend plays (before a read of the sea's hulls, and before a read of the map's fights): each lays the scene first, then is the chain's own
      alter function public.tick_battles(timestamp with time zone) rename to tick_battles_real_spec;
      create function public.tick_battles(p_now timestamptz default now())
      returns integer language plpgsql security definer set search_path = public, pg_temp as $$
      begin
        perform public.spec_battle_step(p_now);
        return public.tick_battles_real_spec(p_now);
      end $$;
      revoke all on function public.tick_battles(timestamp with time zone) from public, anon, authenticated;
      alter function public.tick_arrivals(timestamp with time zone) rename to tick_arrivals_real_spec;
      create function public.tick_arrivals(p_now timestamptz default now())
      returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
      begin
        perform public.spec_battle_step(p_now);
        return public.tick_arrivals_real_spec(p_now);
      end $$;
      revoke all on function public.tick_arrivals(timestamp with time zone) from public, anon, authenticated;
    `)
  })
}

/** Serve the lit world to `page` in place of the shipped image. */
export async function serveBattleWorld(page: Page, kind: 'board' | 'flee'): Promise<void> {
  await serveWorldImage(page, await battleWorld(kind))
}
