// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PRE-BUILT WORLD — the guard that makes shipping one legitimate
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PURE UNIT SPEC. No `page` fixture, so Playwright runs it as a plain Node process — but the
// PostgreSQL is real, and the tarball under test is the one `npm run build` actually emitted into
// dist/, not one this file made up.
//
// ── WHY THIS FILE EXISTS AT ALL ─────────────────────────────────────────────────────────────────
// Since 2026-08-25 the world may arrive PRE-BUILT: `npm run build` applies the chain once and
// ships the resulting PostgreSQL data directory, because replaying 45 migrations in the player's
// tab cost 78.8 s (docs/DEV_LOG.md:177). That makes the image A SECOND COPY OF THE WORLD, and
// this project has already lost a working day to that exact class of defect — migration 0003 was
// edited after production applied it, "production kept the ORIGINAL 70 goods / 214 harbours while
// every fresh rebuild got 243", and the sentence that should never be earned twice:
//
//     "Nothing red happened anywhere. Everything stayed green while the worlds diverged."
//                                                                    — docs/DEV_LOG.md D23
//
// So this file is the red. It asserts, against the emitted artefact:
//
//   1. an image for THIS chain exists in dist/ (a chain that moved without a rebuild is red here);
//   2. it certifies — the world inside it EQUALS data/*.json, judged by scripts/db/world-guard.mjs,
//      the same authority every `npm run db:apply` and every CI apply-proof runs, positive control
//      and all. No second comparator was written for images;
//   3. the fingerprint stamped inside it is this chain's;
//   4. §K.1's opening can actually be played in it;
//   5. THE CHECKS CAN FAIL. Two wounded images are put in front of the same certifier and it must
//      reject both — because "a vacuous assert reads as coverage and is worse than none"
//      (docs/CORE_REUSE.md:1443-1451);
//   6. THE FALLBACK STILL WORKS. Hand the boot an image built from another chain and it must
//      refuse it, say so, apply the chain in the tab, and arrive at a playable world anyway.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test'
import { readFileSync, existsSync } from 'node:fs'
import { gzipSync } from 'node:zlib'
import path from 'node:path'
import {
  certifyWorldImage,
  chainAndFingerprint,
  WORLD_IMAGE_DIR,
  worldImageFileName,
} from '../scripts/db/build-image.mjs'
import { fingerprintChain } from '../src/lib/db/chain'
import { imageRefusal, readStoredChain } from '../src/lib/db/appLocal'
import { asWorldImageFile, worldImageUrl } from '../src/lib/db/worldImage'
import { openLocalDb, LOCAL_AUTH_UID } from '../src/lib/db/localDb'
import { createBootChannel, type BootPhase } from '../src/lib/db/bootState'
import {
  loadChain,
  removeScratchDataDir,
  scratchDataDir,
} from '../src/lib/db/chainSource.node.mjs'

const ROOT = path.resolve(process.cwd())

/** The image THE BUILD EMITTED, found the way the browser finds it: by this chain's fingerprint. */
function emittedImage(): { file: string; bytes: Uint8Array; fingerprint: string } {
  const fingerprint = fingerprintChain(readChainSync())
  const file = path.join(ROOT, 'dist', WORLD_IMAGE_DIR, worldImageFileName(fingerprint))
  if (!existsSync(file)) {
    throw new Error(
      `NO PRE-BUILT WORLD FOR THIS CHAIN.\n` +
        `  expected: ${path.relative(ROOT, file)}\n` +
        `  The build emits dist/${WORLD_IMAGE_DIR}/world-<fingerprint>.tar.gz from the chain in\n` +
        `  supabase/migrations at build time. This file is missing, which means either the build\n` +
        `  has not run since the chain last moved, or it stopped emitting one. Run "npm run build".\n` +
        `  It is red rather than skipped on purpose: a shipped world that no longer matches the\n` +
        `  shipped chain is exactly the divergence of DEV_LOG D23, and it stayed green for a day.`,
    )
  }
  return { file, bytes: new Uint8Array(readFileSync(file)), fingerprint }
}

/** The chain off disk, synchronously, so the fingerprint can be taken inside a non-async helper. */
function readChainSync() {
  if (!chainCache) throw new Error('the chain was not loaded before it was fingerprinted')
  return chainCache
}
let chainCache: { name: string; sql: string }[] | null = null

test.beforeAll(async () => {
  chainCache = await loadChain()
})

// ── the pure pairing rule ──────────────────────────────────────────────────────────────────────

test('the pairing rule accepts only the chain the image was built from, and says what it saw', () => {
  const stamp = { fingerprint: 'abc-45-1', files: 45, applied_at: 'now', auth_uid: null }

  expect(imageRefusal(stamp, 'abc-45-1')).toBeNull()

  const wrong = imageRefusal(stamp, 'def-46-2')
  expect(wrong).toContain('abc-45-1')
  expect(wrong).toContain('def-46-2')

  // An image with no stamp at all is refused too — "it did not say" is not "it agreed".
  expect(imageRefusal(null, 'abc-45-1')).toContain('no app_local.chain row')
})

test('the URL the client asks for carries the fingerprint of the chain it shipped with', () => {
  const { fingerprint } = emittedImage()
  const url = worldImageUrl(fingerprint, '/byeharu-voyage/')
  expect(url).toBe(`/byeharu-voyage/${WORLD_IMAGE_DIR}/world-${fingerprint}.tar.gz`)
  // Which is the cheap half of the safety: a client can only ever name its OWN chain's image, so a
  // moved chain is a 404 and a 404 applies the chain. The authoritative half is the stamp inside.
  expect(url).toContain(fingerprint)
})

// ── the artefact the build actually emitted ────────────────────────────────────────────────────

test('the image dist/ ships was built from THIS chain and holds the world data/*.json describes', async () => {
  // One restore of a ~100 MB data directory plus the world guard's full comparison, twice over
  // (the guard runs its own positive control before it certifies anything).
  test.setTimeout(300_000)
  const { fingerprint, bytes, file } = emittedImage()
  const { fingerprint: chainNow } = await chainAndFingerprint()
  expect(fingerprint).toBe(chainNow)

  const receipt = await certifyWorldImage(bytes, { fingerprint })

  expect(receipt.fingerprint).toBe(fingerprint)
  expect(receipt.files).toBe((await loadChain()).length)
  // Not pinned numbers: the world is whatever data/*.json says today, and world-guard has already
  // asserted the equality good by good. These only insist it is not EMPTY — a certifier that
  // passed over a blank database would be the vacuous assert this file exists to refuse.
  expect(receipt.harbours).toBeGreaterThan(200)
  expect(receipt.goods).toBeGreaterThan(200)
  expect(receipt.ports).toBeGreaterThan(receipt.harbours) // the sea places share the table (0036)
  expect(receipt.market).toBe(receipt.goods * receipt.harbours) // the market covers the world
  expect(bytes.length).toBeGreaterThan(1_000_000)
  expect(file).toContain(fingerprint)
})

// ── THE POSITIVE CONTROL: the certifier must be able to say no ─────────────────────────────────

test('an image paired with the wrong chain is REFUSED — the check is not vacuous', async () => {
  test.setTimeout(300_000)
  const { bytes } = emittedImage()

  // (a) The right bytes, offered as another chain's image. Nothing about the tarball changed; the
  //     only thing wrong is the pairing, which is precisely the D23 defect.
  await expect(certifyWorldImage(bytes, { fingerprint: 'deadbeefdeadbeef-99-ff' })).rejects.toThrow(
    /IMAGE REFUSED/,
  )

  // (b) And the other direction: the STAMP INSIDE the image rewritten, offered as this chain's.
  //     This is the one that proves the check reads the database rather than the file name.
  const wounded = await woundedImage()
  await expect(certifyWorldImage(wounded.bytes, { fingerprint: wounded.chain })).rejects.toThrow(
    /IMAGE REFUSED/,
  )
})

// ── the boot, both ways ────────────────────────────────────────────────────────────────────────

test('the world opens from the image without applying a single migration here', async () => {
  test.setTimeout(300_000)
  const { bytes, fingerprint } = emittedImage()
  const channel = createBootChannel()
  const phases: BootPhase[] = []
  const stop = channel.subscribe(() => {
    const s = channel.get()
    if (phases[phases.length - 1] !== s.phase) phases.push(s.phase)
  })

  const db = await openLocalDb({
    loadChain,
    dataDir: 'memory://',
    channel,
    log: () => {},
    loadImage: () =>
      Promise.resolve({ blob: asWorldImageFile(bytes), url: 'test://image', bytes: bytes.length, note: null }),
  })
  stop()

  try {
    expect(db.fromImage).toBe(true)
    expect(db.fingerprint).toBe(fingerprint)
    // THE POINT OF THE WHOLE SLICE: no `applying` phase, because no migration ran in this tab.
    expect(phases).toEqual(['booting', 'seeding', 'ready'])
    expect(channel.get().imageRefused).toBeNull()
    expect(channel.get().error).toBeNull()

    // And it is the real world, seeded with §K.1's opening through the chain's own new_house().
    const house = await db.pg.query<{ ducats: number; ports: number }>(
      `select p.ducats::int as ducats, (select count(*)::int from public.ports) as ports
         from public.players p where p.auth_uid = $1`,
      [LOCAL_AUTH_UID],
    )
    expect(house.rows[0].ducats).toBe(8000)
    expect(house.rows[0].ports).toBeGreaterThan(200)
  } finally {
    await db.close()
  }
})

test('a world restored from the image persists, and the next boot reuses it like any other', async () => {
  test.setTimeout(300_000)
  const { bytes } = emittedImage()
  const dir = await scratchDataDir('image')
  const loadImage = () =>
    Promise.resolve({ blob: asWorldImageFile(bytes), url: 'test://image', bytes: bytes.length, note: null })
  // A durable data directory is not empty once PGlite has opened it, and PGlite will not unpack an
  // image over an existing database. In a browser that emptying is IndexedDB's; here it is the
  // scratch directory's own remover — the same seam, exercised the same way.
  const resetStore = async (d: string) => {
    await removeScratchDataDir(d)
    return { emptied: true, deleted: [d], note: null }
  }

  try {
    const first = await openLocalDb({ loadChain, dataDir: dir, loadImage, resetStore, log: () => {} })
    expect(first.fromImage).toBe(true)
    await first.pg.query("update public.players set company_name = 'Casa da Imagem' where auth_uid = $1", [
      LOCAL_AUTH_UID,
    ])
    await first.close()

    // Second boot: the stored world's fingerprint matches, so nothing is downloaded, nothing is
    // applied, and the house is where it was left. An image-built world is a world, not a cache.
    const again = await openLocalDb({
      loadChain,
      dataDir: dir,
      log: () => {},
      loadImage: () => {
        throw new Error('the second boot must not ask for an image: the stored world already matches')
      },
    })
    try {
      expect(again.fromImage).toBe(false)
      expect(again.rebuilt).toBe(false)
      const mark = await again.pg.query<{ company_name: string }>(
        'select company_name from public.players where auth_uid = $1',
        [LOCAL_AUTH_UID],
      )
      expect(mark.rows[0].company_name).toBe('Casa da Imagem')
    } finally {
      await again.close()
    }
  } finally {
    await removeScratchDataDir(dir)
  }
})

test('a refused image falls back to applying the chain, and says so out loud', async () => {
  // THE FALLBACK IS THE PRODUCT, not a safety net nobody runs: it is what every boot did before
  // this optimisation existed, and what still happens whenever an image is absent, unreadable or
  // mispaired. So it is proved here end to end, with a full chain apply — minutes, deliberately.
  test.setTimeout(600_000)
  const wounded = await woundedImage()
  const channel = createBootChannel()
  const phases: BootPhase[] = []
  const stop = channel.subscribe(() => {
    const s = channel.get()
    if (phases[phases.length - 1] !== s.phase) phases.push(s.phase)
  })

  const db = await openLocalDb({
    loadChain,
    dataDir: 'memory://',
    channel,
    log: () => {},
    loadImage: () =>
      Promise.resolve({
        blob: asWorldImageFile(wounded.bytes),
        url: 'test://wounded',
        bytes: wounded.bytes.length,
        note: null,
      }),
  })
  stop()

  try {
    expect(db.fromImage).toBe(false)
    // Refused, and NOT in silence: the sentence names both fingerprints and reaches the boot
    // channel, which is what src/app/RebuildNotice.tsx puts on the screen.
    const refused = channel.get().imageRefused
    expect(refused).toContain(wounded.stamped)
    expect(refused).toContain(db.fingerprint)
    expect(phases).toContain('applying')
    expect(channel.get().error).toBeNull()

    // And the world that came out of the fallback is the real one.
    const house = await db.pg.query<{ ducats: number }>(
      'select ducats::int as ducats from public.players where auth_uid = $1',
      [LOCAL_AUTH_UID],
    )
    expect(house.rows[0].ducats).toBe(8000)
    const stored = await readStoredChain(db.pg)
    expect(stored?.fingerprint).toBe(db.fingerprint)
  } finally {
    await db.close()
  }
})

/**
 * The emitted image with its INTERNAL stamp rewritten — a world that is perfectly good and simply
 * is not this chain's. Built by restoring the real image, editing the one row, and dumping again,
 * so everything except the pairing is genuine.
 */
async function woundedImage(): Promise<{ bytes: Uint8Array; chain: string; stamped: string }> {
  const { PGlite } = await import('@electric-sql/pglite')
  const { bytes, fingerprint } = emittedImage()
  const stamped = 'aaaabbbbccccdddd-1-1'
  const pg = await PGlite.create({ loadDataDir: asWorldImageFile(bytes) })
  try {
    await pg.query('update app_local.chain set fingerprint = $1 where singleton', [stamped])
    const tar = new Uint8Array(await (await pg.dumpDataDir('none')).arrayBuffer())
    return { bytes: new Uint8Array(gzipSync(tar)), chain: fingerprint, stamped }
  } finally {
    await pg.close()
  }
}
