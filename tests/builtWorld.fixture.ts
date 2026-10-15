// THE BUILD'S OWN WORLD, FOR A NODE SPEC THAT NEEDS A WHOLE ONE (2026-10-15).
//
// rpc.firstSession, rpc.surface and sea.dateline each opened their world with `openLocalDb({
// loadChain })` and nothing else, so each APPLIED THE WHOLE CHAIN from 0001 in its beforeAll —
// and a beforeAll's time is not in any test's reported duration. Measured on CI run 38699813083,
// rpc.firstSession's hook alone held a shard for ~40 minutes while its test reported 4.6 s. Since
// 0105 a from-zero apply on wasm is that long, and these specs test the RPC surface, not the
// applier.
//
// So they boot the way the PLAYER boots: from the pre-built image `npm run build` emitted for THIS
// chain, through openLocalDb's own `loadImage` seam — the fingerprint pairing, the refusal path and
// the seeding step are the shipped ones (tests/db.image.spec.ts proves that path and certifies the
// image against data/*.json). The from-zero apply is proven where it belongs: the build itself,
// pglite-gate, disposable-chain and tests/db.chain.spec.ts.
//
// No image on disk (a developer who has not built) is not an error: the boot applies the chain,
// exactly as these specs always did.
import { existsSync, readFileSync } from 'node:fs'
import path from 'node:path'
import { asWorldImageFile, WORLD_IMAGE_DIR, worldImageFileName, type WorldImageFetch } from '../src/lib/db/worldImage'

export async function builtWorldImage(fingerprint: string): Promise<WorldImageFetch> {
  const file = path.resolve('dist', WORLD_IMAGE_DIR, worldImageFileName(fingerprint))
  if (!existsSync(file)) {
    return { blob: null, url: '', bytes: 0, note: `no ${file} (run \`npm run build\`), so the chain is applied here` }
  }
  const bytes = new Uint8Array(readFileSync(file))
  return { blob: asWorldImageFile(bytes), url: file, bytes: bytes.length, note: null }
}
