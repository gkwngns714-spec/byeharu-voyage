// THE SHIPPED WORLD WITH THE MERCHANTS SWITCHED ON — the seam the merchant browser spec uses
// (docs/NPC_TRADERS.md §11, the tests/routesOn.fixture.ts pattern).
//
// The build ships merchants dark (0097 `npc_traders_enabled = false`) and the page has no seam to
// flip it, so this opens the build's pre-built world image in Node, turns routes on, LAYS UP one
// Lisbon-homed merchant through the route core (so PORT at Lisbon has a merchant in port, every
// time), runs THE switch — `public.npc_traders_switch(true)`, which plans and starts every other
// merchant through the one executor — and serves the result in place of `db/world-<fp>.tar.gz`.
// The chain fingerprint inside the image is untouched, so the boot's pairing check passes. From
// there the local backend plays pg_cron's part (`tick_arrivals` before every traffic read), so the
// merchants are at sea when the page opens and keep sailing while it is open.

import type { Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'

/** Built once per worker. */
let npcOnImage: Buffer | null = null

/** The merchant fleet laid up at Lisbon, so PORT has one in port. */
export const LAID_UP_AT_LISBON = 'Carreira da Guiné'

export async function npcOn(): Promise<Buffer> {
  if (npcOnImage) return npcOnImage
  const dir = path.resolve('dist', 'db')
  const name = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!name) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
  try {
    const r = await pg.query(`update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled' returning key`)
    if (r.rows.length !== 1) throw new Error('world_config has no standing_routes_enabled row')
    const laid = await pg.query<{ r: { ok: boolean } }>(
      `select cmd.standing_route_pause_for(nf.player_id, nf.route_id, true, 'laid_up', 'Held in port for the browser spec.') as r
         from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.name = $1`,
      [LAID_UP_AT_LISBON],
    )
    if (laid.rows.length !== 1 || !laid.rows[0].r.ok) throw new Error(`could not lay up ${LAID_UP_AT_LISBON}`)
    const sw = await pg.query<{ j: { enabled: boolean; tend: { started: number } } }>(`select public.npc_traders_switch(true) as j`)
    if (!sw.rows[0].j.enabled || sw.rows[0].j.tend.started < 10) {
      throw new Error(`the switch did not put the merchants to sea: ${JSON.stringify(sw.rows[0].j)}`)
    }
    npcOnImage = Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer())
  } finally {
    await pg.close()
  }
  return npcOnImage
}

/** Serve the merchants-on world to `page` in place of the shipped image. */
export async function serveNpcOn(page: Page): Promise<void> {
  const image = await npcOn()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: image, contentType: 'application/gzip' }))
}
