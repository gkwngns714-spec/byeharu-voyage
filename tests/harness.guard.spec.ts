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

interface Tokens {
  /** The file's top-level text: comments gone, every literal AND every dollar-quoted body one word, so
   *  splitting on ';' gives the top-level statements. */
  top: string
  /** The file's code: as `top`, but a `do` body and an `execute` literal inside one are inlined (their own
   *  literals stripped, recursively), because that is where a scene writes. */
  code: string
}

const LIT = ' LIT '

function tokenize(text: string): Tokens {
  let top = ''
  let code = ''
  let i = 0
  let lastWord = ''
  const n = text.length
  const word = /[A-Za-z_][A-Za-z0-9_]*/y
  while (i < n) {
    const c = text[i]
    const c2 = text[i + 1]
    if (c === '-' && c2 === '-') {
      const e = text.indexOf('\n', i)
      i = e < 0 ? n : e
      continue
    }
    if (c === '/' && c2 === '*') {
      let depth = 1
      i += 2
      while (i < n && depth > 0) {
        if (text[i] === '/' && text[i + 1] === '*') {
          depth++
          i += 2
        } else if (text[i] === '*' && text[i + 1] === '/') {
          depth--
          i += 2
        } else i++
      }
      top += ' '
      code += ' '
      continue
    }
    if (c === "'") {
      let j = i + 1
      while (j < n) {
        if (text[j] === "'") {
          if (text[j + 1] === "'") {
            j += 2
            continue
          }
          break
        }
        j++
      }
      top += LIT
      code += LIT
      i = j + 1
      continue
    }
    if (c === '"') {
      const j = text.indexOf('"', i + 1)
      const e = j < 0 ? n : j + 1
      top += text.slice(i, e)
      code += text.slice(i, e)
      i = e
      continue
    }
    if (c === '$') {
      const m = /^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/.exec(text.slice(i, i + 64))
      if (m) {
        const tag = m[0]
        const close = text.indexOf(tag, i + tag.length)
        const body = text.slice(i + tag.length, close < 0 ? n : close)
        top += LIT
        if (lastWord === 'do' || lastWord === 'execute') code += ' ; ' + tokenize(body).code + ' ; '
        else code += LIT
        i = close < 0 ? n : close + tag.length
        continue
      }
    }
    word.lastIndex = i
    const w = word.exec(text)
    if (w) {
      lastWord = w[0].toLowerCase()
      top += w[0]
      code += w[0]
      i += w[0].length
      continue
    }
    top += c
    code += c
    i++
  }
  return { top, code }
}

const statements = (top: string) =>
  top
    .split(';')
    .map((s) => s.replace(/\s+/g, ' ').trim().toLowerCase())
    .filter((s) => s !== '')

/** The statements a read-only transaction refuses, plus the PL/pgSQL verbs that run anything. */
const WRITE =
  /\b(insert|update|delete|merge|truncate|create|alter|drop|grant|revoke|copy|refresh|call|perform|execute)\b/gi
const EXPLAIN_ANALYZE = /\bexplain\s*(?:\([^)]*\banalyze\b[^)]*\)|analyze\b)/i
const GAME_CALL = /\b(public|voyage|cmd|world)\.([a-z_][a-z0-9_]*)\s*\(/gi

const writesIn = (code: string): string[] => {
  const found = new Set<string>()
  for (const m of code.matchAll(WRITE)) found.add(m[1].toLowerCase())
  if (EXPLAIN_ANALYZE.test(code)) found.add('explain analyze')
  return [...found].sort()
}
const gameCallsIn = (code: string): string[] => {
  const found = new Set<string>()
  for (const m of code.matchAll(GAME_CALL)) found.add(`${m[1]}.${m[2]}`.toLowerCase())
  return [...found].sort()
}

/** The first statement as `proof-0343.mjs`'s `guarded()` reads it: the first line that is neither blank nor a `--` comment. */
const firstLine = (text: string) => text.split('\n').find((l) => !l.startsWith('--') && l.trim() !== '') ?? ''
const isGuarded = (text: string) => firstLine(text) === GUARD
const isReadOnlyTransaction = (stmts: string[]) =>
  stmts.length >= 2 &&
  /^(?:begin|start) (?:transaction |work )?read only$/.test(stmts[0]) &&
  /^(?:commit|rollback)$/.test(stmts[stmts.length - 1])

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
