// THE SHIPPED WORLD WITH ROUTES SWITCHED ON — the one seam the browser specs use to see a route.
//
// The local build ships routes dark (0092 `standing_routes_enabled = false`) and the page has no
// seam to flip it, so a spec sets that one world_config row in a patched copy of the build's image
// (worldImage.fixture.ts carries the open / patch / dump / serve once). Shared by
// tests/route.stopface.spec.ts and tests/flicker.spec.ts.

import type { Page } from '@playwright/test'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

export function routesOn(): Promise<Buffer> {
  return patchedWorldImage('routes-on', async (pg) => {
    const r = await pg.query(`update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled' returning key`)
    if (r.rows.length !== 1) throw new Error('world_config has no standing_routes_enabled row')
  })
}

/** Serve the routes-on world to `page` in place of the shipped image. */
export async function serveRoutesOn(page: Page): Promise<void> {
  await serveWorldImage(page, await routesOn())
}

/** Routes on, AND NO WEATHER (hazard_p_max 0): for a spec that times a lap by the wall clock. A storm is 36 hours at sea (675 real seconds)
 *  and a calm 1 to 4 days (450 to 1,800 s); measured on Lisbon to Setubal, 72 legs of 6,000 met one, so a two-leg lap does once in 42. */
export async function serveRoutesOnInClearWeather(page: Page): Promise<void> {
  await serveWorldImage(
    page,
    await patchedWorldImage('routes-on-clear', async (pg) => {
      const r = await pg.query(
        `update public.world_config
            set value = case key when 'standing_routes_enabled' then 'true'::jsonb else '0'::jsonb end
          where key in ('standing_routes_enabled', 'hazard_p_max') returning key`,
      )
      if (r.rows.length !== 2) throw new Error('world_config has no standing_routes_enabled or no hazard_p_max row')
    }),
  )
}
