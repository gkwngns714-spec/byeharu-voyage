// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PREFIX CACHE — a restored prefix must be the chain, and the key must move when the SQL does
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PURE UNIT SPEC (no `page`), real PostgreSQL. scripts/db/prefix-cache.mjs lets the world-image
// build and the proof run restore the longest already-applied prefix of the chain instead of
// replaying it from migration 0001. That is only legitimate if:
//
//   1. THE KEY MOVES WHEN THE SQL DOES — any edit inside a dollar-quoted body (a function, a `do`
//      self-assert), a string, an identifier, a file name, an added file. And it is only USEFUL if
//      a header-comment or whitespace edit keeps it. Both directions are proved on the real chain.
//   2. A PREFIX-BUILT WORLD IS THE SAME WORLD — the content digest (every row, sequence, function
//      body, ACL) of "restore 3, apply 1" equals "apply 4 from nothing".
//   3. A WRONG SNAPSHOT IS REFUSED — a tampered tarball or a manifest naming other files is
//      deleted, not loaded (the check is not vacuous).
//
// The browser's own identity, fingerprintChain(), is deliberately NOT normalised: a comment edit
// still moves the image's name and stamp (proved below), it just no longer costs a full replay.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { test, expect } from '@playwright/test'
import { mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import {
  applyWithPrefixCache,
  chainCacheKey,
  contentDigest,
  normalizeSql,
  prefixKeys,
  type PrefixVariant,
} from '../scripts/db/prefix-cache.mjs'
import { BROWSER_VARIANT } from '../scripts/db/build-image.mjs'
import { fingerprintChain } from '../src/lib/db/chain'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'

type File = { name: string; sql: string }

// ── 1. the normaliser, on the lexical corners that matter ─────────────────────────────────────

test('normalizeSql drops comments and collapses whitespace OUTSIDE quotes, and nothing inside them', () => {
  expect(normalizeSql('select 1 -- why\nfrom x')).toBe(normalizeSql('select 1\n  from   x'))
  expect(normalizeSql('select /* a /* nested */ b */ 1')).toBe('select 1')
  // A comment is never deleted down to nothing: `a/**/b` is two tokens, not `ab`.
  expect(normalizeSql('select a/**/b')).toBe('select a b')
  // Everything quoted is kept byte for byte — including what LOOKS like a comment inside it.
  const body = 'create function f() returns int language sql as $$ select 1 -- inside\n $$'
  expect(normalizeSql(body)).toContain('-- inside\n $$')
  expect(normalizeSql('select $fn$ a  /* x */ $fn$')).toBe('select $fn$ a  /* x */ $fn$')
  expect(normalizeSql("select 'it''s -- not a comment'")).toBe("select 'it''s -- not a comment'")
  expect(normalizeSql("select E'it\\'s -- not a comment' -- but this is")).toBe("select E'it\\'s -- not a comment'")
  expect(normalizeSql('select "odd--name" from t')).toBe('select "odd--name" from t')
  // $1 is a parameter and a$b$ an identifier — neither opens a dollar quote.
  expect(normalizeSql('select $1 -- p')).toBe('select $1')
  expect(normalizeSql('select a$b$ -- c')).toBe('select a$b$')
  // A newline between string constants is SQL ('a'\n'b' = 'ab'); it survives as a newline.
  expect(normalizeSql("select 'a'\n   'b'")).toBe("select 'a'\n'b'")
  expect(normalizeSql("select 'a'   'b'")).toBe("select 'a' 'b'")
  // An unterminated quote is refused, not guessed at.
  expect(() => normalizeSql('select $$ never closed')).toThrow(/unterminated/)
  expect(() => normalizeSql("select 'never closed")).toThrow(/unterminated/)
})

// ── 2. the key, on the real chain ──────────────────────────────────────────────────────────────

test('on the real chain: a comment edit KEEPS the cache key, a body edit MOVES it', async () => {
  const files = await loadChain()
  expect(files.length).toBeGreaterThan(10)
  const base = chainCacheKey(files, 'spec')
  const last = files[files.length - 1]
  const withLast = (sql: string): File[] => [...files.slice(0, -1), { name: last.name, sql }]

  // A header comment added, a comment reworded, whitespace reflowed outside every quote: SAME key.
  const commented = `-- a note added in review\n${last.sql.replace(/^--([^\n]*)/m, '--$1 (reworded)')}`
  expect(commented).not.toBe(last.sql)
  expect(chainCacheKey(withLast(commented), 'spec')).toBe(base)
  // …while the BROWSER'S identity still moves, so the image is still renamed and restamped.
  expect(fingerprintChain(withLast(commented))).not.toBe(fingerprintChain(files))

  // An edit INSIDE a dollar-quoted body — even only to a comment there — MOVES the key: a body's
  // text is what pg_get_functiondef() returns and what the chain's own assertions compare.
  const open = last.sql.search(/\$[A-Za-z_]*\$/)
  expect(open).toBeGreaterThan(-1) // the newest migration has a body (every one has a self-assert)
  const tag = /\$[A-Za-z_]*\$/.exec(last.sql.slice(open))![0]
  const inBody = open + tag.length
  const bodyEdit = `${last.sql.slice(0, inBody)}\n  -- a comment inside the body\n${last.sql.slice(inBody)}`
  expect(chainCacheKey(withLast(bodyEdit), 'spec')).not.toBe(base)

  // A renamed file, an added file, a different base: all move it.
  expect(chainCacheKey([...files.slice(0, -1), { name: `${last.name}x`, sql: last.sql }], 'spec')).not.toBe(base)
  expect(chainCacheKey([...files, { name: '29991231000000_x.sql', sql: 'select 1;' }], 'spec')).not.toBe(base)
  expect(chainCacheKey(files, 'another base')).not.toBe(base)

  // And the prefix keys are PREFIXES: editing file k leaves keys 0..k untouched and moves k+1..n.
  const k = Math.floor(files.length / 2)
  const edited = files.map((f, i) => (i === k ? { name: f.name, sql: `${f.sql}\nselect 1;` } : f))
  const a = prefixKeys(files, 'spec')
  const b = prefixKeys(edited, 'spec')
  expect(b.slice(0, k + 1)).toEqual(a.slice(0, k + 1))
  expect(b.slice(k + 1).every((key, i) => key !== a[k + 1 + i])).toBe(true)
})

// ── 3. a prefix-built world IS the from-zero world, and a wrong snapshot is refused ────────────

const SMALL = 4 // migrations 0001-0004: schemas, the static world, its seed, a house — seconds

// Two INDEPENDENT from-zero applies disagree on uuids (gen_random_uuid) and clock values (now()),
// measured: every seeded table's raw digest differed between two fresh applies of these 4 files.
// So the cross-apply comparison drops exactly those column types and keeps everything else — every
// other column of every row, row counts, every sequence, function body, ACL, policy and role. The
// STRICT digest (all columns, uuids and clocks included) is what each snapshot's round trip is held
// to, every time one is written and every time one is loaded (scripts/db/prefix-cache.mjs).
const STABLE = { stableOnly: true }

async function scratch(): Promise<string> {
  return mkdtemp(path.join(tmpdir(), 'byeharu-prefix-spec-'))
}

test('restore 3 + apply 1 is, row for row, the world of applying 4 from nothing', async () => {
  test.setTimeout(300_000)
  const files = (await loadChain()).slice(0, SMALL)
  const dir = await scratch()
  const quiet = () => {}
  try {
    // From nothing, 4 files — no cache.
    const fresh = await applyWithPrefixCache({ variant: BROWSER_VARIANT, files, cacheDir: dir, log: quiet, fresh: true, snapshots: false })
    expect(fresh.restored).toBe(0)
    const freshDigest = await contentDigest(fresh.db, STABLE)
    await fresh.db.close()

    // Seed the cache with the first 3 (snapshots are taken at n-3..n = 1, 2, 3).
    const seed = await applyWithPrefixCache({ variant: BROWSER_VARIANT, files: files.slice(0, SMALL - 1), cacheDir: dir, log: quiet })
    await seed.db.close()

    // Now 4: three restored, one applied HERE (its self-assert ran, its receipt was captured).
    const lines: string[] = []
    const cached = await applyWithPrefixCache({
      variant: BROWSER_VARIANT, files, cacheDir: dir, log: (...a: unknown[]) => lines.push(a.join(' ')),
    })
    expect(cached.restored).toBe(SMALL - 1)
    expect(cached.applied.map((r) => r.name)).toEqual(files.map((f) => f.name))
    expect(cached.applied.filter((r) => !r.restored).map((r) => r.name)).toEqual([files[SMALL - 1].name])
    // Every file carries a receipt: the restored ones from the run that produced the snapshot.
    expect(cached.receipts).toBe(SMALL)
    expect(lines.join('\n')).toContain(`restored ${SMALL - 1}/${SMALL}`)
    expect(await contentDigest(cached.db, STABLE)).toBe(freshDigest)
    await cached.db.close()
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
})

test('a tampered snapshot or a manifest naming other files is REFUSED and deleted, never loaded', async () => {
  test.setTimeout(300_000)
  const files = (await loadChain()).slice(0, 2)
  const dir = await scratch()
  const quiet = () => {}
  const variant: PrefixVariant = BROWSER_VARIANT
  try {
    const seed = await applyWithPrefixCache({ variant, files, cacheDir: dir, log: quiet })
    await seed.db.close()
    const vdir = path.join(dir, variant.name)
    const stems = (await readdir(vdir)).filter((f) => f.endsWith('.json')).map((f) => f.slice(0, -5)).sort()
    expect(stems.length).toBe(2) // after 1 file and after 2

    // (a) the longest snapshot's tarball is corrupted: refused, deleted, and the next one down used.
    const [p1, p2] = stems
    const tar = path.join(vdir, `${p2}.tar.gz`)
    const bytes = await readFile(tar)
    bytes[bytes.length - 100] ^= 0xff
    await writeFile(tar, bytes)
    const lines: string[] = []
    const r1 = await applyWithPrefixCache({ variant, files, cacheDir: dir, log: (...a: unknown[]) => lines.push(a.join(' ')), snapshots: false })
    expect(lines.join('\n')).toMatch(/REFUSED .*does not hash to its manifest/)
    expect(r1.restored).toBe(1)
    await r1.db.close()
    expect((await readdir(vdir)).some((f) => f.startsWith(p2))).toBe(false)

    // (b) the remaining manifest claims a different file list: refused; nothing is restored.
    const mf = path.join(vdir, `${p1}.json`)
    const manifest = JSON.parse(await readFile(mf, 'utf8'))
    manifest.names = ['20260818000001_something_else.sql']
    await writeFile(mf, JSON.stringify(manifest))
    lines.length = 0
    const r2 = await applyWithPrefixCache({ variant, files, cacheDir: dir, log: (...a: unknown[]) => lines.push(a.join(' ')), snapshots: false })
    expect(lines.join('\n')).toMatch(/REFUSED .*file list differs/)
    expect(r2.restored).toBe(0)
    await r2.db.close()
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
})
