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

export function fightWorld(mine: boolean): Promise<Buffer> {
  return patchedWorldImage(mine ? 'fight-world-mine' : 'fight-world-watch', async (pg) => {
    await pg.exec(`
      update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'convoys_enabled', 'city_treasury_enabled');
      update public.world_config set value = '${FIGHT_ROUND_SECONDS}'::jsonb where key = 'battle_round_seconds';
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
export async function serveFightWorld(page: Page, mine = false): Promise<void> {
  await serveWorldImage(page, await fightWorld(mine))
}

// ── THE FIGHTS THAT ARE SETTLED IN AN INSTANT: HER OWN RAID, AND A NAVY SHIP AGAINST A PIRATE SHIP ──
// The same seam (the wrapped minute job, on its first call), the chain's own functions for everything that is judged:
//   'raid'  her fleet DEPARTS from the harbour she lies in on a two-day passage out and back that began 95 s ago (the real
//           `voyage.depart`), day 1 of HER voyages is a raid (the hazard roll alone is pinned; every other voyage rolls as
//           the chain rolls), and the real `voyage.settle` settles it: the real fight, the real log, kept by 0353 on the
//           day's own row. The map's read then finds it, a degree and a half west of her harbour's roads.
//   'navy'  a navy ship of Portugal and a pirate ship lie at Porto (made at patch time by the real `public.navy_commission`
//           and the hands every fleet is made by, as proof 48 makes them); on the first call the real `public.navy_fight`
//           fights them, and 0364's keeper keeps the fight for the map.
export function instantFightWorld(kind: 'raid' | 'navy'): Promise<Buffer> {
  return patchedWorldImage(`fight-world-${kind}`, async (pg) => {
    await pg.exec(`
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
              v_port, v_port, p_now - interval '95 seconds');
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
