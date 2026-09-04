// ═══════════════════════════════════════════════════════════════════════════════════════════════
// DUPLICATION — the shapes this project keeps re-growing, made to FAIL rather than to be noticed
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE OWNER, 2026-08-22: "most of all, sort out your code so that it is well tidy and organized.
// No spaghetti. And for the future as well, design and organize code so that it does not create
// spaghetti."
//
// `tests/sections.spec.ts` guards WHERE things live. This file guards HOW MANY of them there are.
// The law they both serve is written out in `docs/NO_SPAGHETTI.md`; this is its teeth.
//
// ── WHY, MEASURED (every count below is cited, none is remembered) ─────────────────────────────
//   7 copies of "is this group on a sortie?"            docs/CORE_REUSE.md:1479
//  11 copies of "is this fleet docked?"                 docs/CORE_REUSE.md:1480
//  12 hand-written copies of the chip recipe            src/components/ui/buttonStyles.ts:31-35
//   4 hand-written text-field recipes                   src/components/ui/Input.tsx:5-8
//   7 answers to "how much fits in this hull?"          20260818000017_a_quartermaster…sql:18-31
//        — 4 server, 3 client, and ONE OF THEM WAS ALREADY WRONG: MarketScreen forgot the stores
//          and had been wrong since the day it was written. Nobody introduced a bug; somebody
//          added a term to one copy. That is the disease: duplication does not fail when it is
//          written, it fails when one copy is edited.
//
// ── WHAT THIS FILE IS NOT ──────────────────────────────────────────────────────────────────────
// It is not a style linter and it is not a similarity metric looking for a job. A guard that cries
// wolf gets deleted, which is worse than no guard, so EVERY threshold below was measured against
// the tree before it was chosen and every rule stands at ZERO findings today. Where a shape could
// not be made precise — an unordered `limit 1` in a self-assert is the honest example, since "the
// player's only fleet" and 0014's lottery are statically identical — the rule is NOT here. It is
// in `docs/NO_SPAGHETTI.md` §4 as a reviewer's duty, which is where an unenforceable rule belongs.
//
// PURE SPEC. No `page` fixture, so Playwright runs it as a plain Node process in about a second.

import { test, expect } from '@playwright/test'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'

const ROOT = path.resolve(process.cwd())
const SRC = path.join(ROOT, 'src')
const MIGRATIONS = path.join(ROOT, 'supabase', 'migrations')

/** Every TS/TSX file under `dir`, as repo-relative POSIX paths from `src/`. */
function sourceFiles(dir: string): string[] {
  const out: string[] = []
  const walk = (d: string) => {
    for (const name of readdirSync(d)) {
      const full = path.join(d, name)
      if (statSync(full).isDirectory()) walk(full)
      else if (/\.tsx?$/.test(name)) out.push(full)
    }
  }
  walk(dir)
  return out
}

const rel = (f: string) => path.relative(SRC, f).split(path.sep).join('/')
const read = (f: string) => readFileSync(f, 'utf8')

/** `src/components/**` is ONE authority — the design system. See the recipe test for why. */
const isDesignSystem = (p: string) => p.startsWith('components/')

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 1. COLOUR HAS ONE SOURCE
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// `src/index.css:5` states it: "Screens never hardcode palette literals (slate-900, white/40, …):
// they compose the primitives." Fourteen of the material tokens are derived with `color-mix` off
// the palette precisely so that retuning `--color-accent` retunes the material with it
// (docs/DEV_LOG.md:244-252) — and a literal anywhere is a second palette that will not move when
// the first one does.
//
// The repo has ZERO of these today. That is a cheap number to keep and an expensive one to
// recover, which is exactly when a guard is worth writing.

const COLOUR_PREFIX =
  'bg|text|border|ring|ring-offset|from|via|to|fill|stroke|shadow|outline|decoration|divide|placeholder|caret|accent|selection'
const TAILWIND_PALETTE =
  'slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose'
// `transparent`, `current` and `inherit` are structural, not colours, and are deliberately allowed.
const PALETTE_LITERAL = new RegExp(
  `\\b(?:${COLOUR_PREFIX})-(?:(?:${TAILWIND_PALETTE})-(?:50|100|200|300|400|500|600|700|800|900|950)|white|black)\\b`,
  'g',
)

test('no raw palette literal — colour is a token, and the tokens live in src/index.css', () => {
  const hits: string[] = []
  for (const f of sourceFiles(SRC)) {
    const text = read(f)
    const lines = text.split('\n')
    for (let i = 0; i < lines.length; i++) {
      for (const m of lines[i].matchAll(PALETTE_LITERAL)) hits.push(`${rel(f)}:${i + 1}  ${m[0]}`)
    }
  }

  expect(
    hits,
    `A raw Tailwind palette literal is a SECOND PALETTE. Retuning --color-accent in src/index.css ` +
      `moves every token derived from it and leaves this one behind. Use the semantic token — ` +
      `bg-app / bg-surface / bg-surface-2 / text-ink / text-ink-muted / text-ink-faint / ` +
      `border-edge / accent / success / warning / danger — or add a token to src/index.css @theme ` +
      `if the meaning is genuinely new (docs/NO_SPAGHETTI.md §2).\n` + hits.join('\n'),
  ).toEqual([])
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 2. A CLASS RECIPE IS WRITTEN ONCE
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// THE SHAPE THIS CATCHES, in its own words (src/components/ui/buttonStyles.ts:31-35): "an audit on
// 2026-08-20 found TWELVE hand-written copies of these two recipes across Command, Market and
// Fleets, drifting in border colour and hover between copies." And Input.tsx:5-8: FOUR text-field
// recipes "differing in border colour, in focus ring, in padding and in whether they cleared the
// 44px touch floor — four answers to one question, drifting apart every time one of them was
// touched."
//
// HOW IT READS A RECIPE. A hand-written copy is never one string literal — it is a `className={[
// … ]}` with the base on one line, the state on the next and a ternary for the size. So the whole
// `className=` expression is taken as ONE recipe and every utility token inside it is collected,
// both arms of a ternary included. Reading the literals one at a time would miss every real copy.
//
// THE THRESHOLDS, MEASURED AGAINST THIS TREE RATHER THAN CHOSEN:
//   · a recipe must carry >= 5 utility tokens. At 4 the tree has seven honest repeats of the same
//     typographic idiom (`font-mono text-[10px] text-ink-faint tracking-wider` — the small-caps
//     caption, in four files). That is an idiom, not a recipe, and flagging it would be the wolf.
//   · two recipes in DIFFERENT FILES are a duplicate at >= 75% token overlap. The closest pair in
//     the tree today sits at 0.71 (`break-words flex-1 font-mono min-w-0 text-ink text-sm` against
//     its `text-xs` twin) — real headroom, and 0.75 still catches a copy that drifted by a token.
//   · `src/components/**` counts as ONE authority: it is the place recipes are SUPPOSED to live,
//     and a screen hand-writing a button is a different (and worse) thing than two primitives
//     sharing a house style. The design system's own internal repeat — the eyebrow, in Card.tsx,
//     PageHeader.tsx and Sheet.tsx while SectionLabel exists — is named in docs/NO_SPAGHETTI.md §7
//     rather than silently forgotten.
const MIN_RECIPE_TOKENS = 5
const MAX_RECIPE_OVERLAP = 0.75

interface Recipe {
  file: string
  line: number
  tokens: Set<string>
}

/** The whole `className=` expression, brace-balanced, with its 1-based line. */
function classNameRegions(text: string): { region: string; line: number }[] {
  const out: { region: string; line: number }[] = []
  const re = /className\s*=\s*/g
  let m: RegExpExecArray | null
  while ((m = re.exec(text)) !== null) {
    const start = m.index + m[0].length
    const line = text.slice(0, start).split('\n').length
    const ch = text[start]
    if (ch === '"' || ch === "'") {
      const end = text.indexOf(ch, start + 1)
      if (end > 0) out.push({ region: text.slice(start, end + 1), line })
      continue
    }
    if (ch !== '{') continue
    let depth = 0
    let j = start
    for (; j < text.length; j++) {
      if (text[j] === '{') depth++
      else if (text[j] === '}') {
        depth--
        if (depth === 0) break
      }
    }
    out.push({ region: text.slice(start, j + 1), line })
  }
  return out
}

/** Utility tokens inside a region. A token must carry a `-` or `:` so bare words are ignored. */
function utilityTokens(region: string): Set<string> {
  const toks = new Set<string>()
  for (const m of region.matchAll(/'([^'\n]*)'|"([^"\n]*)"|`([^`$\n]*)`/g)) {
    const literal = (m[1] ?? m[2] ?? m[3] ?? '').trim()
    if (!literal) continue
    for (const t of literal.split(/\s+/)) {
      if (/^[a-z@][\w:./[\]#%,()!<>&*+~-]*$/i.test(t) && /[-:]/.test(t)) toks.add(t)
    }
  }
  return toks
}

test('no class recipe is hand-written twice — a recipe belongs to the design system', () => {
  const recipes: Recipe[] = []
  for (const f of sourceFiles(SRC)) {
    const text = read(f)
    for (const { region, line } of classNameRegions(text)) {
      const tokens = utilityTokens(region)
      if (tokens.size >= MIN_RECIPE_TOKENS) recipes.push({ file: rel(f), line, tokens })
    }
  }
  expect(recipes.length, 'no className recipes were parsed at all — the reader is broken').toBeGreaterThan(20)

  const dupes: string[] = []
  for (let i = 0; i < recipes.length; i++) {
    for (let j = i + 1; j < recipes.length; j++) {
      const a = recipes[i]
      const b = recipes[j]
      if (a.file === b.file) continue
      // The design system is one authority; two primitives are not two screens.
      if (isDesignSystem(a.file) && isDesignSystem(b.file)) continue
      let shared = 0
      for (const t of a.tokens) if (b.tokens.has(t)) shared++
      const overlap = shared / (a.tokens.size + b.tokens.size - shared)
      if (overlap >= MAX_RECIPE_OVERLAP) {
        dupes.push(
          `${a.file}:${a.line}  ~${(overlap * 100).toFixed(0)}%~  ${b.file}:${b.line}\n` +
            `    ${[...a.tokens].sort().join(' ')}\n` +
            `    ${[...b.tokens].sort().join(' ')}`,
        )
      }
    }
  }

  expect(
    dupes,
    `The same class recipe is written in two places. It is not either file's — twelve copies of ` +
      `the chip recipe drifted in border colour and hover before anyone counted them ` +
      `(src/components/ui/buttonStyles.ts:31-35). Name it once: a variant of buttonClasses(), a ` +
      `primitive in src/components/ui/ exported from index.ts, or a composition in src/index.css. ` +
      `Then both callers ask for it. Do NOT wrap one copy in the other ` +
      `(docs/NO_SPAGHETTI.md §5).\n` + dupes.join('\n'),
  ).toEqual([])
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 3. NOTHING RE-DECLARES WHAT A SECTION ALREADY OWNS
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The cheapest possible spelling of "one authority per concept": if `src/components/ui/index.ts`
// or a `src/domain/<name>/index.ts` already exports a name, no screen, shell or store file may
// declare that name at module level — exported or not. A second `Gauge`, a second `shipHoldFree`,
// a second `orderText` is a second author whatever else it is called.
//
// It cannot see a copy that was renamed on the way in (`freeHold` beside `shipHoldFree`), and no
// static rule can. What it CAN do is make the laziest and most common form — copy the function,
// keep the name — impossible to land.

function namesExportedFrom(indexFile: string): Set<string> {
  const text = read(indexFile)
  const names = new Set<string>()
  for (const m of text.matchAll(/export\s*\{([^}]*)\}/g)) {
    for (const part of m[1].split(',')) {
      const name = part.trim().replace(/^type\s+/, '').split(/\s+as\s+/).pop()
      if (name) names.add(name)
    }
  }
  for (const m of text.matchAll(/^export\s+(?:async\s+)?(?:function|const|class)\s+([A-Za-z_$][\w$]*)/gm)) {
    names.add(m[1])
  }
  return names
}

test('a screen never re-declares a name the design system or a domain section owns', () => {
  const owned = new Map<string, string>()
  for (const n of namesExportedFrom(path.join(SRC, 'components/ui/index.ts')))
    owned.set(n, 'components/ui/index.ts')
  for (const section of readdirSync(path.join(SRC, 'domain'))) {
    const index = path.join(SRC, 'domain', section, 'index.ts')
    if (!statSync(path.join(SRC, 'domain', section)).isDirectory()) continue
    for (const n of namesExportedFrom(index)) owned.set(n, `domain/${section}/index.ts`)
  }
  expect(owned.size, 'no owned names were read — the section entrances moved').toBeGreaterThan(20)

  const shadows: string[] = []
  for (const f of sourceFiles(SRC)) {
    const p = rel(f)
    if (isDesignSystem(p) || p.startsWith('domain/')) continue
    const lines = read(f).split('\n')
    for (let i = 0; i < lines.length; i++) {
      const m = /^(?:export\s+)?(?:async\s+)?(?:function|const|class|let)\s+([A-Za-z_$][\w$]*)/.exec(lines[i])
      if (m && owned.has(m[1])) shadows.push(`${p}:${i + 1}  ${m[1]}  (owned by ${owned.get(m[1])})`)
    }
  }

  expect(
    shadows,
    `Something declares a name a section already owns. Import it from the section's entrance ` +
      `instead — and if what you need is genuinely different, it needs a different NAME and a ` +
      `reason, because two things called one thing is how "how much fits in this hull" ended up ` +
      `with seven answers.\n` + shadows.join('\n'),
  ).toEqual([])
})

test('two modules never export the same name', () => {
  const byName = new Map<string, string[]>()
  for (const f of sourceFiles(SRC)) {
    const p = rel(f)
    // index.ts files re-export by design; that is the entrance doing its job.
    if (path.basename(f) === 'index.ts') continue
    for (const m of read(f).matchAll(/^export\s+(?:async\s+)?(?:function|const|class|let)\s+([A-Za-z_$][\w$]*)/gm)) {
      const list = byName.get(m[1]) ?? []
      list.push(p)
      byName.set(m[1], list)
    }
  }

  const clashes = [...byName.entries()]
    .filter(([, files]) => files.length > 1)
    .map(([name, files]) => `${name}  ->  ${files.join(', ')}`)

  expect(
    clashes,
    `Two modules export the same name. One of them is the authority and the other is a copy that ` +
      `will drift — or they are two different things wearing one word, which is the same problem ` +
      `read from the other end. Fold them, or rename the one that is not the concept.\n` +
      clashes.join('\n'),
  ).toEqual([])
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 4. THE CHAIN — every migration proves itself, and a re-cut function declares itself
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// These read `supabase/migrations/*.sql` off disk. They do NOT run SQL — `npm run db:apply` does
// that against real Postgres and is the only thing that can. What they check is the shape a
// self-assert must have to be worth running at all, which no runtime can check for you because a
// migration with no assert applies perfectly.

interface Migration {
  file: string
  short: string
  sql: string
}

function chain(): Migration[] {
  return readdirSync(MIGRATIONS)
    .filter((n) => n.endsWith('.sql'))
    .sort()
    .map((file) => ({ file, short: file.slice(10, 14), sql: read(path.join(MIGRATIONS, file)) }))
}

test('every migration proves itself in the transaction that applies it, and prints the receipt', () => {
  const files = chain()
  expect(files.length, 'no migrations were read').toBeGreaterThan(10)

  const bad: string[] = []
  for (const m of files) {
    if (!/do\s+\$\$/i.test(m.sql)) bad.push(`${m.file}  — no do $$ … $$ self-assert block at all`)
    else if (!new RegExp(`${m.short}\\s+self-assert FAIL`, 'i').test(m.sql))
      bad.push(`${m.file}  — no "raise exception '${m.short} self-assert FAIL: …'"`)
    else if (!new RegExp(`raise\\s+notice\\s+'${m.short}[^']*self-assert ok`, 'i').test(m.sql))
      bad.push(`${m.file}  — no closing "raise notice '${m.short} self-assert ok: …'" receipt`)
  }

  expect(
    bad,
    `A migration lands without proving what its header promised. supabase/migrations/README.md §3: ` +
      `re-read what was just written and raise if it is not what was claimed, then close with the ` +
      `receipt that names what was proven. Assert the PROPERTY, not the statement you just ran, ` +
      `and make sure the assert CAN fail — a vacuous assert reads as coverage and is worse than ` +
      `none (docs/CORE_REUSE.md:1443-1451).\n` + bad.join('\n'),
  ).toEqual([])
})

test('a migration that re-cuts an existing function declares the supersede in its header', () => {
  const files = chain()
  const firstCut = new Map<string, string>()
  const offenders: string[] = []

  for (const m of files) {
    // Line comments carry function names in prose; strip them before reading the SQL.
    const code = m.sql.replace(/^\s*--[^\n]*$/gm, '')
    const header = m.sql.slice(0, 14000)
    const recut = new Set<string>()
    for (const c of code.matchAll(/create\s+(?:or\s+replace\s+)?function\s+([a-z_]+\.[a-z_0-9]+)/gi)) {
      const fn = c[1].toLowerCase()
      // pg_temp IS THE ONE SCHEMA THAT CANNOT BE SUPERSEDED, so this guard does not read it.
      // A `pg_temp.*` function lives in the connection's own temporary schema and is dropped with
      // the session; it never enters the deployed catalogue. So the premise this test is built on
      // — "an earlier migration already created it, and a deployment is now carrying that body" —
      // is false for pg_temp by construction. There is no deployed body to re-cut, no caller that
      // outlives the transaction, and nothing a second definition could drift away from. Worse,
      // the sanctioned fix cannot apply either: a file that is replayed alone, into a fresh
      // session, MUST carry its own copy of any pg_temp helper it uses, so demanding the word
      // "supersede" would be demanding a declaration about a supersede that never happens.
      // THE CASE THAT EXPOSED IT: the hunk-slicing helper `pg_temp.recut` is defined at
      // 20260818000047_the_sea_is_a_free_plane.sql:80 and again at
      // 20260818000050_a_refusal_is_two_numbers_and_a_verb.sql:120 — two definitions by necessity,
      // because neither transaction can see the other's.
      // NARROWED TO pg_temp AND NOTHING ELSE: every persistent schema (public, voyage, cmd,
      // world, …) is still read exactly as before, and 0050's genuine supersede of
      // voyage.sail_refusal is still caught by this test.
      if (fn.startsWith('pg_temp.')) continue
      const owner = firstCut.get(fn)
      if (owner === undefined) firstCut.set(fn, m.file)
      else if (owner !== m.file) recut.add(fn)
    }
    if (recut.size > 0 && !/supersed/i.test(header)) {
      offenders.push(`${m.file}\n    re-cuts: ${[...recut].sort().join(', ')}`)
    }
  }

  expect(
    offenders,
    `This migration re-creates a function an earlier migration already created, without the word ` +
      `"supersede" anywhere in its header. That is the sanctioned way to change a deployed rule — ` +
      `supabase/migrations/README.md:43-48, "a change goes in a NEW file that supersedes the old ` +
      `one" — but only if the file SAYS SO: name what it supersedes and why, state whether the ` +
      `change is a no-op when the new input is absent, and move everything that must move ` +
      `together in the same file. 0017:50-55 is why that last clause exists — do_buy checked room ` +
      `with one function and placed cargo with another function's private copy of the same ` +
      `arithmetic (docs/NO_SPAGHETTI.md §3).\n` + offenders.join('\n'),
  ).toEqual([])
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// 5. ONE ANSWER TO "WHERE IS THE WATER NEAREST THIS POINT?" — 0076
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// There are THREE implementations of that question in this repository, and `docs/DESIGN_ROADSTEAD.md`
// §2.1 MEASURED that two of them are not the same rule:
//
//   voyage.water_roadstead   (SQL, 0076)          12 rings, the MINIMUM-distance cell
//   snapToNav                (src/lib/sea)        12 rings, the MINIMUM-distance cell   — agrees
//   snapToWater              (scripts/sea-grid)    8 rings, the FIRST cell in scan order — DIFFERS
//
// Say it plainly: that is spaghetti, and the one authority is `snapToNav`. It is not folded here
// because folding it means repointing `scripts/build-sea-places.mjs` at `findPath`, which
// REGENERATES `data/sea-places.json` — a different slice with a different blast radius. 0076 names
// it in its own header instead, and these two rules keep it from growing while it waits.
//
// THE CLIENT HALF IS THE SHARPER ONE. A port's roadstead is SERVED (`world.snapshot().ports[]`),
// and `cmd.do_sail` verifies a course against those very numbers. A chart layer or a screen that
// snapped for itself would be a SECOND answer to "where is this port reached from", and the line
// drawn, the course proposed and the endpoint the server checks would become three answers that
// drift the day the raster moves. The client keeps `snapToNav` for exactly one job — a point of
// open water the player TAPPED (`domain/passage`'s `snapSeaPoint`) — so the guard cannot be
// "delete it from the client"; it has to be a count, and this is the count.

/** Files under `dir` with any of these extensions, as repo-relative POSIX paths from `ROOT`. */
function filesUnder(dir: string, exts: RegExp): string[] {
  const out: string[] = []
  const walk = (d: string) => {
    for (const name of readdirSync(d)) {
      const full = path.join(d, name)
      if (statSync(full).isDirectory()) walk(full)
      else if (exts.test(name)) out.push(full)
    }
  }
  walk(dir)
  return out
}

/** The names an `import { … } from '…'` statement brings into a file. */
function importedNames(text: string): Set<string> {
  const names = new Set<string>()
  for (const m of text.matchAll(/import\s+(?:type\s+)?\{([^}]*)\}\s*from/g)) {
    for (const part of m[1].split(',')) {
      const name = part.trim().replace(/^type\s+/, '').split(/\s+as\s+/)[0]
      if (name) names.add(name)
    }
  }
  return names
}

test('snapToNav has ONE importer in src/, and none in the chart or in a screen', () => {
  const importers = sourceFiles(SRC)
    .filter((f) => importedNames(read(f)).has('snapToNav'))
    .map(rel)
    .sort()

  expect(
    importers,
    `The client's one snap has moved or grown a second caller. It exists for exactly one job — a ` +
      `point of open water the player TAPPED — and it lives behind domain/passage's snapSeaPoint. ` +
      `A port is reached from its SERVED roadstead (world.snapshot().ports[].roadstead); snapping ` +
      `for one here would be a second answer to a question the server also answers, and cmd.do_sail ` +
      `refuses the course that disagrees (E_OFF_COURSE).\n` + importers.join('\n'),
  ).toEqual(['domain/passage/index.ts'])

  // Said twice on purpose: the equality above is the whole rule, and this is the half that names
  // the two places it would actually be reached for — a layer that wanted to draw the line, and a
  // screen that wanted to propose a course.
  expect(
    importers.filter((p) => p.startsWith('chart/') || p.startsWith('features/')),
    `A chart layer or a screen imported snapToNav. The roadstead is SERVED — read it off MapPort ` +
      `or off SnapshotPort.roadstead.`,
  ).toEqual([])
})

test('snapToWater — the third snap rule — is called from exactly one file, and it is its own', () => {
  const SCRIPTS = path.join(ROOT, 'scripts')
  const callers: string[] = []
  let callSites = 0
  for (const f of filesUnder(SCRIPTS, /\.(mjs|js|ts)$/)) {
    // Prose names it in several files (0076's own header does); only a CALL counts, and the
    // declaration is not a call.
    const code = read(f).replace(/^\s*\/\/[^\n]*$/gm, '')
    const calls = [...code.matchAll(/(?<!function\s)\bsnapToWater\s*\(/g)]
    if (calls.length > 0) {
      callers.push(path.relative(SCRIPTS, f).split(path.sep).join('/'))
      callSites += calls.length
    }
  }

  expect(
    callers,
    `snapToWater has grown a caller. It is a THIRD, DIFFERENT snap rule (8 rings, first-in-scan-` +
      `order) that can return a different cell from snapToNav and from voyage.water_roadstead, and ` +
      `it is left standing only because folding it regenerates data/sea-places.json. Repoint the ` +
      `new caller at findPath / snapToNav instead of adding to it.\n` + callers.join('\n'),
  ).toEqual(['sea-grid.mjs'])
  // Both of them are findSeaRoute's two endpoints (scripts/sea-grid.mjs:276-277). Pinned as a
  // number so a third call inside the same file cannot hide behind the file list above.
  expect(callSites, 'snapToWater is called somewhere new inside sea-grid.mjs').toBe(2)

  // …and nothing on the client has ever heard of it.
  expect(
    sourceFiles(SRC).filter((f) => /\bsnapToWater\b/.test(read(f))).map(rel),
    'snapToWater reached src/. It is a build-time script rule, and it is not the authority.',
  ).toEqual([])
})
