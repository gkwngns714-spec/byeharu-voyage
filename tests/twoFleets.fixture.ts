// THE SHIPPED WORLD WHERE THE HOUSE FOUNDS WITH TWO FLEETS — for the fleet picker's specs.
//
// A local world founds its house at boot (`public.new_house`, src/lib/db/localDb.ts), AFTER the
// image is loaded, so a second fleet cannot simply be a row in the image: there is no player yet.
// The patch leaves a trigger on `public.ships` instead. When the founding flagship is commissioned
// (the last insert of `new_house`), it forms a second fleet for the same house at the same harbour
// through the chain's own doors — `public.form_fleet` and `public.commission_ship`, the one fleet
// insert and the one ship insert (0096) — and leaves ONE refused order in that fleet's queue, so the
// second fleet is served "stuck" (a `failed` row, the record 0186 keeps until it is dismissed).
//
// Merchants are not touched (`is_npc`), and the trigger returns at depth 2 so the second fleet's own
// flagship does not form a third. The chain fingerprint inside the image is untouched.

import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

export const SECOND_FLEET = 'Segunda'

export function twoFleets(): Promise<Buffer> {
  return patchedWorldImage('two-fleets', async (pg) => {
    await pg.exec(`
      create function public.spec_second_fleet() returns trigger
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
        perform public.commission_ship(new.player_id, v_fleet, 'barca', '${SECOND_FLEET}', true, true);
        insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status, error_code, error_message)
        values (v_fleet, new.player_id, 1, 'SAIL ${SECOND_FLEET} TO CAD', 'SAIL', '{"to":"CAD"}'::jsonb,
                'failed', 'E_NO_CREW', '${SECOND_FLEET} has nobody to sail her.');
        return null;
      end $$;
      create trigger spec_second_fleet after insert on public.ships
        for each row when (new.is_flagship) execute function public.spec_second_fleet();
    `)
  })
}

/** Serve the two-fleet world to `page` in place of the shipped image. */
export async function serveTwoFleets(page: Page): Promise<void> {
  await serveWorldImage(page, await twoFleets())
}
