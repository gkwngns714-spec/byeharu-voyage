// ═══════════════════════════════════════════════════════════════════════════════════════════════
// prefix-cache.mjs — apply ONLY the migrations a cached world has not seen yet
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ── THE COST THIS DELETES (docs/DEV_LOG.md, 2026-10-13) ─────────────────────────────────────────
// Every gate that needs a world built it from migration 0001: `npm run build` (the world image),
// `npm run db:proof` (pglite-gate) — and the cache that existed was keyed on the WHOLE chain's
// text, so adding one migration, or editing one comment, threw the whole apply away. On wasm
// Postgres that apply is tens of minutes, and it grows with every route-walking self-assert.
//
// ── WHAT IT DOES ────────────────────────────────────────────────────────────────────────────────
// After migration N commits, the live database is a pure function of (the base it started from,
// files 1..N). So a PostgreSQL data directory dumped at that moment is a legitimate stand-in for
// "apply files 1..N" — for exactly that base and exactly those files, and nothing else. This module
// keeps such snapshots, keyed by a ROLLING key over (base, file 1, …, file N); on the next apply it
// finds the LONGEST cached prefix of the current chain, restores it, and applies only the rest.
//
//   * Every migration after the restored prefix runs HERE, in this database, through the same
//     applier (src/lib/db/applyChain.ts) — its self-assert runs, its receipt is captured.
//   * The restored prefix's notices travel in the snapshot's manifest, recorded when those files
//     really ran; the every-migration-prints-a-receipt floor is judged on the WHOLE chain exactly
//     as before (a snapshot of a migration that printed no receipt still counts as no receipt).
//   * NOTHING HERE REPLACES A FROM-ZERO APPLY AS A NET. `disposable-chain`
//     (.github/workflows/migrations-apply-proof.yml) applies the whole chain from nothing on a real
//     Postgres on every PR, and `npm run db:apply` still does so on wasm. This is a cache.
//
// ── WHY A SNAPSHOT CANNOT LIE ABOUT WHAT IT HOLDS ───────────────────────────────────────────────
//   1. ITS NAME IS ITS KEY, and the key covers the base (variant, engine version, base SQL) and
//      every file's name and normalised text, in order. A file that moved is a different key.
//   2. ITS MANIFEST NAMES EVERY FILE AND THE SHA-256 OF ITS BYTES. Load refuses a manifest whose
//      file list differs from the chain's first N names, whose key is not the recomputed key, or
//      whose tarball does not hash to what the manifest says.
//   3. THE ROUND TRIP IS PROVEN, EVERY TIME ONE IS WRITTEN. Before a snapshot reaches its name it
//      is restored into a second PostgreSQL and a content digest — every row of every table, every
//      sequence, every function body, every ACL — must equal the digest of the live database it
//      was dumped from. Then, on every LOAD, the restored database is digested again against the
//      manifest. A lossy restore (an unflushed sequence, an unlogged table) is a refusal, not a
//      silent drift.
//
// ── THE NORMALISED KEY (owner row: "a comment edit must not cost a full replay") ────────────────
// `normalizeSql()` drops SQL comments and collapses whitespace OUTSIDE quoted text only. Every
// dollar-quoted body (`$$ … $$`, `$fn$ … $fn$` — function bodies AND `do` blocks) and every string
// and quoted identifier is kept byte for byte, comments inside a body included: a body's text is
// what pg_get_functiondef() returns and what the chain's own assertions compare. So a header-comment
// edit keeps the key; any edit inside a body moves it. tests/db.prefixCache.spec.ts proves both.
//
// The BROWSER'S identity is untouched: src/lib/db/chain.ts `fingerprintChain()` still hashes the
// raw text, the image is still named and stamped with it, and the boot still refuses a mismatch.
// A comment edit therefore still produces a NEW image under a NEW name — built from the cached
// prefix in seconds instead of from migration 0001.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { createHash } from 'node:crypto'
import { existsSync } from 'node:fs'
import { mkdir, readdir, readFile, rename, rm, writeFile } from 'node:fs/promises'
import { gzipSync } from 'node:zlib'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = path.resolve(HERE, '..', '..')

/**
 * Bumped whenever the snapshot or manifest layout changes — OR WHAT `contentLines()` READS, since
 * every manifest carries a digest of it — so an old cache simply misses (it is in every key)
 * instead of being refused on load. Seen 2026-10-13: a cache written by an earlier digest was,
 * correctly, refused as "restored to a different database"; the number is what makes that a miss.
 */
export const PREFIX_CACHE_FORMAT = 2

// ─────────────────────────────────────────────────────────────────────────────────────────────────
// 1. THE NORMALISED TEXT
// ─────────────────────────────────────────────────────────────────────────────────────────────────

const isSpace = (c) => c === ' ' || c === '\t' || c === '\n' || c === '\r' || c === '\f' || c === '\v'
// PostgreSQL identifier characters (scan.l `ident_cont`): letters, digits, _, $, and any non-ASCII.
const isIdentChar = (c) => c !== undefined && (/[A-Za-z0-9_$]/.test(c) || c.charCodeAt(0) >= 0x80)
const DOLLAR_TAG_RE = /^\$(?:[A-Za-z_\u0080-￿][A-Za-z0-9_\u0080-￿]*)?\$/

/**
 * The SQL with comments removed and whitespace collapsed — OUTSIDE quoted text only.
 *
 * Kept verbatim: dollar-quoted text (with any comments inside it), '…' and E'…' strings, "…"
 * identifiers. A whitespace/comment run becomes ONE separator — "\n" if the run held a newline,
 * else " " — never nothing, so token boundaries survive; the newline is kept because PostgreSQL
 * gives it meaning between string constants ('a'\n'b' is 'ab'; 'a' 'b' is a syntax error).
 *
 * THROWS on an unterminated comment, string, identifier or dollar quote: a file the lexer cannot
 * finish is not one this function will pretend to have understood.
 */
export function normalizeSql(sql) {
  const n = sql.length
  let out = ''
  let gap = '' // '', ' ' or '\n' — the separator owed before the next token
  let i = 0
  const emit = (text) => {
    if (gap && out.length) out += gap
    gap = ''
    out += text
  }
  const owe = (sawNewline) => {
    if (sawNewline) gap = '\n'
    else if (!gap) gap = ' '
  }

  while (i < n) {
    const c = sql[i]

    if (isSpace(c)) {
      owe(c === '\n')
      i += 1
      continue
    }

    // -- line comment: to the end of the line (the newline itself is whitespace, handled above).
    if (c === '-' && sql[i + 1] === '-') {
      const nl = sql.indexOf('\n', i)
      i = nl === -1 ? n : nl
      owe(false)
      continue
    }

    // /* block comment */ — nests in PostgreSQL.
    if (c === '/' && sql[i + 1] === '*') {
      let depth = 1
      let j = i + 2
      let sawNewline = false
      while (j < n && depth > 0) {
        if (sql[j] === '/' && sql[j + 1] === '*') {
          depth += 1
          j += 2
        } else if (sql[j] === '*' && sql[j + 1] === '/') {
          depth -= 1
          j += 2
        } else {
          if (sql[j] === '\n') sawNewline = true
          j += 1
        }
      }
      if (depth > 0) throw new Error(`normalizeSql: unterminated /* comment at offset ${i}`)
      owe(sawNewline)
      i = j
      continue
    }

    // $tag$ … $tag$ — kept byte for byte. Not a quote when glued to an identifier (foo$bar) or a
    // positional parameter ($1 — the tag may not start with a digit, so the regex refuses it).
    if (c === '$' && !isIdentChar(sql[i - 1])) {
      const m = DOLLAR_TAG_RE.exec(sql.slice(i, i + 128))
      if (m) {
        const tag = m[0]
        const end = sql.indexOf(tag, i + tag.length)
        if (end === -1) throw new Error(`normalizeSql: unterminated dollar quote ${tag} at offset ${i}`)
        emit(sql.slice(i, end + tag.length))
        i = end + tag.length
        continue
      }
    }

    // '…' — '' is an escaped quote; in an E'…' string a backslash escapes the next character.
    if (c === "'") {
      const escapes = (sql[i - 1] === 'E' || sql[i - 1] === 'e') && !isIdentChar(sql[i - 2])
      let j = i + 1
      for (;;) {
        if (j >= n) throw new Error(`normalizeSql: unterminated string at offset ${i}`)
        if (escapes && sql[j] === '\\') j += 2
        else if (sql[j] === "'") {
          if (sql[j + 1] === "'") j += 2
          else break
        } else j += 1
      }
      emit(sql.slice(i, j + 1))
      i = j + 1
      continue
    }

    // "…" quoted identifier — "" is an escaped quote.
    if (c === '"') {
      let j = i + 1
      for (;;) {
        if (j >= n) throw new Error(`normalizeSql: unterminated quoted identifier at offset ${i}`)
        if (sql[j] === '"') {
          if (sql[j + 1] === '"') j += 2
          else break
        } else j += 1
      }
      emit(sql.slice(i, j + 1))
      i = j + 1
      continue
    }

    emit(c)
    i += 1
  }
  return out
}

// ─────────────────────────────────────────────────────────────────────────────────────────────────
// 2. THE ROLLING KEY
// ─────────────────────────────────────────────────────────────────────────────────────────────────

const sha256 = (text) => createHash('sha256').update(text).digest('hex')

/**
 * `keys[k]` identifies "base `baseId`, then files[0..k-1] applied" — so `keys[0]` is the bare base
 * and `keys[files.length]` the whole chain. Files must already be in apply (filename) order.
 * A changed name, a changed normalised text, an inserted or removed file, or a different base all
 * move every key from that point on, and no key before it.
 */
export function prefixKeys(files, baseId) {
  const keys = [sha256(`byeharu-prefix-cache/${PREFIX_CACHE_FORMAT}\0${baseId}`)]
  for (const f of files) {
    keys.push(sha256(`${keys[keys.length - 1]}\0${f.name}\0${normalizeSql(f.sql)}`))
  }
  return keys
}

/** The key of the WHOLE chain over `baseId` — what "this chain, modulo comments" means. */
export function chainCacheKey(files, baseId = '') {
  return prefixKeys(files, baseId)[files.length]
}

/**
 * Which prefix lengths get a snapshot when a chain of `n` files is applied: the last four (a new
 * migration on top restores n; an edit to the newest restores n-1; a short series of unpushed
 * migrations restores further back), plus one every 32 files as insurance against a deep edit.
 */
export function snapshotLengths(n) {
  const out = new Set()
  for (let k = Math.max(1, n - 3); k <= n; k += 1) out.add(k)
  for (let k = 32; k < n; k += 32) out.add(k)
  return out
}

// ─────────────────────────────────────────────────────────────────────────────────────────────────
// 3. THE CONTENT DIGEST — what "the restored database is the one that was dumped" is judged by
// ─────────────────────────────────────────────────────────────────────────────────────────────────

const USER_SCHEMAS = `n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg\\_%'`

/**
 * A digest of everything a later migration or a proof could observe: every row of every ordinary
 * table (as a SET — md5 of each row's text, sorted), every sequence's position, every function's
 * definition and ACL, every relation's ACL and RLS flags, every policy, every role, every default
 * ACL. Read-only.
 */
export async function contentLines(pg, { stableOnly = false } = {}) {
  const lines = []
  // `stableOnly` drops the columns two from-zero applies legitimately disagree on — uuids
  // (gen_random_uuid) and clock values (now()) — so two INDEPENDENT applies can be compared. The
  // snapshot round trip never uses it: a restore must reproduce those values too, exactly.
  const tables = await pg.query(`
    select format('%I.%I', n.nspname, c.relname) as t,
           coalesce((select string_agg(format('z.%I', a.attname), ', ' order by a.attnum)
                       from pg_attribute a
                      where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                        and a.atttypid not in ('uuid'::regtype, 'timestamptz'::regtype,
                                               'timestamp'::regtype, 'date'::regtype, 'interval'::regtype)),
                    'null') as stable_cols
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where c.relkind in ('r', 'p', 'm') and ${USER_SCHEMAS}
     order by 1`)
  for (const { t, stable_cols } of tables.rows) {
    const row = stableOnly ? `row(${stable_cols})::text` : 'z::text'
    const r = await pg.query(
      `select count(*)::bigint::text as n,
              coalesce(md5(string_agg(x.h, '' order by x.h)), '') as d
         from (select md5(${row}) as h from ${t} z) x`,
    )
    lines.push(`T ${t} ${r.rows[0].n} ${r.rows[0].d}`)
  }
  // format('%s', …) throughout: it renders "char", boolean and array columns without the operator
  // ambiguity `||` has for them.
  const blocks = [
    `select format('%I.%I %s', schemaname, sequencename, coalesce(last_value::text, 'unset')) as l
       from pg_sequences order by 1`,
    `select format('%s %s %s %s', p.oid::regprocedure,
              md5(case when p.prokind in ('f', 'p', 'w') then pg_get_functiondef(p.oid) else p.prosrc end),
              coalesce(p.proacl::text, '-'), pg_get_userbyid(p.proowner)) as l
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where ${USER_SCHEMAS} and p.prokind <> 'a' order by 1`,
    `select format('%I.%I %s %s %s %s %s', n.nspname, c.relname, c.relkind, coalesce(c.relacl::text, '-'),
              c.relrowsecurity, c.relforcerowsecurity, pg_get_userbyid(c.relowner)) as l
       from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where ${USER_SCHEMAS} order by 1`,
    `select format('%I.%I %s %s %s %s %s', schemaname, tablename, policyname, cmd, roles,
              coalesce(qual, ''), coalesce(with_check, '')) as l
       from pg_policies order by 1`,
    `select format('%s %s %s %s %s %s', rolname, rolsuper, rolinherit, rolcreaterole, rolcanlogin, rolbypassrls) as l
       from pg_roles order by 1`,
    `select format('%s %s %s %s', pg_get_userbyid(d.defaclrole), coalesce(n.nspname, '-'), d.defaclobjtype,
              d.defaclacl) as l
       from pg_default_acl d left join pg_namespace n on n.oid = d.defaclnamespace order by 1`,
    `select format('%s %s', n.nspname, coalesce(n.nspacl::text, '-')) as l from pg_namespace n
      where ${USER_SCHEMAS} order by 1`,
  ]
  for (const sql of blocks) {
    for (const { l } of (await pg.query(sql)).rows) lines.push(l)
    lines.push('--')
  }
  return lines
}

/** sha-256 over contentLines(). */
export async function contentDigest(pg, options) {
  return sha256((await contentLines(pg, options)).join('\n'))
}

// ─────────────────────────────────────────────────────────────────────────────────────────────────
// 4. SNAPSHOT FILES
// ─────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Rebuild a dumped tar keeping only the write-ahead-log segments in [first, last] — the range a
 * restored database replays from its last checkpoint. Everything else in pg_wal is recycled
 * scratch (DEV_LOG 2026-08-25: 64 of 67 retained megabytes). Lives here, the lower module, so the
 * world-image builder and the snapshot writer share ONE trim; build-image.mjs re-exports it.
 */
export function dropSurplusWal(tar, first, last) {
  const dec = new TextDecoder()
  const kept = []
  let off = 0
  let dropped = 0
  while (off + 512 <= tar.length) {
    const nameBytes = tar.subarray(off, off + 100)
    const nul = nameBytes.indexOf(0)
    const name = dec.decode(nul === -1 ? nameBytes : nameBytes.subarray(0, nul))
    if (!name) break // the two zero blocks that end a tar
    const size =
      parseInt(dec.decode(tar.subarray(off + 124, off + 136)).replace(/\0.*$/, '').trim(), 8) || 0
    const total = 512 + Math.ceil(size / 512) * 512
    const segment = /^\/?pg_wal\/([0-9A-F]{24})$/.exec(name)
    if (segment && (segment[1] < first || segment[1] > last)) {
      dropped += size
    } else {
      kept.push(tar.subarray(off, off + total))
    }
    off += total
  }
  if (dropped === 0) return tar

  const end = new Uint8Array(1024) // a tar ends with two zero blocks
  const out = new Uint8Array(kept.reduce((n, b) => n + b.length, 0) + end.length)
  let at = 0
  for (const block of kept) {
    out.set(block, at)
    at += block.length
  }
  out.set(end, at)
  return out
}

/**
 * Checkpoint, then dump the data directory with the surplus log trimmed. The CHECKPOINT is
 * load-bearing, not tidiness: PGlite's dump is a raw copy of its files, and without a checkpoint a
 * restore would crash-recover from the log — which advances every sequence by its prefetch (32)
 * and would make "the same world" hand out different ids. The content digest catches exactly that.
 */
export async function dumpCheckpointed(pg) {
  await pg.query('checkpoint')
  const dumped = new Uint8Array(await (await pg.dumpDataDir('none')).arrayBuffer())
  const wal = (
    await pg.query(
      `select pg_walfile_name(checkpoint_lsn) as needed,
              pg_walfile_name(pg_current_wal_lsn()) as current
         from pg_control_checkpoint()`,
    )
  ).rows[0]
  return { tar: dropSurplusWal(dumped, wal.needed, wal.current), dumpedBytes: dumped.length }
}

async function restore(bytes) {
  const { PGlite } = await import('@electric-sql/pglite')
  return PGlite.create({
    loadDataDir: new File([bytes], 'snapshot.tar.gz', { type: 'application/gzip' }),
  })
}

const fileStem = (variant, k, key) => `${variant}-p${String(k).padStart(4, '0')}-${key.slice(0, 24)}`

async function engineVersion() {
  const pkg = JSON.parse(
    await readFile(path.join(REPO_ROOT, 'node_modules', '@electric-sql', 'pglite', 'package.json'), 'utf8'),
  )
  return pkg.version
}

/**
 * The base identity a variant's keys start from: the variant's own id (what it does before
 * migration 0001, including any SQL it runs), the PGlite version (a data directory is an engine
 * artefact) and this file's format number.
 */
export async function variantBaseId(variant) {
  return `${variant.name}\0${variant.baseId}\0pglite ${await engineVersion()}`
}

/**
 * Find the longest cached prefix of `files` in `dir`, and PROVE it before handing it back.
 * Returns null when nothing usable is cached. A manifest that disagrees with the chain or with
 * its own tarball is a refusal (it is deleted and the search continues shorter), never a load.
 */
async function findLongestPrefix({ dir, variant, keys, files, log }) {
  if (!existsSync(dir)) return null
  const entries = new Set(await readdir(dir))
  for (let k = files.length; k >= 1; k -= 1) {
    const stem = fileStem(variant.name, k, keys[k])
    if (!entries.has(`${stem}.json`) || !entries.has(`${stem}.tar.gz`)) continue
    const why = []
    let manifest = null
    let bytes = null
    try {
      manifest = JSON.parse(await readFile(path.join(dir, `${stem}.json`), 'utf8'))
      bytes = new Uint8Array(await readFile(path.join(dir, `${stem}.tar.gz`)))
    } catch (err) {
      why.push(`unreadable (${err instanceof Error ? err.message : String(err)})`)
    }
    if (manifest) {
      if (manifest.format !== PREFIX_CACHE_FORMAT) why.push(`format ${manifest.format}`)
      if (manifest.key !== keys[k]) why.push('its key is not this chain prefix\'s key')
      const names = files.slice(0, k).map((f) => f.name)
      if (JSON.stringify(manifest.names) !== JSON.stringify(names)) why.push('its file list differs')
      if (!Array.isArray(manifest.notices) || manifest.notices.length !== k) why.push('its notices are not one per file')
      if (bytes && manifest.tarSha256 !== sha256(bytes)) why.push('its tarball does not hash to its manifest')
    }
    if (why.length) {
      log(`prefix cache: REFUSED ${stem} — ${why.join('; ')}; deleting it`)
      await rm(path.join(dir, `${stem}.json`), { force: true })
      await rm(path.join(dir, `${stem}.tar.gz`), { force: true })
      continue
    }
    return { k, stem, manifest, bytes }
  }
  return null
}

/**
 * Apply `files` (already in apply order) on top of `variant`'s base, restoring the longest cached
 * prefix and snapshotting along the way.
 *
 * `variant` = { name, baseId, create(): Promise<PGlite> } — `create` returns a fresh engine with
 * the base already applied (for `preamble`, the Supabase-shaped fixture; for `browser`, nothing).
 *
 * Returns the live database and EVERY file's record — the restored ones carry the notices from
 * the run that produced the snapshot and `restored: true` — so a caller's receipt floor is judged
 * on the whole chain, exactly as if it had all run here.
 */
export async function applyWithPrefixCache({
  variant,
  files,
  cacheDir,
  log = console.log,
  onProgress,
  fresh = process.env.BYEHARU_PREFIX_CACHE === 'off',
  // THE LAW (owner, 2026-10-17): a pull request's CI never rebuilds a world from scratch. With
  // BYEHARU_PREFIX_CACHE=required a chain with no usable cached prefix is a FAILURE, stated, not a
  // from-zero apply — docs/CI.md, "The law". CI sets it on a PR's build and proof steps, never on
  // main (main's from-zero apply is what makes the snapshots) and never when the PR changed the
  // chain machinery (scripts/ci/select-specs.mjs decides that: an edited old migration or preamble
  // moves every key). An explicit `fresh: true` (a test seeding a tiny chain) is deliberate and exempt.
  required = process.env.BYEHARU_PREFIX_CACHE === 'required',
  snapshots = true,
}) {
  const { applyChain } = await import('../../src/lib/db/applyChain.ts')
  const { orderChain } = await import('../../src/lib/db/chain.ts')
  const ordered = orderChain(files)
  const keys = prefixKeys(ordered, await variantBaseId(variant))
  const dir = path.join(cacheDir, variant.name)
  const t0 = Date.now()

  const hit = fresh ? null : await findLongestPrefix({ dir, variant, keys, files: ordered, log })
  let pg
  let restored = []
  let restoreMs = 0
  if (hit) {
    const tr = Date.now()
    pg = await restore(hit.bytes)
    // THE POSITIVE CONTROL ON LOAD: the database that came out of the tarball must be, row for row,
    // the one whose digest the manifest recorded when it was dumped.
    const digest = await contentDigest(pg)
    if (digest !== hit.manifest.digest) {
      await pg.close()
      throw new Error(
        `PREFIX SNAPSHOT REFUSED: ${hit.stem} restored to a database whose content digest ${digest.slice(0, 16)} ` +
          `is not the ${String(hit.manifest.digest).slice(0, 16)} recorded when it was dumped. Delete ` +
          `${dir} and rebuild; do not trust this cache.`,
      )
    }
    restoreMs = Date.now() - tr
    restored = ordered.slice(0, hit.k).map((f, i) => ({
      name: f.name,
      ms: hit.manifest.ms?.[i] ?? 0,
      notices: hit.manifest.notices[i],
      receipt: hit.manifest.notices[i].some((line) => /self-assert ok:/i.test(line)),
      restored: true,
    }))
    log(
      `prefix cache: restored ${hit.k}/${ordered.length} migration(s) from ${hit.stem} in ` +
        `${(restoreMs / 1000).toFixed(1)} s (key ${keys[hit.k].slice(0, 16)} = this chain's first ${hit.k} ` +
        `file(s), names and content digest verified); applying ${ordered.length - hit.k}`,
    )
  } else {
    if (required && !fresh) {
      throw new Error(
        `NO USABLE PREFIX SNAPSHOT for this chain (${ordered.length} file(s), variant ${variant.name}, ` +
          `cache ${dir}) — refusing to rebuild the world from zero on a pull request ` +
          '(BYEHARU_PREFIX_CACHE=required; docs/CI.md, "The law"). Main\'s run on this PR\'s base saves ' +
          'the snapshot a PR builds on; re-run this job after main\'s run has finished. A PR that changed ' +
          'the chain machinery or an old migration is exempt (scripts/ci/select-specs.mjs lifts it).',
      )
    }
    pg = await variant.create()
    log(`prefix cache: no cached prefix for this chain${fresh ? ' (disabled)' : ''}; applying all ${ordered.length}`)
  }

  const want = snapshots ? snapshotLengths(ordered.length) : new Set()
  const records = [...restored]
  let snapshotMs = 0
  const result = await applyChain(pg, ordered, onProgress, {
    startAt: hit ? hit.k : 0,
    afterEach: async (m, index) => {
      records.push({ ...m, restored: false })
      const k = index + 1
      if (!want.has(k)) return
      const ts = Date.now()
      await writeSnapshot({ pg, dir, variant, k, key: keys[k], records, log })
      snapshotMs += Date.now() - ts
    },
  })

  if (snapshots) await prune({ dir, variant, keys, keep: new Set([...want, hit?.k ?? 0]), log })

  return {
    db: pg,
    applied: records,
    restored: hit ? hit.k : 0,
    restoredFrom: hit ? hit.stem : null,
    key: keys[ordered.length],
    receipts: records.filter((r) => r.receipt).length,
    applyMs: result.ms,
    restoreMs,
    snapshotMs,
    ms: Date.now() - t0,
  }
}

async function writeSnapshot({ pg, dir, variant, k, key, records, log }) {
  const { tar } = await dumpCheckpointed(pg)
  const digest = await contentDigest(pg)
  const gz = new Uint8Array(gzipSync(tar, { level: 1 }))

  // THE ROUND TRIP, PROVEN BEFORE THE SNAPSHOT EARNS A NAME.
  const back = await restore(gz)
  let digestBack
  try {
    digestBack = await contentDigest(back)
  } finally {
    await back.close()
  }
  if (digestBack !== digest) {
    throw new Error(
      `PREFIX SNAPSHOT REFUSED at ${k} file(s): the dumped data directory restored to content digest ` +
        `${digestBack.slice(0, 16)}, not the live database's ${digest.slice(0, 16)}. A restore that ` +
        'loses or changes data cannot stand in for applying the chain.',
    )
  }

  const stem = fileStem(variant.name, k, key)
  const manifest = {
    format: PREFIX_CACHE_FORMAT,
    variant: variant.name,
    key,
    names: records.slice(0, k).map((r) => r.name),
    notices: records.slice(0, k).map((r) => r.notices),
    ms: records.slice(0, k).map((r) => r.ms),
    tarSha256: sha256(gz),
    digest,
    createdAt: new Date().toISOString(),
  }
  await mkdir(dir, { recursive: true })
  const tmp = `.${process.pid}.tmp`
  await writeFile(path.join(dir, `${stem}.tar.gz${tmp}`), gz)
  await writeFile(path.join(dir, `${stem}.json${tmp}`), JSON.stringify(manifest))
  // Tarball first, manifest last: a reader that sees the manifest sees a complete tarball.
  await rename(path.join(dir, `${stem}.tar.gz${tmp}`), path.join(dir, `${stem}.tar.gz`))
  await rename(path.join(dir, `${stem}.json${tmp}`), path.join(dir, `${stem}.json`))
  log(`prefix cache: snapshot after ${k} file(s) — ${(gz.length / 1048576).toFixed(2)} MB, round trip verified`)
}

/** Keep only this chain's wanted snapshots (and the one restored from); the cache stays bounded. */
async function prune({ dir, variant, keys, keep, log }) {
  if (!existsSync(dir)) return
  const wanted = new Set()
  for (const k of keep) if (k >= 1 && k < keys.length) wanted.add(fileStem(variant.name, k, keys[k]))
  let removed = 0
  for (const f of await readdir(dir)) {
    const stem = f.replace(/\.(json|tar\.gz)(\.\d+\.tmp)?$/, '')
    if (!stem.startsWith(`${variant.name}-p`) || wanted.has(stem)) continue
    await rm(path.join(dir, f), { force: true })
    removed += 1
  }
  if (removed) log(`prefix cache: pruned ${removed} file(s) not on this chain's snapshot path`)
}
