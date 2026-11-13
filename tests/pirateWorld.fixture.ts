// THE SHIPPED WORLD WITH THE BRETHREN OPEN (0338's knob `pirates_joinable`, lit by 0381), for the browser specs that walk a pirate company.
//
// The local build ships the knob false and the page has no seam to set it, so a spec sets that one world_config row in a patched copy of the
// build's image (worldImage.fixture.ts carries the open / patch / dump / serve once). `pirateCompany()` goes one step further: the world's one
// local captain is founded UNDER THE SKULL through the real door (cmd.found_house), so the boot finds her house and the page opens on a
// company of the Brethren lying at Port Royal. The crowns' purses and the closed economy are lit too, as production runs them: a war stance
// prices nothing while the economy is open (public.country_factor answers 1), and a closed founding needs a capital that can pay.
import type { Page } from '@playwright/test'
import type { PGlite } from '@electric-sql/pglite'
import { LOCAL_AUTH_UID } from '../src/lib/db/localDb'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

/** The switches production runs lit that a pirate company's prices, fees and standing read. */
export const PIRATE_WORLD_SWITCHES = ['pirates_joinable', 'economy_closed', 'city_treasury_enabled', 'influence_enabled', 'regard_enabled', 'pirates_bite', 'levels_bite', 'standing_routes_enabled']

async function light(pg: PGlite): Promise<void> {
  const r = await pg.query(`update public.world_config set value = 'true'::jsonb where key = any($1) returning key`, [PIRATE_WORLD_SWITCHES])
  if (r.rows.length !== PIRATE_WORLD_SWITCHES.length) throw new Error(`world_config holds ${r.rows.length} of the ${PIRATE_WORLD_SWITCHES.length} switches a pirate world lights`)
  // a closed founding is paid by the capital: Port Royal's purse must hold the starting money (a never-seeded local world's purses are empty)
  await pg.query(`update public.port_treasury set ducats = 100000000 where ducats < 100000000`)
}

/** The Brethren open to companies; the local captain still founds as the build founds her (Portugal, at Lisbon). */
export function brethrenOpen(): Promise<Buffer> {
  return patchedWorldImage('brethren-open', light)
}

/** The Brethren open, and the local captain founded under the skull through cmd.found_house. */
export function pirateCompany(): Promise<Buffer> {
  return patchedWorldImage('pirate-company', async (pg) => {
    await light(pg)
    await pg.transaction(async (tx) => {
      await tx.query('select cmd.assume_identity($1)', [LOCAL_AUTH_UID])
      const r = await tx.query<{ r: { ok: boolean; error_code?: string } }>(`select cmd.found_house('Skull Company', 'PIR') as r`)
      if (!r.rows[0]?.r.ok) throw new Error(`cmd.found_house under the pirates answered ${JSON.stringify(r.rows[0]?.r)}`)
    })
  })
}

export async function serveBrethrenOpen(page: Page): Promise<void> {
  await serveWorldImage(page, await brethrenOpen())
}

export async function servePirateCompany(page: Page): Promise<void> {
  await serveWorldImage(page, await pirateCompany())
}
