// THE WORLDS THE FLEETS PAGE IS PROVEN ON (F5, 2026-11-11) — throwaway copies of this build's own image, never a real switch.
//
// The shipped world founds a company with ONE ship and fleet room dark. The Fleets page's flows need more: a fleet of two ships (a new fleet takes one of them), a purse
// that covers the first fleet price (60,000; a founding purse is 40,000), and the room lit. Each is made the way tests/twoFleets.fixture.ts makes a second fleet: the patch
// runs against a copy of the image in Node, the page is served the copy, and nothing is written to disk.
//
//   · `fleet_room_bite` is set true IN THE COPY ONLY (the same line tests/fleets.room.spec.ts and tests/fleets.move.spec.ts use);
//   · a trigger on `public.ships` commissions a second ship into the founding fleet through the chain's own door (`public.commission_ship`) when the founding flagship is
//     laid, and pays the purse through `public.credit` — a local world founds its company at boot, AFTER the image is loaded, so neither can be a row in the image.

import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

/** The second ship of the founding fleet: three words, so a tile that cut a name would show it. */
export const SECOND_SHIP = 'Andorinha do Mar'
/** What the patch adds to the founding purse. */
export const EXTRA_PURSE = 200_000

const LIGHT = `update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite'`
// 0370 lit fleet room in the shipped world, so the dark world is made here too: the switch set back in the copy (what a rollback of 0370 would show).
const DARK = `update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite'`

const SECOND_SHIP_TRIGGER = `
  create function public.spec_second_ship() returns trigger
  language plpgsql security definer set search_path = public, pg_temp as $$
  begin
    if pg_trigger_depth() > 1 then return null; end if;
    if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
    if exists (select 1 from public.ships s where s.player_id = new.player_id and s.name = '${SECOND_SHIP}') then return null; end if;
    perform public.commission_ship(new.player_id, new.fleet_id, 'barca', '${SECOND_SHIP}', false, true);
    perform public.credit(new.player_id, 'SPEC', ${EXTRA_PURSE});
    return null;
  end $$;
  create trigger spec_second_ship after insert on public.ships
    for each row when (new.is_flagship) execute function public.spec_second_ship();
`

/** Fleet room lit, a founding fleet of two ships, a purse that covers the first prices. */
export async function serveLitTwoShips(page: Page): Promise<void> {
  await serveWorldImage(
    page,
    await patchedWorldImage('fleets-page-lit-two', async (pg) => {
      await pg.exec(LIGHT)
      await pg.exec(SECOND_SHIP_TRIGGER)
    }),
  )
}

/** Fleet room DARK (the state before 0370, and after its rollback), a founding fleet of two ships: everything a lit page would offer has something to offer it on. */
export async function serveDarkTwoShips(page: Page): Promise<void> {
  await serveWorldImage(
    page,
    await patchedWorldImage('fleets-page-dark-two', async (pg) => {
      await pg.exec(DARK)
      await pg.exec(SECOND_SHIP_TRIGGER)
    }),
  )
}

/** Fleet room lit and the founding company as it is: one ship. */
export async function serveLitOneShip(page: Page): Promise<void> {
  await serveWorldImage(
    page,
    await patchedWorldImage('fleets-page-lit-one', async (pg) => {
      await pg.exec(LIGHT)
    }),
  )
}

// THE SAME FLEET WITH GOODS ABOARD (2026-11-14, tests/fleets.ships.spec.ts): the second ship is commissioned and three goods are loaded through the chain's one cargo
// mover (`public.fleet_load`), so a ship's own cargo has something to print.
const LADEN_TRIGGER = `
  create function public.spec_second_ship_laden_fleet() returns trigger
  language plpgsql security definer set search_path = public, pg_temp as $$
  declare
    g record;
  begin
    if pg_trigger_depth() > 1 then return null; end if;
    if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
    if exists (select 1 from public.ships s where s.player_id = new.player_id and s.name = '${SECOND_SHIP}') then return null; end if;
    perform public.commission_ship(new.player_id, new.fleet_id, 'barca', '${SECOND_SHIP}', false, true);
    perform public.credit(new.player_id, 'SPEC', ${EXTRA_PURSE});
    for g in select gd.code from public.goods gd order by gd.code limit 3 loop
      perform public.fleet_load(new.fleet_id, g.code, 15, 1);
    end loop;
    return null;
  end $$;
  create trigger spec_second_ship_laden_fleet after insert on public.ships
    for each row when (new.is_flagship) execute function public.spec_second_ship_laden_fleet();
`

/** Fleet room lit, a founding fleet of two ships with three goods aboard. */
export async function serveLitTwoShipsLaden(page: Page): Promise<void> {
  await serveWorldImage(
    page,
    await patchedWorldImage('fleets-page-lit-two-laden', async (pg) => {
      await pg.exec(LIGHT)
      await pg.exec(LADEN_TRIGGER)
    }),
  )
}
