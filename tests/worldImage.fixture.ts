// A PATCHED COPY OF THE SHIPPED WORLD — the one seam a browser spec has to see a world the local
// build does not ship (routes switched on, a second fleet).
//
// The page has no seam to change the world it boots, and must not have one: the shipped image is
// the chain's own output (scripts/db/build-image.mjs). So a spec builds its own copy in Node: it
// opens the build's pre-built image, runs ONE patch against it, and serves the result in place of
// `db/world-<fp>.tar.gz`. The chain fingerprint inside the image is untouched, so the boot's
// pairing check passes exactly as it does for the shipped image — only what the patch changed
// differs. Written once here (2026-10-20) when the fleet picker's two-fleet world became the second
// patch after routesOn.fixture.ts's flag — the open / patch / dump / serve was about to be copied.
//
// Each patch is built once per worker and keyed by name, so a spec file's tests share one build.

import type { Page } from '@playwright/test'
import type { PGlite } from '@electric-sql/pglite'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile } from '../src/lib/db/worldImage'

const built = new Map<string, Promise<Buffer>>()

/** The shipped image, patched by `patch`, as the bytes the page downloads. Built once per worker per `name`. */
export function patchedWorldImage(name: string, patch: (pg: PGlite) => Promise<void>): Promise<Buffer> {
  let p = built.get(name)
  if (!p) {
    p = build(patch)
    built.set(name, p)
  }
  return p
}

async function build(patch: (pg: PGlite) => Promise<void>): Promise<Buffer> {
  const dir = path.resolve('dist', 'db')
  const file = existsSync(dir) ? readdirSync(dir).find((f) => /^world-.*\.tar\.gz$/.test(f)) : undefined
  if (!file) throw new Error(`no world image under ${dir} — run \`npm run build\` first`)
  const { PGlite } = await import('@electric-sql/pglite')
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(new Uint8Array(readFileSync(path.join(dir, file)))) })
  try {
    await patch(pg)
    return Buffer.from(await (await pg.dumpDataDir('gzip')).arrayBuffer())
  } finally {
    await pg.close()
  }
}

/** Serve `image` to `page` in place of the shipped world image. */
export async function serveWorldImage(page: Page, image: Buffer): Promise<void> {
  await page.route('**/db/world-*.tar.gz', (route) => route.fulfill({ body: image, contentType: 'application/gzip' }))
}
