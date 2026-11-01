// A VETERAN'S WORLD, BUILT AT RUN TIME — eight hulls and six captains, the rows a canary world does not have.
//
// The canary boots with ONE hull (`twoFleets()` gives two) and no captain, so a list of hulls was never longer than a
// phone's glass in any spec. A veteran's is: the cap is EARNED (`public.earned_caps`, raised with the Trading level;
// the flat knob is `world_config.fleet_max`), and the owner's world will hold more hulls than two. The sweep of
// 2026-11-02 built this world in a scratch image and measured that FLEETS and YOU scrolled the PAGE 122 px (FLEETS) and
// 140 px (YOU) at 390×844. This is that world, written once where a spec can use it (docs/dev-log/2026-11-02-sheets-grow.md).
//
// HOW (the way `twoFleets.fixture.ts` does it — nothing is written to disk, nothing outside the spec's browser sees it):
//   · the knob `fleet_max` is raised to EIGHT in this throwaway image only;
//   · a trigger on `public.ships` forms the other seven fleets through the chain's own doors (`public.form_fleet`,
//     `public.commission_ship`) the moment the house's founding flagship is commissioned — a local world founds its
//     house at boot, AFTER the image is loaded, so a fleet cannot simply be a row in the image;
//   · `world.captains()` is replaced by a type-shaped read of six captains (`YourCaptain`), the way `playedWorld()`
//     replaces `world.ledger` — a captain is signed at an Inn, which a spec does not walk.
// One of the fleets has a 24-character name (the longest the chain allows: fleets_name_check), one captain a 47-character name and one sails nowhere (ashore): the
// rows that must carry their full text when the glass cuts them (U5).

import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

/** How many hulls the veteran owns — the throwaway image raises `fleet_max` to this. */
export const VETERAN_HULLS = 8

/** The seven fleets the trigger forms (the founding one, `Gaivota`, makes eight). The fifth name is the longest the chain allows (24 characters). */
export const VETERAN_FLEETS = [
  'Santa Clara',
  'Boa Esperança',
  'São Gabriel',
  'Fortuna',
  'Nossa Senhora da Estrela',
  'Flor do Mar',
  'Santo António',
] as const

/** The captains `world.captains()` serves in this world (a 47-character name among them). */
export const VETERAN_CAPTAINS = 6

/** A jsonb literal for a SQL string (standard_conforming_strings: only the quote needs doubling). */
const jsonb = (value: unknown) => `'${JSON.stringify(value).replace(/'/g, "''")}'::jsonb`

/** `world.captains()`'s answer: six captains of every grade, one ashore, one whose bonus nothing reads yet. */
function captainsRead() {
  const levels = (exploration: number, trading: number) => [
    { track: 'exploration', word: 'Exploration', level: exploration, own: exploration, points: 40 * exploration, next_at: 40 * (exploration + 1), cap_line: null },
    { track: 'trading', word: 'Trading', level: trading, own: trading, points: 40 * trading, next_at: 40 * (trading + 1), cap_line: null },
    { track: 'combat', word: 'Combat', level: 1, own: 1, points: 0, next_at: 40, cap_line: null },
  ]
  const trait = (code: string, word: string, focus: string, pct: number, inUse: boolean) => ({
    code,
    word,
    focus_word: focus,
    pct,
    lines: [`+${pct}% ${word.toLowerCase()}`],
    uses: true,
    in_use: inUse,
    note: null,
  })
  const captain = (
    code: string,
    name: string,
    grade: string,
    ord: number,
    jobWord: string,
    focusWord: string,
    ship: string | null,
    fleet: string | null,
    pct: number,
    inUse: boolean,
  ) => ({
    code,
    name,
    grade,
    grade_ord: ord,
    slots: ord + 1,
    known: ord * 2,
    job: jobWord.toLowerCase().replace(/ /g, '_'),
    job_word: jobWord,
    focus: focusWord.toLowerCase(),
    focus_word: focusWord,
    traits: [trait(jobWord.toLowerCase().replace(/ /g, '_'), jobWord, focusWord, pct, inUse)],
    active: inUse ? [jobWord.toLowerCase().replace(/ /g, '_')] : [],
    languages: ['Portuguese', 'Spanish'],
    speaks: 'Speaks Portuguese, Spanish',
    ship,
    fleet,
    cabin_word: ship === null ? null : 'Chart room',
    can_change: true,
    levels: levels(ord + 2, ord + 1),
    homesick: null,
    promote: null,
  })
  return {
    captains: [
      captain('cap-albuquerque', 'Afonso de Albuquerque', 'S', 4, 'Navigator', 'Exploration', 'Santa Clara', 'Santa Clara', 12, true),
      captain('cap-gama', 'Vasco da Gama', 'A', 3, 'Gem trader', 'Trading', 'Boa Esperança', 'Boa Esperança', 9, true),
      captain('cap-castela', 'Isabel de Castela', 'B', 2, 'Quartermaster', 'Trading', null, null, 7, true),
      captain('cap-dias', 'Bartolomeu Dias', 'C', 1, 'Surgeon', 'Exploration', 'São Gabriel', 'São Gabriel', 5, false),
      captain('cap-conceicao', 'Ana Maria da Conceição Fernandes de Albuquerque', 'A', 3, 'Spice trader', 'Trading', 'Fortuna', 'Fortuna', 8, true),
      captain('cap-pacheco', 'Duarte Pacheco', 'B', 2, 'Gunner', 'Combat', 'Flor do Mar', 'Flor do Mar', 6, false),
    ],
  }
}

/** The veteran's image: eight hulls (the founding flagship and seven formed at its commissioning) and six captains. */
export function veteranWorld(): Promise<Buffer> {
  return patchedWorldImage('veteran', async (pg) => {
    const raised = await pg.query(`update public.world_config set value = '${VETERAN_HULLS}'::jsonb where key = 'fleet_max' returning key`)
    if (raised.rows.length !== 1) throw new Error('world_config has no fleet_max row')
    const names = `array[${VETERAN_FLEETS.map((n) => `'${n.replace(/'/g, "''")}'`).join(', ')}]`
    await pg.exec(`
      create function public.spec_veteran_fleets() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $fn$
      declare
        v_port  uuid;
        v_fleet uuid;
        v_name  text;
      begin
        if pg_trigger_depth() > 1 then return null; end if;
        if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
        if exists (select 1 from public.fleets f where f.player_id = new.player_id and f.name = '${VETERAN_FLEETS[0]}') then return null; end if;
        select f.port_id into v_port from public.fleets f where f.id = new.fleet_id;
        foreach v_name in array ${names} loop
          v_fleet := public.form_fleet(new.player_id, v_name, v_port);
          perform public.commission_ship(new.player_id, v_fleet, 'barca', v_name, true, true);
        end loop;
        return null;
      end $fn$;
      create trigger spec_veteran_fleets after insert on public.ships
        for each row when (new.is_flagship) execute function public.spec_veteran_fleets();
    `)
    await pg.exec('drop function if exists world.captains()')
    await pg.exec(`create function world.captains() returns jsonb language sql stable as $f$ select ${jsonb(captainsRead())} $f$`)
  })
}

/** Serve the veteran's world to `page` in place of the shipped image. Call it before `page.goto`. */
export async function serveVeteranWorld(page: Page): Promise<void> {
  await serveWorldImage(page, await veteranWorld())
}
