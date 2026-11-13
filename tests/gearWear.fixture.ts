// THE SHIPPED WORLD WITH WORN FITTINGS ABOARD HER FOUNDING SHIP — the seam the browser specs use to see gear wear (0158).
//
// The build ships gear wear dark (`gear_wear_bite` false), a founding barca carries no fitting at all, and the page has no
// seam to wear one, so a spec patches a copy of the build's image (worldImage.fixture.ts carries the open / patch / dump /
// serve once): a trigger fits the founding ship through the game's own core (public.mount_fitting: two Storm canvas and
// one Boarding gear, what a new company may fit) and writes a wear on two of the three, as public.wear_units_for would
// after storms. `lit` sets the switch; dark, the same worn ship is served and the page must draw none of it.
// Used by tests/gear.wear.spec.ts.

import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

/** What the trigger leaves aboard: the wear of each unit (0 = new), and what the page should count. */
export const WORN_SHIP = {
  units: [
    { item: 'storm-canvas', wear: 62 },
    { item: 'storm-canvas', wear: 20 },
    { item: 'boarding-gear', wear: 0 },
  ],
  /** units with a wear above nothing */
  worn: 2,
  /** what the most worn works at: 1 - 62 / 200 */
  weakest: 69,
} as const

export function gearWearWorld(lit: boolean): Promise<Buffer> {
  return patchedWorldImage(lit ? 'gear-wear-lit' : 'gear-wear-dark', async (pg) => {
    await pg.exec(`
      create function public.spec_gear_wear() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $fn$
      declare
        v_n int;
      begin
        if pg_trigger_depth() > 1 then return null; end if;
        if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
        perform public.mount_fitting(new.id, 'storm-canvas');
        perform public.mount_fitting(new.id, 'storm-canvas');
        perform public.mount_fitting(new.id, 'boarding-gear');
        update public.fitted_units u set wear = w.wear
          from (select fu.id, case row_number() over (order by fu.mounted_at, fu.id) when 1 then ${WORN_SHIP.units[0].wear} else ${WORN_SHIP.units[1].wear} end as wear
                  from public.fitted_units fu where fu.ship_id = new.id and fu.item_code = 'storm-canvas') w
         where u.id = w.id;
        select count(*) into v_n from public.fitted_units fu where fu.ship_id = new.id and fu.wear > 0;
        if v_n <> ${WORN_SHIP.worn} then
          raise exception 'spec: % worn units aboard, wanted ${WORN_SHIP.worn}', v_n;
        end if;
        return null;
      end $fn$;
      create trigger spec_gear_wear after insert on public.ships
        for each row when (new.is_flagship) execute function public.spec_gear_wear();
    `)
    const r = await pg.query(`update public.world_config set value = '${lit ? 'true' : 'false'}'::jsonb where key = 'gear_wear_bite' returning key`)
    if (r.rows.length !== 1) throw new Error('world_config has no gear_wear_bite row')
  })
}

/** Serve the worn-fittings world to `page` in place of the shipped image. Call it before `page.goto`. */
export async function serveGearWearWorld(page: Page, lit: boolean): Promise<void> {
  await serveWorldImage(page, await gearWearWorld(lit))
}
