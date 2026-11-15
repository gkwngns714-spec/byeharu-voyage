// THE SHIPPED WORLD WITH ONE BATTLE, OPENED WHEN THE MAP FIRST ASKS — for the map's ring spec (0364, owner row 321).
//
// Attacks ship dark (`attack_enabled` false) and the page has no seam to light them, so, like raidWorld.fixture.ts,
// this patches a COPY of the built image (tests/worldImage.fixture.ts) and leaves the chain alone:
//   * `attack_enabled`, `convoys_enabled` and `city_treasury_enabled` are LIT in the copy, the harbours' purses are
//     filled, and Spain's cargo ships exist (the real `public.tick_cargo_ships`);
//   * `battle_round_seconds` is 5, so a battle is 35 s (six rounds and the boarding) instead of 7 minutes;
//   * for the WATCHED battle a second company is founded by the real `public.new_house`, with the best-gunned hull;
//   * THE BATTLE OPENS ON THE FIRST CALL OF THE MINUTE JOB. The local backend plays that job before every read of the
//     battles on the map (src/lib/rpc/localBackend.ts), so the first `world.fights()` the map sends finds a battle that
//     began that instant: a page spec cannot know how long the boot took. The copy's `public.tick_battles` is the
//     chain's own body under another name, wrapped: on its first call one of Spain's cargo ships SAILS (the real
//     `public.cargo_ship_step`, then slowed so she is still at sea), the attacking fleet is laid at anchor a fifth of a
//     degree north of her, and the real `public.battle_open` opens the battle; every call then runs the chain's job.
//   * once the battle is over the wrapper moves ITS clock back 45 s, once: the ring is kept 60 s after the end by the
//     server (`world.fights`, keep_seconds), and a page spec should not sit through all of it. The 15 s that are left
//     are real.
// `mine` true: the attacker is the page's own company (her card, with the stance buttons). False: the second company
// (a watcher's read). Everything the page then shows is the chain's own reads of a real battle.

import type { Page } from '@playwright/test'
import { LOCAL_AUTH_UID } from '../src/lib/db/localDb'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// both names are the longest the tables take (24 letters): a name is never cut on the sheet
export const FIGHT_OTHER_UID = '00000000-0364-4000-8000-0000000000bb'
export const FIGHT_OTHER_COMPANY = 'Casa da Ronda Atlântica.'
export const FIGHT_OTHER_FLEET = 'Ronda do Estreito Largo.'
export const FIGHT_ROUND_SECONDS = 5

// EVERY BUILT WORLD HAS ITS OWN DICE (0031's world_secret), so the spec that reads these worlds may assume no outcome of a fight. SPEC_WORLD_SECRET gives the copy
// another secret, to prove that: scripts/ops/harness/fight-rings/dice.sh runs the specs under many.
const SECRET_SQL = process.env.SPEC_WORLD_SECRET
  ? `update public.world_config set value = to_jsonb('${process.env.SPEC_WORLD_SECRET.replace(/[^A-Za-z0-9_-]/g, '')}'::text) where key = 'world_secret';`
  : ''

/** `ticks` true (tests/map.battleClose.spec.ts): the battle is left a TICK battle (0435): its card has Watch, which opens the battle screen. */
export function fightWorld(mine: boolean, ticks = false): Promise<Buffer> {
  return patchedWorldImage(`${mine ? 'fight-world-mine' : 'fight-world-watch'}${ticks ? '-ticks' : ''}`, async (pg) => {
    await pg.exec(`
      ${SECRET_SQL}
      update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'convoys_enabled', 'city_treasury_enabled');
      update public.world_config set value = '${FIGHT_ROUND_SECONDS}'::jsonb where key = 'battle_round_seconds';
      ${ticks ? '' : `update public.world_config set value = '[]'::jsonb where key = 'tick_fight_kinds';   -- 0435: these specs drive the round-by-round battle`}
      insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
      update public.port_treasury set ducats = 50000000, reserve = 0;
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';
      ${mine ? '' : `select public.new_house('${FIGHT_OTHER_UID}'::uuid, '${FIGHT_OTHER_COMPANY}', 'PRT', 'LIS', '${FIGHT_OTHER_FLEET}',
               (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Ronda', null, false);`}

      create table public.spec_fight (battle uuid primary key, shifted boolean not null default false);
      revoke all on table public.spec_fight from public, anon, authenticated;
      alter function public.tick_battles(timestamp with time zone) rename to tick_battles_real_spec;
      create function public.tick_battles(p_now timestamptz default now())
      returns integer language plpgsql security definer set search_path = public, pg_temp as $$
      declare
        v_target uuid;
        v_fleet  uuid;
        v_battle uuid;
        v_n      int;
      begin
        if not exists (select 1 from public.spec_fight) then
          select f.id into v_fleet
            from public.fleets f join public.players p on p.id = f.player_id
           where not p.is_npc and p.auth_uid = '${mine ? LOCAL_AUTH_UID : FIGHT_OTHER_UID}'::uuid
           order by f.id limit 1;
          select c.fleet_id into v_target
            from public.cargo_ships c join public.nations n on n.id = c.nation_id join public.fleets f on f.id = c.fleet_id
           where n.code = 'ESP' and f.status = 'DOCKED' order by c.ord limit 1;
          if v_fleet is not null and v_target is not null then
            update public.fleets set ready_at = null where id = v_target;
            perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 100000) from public.cargo_ships c where c.fleet_id = v_target;
            perform public.cargo_ship_step(v_target, p_now);
            update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
             where vo.fleet_id = v_target and vo.status = 'SAILING';
            perform voyage.recompute_eta(vo.id) from public.voyages vo where vo.fleet_id = v_target and vo.status = 'SAILING';
            update public.ships set cargo = '{}'::jsonb${mine ? `, class_id = (select c.id from public.ship_classes c order by c.attack desc, c.code limit 1), durability = (select c.durability from public.ship_classes c order by c.attack desc, c.code limit 1)` : ''} where fleet_id = v_fleet;
            update public.fleets x set status = 'ANCHORED', port_id = null, lat = p.lat + 0.2, lon = p.lon, version = x.version + 1
              from voyage.fleet_point(v_target, p_now) p where x.id = v_fleet;
            v_battle := public.battle_open('ATTACK', v_fleet, v_target, p_now);
            ${ticks ? `-- A TICK BATTLE'S RING GOES THE MOMENT IT ENDS, and a fight may end at its first tick: its clock is held open to the boarding
            -- (tick 120, 73.2 s), as 0436's own probe holds its battle; the fight on the timeline is the chain's, untouched.
            update public.battles b set ticks = jsonb_set(b.ticks, '{n}', '120'::jsonb), resolves_at = b.started_at + interval '73.2 seconds',
                   next_round_at = b.started_at + interval '73.2 seconds' where b.id = v_battle and b.ticks is not null;
            update public.fleets f set busy_until = p_now + interval '73.2 seconds' where f.id in (v_fleet, v_target) and f.busy_until is not null;` : ''}
            insert into public.spec_fight (battle) values (v_battle);
          end if;
        end if;
        v_n := public.tick_battles_real_spec(p_now);
        update public.battles b set started_at = b.started_at - interval '45 seconds', resolves_at = b.resolves_at - interval '45 seconds'
          from public.spec_fight s where s.battle = b.id and not s.shifted and b.status <> 'FIGHTING';
        if found then
          update public.spec_fight set shifted = true;
        end if;
        return v_n;
      end $$;
      revoke all on function public.tick_battles(timestamp with time zone) from public, anon, authenticated;
    `)
  })
}

/** Serve the one-battle world to `page` in place of the shipped image. */
export async function serveFightWorld(page: Page, mine = false, ticks = false): Promise<void> {
  await serveWorldImage(page, await fightWorld(mine, ticks))
}

// ── THE FIGHTS THAT ARE SETTLED IN AN INSTANT: HER OWN RAID, AND A NAVY SHIP AGAINST A PIRATE SHIP ──
// The same seam (the wrapped minute job, on its first call), the chain's own functions for everything that is judged:
//   'raid'  her fleet DEPARTS from the harbour she lies in on a two-day passage out and back that began one voyage-day and 5 s ago
//           (24 sim-hours at the served time_compression: 450 s since 0413, 90 s before it; it was a fixed 95 s, which 0413 left short of day 1) (the real
//           `voyage.depart`), day 1 of HER voyages is a raid (the hazard roll alone is pinned; every other voyage rolls as
//           the chain rolls), and the real `voyage.settle` settles it: the real fight, the real log, kept by 0353 on the
//           day's own row. The map's read then finds it, a degree and a half west of her harbour's roads.
//   'navy'  a navy ship of Portugal and a pirate ship lie at Porto (made at patch time by the real `public.navy_commission`
//           and the hands every fleet is made by, as proof 48 makes them); on the first call the real `public.navy_fight`
//           fights them, and 0364's keeper keeps the fight for the map.
export function instantFightWorld(kind: 'raid' | 'navy'): Promise<Buffer> {
  return patchedWorldImage(`fight-world-${kind}`, async (pg) => {
    await pg.exec(`
      ${SECRET_SQL}
      update public.world_config set value = 'true'::jsonb where key in ('combat_bite', 'city_treasury_enabled', 'navy_enabled', 'pirates_bite');
      insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
      update public.port_treasury set ducats = 50000000, reserve = 0;
      update public.ports set crew_pool = 2000;
      create table public.spec_instant (done boolean primary key);
      revoke all on table public.spec_instant from public, anon, authenticated;
      create table public.spec_navy (navy uuid, pirate uuid);
      revoke all on table public.spec_navy from public, anon, authenticated;

      alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_spec;
      create function voyage.hazard_roll(p_voyage uuid, p_day integer)
      returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
      language plpgsql stable security definer set search_path = public, pg_temp as $$
      begin
        if ${kind === 'raid' ? 'true' : 'false'} and p_day = 1 and exists (select 1 from public.voyages v join public.players p on p.id = v.player_id
                                   where v.id = p_voyage and p.auth_uid = '${LOCAL_AUTH_UID}'::uuid) then
          return query select true, 'PIRATES'::text, 0.5::numeric, 1::numeric;
        else
          return query select * from voyage.hazard_roll_real_spec(p_voyage, p_day);
        end if;
      end $$;

      ${kind === 'navy' ? `
      do $$
      declare
        v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
        v_cap  uuid := public.realm_capital((select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT'));
        v_port uuid := (select p.id from public.ports p where p.code = 'OPO');
        v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
        v_n    uuid;
        v_pl   uuid;
        v_p    uuid;
      begin
        insert into public.navy_realms (nation_id, ships, read_at) values (v_nat, 25, now()) on conflict (nation_id) do update set ships = 25, read_at = now();
        v_n := public.navy_commission(v_nat, 1, v_cap, public.refit_yard(v_cap), v_port, now());
        update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_n;
        insert into public.players (company_name, nation_id, ducats, is_npc) values ('Brethren 1', v_pir, 0, true) returning id into v_pl;
        v_p := public.form_fleet(v_pl, 'Pirate ship 1', v_port);
        perform public.commission_ship(v_pl, v_p, public.wc_text('pirate_ship_class'), 'Pirate ship 1', true, false);
        update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_p;
        insert into public.pirate_ships (fleet_id, player_id, ord, home_port, sea_id, mission, haunt_port, last_port, created_at)
        values (v_p, v_pl, 1, (select p.id from public.ports p where p.code = 'POR'), (select p.sea_id from public.ports p where p.id = v_port), 'CRUISE', v_port, v_port, now());
        insert into public.spec_navy values (v_n, v_p);
      end $$;` : ''}

      alter function public.tick_battles(timestamp with time zone) rename to tick_battles_real_spec;
      create function public.tick_battles(p_now timestamptz default now())
      returns integer language plpgsql security definer set search_path = public, pg_temp as $$
      declare
        v_fleet uuid;
        v_port  uuid;
        v_lat   numeric;
        v_lon   numeric;
        r       record;
      begin
        if not exists (select 1 from public.spec_instant) then
          ${kind === 'raid' ? `
          select f.id, f.port_id into v_fleet, v_port
            from public.fleets f join public.players p on p.id = f.player_id
           where p.auth_uid = '${LOCAL_AUTH_UID}'::uuid and f.status = 'DOCKED' order by f.id limit 1;
          if v_fleet is not null then
            select r2.roadstead_lat, r2.roadstead_lon into v_lat, v_lon from public.sea_reaches r2 where r2.port_id = v_port limit 1;
            update public.fleets f set ready_at = null where f.id = v_fleet;
            perform voyage.depart(v_fleet,
              jsonb_build_array(
                jsonb_build_object('a', jsonb_build_array(v_lat, v_lon), 'b', jsonb_build_array(v_lat, v_lon - 1.5), 'nm', voyage.fleet_speed(v_fleet) * 24,
                                   'sea_id', (select p.sea_id from public.ports p where p.id = v_port), 'hazard_mult', 1),
                jsonb_build_object('a', jsonb_build_array(v_lat, v_lon - 1.5), 'b', jsonb_build_array(v_lat, v_lon), 'nm', voyage.fleet_speed(v_fleet) * 24,
                                   'sea_id', (select p.sea_id from public.ports p where p.id = v_port), 'hazard_mult', 1)),
              v_port, v_port, p_now - make_interval(secs => (24 * 3600 / public.wc_num('time_compression') + 5)::double precision));
            perform voyage.settle(v_fleet, p_now);
            insert into public.spec_instant values (true);
          end if;` : `
          if exists (select 1 from public.players p where p.auth_uid = '${LOCAL_AUTH_UID}'::uuid) then
            for r in select s.navy, s.pirate from public.spec_navy s loop
              perform voyage.settle(r.navy, p_now);
              perform voyage.settle(r.pirate, p_now);
              perform public.navy_fight(r.navy, r.pirate, p_now);
            end loop;
            insert into public.spec_instant values (true);
          end if;`}
        end if;
        return public.tick_battles_real_spec(p_now);
      end $$;
      revoke all on function public.tick_battles(timestamp with time zone) from public, anon, authenticated;
    `)
  })
}

/** Serve the world with one raid on her own fleet, or one navy fight, to `page` in place of the shipped image. */
export async function serveInstantFightWorld(page: Page, kind: 'raid' | 'navy'): Promise<void> {
  await serveWorldImage(page, await instantFightWorld(kind))
}

// ── A RAID AS PROD FIGHTS IT (read 2026-11-15): THE RAIDER LIES IN HER PORT, THE SHIP SET UPON IS UNDER SAIL ──
// The same seam. On the first call of the minute job one of Spain's cargo ships SAILS (at an eighth of her pace, so a short hop lasts:
// she is still seen to move, and then to stand) and a pirate ship is made in a harbour 60 to 180 nm from her (the hands the navy world
// above makes one by: she is DOCKED there, as every raider prod's read found). On the first call RAID_OPENS_AFTER_S later
// (the map has both ships by then, as it has prod's) the real `public.battle_open` opens the
// RAID. It is a TICK battle (0435); `fight_ranges` are the chain's, so its clock is held open to the boarding (73 s) whatever the dice say. The battle is
// then left to the chain: the minute job or `cmd.battle_end` closes it. tests/map.fightStill.spec.ts reads it.
export const RAID_PIRATE_FLEET = 'Black Squall'
/** The raid opens this long after the ship sailed: the map's roster (asked every 30 s) has her under sail by then. */
export const RAID_OPENS_AFTER_S = 50

export function raidTickWorld(): Promise<Buffer> {
  return patchedWorldImage('fight-world-raid-tick', async (pg) => {
    await pg.exec(`
      ${SECRET_SQL}
      update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'convoys_enabled', 'city_treasury_enabled', 'pirates_bite');
      -- the map's roster of the world's ships is served (world.sea_roster is gated by both switches), and no merchant is started
      update public.world_config set value = '0'::jsonb where key = 'npc_fleet_max';
      update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
      insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
      update public.port_treasury set ducats = 50000000, reserve = 0;
      update public.ports set crew_pool = 2000;
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';

      create table public.spec_fight (one boolean primary key default true, battle uuid, pirate uuid, target uuid, sailed_at timestamptz);
      revoke all on table public.spec_fight from public, anon, authenticated;
      alter function public.tick_battles(timestamp with time zone) rename to tick_battles_real_spec;
      create function public.tick_battles(p_now timestamptz default now())
      returns integer language plpgsql security definer set search_path = public, pg_temp as $$
      declare
        v_target uuid;
        v_port   uuid;
        v_pl     uuid;
        v_p      uuid;
        v_battle uuid;
        s        public.spec_fight%rowtype;
      begin
        select * into s from public.spec_fight;
        if s.one is null and exists (select 1 from public.players p where p.auth_uid = '${LOCAL_AUTH_UID}'::uuid) then
          -- FIRST CALL: the ship sails and the raider lies in her harbour, so the map has both before any fight
          select c.fleet_id into v_target
            from public.cargo_ships c join public.nations n on n.id = c.nation_id join public.fleets f on f.id = c.fleet_id
           where n.code = 'ESP' and f.status = 'DOCKED' order by c.ord limit 1;
          if v_target is not null then
            update public.fleets set ready_at = null where id = v_target;
            perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 100000) from public.cargo_ships c where c.fleet_id = v_target;
            perform public.cargo_ship_step(v_target, p_now);
            -- an eighth of her pace: her hop may be a short one, and she must still be at sea when the raid opens and ends; she is still seen to move
            update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 8) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
             where vo.fleet_id = v_target and vo.status = 'SAILING';
            perform voyage.recompute_eta(vo.id) from public.voyages vo where vo.fleet_id = v_target and vo.status = 'SAILING';
            -- the raider's harbour: the nearest one 60 to 240 nm from the ship's own (attack_reach_nm is 240)
            select p.id into v_port
              from public.ports p cross join voyage.fleet_point(v_target, p_now) pt
             where p.kind = 'HARBOUR'
               and voyage.gc_distance_nm(pt.lat::float8, pt.lon::float8, p.lat::float8, p.lon::float8) between 60 and 180
             order by voyage.gc_distance_nm(pt.lat::float8, pt.lon::float8, p.lat::float8, p.lon::float8) limit 1;
            insert into public.players (company_name, nation_id, ducats, is_npc) values ('Brethren 1', (select n.id from public.nations n where n.code = 'PIR'), 0, true) returning id into v_pl;
            v_p := public.form_fleet(v_pl, '${RAID_PIRATE_FLEET}', v_port);
            perform public.commission_ship(v_pl, v_p, public.wc_text('pirate_ship_class'), '${RAID_PIRATE_FLEET}', true, false);
            update public.ships sh set crew = c.crew_required from public.ship_classes c where c.id = sh.class_id and sh.fleet_id = v_p;
            insert into public.pirate_ships (fleet_id, player_id, ord, home_port, sea_id, mission, haunt_port, last_port, created_at)
            values (v_p, v_pl, 1, v_port, (select p.sea_id from public.ports p where p.id = v_port), 'CRUISE', v_port, v_port, p_now);
            update public.fleets set ready_at = null where id = v_p;
            insert into public.spec_fight (pirate, target, sailed_at) values (v_p, v_target, p_now);
          end if;
        elsif s.battle is null and s.sailed_at <= p_now - interval '${RAID_OPENS_AFTER_S} seconds' then
          -- LATER: the raid opens. THE DICE DO NOT SET HOW LONG THE SPEC HAS: the battle's clock is held open to the boarding
          -- (tick 120, 73.2 s), as 0436's own probe holds its battle; the fight on the timeline is the chain's, untouched.
          v_battle := public.battle_open('RAID', s.pirate, s.target, p_now);
          update public.battles b set ticks = jsonb_set(b.ticks, '{n}', '120'::jsonb), resolves_at = b.started_at + interval '73.2 seconds',
                 next_round_at = b.started_at + interval '73.2 seconds' where b.id = v_battle;
          update public.fleets f set busy_until = p_now + interval '73.2 seconds' where f.id in (s.pirate, s.target);
          update public.spec_fight set battle = v_battle;
        end if;
        return public.tick_battles_real_spec(p_now);
      end $$;
      revoke all on function public.tick_battles(timestamp with time zone) from public, anon, authenticated;
    `)
  })
}

/** Serve the world with one raid fought as prod fights it to `page` in place of the shipped image. */
export async function serveRaidTickWorld(page: Page): Promise<void> {
  await serveWorldImage(page, await raidTickWorld())
}
