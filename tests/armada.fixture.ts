import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// A COMPANY OF TWO FLEETS IN ONE PORT, for the armada specs (0367, docs/ARMADA.md). The shipped world founds a company with one fleet of one ship, and while fleet room is
// dark (the real state) no player can start a second fleet. An armada needs two, so this patch gives the founding company a second fleet at the founding port, with one
// crewed ship, and a purse that covers both fleets' supplies. Nothing about armadas is patched: the switch, the knobs and every door are the shipped ones.

/** The second fleet's name: three words, so a row that cut a name would show it. */
export const SECOND_FLEET = 'Frota do Sul'
/** What the patch adds to the founding purse. */
export const EXTRA_PURSE = 200_000

export const SECOND_FLEET_SQL = `
  create function public.spec_armada_second_fleet() returns trigger
  language plpgsql security definer set search_path = public, pg_temp as $$
  declare
    v_port  uuid;
    v_fleet uuid;
  begin
    if pg_trigger_depth() > 1 then return null; end if;
    if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
    if exists (select 1 from public.fleets f where f.player_id = new.player_id and f.name = '${SECOND_FLEET}') then return null; end if;
    select f.port_id into v_port from public.fleets f where f.id = new.fleet_id;
    v_fleet := public.form_fleet(new.player_id, '${SECOND_FLEET}', v_port);
    perform public.commission_ship(new.player_id, v_fleet, 'barca', 'Andorinha do Sul', true, true);
    perform public.credit(new.player_id, 'SPEC', ${EXTRA_PURSE});
    return null;
  end $$;
  create trigger spec_armada_second_fleet after insert on public.ships
    for each row when (new.is_flagship) execute function public.spec_armada_second_fleet();
`

/** Serve the two-fleet world to `page` in place of the shipped image. */
export async function serveArmadaWorld(page: Page): Promise<void> {
  await serveWorldImage(
    page,
    await patchedWorldImage('armada-two-fleets', async (pg) => {
      await pg.exec(SECOND_FLEET_SQL)
    }),
  )
}
