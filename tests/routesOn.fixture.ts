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
