// THE SHIPPED WORLD WHERE THE HOUSE FOUNDS WITH THREE REAL CAPTAINS SEATED — for the captain's sheet (0337, docs/WORLD_POWERS.md 2.4).
//
// A local world founds its house at boot (`public.new_house`, src/lib/db/localDb.ts), AFTER the image is loaded, so a captain cannot simply be a row in the image: there is
// no player yet. The patch leaves a trigger on `public.ships`, as tests/twoFleets.fixture.ts does. When the founding flagship is commissioned (the last insert of `new_house`),
// it signs three captains into that fleet through the game's own door (`public.sign_officer`, which seats each in a cabin by `public.captain_seat_pick` and pays her wage from the
// house's purse) and sets what each uses through `public.captain_traits_set_for`. Nothing is stubbed: `world.captains` and `world.captain_stats` answer from the real tables.
//
// WHO SITS WHERE (the founding Barca has three cabins: 1 the Captain's, 2 Trading, 3 Exploration), and what she adds. Each is an S captain, so every trait is at her kit's base
// (9 % for her job, 5.4 % for the others); the company is level 1 in every track and levels_bite is off in the shipped chain, so a level multiplies nothing; her cabin is her job's
// own (or the Captain's), so it takes nothing off. The figures are MEASURED from data/officers.json and public.captain_traits, then pinned here (docs/NO_SPAGHETTI.md section 6):
//   TURGUT   Boarder (combat)        Captain's cabin   BOARDER 9, GUNNER 5.4        Boarding +9 % attack · Gunnery +5.4 % accuracy and reach
//   WELSER   Purser (trading)        Trading cabin     PURSER 9                     Trade +9 % better prices
//   ELCANO   Navigator (exploration) Exploration cabin NAVIGATOR 9, PILOT 5.4, PROVISIONER 5.4   Seamanship +9 % speed · -5.4 % storm damage · +5.4 % days of supplies
// The wages (7,500 + 8,000 + 7,500) come out of the 40,000 the house is founded with.
//
// Merchants are not touched (`is_npc`), and the trigger returns at depth 2. The chain fingerprint inside the image is untouched.

import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

/** The three captains the patch signs: their code, their name as the YOU list prints it, and the sheet's parts as the server words them (the minus is U+2212, the server's own). */
export const SHEET_CAPTAINS = [
  {
    code: 'TURGUT',
    name: 'Turgut Reis',
    traits: ['BOARDER', 'GUNNER'],
    parts: { gunnery: '+5.4% accuracy · +5.4% reach', boarding: '+9% attack' } as Record<string, string>,
  },
  {
    code: 'WELSER',
    name: 'Bartholomäus Welser',
    traits: ['PURSER'],
    parts: { trade: '+9% better prices' } as Record<string, string>,
  },
  {
    code: 'ELCANO',
    name: 'Juan Sebastián Elcano',
    traits: ['NAVIGATOR', 'PILOT', 'PROVISIONER'],
    parts: { seamanship: '+9% speed · −5.4% storm damage · +5.4% days of supplies' } as Record<string, string>,
  },
] as const

/** The five stats in the order the server serves them. */
export const SHEET_STATS = ['gunnery', 'boarding', 'seamanship', 'trade', 'care'] as const

export function captainSheetWorld(): Promise<Buffer> {
  return patchedWorldImage('captain-sheet', async (pg) => {
    const codes = SHEET_CAPTAINS.map((c) => `'${c.code}'`).join(', ')
    await pg.exec(`
      create function public.spec_captain_sheet() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $fn$
      declare
        v_c text;
        v_r jsonb;
      begin
        if pg_trigger_depth() > 1 then return null; end if;
        if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
        if exists (select 1 from public.player_officers po join public.officers o on o.id = po.officer_id where po.player_id = new.player_id and o.code = 'ELCANO') then return null; end if;
        foreach v_c in array array[${codes}] loop
          v_r := public.sign_officer(new.player_id, v_c, new.fleet_id);
          if not coalesce((v_r ->> 'ok')::boolean, false) then
            raise exception 'spec: % was refused: %', v_c, v_r;
          end if;
        end loop;
        ${SHEET_CAPTAINS.map((c) => `perform public.captain_traits_set_for(new.player_id, '${c.code}', array[${c.traits.map((t) => `'${t}'`).join(', ')}]);`).join('\n        ')}
        return null;
      end $fn$;
      create trigger spec_captain_sheet after insert on public.ships
        for each row when (new.is_flagship) execute function public.spec_captain_sheet();
    `)
  })
}

/** Serve the captain's-sheet world to `page` in place of the shipped image. Call it before `page.goto`. */
export async function serveCaptainWorld(page: Page): Promise<void> {
  await serveWorldImage(page, await captainSheetWorld())
}
