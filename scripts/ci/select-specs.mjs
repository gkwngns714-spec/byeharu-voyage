// ═══════════════════════════════════════════════════════════════════════════════════════════════
// select-specs.mjs — WHICH SPECS A PULL REQUEST HAS TO RUN, and why (the one authority)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner's order (2026-10-17): "make CI shorter — CI tests only from where we made something
// new, not the whole game". A PR runs the specs its diff can reach; a push to main runs ALL of
// them (that run is the net, and it is unchanged). Every rule below is deterministic — the same
// diff always selects the same specs — and every selected spec carries the reason(s) it was
// selected, printed in the workflow log of every PR.
//
// THE DIFF is the PR's merge commit against its FIRST PARENT (the main GitHub merged onto), never
// `pull_request.base.sha`, which can be older (run 38711128598 counted main's own new migration
// as the PR's). In CI: `--base HEAD^1 --head HEAD`.
//
// ── THE RULES (in the order they are applied) ──────────────────────────────────────────────────
//   F  FULL SUITE when the diff touches what EVERY spec stands on and no import can show it:
//        playwright*.config.ts · package.json / package-lock.json · tsconfig*.json · vite.config.ts
//        · index.html · src/main.tsx · src/lib/db/** (the engine every world boots on)
//        · scripts/db/{build-image,prefix-cache,apply-chain}.mjs, scripts/db/supabase-preamble.sql
//          (the world-image pipeline) · tests/appReady.fixture.ts (the readiness/skip gate every
//          browser spec's non-vacuity rests on) · an EDITED, deleted or renamed migration (an old
//          file changing changes every world; an ADDED one is rule S)
//   C  a spec file that itself changed is selected.
//   G  IMPORT GRAPH: a spec that imports a changed file, transitively, through tests/, src/,
//      scripts/ and data/ (static `import … from`, `export … from`, `import()`; relative paths).
//      A helper fixture (seaFrame, seaCourse, mapWorld, routesOn, npcOn, builtWorld) reaches
//      exactly the specs that import it — which is why only appReady is rule F.
//   N  NAMED FILE: a spec that quotes a changed file's base name ('MapScreen.tsx',
//      'ships.generated.json' — what it readFileSync's by name).
//   T  TREE SCANNERS: a spec that walks a directory (`readdirSync`) is selected whenever src/,
//      scripts/, data/ or supabase/migrations/ changed — its input is the tree, not an import.
//   A  APP SHELL: src/app/**, src/index.css, src/components/ui/**, public/** → every browser spec
//      (a spec that opens `page`): every face is drawn inside them. EXCEPT public/flags/** (2026-10-18):
//      a nation's flag picture is drawn only by the design system's Flag and the chart's names, and
//      the spec that reads that folder (tests/flags.spec.ts, `'public', 'flags'`) is the one it
//      selects; a change to Flag.tsx itself is still rule A.
//   I  TEST IDS: a browser spec that names a data-testid which a changed (or rule-S-affected) src
//      file declares, or declared before the change.
//   L  FACES: a changed .tsx/.css under src/features, src/live or src/components → layout.spec,
//      wide.layout.spec and align.spec, which measure every tab's tables, and every list's rows
//      (one line per row, one column per list, no cut sentence, no label on a chart line — owner
//      rows 196/198/199/201), at phone and wide width.
//   S  SQL: for each ADDED migration, the names it DEFINES (`create [or replace] function s.n`,
//      `alter|drop function s.n`, a hunk target `'s.n(`, and the tables it creates / alters /
//      writes / indexes / triggers on) and the names it merely MENTIONS (any other `cmd.` `world.`
//      `voyage.` `public.` name in its text — comments included, which is where a re-cut lists its
//      callers). A defined name selects every spec that names it (`world.market`, its RPC
//      catalogue key `worldMarket`, or a bare `port_offers`-style name), and makes every src file
//      that names it "affected" (so rules G, I and L follow it into the app). A mentioned name
//      selects specs that name it qualified. A defined `npc_*` name selects every npc-pool spec
//      (the merchants-on world they stand in is built by those functions). Every added migration
//      selects db.chain.spec and db.image.spec (the chain applies with its receipt; the image it
//      builds certifies).
//
// ── THE GROWTH TEST (db.chain's "the world grows under a live house", 45-65 min) ───────────────
//   Runs on a PR only when the CHAIN MACHINERY changed: src/lib/db/**, tests/frozenChain.ts,
//   scripts/db/** (not world-guard.mjs, proofs/, nor the proof runner proof.mjs and its fixtures
//   proof-courses.mjs / market-fixture.mjs: in no snapshot key), package(-lock).json, vite.config.ts, an edited (not added) migration, a migration
//   added before the base chain's newest file (out of order: no kept snapshot is a prefix), or
//   tests/db.chain.spec.ts (since 2026-10-17 it reads the chain's end off the directory, so a
//   migration PR does not touch it; the `// And to 0NNN …` + `const LAST = …` bump every migration
//   PR used to make stays exempt, for the control commits that predate the change). A new
//   migration alone does NOT run it: that file is proven by
//   migrations-apply-proof (applied on main's snapshot, its self-asserts run) and by db.chain's
//   other tests; main's full run then re-proves the growth.
//   THE SAME SET IS THE ONE EXEMPTION FROM THE NO-FROM-ZERO LAW (docs/CI.md, 2026-10-17): a PR's
//   CI may apply a chain from scratch only when `growth.run` is true — the chain machinery or an
//   old file changed, so no kept snapshot can be expected to fit. Every workflow reads it from
//   selection.json; nothing else decides it.
//
// ── THE MERCHANTS-ON WORLD (npc-on-world) ──────────────────────────────────────────────────────
//   Built only when a selected spec is in the npc pool (a spec importing tests/npcOn.fixture.ts —
//   the same cut the pool action makes, computed HERE so there is one list).
//
// ── migrations-apply-proof's pglite legs ────────────────────────────────────────────────────────
//   `the rest` (grant lockdown and nine more, minutes) always runs. `ledger` (02) and `merchants`
//   (12) run when an added migration defines or mentions a qualified name the proof file names,
//   when the proof file itself changed, or on any change to scripts/db/**, package(-lock).json or
//   an edited migration. On main: all three.
//
// USAGE
//   node scripts/ci/select-specs.mjs [--base REV] [--head REV] [--out selection.json] [--full]
//       select; --head omitted = the working tree; --full = not a PR (push to main / dispatch)
//   node scripts/ci/select-specs.mjs count <selection.json> [--grep-invert TEXT]
//       the verdict's denominator: tests `playwright test --list` finds in the selected files
//   node scripts/ci/select-specs.mjs self-test
//       positive controls over real commits in this repo's history (needs full history)
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync, existsSync, readdirSync, statSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const GROWTH_TITLE = 'the world grows under a live house'
const SCHEMAS = ['cmd', 'world', 'voyage', 'public']

const git = (args, input) =>
  execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, input })

// ── the tree being judged: the working tree, or a commit read through `git cat-file --batch` ──
function treeReader(head) {
  if (!head) {
    const walk = (d, out = []) => {
      for (const n of readdirSync(path.join(ROOT, d))) {
        const rel = d ? `${d}/${n}` : n
        if (n === 'node_modules' || n === '.git' || n === 'dist') continue
        const st = statSync(path.join(ROOT, rel))
        if (st.isDirectory()) walk(rel, out)
        else out.push(rel)
      }
      return out
    }
    const files = ['tests', 'src', 'scripts', 'data'].filter((d) => existsSync(path.join(ROOT, d))).flatMap((d) => walk(d))
    return { files, read: (f) => (existsSync(path.join(ROOT, f)) ? readFileSync(path.join(ROOT, f), 'utf8') : null) }
  }
  const files = git(['ls-tree', '-r', '--name-only', head, '--', 'tests', 'src', 'scripts', 'data'])
    .split('\n')
    .filter(Boolean)
  const cache = new Map()
  const wanted = files.filter((f) => /\.(m?[jt]sx?|d\.mts|css|json)$/.test(f) && !/\.cache\.json$/.test(f))
  const buf = execFileSync('git', ['cat-file', '--batch'], {
    cwd: ROOT,
    input: wanted.map((f) => `${head}:${f}`).join('\n') + '\n',
    maxBuffer: 1024 * 1024 * 1024,
  })
  let at = 0
  for (const f of wanted) {
    const nl = buf.indexOf(10, at)
    const header = buf.subarray(at, nl).toString('utf8')
    const size = Number(header.split(' ')[2])
    if (header.endsWith('missing') || !Number.isFinite(size)) { at = nl + 1; continue }
    cache.set(f, buf.subarray(nl + 1, nl + 1 + size).toString('utf8'))
    at = nl + 1 + size + 1
  }
  return {
    files,
    read: (f) => (cache.has(f) ? cache.get(f) : (() => { try { return git(['show', `${head}:${f}`]) } catch { return null } })()),
  }
}

// ── the diff ─────────────────────────────────────────────────────────────────────────────────
function diffOf(base, head) {
  const args = ['diff', '--name-status', '-M', base]
  if (head) args.push(head)
  return git(args)
    .split('\n')
    .filter(Boolean)
    .map((l) => {
      const [st, a, b] = l.split('\t')
      return { status: st[0], path: b ?? a, oldPath: b ? a : undefined }
    })
}
const fileDiff = (base, head, file) => git(['diff', '-U0', base, ...(head ? [head] : []), '--', file])

// ── the import graph ───────────────────────────────────────────────────────────────────────────
const IMPORT_RE = /(?:\bimport\s+(?:type\s+)?(?:[^'"]*?\s+from\s+)?|\bexport\s+(?:type\s+)?[^'";]*?\s+from\s+|\bimport\s*\(\s*)['"]([^'"]+)['"]/g
const EXTS = ['', '.ts', '.tsx', '.mjs', '.js', '.d.mts', '/index.ts', '/index.tsx', '/index.mjs', '/index.js']

function buildGraph(tree) {
  const set = new Set(tree.files)
  const deps = new Map()
  for (const f of tree.files) {
    if (!/\.(m?[jt]sx?)$/.test(f)) continue
    const text = tree.read(f)
    if (text == null) continue
    const out = new Set()
    for (const m of text.matchAll(IMPORT_RE)) {
      const spec = m[1]
      if (!spec.startsWith('.')) continue
      const base = path.posix.normalize(path.posix.join(path.posix.dirname(f), spec))
      for (const e of EXTS) {
        if (set.has(base + e)) { out.add(base + e); break }
      }
      // `foo.mjs` imported from TS also stands for its `foo.d.mts`
      if (base.endsWith('.mjs') && set.has(base.replace(/\.mjs$/, '.d.mts'))) out.add(base.replace(/\.mjs$/, '.d.mts'))
    }
    deps.set(f, out)
  }
  return deps
}

/** For each spec: the chain spec → … → target, for every file it reaches. */
function reachOf(deps, spec) {
  const via = new Map([[spec, null]])
  const queue = [spec]
  while (queue.length) {
    const f = queue.shift()
    for (const d of deps.get(f) ?? []) {
      if (via.has(d)) continue
      via.set(d, f)
      queue.push(d)
    }
  }
  const chain = (t) => { const p = []; for (let x = t; x; x = via.get(x)) p.unshift(x); return p }
  return { has: (t) => via.has(t), chain }
}

// ── SQL names ──────────────────────────────────────────────────────────────────────────────────
const Q = `(?:${SCHEMAS.join('|')})\\.[a-z_][a-z0-9_]*`
function sqlNames(sql, knownTables = new Set()) {
  const lower = sql.toLowerCase()
  const defined = new Set()
  const tables = new Set()
  const add = (s, n) => n && s.add(n.replace(/"/g, ''))
  for (const m of lower.matchAll(new RegExp(`\\b(?:create\\s+(?:or\\s+replace\\s+)?function|alter\\s+function|drop\\s+function(?:\\s+if\\s+exists)?)\\s+(${Q})`, 'g'))) add(defined, m[1])
  // a re-cut's hunk row: ('world.trade_routes(uuid, …)', 1, $h$old$h$, $h$new$h$) — NOT every quoted
  // signature (a self-assert reads bodies it does not change through the same quoting)
  for (const m of lower.matchAll(new RegExp(`\\(\\s*'(${Q})\\([^)']*\\)'\\s*,\\s*\\d+\\s*,`, 'g'))) add(defined, m[1])
  const tableRe = new RegExp(
    `\\b(?:create\\s+(?:unlogged\\s+)?table(?:\\s+if\\s+not\\s+exists)?|alter\\s+table(?:\\s+if\\s+exists)?(?:\\s+only)?|drop\\s+table(?:\\s+if\\s+exists)?|insert\\s+into|update|delete\\s+from|truncate(?:\\s+table)?|on(?:\\s+only)?)\\s+(${Q})\\b(?!\\s*\\()`,
    'g',
  )
  for (const m of lower.matchAll(tableRe)) add(tables, m[1])
  const mentioned = new Set()
  for (const m of lower.matchAll(new RegExp(`\\b(${Q})\\b`, 'g'))) {
    // a mention of a TABLE is not followed: every migration reads public.players and public.ports
    if (!defined.has(m[1]) && !tables.has(m[1]) && !knownTables.has(m[1])) mentioned.add(m[1])
  }
  return { defined: [...defined].sort(), tables: [...tables].sort(), mentioned: [...mentioned].sort() }
}

/** The RPC catalogue: `world.market` → `worldMarket`, read from src/lib/rpc/catalog.ts. */
function catalogKeys(tree) {
  const text = tree.read('src/lib/rpc/catalog.ts') ?? ''
  const keys = new Map()
  for (const m of text.matchAll(/^\s{2}(\w+):\s*\{\s*(?:\n\s*)?schema:\s*'(\w+)',\s*(?:\n\s*)?fn:\s*'(\w+)'/gm)) keys.set(`${m[2]}.${m[3]}`, m[1])
  return keys
}

const wordIn = (text, w) => new RegExp(`(^|[^A-Za-z0-9_])${w.replace(/[.$]/g, '\\$&')}([^A-Za-z0-9_]|$)`).test(text)

// ── THE SELECTION ──────────────────────────────────────────────────────────────────────────────
const FULL_RULES = [
  [/^playwright(\.[\w-]+)?\.config\.ts$/, 'the Playwright config every spec runs under'],
  [/^package(-lock)?\.json$/, 'the dependency set every spec runs on'],
  [/^tsconfig[\w.-]*\.json$/, 'the compiler settings every spec is held to'],
  [/^vite\.config\.ts$/, 'the build (and its world-image plugin) every browser spec is served from'],
  [/^index\.html$/, 'the page every browser spec opens'],
  [/^src\/main\.tsx$/, 'the app entry every browser spec boots'],
  [/^src\/lib\/db\//, 'the PGlite engine every world (app, image, db specs) boots on'],
  [/^scripts\/db\/(build-image|prefix-cache|apply-chain)\.mjs$/, 'the world-image / chain-apply pipeline'],
  [/^scripts\/db\/supabase-preamble\.sql$/, 'the preamble every chain apply starts from'],
  [/^tests\/appReady\.fixture\.ts$/, 'the readiness/skip gate every browser spec rests on'],
]
const GROWTH_RULES = [
  // scripts/db/proofs/** is not machinery either (K5, 2026-10-18): a proof runs ON an applied world, in a
  // rolled-back transaction, and is in no snapshot's key; a changed proof selects its own pglite leg (below).
  // Nor is the proof RUNNER, scripts/db/proof.mjs, nor the fixtures it installs after the apply
  // (proof-courses.mjs, market-fixture.mjs) (2026-10-19): they read the world applyChainCached() built and
  // write nothing a snapshot carries, so a kept snapshot fits exactly as before. Measured on 2613844 (a
  // one-line header edit to proof.mjs): it sent the 45-65 min growth test and lifted the from-zero law for
  // nothing. A change to any of them still runs EVERY pglite leg (below): they are the gate's own code.
  // scripts/db/world-guard.mjs is NOT machinery (K4, 2026-10-18): it certifies an applied world after the
  // fact and is in no snapshot's key (those hash the migrations, the preamble and the config), so a kept
  // snapshot fits a chain whose guard changed exactly as before. The specs that run it (db.chain,
  // db.image) are still selected by rule G through apply-chain / build-image.
  /^src\/lib\/db\//, /^tests\/frozenChain\.ts$/, /^scripts\/db\/(?!world-guard\.mjs$|proofs\/|proof\.mjs$|proof-courses\.mjs$|market-fixture\.mjs$)/, /^package(-lock)?\.json$/, /^vite\.config\.ts$/,
]
const SHELL_RE = /^(src\/app\/|src\/index\.css$|src\/components\/ui\/|public\/(?!flags\/))/
const FLAGS_RE = /^public\/flags\//
const FACE_RE = /^src\/(features|live|components)\/.*\.(tsx|css)$/
const SCANNED_RE = /^(src|scripts|data|supabase\/migrations)\//
const MIGRATION_RE = /^supabase\/migrations\/.*\.sql$/
const PROOF_LEGS = { ledger: 'scripts/db/proofs/02_ledger_reconciliation.sql', merchants: 'scripts/db/proofs/12_merchant_companies.sql' }

export function select({ base, head, full = false }) {
  const tree = treeReader(head)
  const specs = tree.files.filter((f) => /^tests\/[^/]+\.spec\.ts$/.test(f)).sort()
  const text = new Map(specs.map((s) => [s, tree.read(s) ?? '']))
  const npcPool = specs.filter((s) => text.get(s).includes('npcOn.fixture'))
  const browser = specs.filter((s) => /\{[^}]*\bpage\b[^}]*\}/.test(text.get(s)))
  const reasons = new Map()
  const pick = (s, why) => { if (!reasons.has(s)) reasons.set(s, []); if (!reasons.get(s).includes(why)) reasons.get(s).push(why) }

  const changed = full ? [] : diffOf(base, head)
  const out = {
    base: base ?? null, head: head ?? '(working tree)', mode: 'scoped', fullReasons: [],
    changed: changed.map((c) => `${c.status} ${c.path}`),
    sql: [], growth: { run: false, why: [] }, npcWorld: { run: false, why: '' },
    pglite: { 'the rest': ['always'], ledger: [], merchants: [] },
    pools: { npc: npcPool.map((s) => s.slice('tests/'.length)) },
    specs: [],
  }
  if (full) {
    out.mode = 'full'; out.fullReasons.push('not a pull request (push to main / dispatch): the whole suite, always')
  }
  const paths = changed.flatMap((c) => (c.oldPath ? [c.path, c.oldPath] : [c.path]))

  for (const c of changed) {
    for (const [re, why] of FULL_RULES) if (re.test(c.path) || (c.oldPath && re.test(c.oldPath))) out.fullReasons.push(`${c.path}: ${why}`)
    if (MIGRATION_RE.test(c.path) && c.status !== 'A') out.fullReasons.push(`${c.path}: an existing migration was ${{ M: 'edited', D: 'deleted', R: 'renamed' }[c.status] ?? c.status} — every world changes`)
  }
  if (out.fullReasons.length) out.mode = 'full'

  // ── growth ──
  if (full) out.growth = { run: true, why: ['not a pull request'] }
  // An ADDED migration that sorts before the base chain's newest file (a file deployed out of order,
  // e.g. 0150 landing after main took 0151/0152) makes the base chain a non-prefix of this one: no
  // kept snapshot can fit it, exactly as when an old file changes — the same exemption.
  const versionOf = (p) => /^supabase\/migrations\/(\d{14})_[^/]*\.sql$/.exec(p)?.[1]
  const baseNewest = !full && base
    ? git(['ls-tree', '--name-only', base, '--', 'supabase/migrations/']).split('\n').map(versionOf).filter(Boolean).sort().pop()
    : undefined
  const testWhy = []
  for (const c of changed) {
    if (GROWTH_RULES.some((re) => re.test(c.path))) out.growth.why.push(`${c.path} is chain machinery`)
    if (MIGRATION_RE.test(c.path) && c.status !== 'A') out.growth.why.push(`${c.path}: an existing migration changed`)
    if (c.status === 'A' && baseNewest && versionOf(c.path) && versionOf(c.path) < baseNewest) {
      out.growth.why.push(`${c.path}: added before the base chain's newest file (${baseNewest}) — no kept snapshot is a prefix`)
    }
    if (c.path === 'tests/db.chain.spec.ts') {
      // The routine chain-end bump is history since 2026-10-17 (the spec reads the newest file off
      // disk); the exemption stays only so the control commits below keep their known answer.
      const lines = fileDiff(base, head, c.path).split('\n').filter((l) => /^[+-]/.test(l) && !/^(\+\+\+|---)/.test(l))
      const routine = lines.every((l) => /^[+-](\/\/ And to |const LAST = )/.test(l))
      // The growth test LIVES in this file, so an edit to it runs the test — but the file is in no
      // snapshot's key (those hash the migrations, the preamble and the config), so it is NOT chain
      // machinery and never lifts the law: `growth.run` (read as `cold` by build.yml,
      // acceptance.yml and migrations-apply-proof.yml) stays false for it (2026-10-18; before, a
      // spec edit sent main's disposable-chain from zero for ~50 min).
      if (!routine) testWhy.push('tests/db.chain.spec.ts changed beyond the routine chain-end bump (the growth test lives there)')
    }
  }
  out.growth.run = out.growth.why.length > 0
  // `test`: does the growth TEST run on this diff — whenever the machinery changed, or its own file did.
  out.growth.test = out.growth.run || testWhy.length > 0
  out.growth.testWhy = testWhy
  out.growth.grepInvert = out.growth.test ? '' : GROWTH_TITLE

  if (out.mode === 'full') {
    for (const s of specs) pick(s, 'FULL: ' + out.fullReasons[0])
  } else {
    const deps = buildGraph(tree)
    const reach = new Map(specs.map((s) => [s, reachOf(deps, s)]))
    const affected = new Map() // src file → why it counts as changed
    for (const c of changed) affected.set(c.path, 'changed')

    // S — added migrations
    const keys = catalogKeys(tree)
    const srcFiles = tree.files.filter((f) => /^src\/.*\.(tsx?|mjs)$/.test(f))
    const knownTables = new Set(
      git(['grep', '-h', '-ioE', `create (unlogged )?table (if not exists )?(${SCHEMAS.join('|')})\\.[a-z_][a-z0-9_]*`, ...(head ? [head] : []), '--', 'supabase/migrations'])
        .split('\n')
        .map((l) => l.toLowerCase().split(/\s+/).pop())
        .filter(Boolean),
    )
    for (const c of changed) {
      if (!(MIGRATION_RE.test(c.path) && c.status === 'A')) continue
      const sql = tree.read(c.path) ?? readFileSync(path.join(ROOT, c.path), 'utf8')
      const names = sqlNames(sql, knownTables)
      const short = path.basename(c.path).slice(0, 20)
      out.sql.push({ migration: c.path, ...names })
      pick('tests/db.chain.spec.ts', `S: ${short} is a new migration (the chain applies, every receipt prints)`)
      pick('tests/db.image.spec.ts', `S: ${short} is a new migration (the world image it builds certifies)`)
      const forms = (n) => {
        const f = [n]
        if (keys.has(n)) f.push(keys.get(n))
        const bare = n.split('.')[1]
        if (bare.includes('_')) f.push(bare)
        return f
      }
      for (const n of [...names.defined, ...names.tables]) {
        for (const s of specs) {
          const hit = forms(n).find((w) => wordIn(text.get(s), w))
          if (hit) pick(s, `S: ${short} defines ${n}, which this spec names (${hit})`)
        }
        // Into the app ONLY through the RPC catalogue: a src file that calls the wrapper. Not by a
        // name in a comment (src/lib/rpc/types.ts names half the server in its doc comments), and
        // not src/lib/rpc/ itself (the catalogue every rpc-importing spec reaches).
        if (keys.has(n)) {
          for (const f of srcFiles) {
            if (f.startsWith('src/lib/rpc/') || affected.has(f)) continue
            if (wordIn(tree.read(f) ?? '', keys.get(n))) affected.set(f, `calls ${keys.get(n)} (${n}), which ${short} defines`)
          }
        }
        if (/^\w+\.npc_/.test(n)) for (const s of npcPool) pick(s, `S: ${short} defines ${n} — the merchants-on world this npc-pool spec stands in is built by it`)
      }
      for (const n of names.mentioned) {
        for (const s of specs) if (wordIn(text.get(s), n)) pick(s, `S: ${short} mentions ${n}, which this spec names`)
      }
      for (const [leg, proof] of Object.entries(PROOF_LEGS)) {
        const ptext = (tree.read(proof) ?? '').toLowerCase()
        const hit = [...names.defined, ...names.tables, ...names.mentioned].filter((n) => wordIn(ptext, n))
        if (hit.length) out.pglite[leg].push(`${short} names ${hit.slice(0, 6).join(', ')}${hit.length > 6 ? ` (+${hit.length - 6})` : ''}, which ${path.basename(proof)} names`)
      }
    }

    for (const s of specs) {
      const r = reach.get(s)
      const t = text.get(s)
      for (const p of paths) {
        if (p === s) pick(s, 'C: the spec itself changed')
        else if (r.has(p)) pick(s, `G: imports ${r.chain(p).slice(1).join(' → ')}`)
        else if (/\.[a-z]+$/.test(p) && new RegExp(`['"/]${path.basename(p).replace(/[.$]/g, '\\$&')}['"]`).test(t)) pick(s, `N: names ${path.basename(p)}`)
        if (SCANNED_RE.test(p) && t.includes('readdirSync(') && !reasons.get(s)?.some((x) => x.startsWith('T:'))) {
          // The roots it walks, by the quoted directory names it joins ('src', 'migrations', …);
          // a scanner that names none (it walks a built world's directory) is taken to walk every
          // root that can shape a world — never scripts/ci/, which only CI runs.
          const roots = ['src', 'scripts', 'data', 'migrations'].filter((r) => t.includes(`'${r}'`))
          const root = p.startsWith('supabase/migrations/') ? 'migrations' : p.split('/')[0]
          if (roots.includes(root)) pick(s, `T: walks ${roots.join(', ')}, and ${p} changed`)
          else if (roots.length === 0 && !p.startsWith('scripts/ci/')) pick(s, `T: walks a directory built from the repo (no root named), and ${p} changed`)
        }
      }
      for (const [f, why] of affected) {
        if (why === 'changed' || f === s) continue
        if (r.has(f)) pick(s, `G: imports ${r.chain(f).slice(1).join(' → ')} (${why})`)
      }
    }

    // A, I, L
    for (const [f, why] of affected) {
      const tag = why === 'changed' ? '' : ` (${why})`
      if (SHELL_RE.test(f) && why === 'changed') for (const s of browser) pick(s, `A: ${f} is the app shell every face is drawn in`)
      if (FLAGS_RE.test(f)) for (const [s, t] of text) if (t.includes("'public', 'flags'")) pick(s, `A: ${f} is a flag picture this spec holds to the nations`)
      if (FACE_RE.test(f)) for (const s of ['tests/layout.spec.ts', 'tests/wide.layout.spec.ts', 'tests/align.spec.ts']) if (text.has(s)) pick(s, `L: ${f} is a face this spec measures${tag}`)
      if (!/^src\/.*\.(tsx?|mjs)$/.test(f)) continue
      const ids = new Set()
      for (const m of (tree.read(f) ?? '').matchAll(/data-testid=["'{`]+([\w-]+)/g)) ids.add(m[1])
      if (why === 'changed') {
        try { for (const m of fileDiff(base, head, f).matchAll(/^-.*?data-testid=["'{`]+([\w-]+)/gm)) ids.add(m[1]) } catch { /* a new file has no old side */ }
      }
      for (const id of ids) {
        for (const s of browser) {
          const t = text.get(s)
          if (t.includes(`'${id}'`) || t.includes(`"${id}"`) || t.includes(`=${id}]`)) pick(s, `I: names data-testid "${id}", which ${f} declares${tag}`)
        }
      }
    }

    // W: a dictionary value REWORDED selects every spec that still pins a piece of the OLD words.
    // A spec asserts visible text without importing the dictionary, so G/N cannot see it: #299
    // (plain words) rewrote 1,147 values, its PR selected no layout spec, and main went red on
    // tests/layout.spec.ts pinning 'per day at sea' and 'over the market'. A piece is a run of two
    // or more words between placeholders and punctuation; one the new value still says is skipped.
    for (const c of changed) {
      if (!/^src\/lib\/i18n\/dict\/.*\.ts$/.test(c.path)) continue
      let diff = ''
      try { diff = fileDiff(base, head, c.path) } catch { continue }
      const VAL_RE = { '-': /^-\s*(\w+):\s*'((?:[^'\\]|\\.)*)'/gm, '+': /^\+\s*(\w+):\s*'((?:[^'\\]|\\.)*)'/gm }
      const vals = (sign) => new Map([...diff.matchAll(VAL_RE[sign])].map((m) => [m[1], m[2]]))
      const olds = vals('-'), news = vals('+')
      for (const [key, old] of olds) {
        const now = news.get(key) ?? ''
        for (const piece of old.split(/\{[^}]*\}|[,.·:;—()?!]/)) {
          const p = piece.trim()
          if (p.length < 8 || !/\S\s+\S/.test(p) || now.includes(p)) continue
          for (const [spec, st] of text) if (st.includes(p)) pick(spec, `W: ${c.path} rewords ${key} ('${p}'), which this spec pins`)
        }
      }
    }

    // pglite legs: machinery and the proof files themselves
    for (const c of changed) {
      for (const [leg, proof] of Object.entries(PROOF_LEGS)) {
        if (c.path === proof) out.pglite[leg].push(`${c.path} changed`)
        else if (/^scripts\/db\/(?!proofs\/)/.test(c.path) || /^package(-lock)?\.json$/.test(c.path) || (MIGRATION_RE.test(c.path) && c.status !== 'A')) out.pglite[leg].push(`${c.path} changed (the gate's own machinery / an old migration)`)
      }
    }
  }
  if (full || out.fullReasons.length) for (const leg of Object.keys(PROOF_LEGS)) out.pglite[leg].push(full ? 'not a pull request' : 'full suite')

  out.specs = [...reasons.keys()].sort().map((s) => ({ file: s.slice('tests/'.length), why: reasons.get(s) }))
  const npcSel = out.specs.filter((s) => out.pools.npc.includes(s.file))
  out.npcWorld = npcSel.length
    ? { run: true, why: `npc-pool spec(s) selected: ${npcSel.map((s) => s.file).join(', ')}` }
    : { run: false, why: 'no npc-pool spec selected' }
  return out
}

export function report(sel) {
  const L = []
  L.push(`diff: ${sel.base} .. ${sel.head}   (${sel.changed.length} file(s))`)
  for (const c of sel.changed) L.push(`  ${c}`)
  L.push(`mode: ${sel.mode.toUpperCase()}`)
  for (const r of sel.fullReasons) L.push(`  full because ${r}`)
  for (const q of sel.sql) {
    L.push(`sql ${path.basename(q.migration)}:`)
    L.push(`  defines   ${q.defined.join(', ') || '-'}`)
    L.push(`  tables    ${q.tables.join(', ') || '-'}`)
    L.push(`  mentions  ${q.mentioned.length} name(s): ${q.mentioned.slice(0, 25).join(', ')}${q.mentioned.length > 25 ? ', …' : ''}`)
  }
  L.push(`specs selected: ${sel.specs.length}`)
  for (const s of sel.specs) {
    L.push(`  ${s.file}`)
    for (const w of sel.mode === 'full' ? s.why.slice(0, 1) : s.why.slice(0, 8)) L.push(`      ${w}`)
    if (sel.mode !== 'full' && s.why.length > 8) L.push(`      … and ${s.why.length - 8} more reason(s)`)
  }
  if (sel.specs.length === 0) L.push('  (none — no spec can reach what this diff changed)')
  L.push(`growth test: ${sel.growth.test ? 'RUNS' : 'deferred to main'} — ${[...sel.growth.why, ...(sel.growth.testWhy ?? [])].join('; ') || 'no chain machinery changed (a new migration alone does not run it)'}`)
  L.push(`from zero allowed (cold): ${sel.growth.run ? 'yes' : 'no'}${sel.growth.run ? '' : ' — nothing in a snapshot key changed'}`)
  L.push(`merchants-on world: ${sel.npcWorld.run ? 'BUILT' : 'not built'} — ${sel.npcWorld.why}`)
  for (const [leg, why] of Object.entries(sel.pglite)) L.push(`pglite-gate (${leg}): ${why.length ? 'RUNS — ' + why.join('; ') : 'skipped — no added migration names what its proof names'}`)
  return L.join('\n')
}

// ── POSITIVE CONTROLS — real commits of this repo, each with a known right answer ─────────────
// A selector that selects nothing is green on every PR and proves nothing; one that selects
// everything is the old CI. These pin both edges, plus the two cases the owner's order turns on
// (a new migration does NOT run the growth test; a spec-only PR runs only its specs). CI runs them
// before trusting a selection; a rule change that breaks one is red here, not silently on a PR.
const CONTROLS = [
  {
    name: 'plain words (bdd50bf: dictionary values reworded) → the specs that pin the old words',
    sha: 'bdd50bf',
    check: (s, has) => [
      [s.mode === 'scoped', 'scoped'],
      [has('layout.spec.ts'), 'layout.spec selected (it pinned "per day at sea" and "over the market")'],
    ],
  },
  {
    name: 'docs only (234bcb9: RESUME.md) → nothing',
    sha: '234bcb9',
    check: (s) => [
      [s.mode === 'scoped', 'scoped'],
      [s.specs.length === 0, `0 specs (got ${s.specs.length})`],
      [!s.growth.test && !s.npcWorld.run, 'no growth test, no merchants-on world'],
      [s.pglite.ledger.length === 0 && s.pglite.merchants.length === 0, 'pglite ledger + merchants legs skipped'],
    ],
  },
  {
    name: 'new migration 0136 (55c5ea2: trade_routes / port_offers) → the specs that name them',
    sha: '55c5ea2',
    check: (s, has) => [
      [s.mode === 'scoped', 'scoped'],
      [has('rpc.surface.spec.ts') && has('db.chain.spec.ts') && has('db.image.spec.ts'), 'rpc.surface + db.chain + db.image selected'],
      [!has('layout.spec.ts') && !has('map.hulls.spec.ts') && !has('map.merchants.spec.ts'), 'no layout / npc-pool spec'],
      [!s.growth.test && s.growth.grepInvert === GROWTH_TITLE, 'growth test deferred (a new migration + the routine LAST bump)'],
      [!s.npcWorld.run, 'no merchants-on world'],
      [s.pglite.merchants.length > 0 && s.pglite.ledger.length === 0, 'merchants leg runs (proof 12 names port_offers), ledger leg skipped'],
    ],
  },
  {
    name: 'spec-only PR #141 (b509a12: three map specs + a new helper fixture) → those three',
    sha: 'b509a12',
    check: (s) => [
      [s.mode === 'scoped', 'scoped (a helper fixture reaches only its importers)'],
      [JSON.stringify(s.specs.map((x) => x.file)) === JSON.stringify(['map.goto.spec.ts', 'map.hulls.spec.ts', 'map.merchants.spec.ts']), `exactly map.goto/hulls/merchants (got ${s.specs.map((x) => x.file).join(', ')})`],
      [s.npcWorld.run && !s.growth.test, 'merchants-on world built, growth deferred'],
    ],
  },
  {
    name: 'shared test infra (53c67ba: tests/appReady.fixture.ts) → the full suite',
    sha: '53c67ba',
    check: (s) => [
      [s.mode === 'full', 'full'],
      [s.fullReasons.some((r) => r.startsWith('tests/appReady.fixture.ts')), 'because of appReady.fixture.ts'],
    ],
  },
  {
    name: "a world-guard edit + a new migration (da37072: 0143) → growth deferred (the guard is in no snapshot's key)",
    sha: 'da37072',
    check: (s) => [
      [!s.growth.test, `growth test deferred (got: ${s.growth.why.join('; ') || 'none'})`],
    ],
  },
  {
    name: 'a proof edit (c4f364a: proofs/06_haggle.sql + client) → growth deferred (a proof is in no snapshot key)',
    sha: 'c4f364a',
    check: (s) => [
      [!s.growth.test, `growth test deferred (got: ${s.growth.why.join('; ') || 'none'})`],
    ],
  },
  {
    name: 'the proof runner alone (2613844: scripts/db/proof.mjs header) → growth deferred, every pglite leg runs (the runner is in no snapshot key)',
    sha: '2613844',
    check: (s) => [
      [!s.growth.run, `from zero NOT allowed, growth deferred (got: ${s.growth.why.join('; ') || 'none'})`],
      [s.pglite.ledger.length > 0 && s.pglite.merchants.length > 0, "ledger + merchants legs run (the gate's own code changed)"],
    ],
  },
  // THE TWO PRs THAT TURNED MAIN'S ACCEPTANCE RED FOR 25 RUNS (2026-10-18). The selection DID pick
  // their specs; no PR job ran them, because acceptance.yml had no `pull_request` trigger (#165).
  // These hold the selection to the answer it gave, so a narrowing rule cannot drop it unnoticed.
  {
    name: 'map flags + day lamp (4319daa, #234: MapScreen, hitTest, index.css) → map.marks + map.noblink',
    sha: '4319daa',
    check: (s, has) => [
      [s.mode === 'scoped', 'scoped'],
      [has('map.marks.spec.ts'), 'map.marks selected (it reads MapScreen.tsx\'s hit test)'],
      [has('map.noblink.spec.ts'), 'map.noblink selected (the chart\'s layers)'],
    ],
  },
  {
    name: 'the desk terminal (db7c956, #225: CommandScreen\'s wide shape) → route.stopface',
    sha: 'db7c956',
    check: (s, has) => [
      [s.mode === 'scoped', 'scoped'],
      [has('route.stopface.spec.ts'), 'route.stopface selected'],
    ],
  },
  {
    name: 'chain machinery (8c73c0f: src/lib/db, scripts/db) → full suite + growth test',
    sha: '8c73c0f',
    check: (s) => [
      [s.mode === 'full', 'full'],
      [s.growth.run && s.growth.grepInvert === '', 'growth test runs'],
    ],
  },
]

function selfTest() {
  let ok = true
  for (const c of CONTROLS) {
    let s
    try {
      s = select({ base: `${c.sha}^1`, head: c.sha })
    } catch (e) {
      console.log(`FAIL  ${c.name}\n      could not read ${c.sha} (is the history fetched? fetch-depth: 0): ${e.message}`)
      ok = false
      continue
    }
    const files = new Set(s.specs.map((x) => x.file))
    const results = c.check(s, (f) => files.has(f))
    const bad = results.filter(([pass]) => !pass)
    console.log(`${bad.length ? 'FAIL' : 'ok  '}  ${c.name}`)
    for (const [pass, what] of results) console.log(`      ${pass ? '✓' : '✗'} ${what}`)
    if (bad.length) ok = false
  }
  console.log(ok ? `OK: all ${CONTROLS.length} positive controls hold` : 'FAILED: the selector no longer gives the known answer for a real commit')
  return ok
}

// ── CLI ────────────────────────────────────────────────────────────────────────────────────────
const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (isMain) {
  const argv = process.argv.slice(2)
  const opt = (n) => { const i = argv.indexOf(`--${n}`); return i >= 0 ? argv[i + 1] : undefined }
  if (argv[0] === 'count') {
    const sel = JSON.parse(readFileSync(argv[1], 'utf8'))
    const { listTests } = await import('./shard-plan.mjs')
    const gi = opt('grep-invert')
    const q = (a) => (process.platform === 'win32' ? JSON.stringify(a) : a)
    const files = new Set(sel.specs.map((s) => s.file))
    let n = 0
    try {
      n = listTests(gi ? ['--grep-invert', q(gi)] : []).filter((t) => files.has(t.file)).length
    } catch (e) {
      console.error(String(e.message ?? e)); process.exit(1)
    }
    console.log(n)
  } else if (argv[0] === 'self-test') {
    process.exit(selfTest() ? 0 : 1)
  } else {
    const sel = select({ base: opt('base'), head: opt('head'), full: argv.includes('--full') })
    if (!sel.base && sel.mode !== 'full') { console.error('select-specs: --base is required unless --full'); process.exit(2) }
    console.log(report(sel))
    if (opt('out')) writeFileSync(opt('out'), JSON.stringify(sel, null, 2) + '\n')
  }
}
