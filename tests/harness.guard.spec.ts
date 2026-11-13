// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HARNESS GUARD — a SQL file under scripts/ops/harness/ is a PROD CHECK or a LOCAL SCENE, and says so
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// CLAUDE.md: "Prod is read-only for checks. Wrap them in `begin transaction read only`, and call only
// functions whose `provolatile` is 's' or 'i'." The harness holds ~145 SQL files that are run in two ways.
// A PROD CHECK goes through `npx supabase db query --linked -f <file>` against the LIVE game. A SCENE is
// read by a local proof runner (`proof-XXXX.mjs`) and executed on the cached PGlite world inside a
// transaction the runner rolls back — and a scene WRITES: purses rewritten, switches flipped, real jobs
// run. Run through `db query --linked -f`, a scene would COMMIT on production what the harness rolls
// back, and nothing in the CLI, the file name or the folder would have said no. On 2026-11-08 a review
// found 91 of 145 files carrying neither the read-only wrapper nor any refusal, among them two bare
// writing `do` blocks (`city-reserve/dark-scene.sql`, `cost.sql`). This spec is the rule with teeth.
//
// THE TWO CLASSES, and what each must say about itself (scripts/ops/harness/README.md, "Two classes"):
//   PROD CHECK   a pure read. Its first statement is `begin transaction read only`, its last `commit`
//                (or `rollback`: the same thing for a transaction that wrote nothing). Postgres then
//                refuses any write inside it, whatever the file turns out to contain.
//   LOCAL SCENE  anything that writes, or calls a function the chain does not declare stable or
//                immutable. Its first statement is THE GUARD: a `do` block that raises unless
//                `inet_server_addr()` is null — null on PGlite, which has no server address, and never
//                null on a Supabase connection. A scene run on production refuses before its second
//                statement. `city-reserve/proof-0343.mjs` refuses to run a scene file without it.
//
// HOW A FILE IS READ. The SQL is tokenised, not grepped. Comments go; every string and dollar-quoted
// literal becomes one word, so a hunk `$h$ … perform … $h$` inside a prod check is DATA and never a
// write; the body of a `do` block, and of an `execute` literal inside one, is CODE, because that is
// where a scene writes. A write is any statement a read-only transaction refuses (insert, update,
// delete, merge, truncate, create, alter, drop, grant, revoke, copy, refresh) plus `call`, `perform`
// and `execute` (PL/pgSQL running what it likes) and `explain analyze` (it RUNS the statement).
// Volatility comes from the chain itself: the last `create function` of each name under
// supabase/migrations, its `stable` / `immutable` word read off the header, `volatile` by default —
// the same answer `volatility.sql` asks production for, read statically.
//
// PURE SPEC. No `page` fixture. One in-memory PGlite for the guard's own proof; Playwright runs the
// file as a plain Node process.

import { test, expect } from '@playwright/test'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'
import { gameCallsIn, isReadOnlyTransaction, readOnlyVerdict, statements, tokenize, writesIn } from '../scripts/ops/harness/read-only.mjs'

const ROOT = path.resolve(process.cwd())
const HARNESS = path.join(ROOT, 'scripts', 'ops', 'harness')
const MIGRATIONS = path.join(ROOT, 'supabase', 'migrations')

/** THE GUARD, byte for byte: the first statement of every local scene. `proof-0343.mjs` holds the
 *  same text and refuses a scene file that does not start with it; the pin test below keeps the two equal. */
const GUARD =
  "do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;"

const read = (f: string) => readFileSync(f, 'utf8').replaceAll('\r', '')

/** Every file under `dir` matching `exts`, as POSIX paths relative to `dir`. */
function filesUnder(dir: string, exts: RegExp): string[] {
  const out: string[] = []
  const walk = (d: string) => {
    for (const name of readdirSync(d)) {
      const full = path.join(d, name)
      if (statSync(full).isDirectory()) walk(full)
      else if (exts.test(name)) out.push(path.relative(dir, full).split(path.sep).join('/'))
    }
  }
  walk(dir)
  return out.sort()
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 1. THE READER
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// The reader lives in scripts/ops/harness/read-only.mjs (tokenize, statements, writesIn, gameCallsIn,
// isReadOnlyTransaction, readOnlyVerdict): ONE reader, imported here and asked by every ops shell script
// before it sends a file to production (`node read-only.mjs <file>`). Section 5 holds the scripts to it.

/** The first statement as `proof-0343.mjs`'s `guarded()` reads it: the first line that is neither blank nor a `--` comment. */
const firstLine = (text: string) => text.split('\n').find((l) => !l.startsWith('--') && l.trim() !== '') ?? ''
const isGuarded = (text: string) => firstLine(text) === GUARD

test('the reader: a hunk is data, a do body is code, an execute inside it is code, a wrapper is seen', () => {
  // A prod check whose hunk literal is full of write words is still a pure read.
  const check = tokenize(
    "-- perform in a comment\nbegin transaction read only;\nwith h(old) as (values ($h$ perform public.tick(); insert into x values ('a'); $h$)) select 'update' as word, count(*) from h;\ncommit;",
  )
  expect(writesIn(check.code)).toEqual([])
  expect(statements(check.top)).toEqual(['begin transaction read only', 'with h(old) as (values ( lit )) select lit as word, count(*) from h', 'commit'])
  expect(isReadOnlyTransaction(statements(check.top))).toBe(true)

  // A do block that writes is a write, and a function call inside it is seen.
  const scene = tokenize("do $$ begin update public.world_config set value = 'x'; perform public.crown_aid(null); end $$;")
  expect(writesIn(scene.code)).toEqual(['perform', 'update'])
  expect(gameCallsIn(scene.code)).toEqual(['public.crown_aid'])
  expect(isReadOnlyTransaction(statements(scene.top))).toBe(false)

  // An `execute $f$ … $f$` inside a do block is code too (the chain creates most functions that way).
  const nested = tokenize('do $m$ begin execute $f$ create function public.f(p int) returns int language sql stable as $b$ select 1 $b$ $f$; end $m$;')
  expect(writesIn(nested.code)).toEqual(['create', 'execute'])
  expect(nested.code).toMatch(/create function public\.f\(p int\) returns int language sql stable as\s+LIT/)

  // The guard is the first statement only when it is the first non-comment line, exactly.
  expect(isGuarded(`-- a header\n\n${GUARD}\ndo $$ begin end $$;`)).toBe(true)
  expect(isGuarded(`select 1;\n${GUARD}`)).toBe(false)
  expect(isGuarded(GUARD.replace(' is not null', ' is null'))).toBe(false)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 2. VOLATILITY, READ OFF THE CHAIN
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `volatility.sql` asks production `provolatile` before a prod check runs; this is the same question put
// to the chain's text. The last `create [or replace] function|procedure schema.name(` wins; the keyword is
// read from that statement with its body removed (`stable`, `immutable`, else volatile; a procedure is
// `p` and is only ever reached by `call`, a write).

type Volatility = 's' | 'i' | 'v' | 'p'

/** Functions the chain makes by EXECUTE-ing text it builds at run time (a rewritten `pg_get_functiondef`,
 *  a `format()`), so no `create function` the reader can see names them. Each entry is the `provolatile`
 *  read off the cached world (head 0338, 2026-11-08: 849 live functions, every one the reader DID see
 *  agreeing with it, these seven unseen). Add one only with that reading in hand. */
const DERIVED: Readonly<Record<string, Volatility>> = {
  // 20260818000203…:299 rewrites voyage.ship_speed_at's definition into voyage.fleet_speed_at; both pure reads.
  'voyage.fleet_speed_at': 's',
  'voyage.ship_speed_at': 's',
  // 20260818000169…:514-560 re-creates world.quote_priced from a hunk-edited definition.
  'world.quote_priced': 's',
  'public.standing_route_state': 's',
  'public.stats_recent': 's',
  'world.skill_bonuses_at': 's',
  'world.voyage_view': 's',
}

function chainVolatility(): Map<string, Volatility> {
  const vol = new Map<string, Volatility>()
  for (const file of readdirSync(MIGRATIONS).filter((n) => n.endsWith('.sql')).sort()) {
    const { code } = tokenize(read(path.join(MIGRATIONS, file)))
    for (const s of code.split(';')) {
      const c = /\bcreate\s+(?:or\s+replace\s+)?(function|procedure)\s+([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*\(/i.exec(s)
      if (c) {
        const kind: Volatility =
          c[1].toLowerCase() === 'procedure' ? 'p' : /\bimmutable\b/i.test(s) ? 'i' : /\bstable\b/i.test(s) ? 's' : 'v'
        vol.set(`${c[2]}.${c[3]}`.toLowerCase(), kind)
        continue
      }
      const a = /\balter\s+function\s+([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*\([^)]*\)([\s\S]*)$/i.exec(s)
      if (a) {
        const kw = /\b(immutable|stable|volatile)\b/i.exec(a[3])
        if (kw) vol.set(`${a[1]}.${a[2]}`.toLowerCase(), kw[1][0].toLowerCase() as Volatility)
      }
    }
  }
  return vol
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 3. THE TREE
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** Pure reads a LOCAL runner executes with `db.query(sql)` inside its OWN `begin … rollback`. The runner's
 *  transaction is the wrapper: `begin … commit` in the file would COMMIT the runner's work, and the guard
 *  (a second statement) would break `db.query`'s one-statement protocol. Each entry names its runner, and
 *  the test checks that runner still names the file. */
const RUNNER_QUERIES: Readonly<Record<string, string>> = {
  'haul/bands.sql': 'haul/sweep.mjs',
  'speed/player.sql': 'speed/players.mjs',
}

/** Not SQL: `sim/dump2.sql`'s OUTPUT, `pg_get_functiondef` bodies behind `===== name [volatility]` lines.
 *  Nothing in them can run — the first line is a syntax error, and a simple-protocol query parses the whole
 *  string before it runs any of it. The test checks they still start that way. */
const NOT_SQL = new Set(['sim/bodies2.sql', 'sim/npc_bodies.sql'])

test('every harness SQL file is a prod check inside a read-only transaction or a guarded local scene', () => {
  const vol = chainVolatility()
  expect(vol.size, 'no functions were read off the chain — the volatility reader is broken').toBeGreaterThan(500)

  const files = filesUnder(HARNESS, /\.sql$/i)
  expect(files.length, 'no harness SQL files were read — the walker is broken').toBeGreaterThan(100)

  const unguardedWriters: string[] = []
  const unwrappedReads: string[] = []
  const brokenExceptions: string[] = []
  let scenes = 0
  let checks = 0

  for (const rel of files) {
    const text = read(path.join(HARNESS, rel))
    if (NOT_SQL.has(rel)) {
      if (!/^=====/.test(firstLine(text))) brokenExceptions.push(`${rel}: listed as not-SQL, but its first line is not a ===== separator`)
      continue
    }
    const { top, code } = tokenize(text)
    const stmts = statements(top)
    const writes = writesIn(code)
    const volatile =
      writes.length > 0
        ? []
        : gameCallsIn(code)
            .map((fn) => [fn, vol.get(fn) ?? DERIVED[fn]] as const)
            .filter(([, v]) => v !== 's' && v !== 'i')
            .map(([fn, v]) => `${fn} [${v ?? 'not created by any migration'}]`)
    const guarded = isGuarded(text)

    if (writes.length > 0 || volatile.length > 0) {
      scenes++
      if (!guarded) unguardedWriters.push(`${rel}  — ${writes.length ? 'writes: ' + writes.join(', ') : 'calls ' + volatile.join(', ')}`)
      continue
    }
    if (guarded) {
      scenes++ // a read-only scene (crown-ships/parity-scene.sql): local by declaration, its runner's transaction its wrapper
      continue
    }
    if (rel in RUNNER_QUERIES) {
      const runner = path.join(HARNESS, RUNNER_QUERIES[rel])
      if (!read(runner).includes(`'./${path.basename(rel)}'`)) brokenExceptions.push(`${rel}: ${RUNNER_QUERIES[rel]} no longer names it; the exception has no runner`)
      continue
    }
    if (isReadOnlyTransaction(stmts)) {
      checks++
      continue
    }
    unwrappedReads.push(`${rel}  — first statement "${(stmts[0] ?? '').slice(0, 60)}", last "${(stmts[stmts.length - 1] ?? '').slice(0, 40)}"`)
  }

  expect(scenes, 'no scene was recognised — the write reader is broken').toBeGreaterThan(10)
  expect(checks, 'no prod check was recognised — the wrapper reader is broken').toBeGreaterThan(50)
  expect(brokenExceptions, 'an exception listed above no longer holds; fix the list, not the file').toEqual([])

  expect(
    unguardedWriters,
    `A harness file WRITES (or calls a function the chain does not declare stable or immutable) and does not ` +
      `open with the guard. Run through \`db query --linked -f\` it would commit on production what its runner ` +
      `rolls back. Make its FIRST statement exactly this line, after the header comments and before anything else:\n` +
      `${GUARD}\n` +
      `A function the chain creates by rewriting another's definition text goes in DERIVED, with its provolatile ` +
      `read off a world. Nothing else changes (scripts/ops/harness/README.md, "Two classes").\n` +
      unguardedWriters.join('\n'),
  ).toEqual([])

  expect(
    unwrappedReads,
    `A harness file is a pure read and is NOT a read-only transaction. A prod check opens with ` +
      `\`begin transaction read only;\` and closes with \`commit;\`, so Postgres itself refuses any write the ` +
      `file turns out to hold. If it is a scene a local runner rolls back, give it the guard instead; if a ` +
      `runner executes it with db.query inside its own transaction, list it in RUNNER_QUERIES with that runner ` +
      `(scripts/ops/harness/README.md, "Two classes").\n` +
      unwrappedReads.join('\n'),
  ).toEqual([])
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 4. THE GUARD ITSELF
// ═══════════════════════════════════════════════════════════════════════════════════════════════

test('the guard text is one text: proof-0343.mjs refuses a scene without exactly it', () => {
  const runner = read(path.join(HARNESS, 'city-reserve', 'proof-0343.mjs'))
  expect(
    runner.includes(`const GUARD = ${JSON.stringify(GUARD)}`),
    'proof-0343.mjs holds a different GUARD text from this spec; the two must stay byte-equal, or a scene one accepts the other refuses',
  ).toBe(true)
  // …and every guarded file in the tree carries that exact line as its first statement (not a near copy).
  const guardedFiles = filesUnder(HARNESS, /\.sql$/i).filter((rel) => isGuarded(read(path.join(HARNESS, rel))))
  expect(guardedFiles.length).toBeGreaterThan(10)
  for (const rel of guardedFiles) expect(firstLine(read(path.join(HARNESS, rel))), rel).toBe(GUARD)
})

test('the guard passes on PGlite (no server address) and refuses where the address is not null', async () => {
  test.setTimeout(120_000)
  const { PGlite } = await import('@electric-sql/pglite')
  const db = await PGlite.create()
  try {
    // The premise, on the real engine the harness runs on: PGlite has no server address.
    const local = await db.query<{ local: boolean }>('select inet_server_addr() is null as local')
    expect(local.rows[0].local).toBe(true)
    // So the guard, byte for byte as the scenes carry it, passes and lets the scene follow.
    await expect(db.exec(GUARD)).resolves.toBeDefined()
    // And the same block with a server address where PGlite has none refuses, with the scene's own words — the
    // branch a Supabase connection takes, where inet_server_addr() is never null.
    await expect(db.exec(GUARD.replace('inet_server_addr()', "'10.0.0.1'::inet"))).rejects.toThrow(/local PGlite world only: this scene writes/)
  } finally {
    await db.close()
  }
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 5. THE SHELL SCRIPTS ASK THE SAME READER
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A script that sends a FILE to production (`db query --linked … -f`) refuses a file that is not a read-only
// prod check. Until 2026-11-12 each looked for the words in the file's first 40 or 400 BYTES; on 2026-11-12
// 04:49 UTC the 30-minute after-check of 0353 refused its own `combat-log/after.sql`, whose header comment is
// 700 bytes long. The rule is the first STATEMENT, and its one judge is `read-only.mjs` (readOnlyVerdict).

test('the judge reads the first statement, not the first bytes: a long CRLF header passes, a write refuses', () => {
  const header = `-- ${'a prod check with a long header. '.repeat(20)}\r\n-- its second line\r\n\r\n/* and a block\r\n   comment */\r\n`
  expect(header.length, 'the header must be longer than the old 400-byte window').toBeGreaterThan(600)

  // The file that stopped the after-check: a long header, CRLF line endings, mixed case.
  expect(readOnlyVerdict(`${header}Begin Transaction READ ONLY;\r\nselect 1;\r\ncommit;\r\n`)).toEqual({ ok: true, reason: '' })
  expect(readOnlyVerdict(`${header}begin transaction read only;\r\nselect 1;\r\nrollback;\r\n`).ok).toBe(true)

  // A write first refuses, though the words the old guard looked for are in its first 40 bytes.
  const updateFirst = readOnlyVerdict("update public.world_config set value = 'x'; -- begin transaction read only\nbegin transaction read only;\nselect 1;\ncommit;\n")
  expect(updateFirst.ok).toBe(false)
  expect(updateFirst.reason).toContain('its first statement is "update public.world_config')
  // The words in a comment or a literal are not a statement.
  expect(readOnlyVerdict('-- begin transaction read only\nselect 1;\ncommit;\n').ok).toBe(false)
  expect(readOnlyVerdict("select 'begin transaction read only';\ncommit;\n").ok).toBe(false)
  // A plain `begin` is not read only; a file left open is not a prod check.
  expect(readOnlyVerdict('begin;\nselect 1;\ncommit;\n').ok).toBe(false)
  expect(readOnlyVerdict('begin transaction read only;\nselect 1;\n').ok).toBe(false)
  // A write verb inside the wrapper refuses too (Postgres would refuse it; the script says so first)…
  expect(readOnlyVerdict('begin transaction read only;\nupdate public.ports set name = name;\ncommit;\n')).toEqual({ ok: false, reason: 'it writes: update' })
  expect(readOnlyVerdict('begin transaction read only;\nexplain analyze select 1;\ncommit;\n').reason).toBe('it writes: explain analyze')
  // …and a hunk full of write words is data, as it is for the tree.
  expect(readOnlyVerdict('begin transaction read only;\nselect count(*) from (values ($h$ update x set y = 1; $h$)) h(old);\ncommit;\n').ok).toBe(true)
})

test('every ops shell script that sends a file to production asks read-only.mjs first, and none counts bytes', () => {
  const OPS = path.join(ROOT, 'scripts', 'ops')
  const scripts = filesUnder(OPS, /\.sh$/i)
  expect(scripts.length, 'no ops shell script was read — the walker is broken').toBeGreaterThan(10)

  const senders: string[] = []
  const wrong: string[] = []
  for (const rel of scripts) {
    const lines = read(path.join(OPS, rel)).split('\n')
    const code = lines.map((l) => (l.trimStart().startsWith('#') ? '' : l))
    if (code.some((l) => /\bhead\s+-c\b/.test(l) && /read only/i.test(l))) wrong.push(`${rel}: judges "read only" by a byte count (head -c)`)
    const send = code.findIndex((l) => /db query\b.*--linked\b.*\s-f\s/.test(l))
    if (send < 0) continue
    senders.push(rel)
    const ask = code.findIndex((l) => /^\s*node ".*\/\.\.\/read-only\.mjs" "\$\w+" \|\| exit 3\b/.test(l))
    if (ask < 0 || ask > send) wrong.push(`${rel}: sends a file to production without asking read-only.mjs before it`)
  }
  // The five that send a file today; a sixth must ask too (the loop above), this list only proves the scan sees them.
  expect(senders).toEqual(['harness/arrfast/pq.sh', 'harness/combat-log/after-check.sh', 'harness/raid/after-check.sh', 'harness/raid/pq.sh', 'harness/sim/pq.sh'])
  expect(
    wrong,
    'An ops script sends a SQL file to production and does not ask the one judge first. Put this line before the ' +
      '`db query --linked -f`, with the file as its argument:\n  node "$(dirname "$0")/../read-only.mjs" "$1" || exit 3\n' +
      wrong.join('\n'),
  ).toEqual([])
})

test('read-only.mjs on the command line: exit 0 for a prod check, exit 3 and REFUSING for anything else', async () => {
  const { spawnSync } = await import('node:child_process')
  const judge = path.join(HARNESS, 'read-only.mjs')
  const run = (file: string) => spawnSync(process.execPath, [judge, file], { encoding: 'utf8' })

  // The three files the 0353 after-check sends, as they lie in this checkout (CRLF or LF).
  for (const rel of ['combat-log/after.sql', 'two-sides/golden.sql', 'combat-log/after-lit.sql']) {
    const r = run(path.join(HARNESS, rel))
    expect(`${rel}: ${r.status} ${r.stdout}`).toBe(`${rel}: 0 `)
  }
  // `after.sql` is the file the 400-byte window missed: its wrapper opens after byte 400.
  expect(readFileSync(path.join(HARNESS, 'combat-log', 'after.sql'), 'utf8').toLowerCase().indexOf('begin transaction read only')).toBeGreaterThan(400)

  // A scene that writes, and a file that is not there, both refuse.
  const scene = run(path.join(HARNESS, 'combat-log', 'cost.sql'))
  expect(scene.status).toBe(3)
  expect(scene.stdout).toMatch(/^REFUSING: .*cost\.sql is not a read-only prod check/)
  const missing = run(path.join(HARNESS, 'combat-log', 'no-such-file.sql'))
  expect(missing.status).toBe(3)
  expect(missing.stdout).toMatch(/^REFUSING: /)
})
