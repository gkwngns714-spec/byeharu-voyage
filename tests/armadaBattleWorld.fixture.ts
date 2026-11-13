// THE SHIPPED WORLD WITH ONE BATTLE STARTED BY AN ARMADA OF SIX (the owner's number), OPENED WHEN THE MAP FIRST ASKS — for the armada's
// battle spec (0379, docs/ARMADA.md section 7, owner row 323).
//
// The same seam as tests/fightWorld.fixture.ts (which says why): attacks ship dark, so a COPY of the built image is
// patched and the chain is left alone. In the copy `attack_enabled`, `convoys_enabled` and `city_treasury_enabled` are
// lit, a company may keep seven fleets (`fleet_max`: the shipped two leave no room for an armada of six), a round is
// ARMADA_ROUND_SECONDS (so the page has time to press a stance), and the copy's `public.tick_battles`
// is the chain's own body under another name, wrapped. On its FIRST call:
//   · one of Spain's cargo ships SAILS with gold aboard (the real `public.cargo_ship_step`, then slowed);
//   · the page's own company gets a warship in her fleet and FIVE MORE FLEETS, each with a warship, made by the hands
//     every fleet is made by (`public.form_fleet`, `public.commission_ship`); all six lie docked in the cargo ship's
//     home port, so the six fleets and the ship are close together on the glass and the ring's size is the count's;
//   · the six fleets are formed into an armada by 0367's own core (`public.armada_form_for`);
//   · the real `public.battle_open` opens the battle for her FIRST fleet. 0379 puts her five sisters on her side.
// Everything the page then shows is the chain's own reads of that real battle. The fleets' and the armada's names are
// the longest the tables take (24 letters): a name is never cut on the sheet.

import type { Page } from '@playwright/test'
import { LOCAL_AUTH_UID } from '../src/lib/db/localDb'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

export const ARMADA_NAME = 'Armada Real do Mar Largo'
export const ARMADA_SISTERS = ['Esquadra do Mar do Norte', 'Guarda da Costa Dourada.', 'Ronda do Estreito Largo.', 'Vigia do Golfo de Cádiz.', 'Patrulha do Mar da Palha'] as const
export const ARMADA_ROUND_SECONDS = 10

export function armadaBattleWorld(): Promise<Buffer> {
  return patchedWorldImage('armada-battle-world', async (pg) => {
    await pg.exec(`
      update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'convoys_enabled', 'city_treasury_enabled');
      update public.world_config set value = '${ARMADA_ROUND_SECONDS}'::jsonb where key = 'battle_round_seconds';
      update public.world_config set value = '7'::jsonb where key = 'fleet_max';
      insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
      update public.port_treasury set ducats = 50000000, reserve = 0;
      update public.ports set crew_pool = 2000;
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';
      select public.tick_cargo_ships(now(), n.id) from public.nations n where n.code = 'ESP';

      create table public.spec_fight (battle uuid primary key, shifted boolean not null default false);
      revoke all on table public.spec_fight from public, anon, authenticated;
      alter function public.tick_battles(timestamp with time zone) rename to tick_battles_real_spec;
      create function public.tick_battles(p_now timestamptz default now())
      returns integer language plpgsql security definer set search_path = public, pg_temp as $$
      declare
        v_target uuid;
        v_fleet  uuid;
        v_pl     uuid;
        v_port   uuid;
        v_s      uuid;
        v_all    jsonb;
        v_names  text[] := array[${ARMADA_SISTERS.map((n) => `'${n}'`).join(', ')}];
        k        int;
        v_guns   text := (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1);
        v_battle uuid;
        v_n      int;
      begin
        if not exists (select 1 from public.spec_fight) then
          select f.id, f.player_id into v_fleet, v_pl
            from public.fleets f join public.players p on p.id = f.player_id
           where not p.is_npc and p.auth_uid = '${LOCAL_AUTH_UID}'::uuid
           order by f.id limit 1;
          select c.fleet_id, c.home_port_id into v_target, v_port
            from public.cargo_ships c join public.nations n on n.id = c.nation_id join public.fleets f on f.id = c.fleet_id
           where n.code = 'ESP' and f.status = 'DOCKED' order by c.ord limit 1;
          if v_fleet is not null and v_target is not null then
            update public.fleets set ready_at = null where id = v_target;
            perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, 100000) from public.cargo_ships c where c.fleet_id = v_target;
            perform public.cargo_ship_step(v_target, p_now);
            update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
             where vo.fleet_id = v_target and vo.status = 'SAILING';
            perform voyage.recompute_eta(vo.id) from public.voyages vo where vo.fleet_id = v_target and vo.status = 'SAILING';
            -- her fleet: a warship, an empty hold, docked in the cargo ship's home port; and her two sisters beside her
            update public.ships set cargo = '{}'::jsonb, class_id = (select c.id from public.ship_classes c where c.code = v_guns),
                                    durability = (select c.durability from public.ship_classes c where c.code = v_guns) where fleet_id = v_fleet;
            update public.fleets x set status = 'DOCKED', port_id = v_port, lat = null, lon = null, ready_at = null, version = x.version + 1 where x.id = v_fleet;
            v_all := jsonb_build_array(v_fleet);
            for k in 1 .. array_length(v_names, 1) loop
              v_s := public.form_fleet(v_pl, v_names[k], v_port);
              perform public.commission_ship(v_pl, v_s, v_guns, 'Nau ' || k, true, true);
              update public.fleets set created_at = created_at + make_interval(secs => k) where id = v_s;   -- made one after another: the armada's order reads it
              v_all := v_all || to_jsonb(v_s);
            end loop;
            perform public.armada_form_for(v_pl, v_all, '${ARMADA_NAME}');
            v_battle := public.battle_open('ATTACK', v_fleet, v_target, p_now);
            insert into public.spec_fight (battle) values (v_battle);
          end if;
        end if;
        v_n := public.tick_battles_real_spec(p_now);
        return v_n;
      end $$;
      revoke all on function public.tick_battles(timestamp with time zone) from public, anon, authenticated;
    `)
  })
}

/** Serve the armada's-battle world to `page` in place of the shipped image. */
export async function serveArmadaBattleWorld(page: Page): Promise<void> {
  await serveWorldImage(page, await armadaBattleWorld())
}
