// THE SHIPPED WORLD WITH ROUTES SWITCHED ON — the one seam the browser specs use to see a route.
//
// The local build ships routes dark (0092 `standing_routes_enabled = false`) and the page has no
// seam to flip it, so a spec builds its own: it opens the build's pre-built world image in Node,
// sets that one world_config row, and serves the result in place of `db/world-<fp>.tar.gz`. The
// chain fingerprint inside the image is untouched, so the boot's pairing check passes exactly as
// it does for the shipped image — only the flag differs. Shared by tests/route.stopface.spec.ts and
// tests/flicker.spec.ts.

import type { Page } from '@playwright/test'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'

/** Built once per worker. */
let routesOnImage: Buffer | null = null

export async function routesOn(): Promise<Buffer> {
  if (routesOnImage) return routesOnImage
  const dir = path.resolve('dist', 'db')
  const name = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!name) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, name)))) })
  try {
    const r = await pg.query(`update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled' returning key`)
    if (r.rows.length !== 1) throw new Error('world_config has no standing_routes_enabled row')
    routesOnImage = Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer())
  } finally {
    await pg.close()
  }
  return routesOnImage
}

/** Serve the routes-on world to `page` in place of the shipped image. */
export async function serveRoutesOn(page: Page): Promise<void> {
  const image = await routesOn()
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: image, contentType: 'application/gzip' }))
}
