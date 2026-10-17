// ═══════════════════════════════════════════════════════════════════════════════════════════════
// shard-plan.mjs — split the Playwright suite into N shards by MEASURED TIME, not by test count
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY NOT `--shard=i/N`: Playwright's own sharding cuts the ordered list of test groups into N
// contiguous chunks of equal COUNT. Measured on the first 4-shard run (38345661180, 2026-10-13):
// shards of 101 / 82 / 95 / 87 tests took 29.8m / 32s / 1.9m / 20.0m — db.chain.spec.ts alone is
// 29.6 minutes of test time (four tests that each build the world from migration 0001, the
// from-zero coverage nobody may drop) and all four landed in one chunk.
//
// SO: every spec file is one group weighted by its measured seconds (tests/shard-weights.json),
// except the files listed under `splitFiles`, whose tests are independent and become one group
// each. Groups are dealt longest-first onto the least-loaded shard (LPT). The output is a
// Playwright `--test-list` file for shard `i`: whole files by name, split tests by their
// `file:line:col › title` id — the exact format `playwright test --list` prints.
//
// NOTHING CAN FALL BETWEEN SHARDS UNNOTICED: the plan is built from `playwright test --list`
// itself (a new spec is in it with the default weight), every listed test lands in exactly one
// shard by construction, and the `acceptance` verdict job independently requires the passes
// summed over the shards to EQUAL the `--list` total.
//
// USAGE   node scripts/ci/shard-plan.mjs <i> <N> <out-file> [--files=RE | --not-files=RE] [--grep-invert=TEXT]
//
//   --files / --not-files (2026-10-15) carve the suite into DISJOINT pools by spec file name, so
//   acceptance.yml can run the pure-Node world-building specs (db.*) on their own runner without
//   waiting for the merchants-on world the browser shards need. The two flags are each other's
//   complement with the same RE, so every listed test is in exactly one pool, and the verdict's
//   sum-equals-`--list` floor still sees every test.
//   --grep-invert is handed to `playwright test --list` verbatim; the verdict must list with the
//   same value (acceptance.yml passes it through a job output), or its denominator disagrees.
//
//   --select=selection.json (2026-10-17) narrows the plan to the spec files
//   scripts/ci/select-specs.mjs chose for a PR. Only a `scoped` selection narrows anything; a
//   `full` one (every push to main) plans exactly what it planned before. Under a scoped selection
//   a pool or shard left with no tests is a legitimate outcome, not a broken cut: the plan writes
//   an EMPTY list and says so, and the pool action skips the run. In every case
//   `<out-file>.count` holds the number of tests planned for this shard — the per-shard floor
//   reads it, so "planned 0, ran 0" is the only zero that can be green.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')

/** Every test Playwright would run, as `{ file, id }`, parsed from `playwright test --list`. */
export function listTests(extraArgs = []) {
  const out = execFileSync('npx', ['playwright', 'test', '--list', ...extraArgs], {
    cwd: ROOT,
    encoding: 'utf8',
    shell: process.platform === 'win32',
    maxBuffer: 64 * 1024 * 1024,
  })
  const tests = []
  for (const line of out.split(/\r?\n/)) {
    const m = /^\s*\[[^\]]+\] › ((.+?):\d+:\d+ › (.+))$/.exec(line)
    if (m) tests.push({ id: m[1], file: m[2].replace(/\\/g, '/'), title: m[3] })
  }
  const total = /^Total: (\d+) tests? in/m.exec(out)
  if (!total || Number(total[1]) !== tests.length || tests.length === 0) {
    throw new Error(
      `shard-plan: parsed ${tests.length} test(s) from \`playwright test --list\` but it reported ` +
        `${total ? total[1] : 'no total'}. Refusing to plan shards over a list it cannot read.`,
    )
  }
  return tests
}

/** Deal `tests` onto `n` shards, longest group first onto the least-loaded shard. */
export function planShards(tests, n, weights) {
  const split = new Set(weights.splitFiles ?? [])
  const groups = new Map()
  for (const t of tests) {
    const key = split.has(t.file) ? t.id : t.file
    const g = groups.get(key) ?? {
      key,
      seconds: split.has(t.file)
        ? (weights.tests?.[`${t.file} › ${t.title}`] ?? 1)
        : (weights.files?.[t.file] ?? weights.defaultFileSeconds ?? 30),
      tests: 0,
    }
    g.tests += 1
    groups.set(key, g)
  }
  const shards = Array.from({ length: n }, () => ({ seconds: 0, tests: 0, entries: [] }))
  const ordered = [...groups.values()].sort((a, b) => b.seconds - a.seconds || (a.key < b.key ? -1 : 1))
  for (const g of ordered) {
    const s = shards.reduce((best, x) => (x.seconds < best.seconds ? x : best), shards[0])
    s.seconds += g.seconds
    s.tests += g.tests
    s.entries.push(g.key)
  }
  return shards
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (isMain) {
  const [i, n, outFile] = [Number(process.argv[2]), Number(process.argv[3]), process.argv[4]]
  if (!Number.isInteger(i) || !Number.isInteger(n) || i < 1 || i > n || !outFile) {
    console.error('usage: node scripts/ci/shard-plan.mjs <i> <N> <out-file>')
    process.exit(2)
  }
  const weights = JSON.parse(readFileSync(path.join(ROOT, 'tests', 'shard-weights.json'), 'utf8'))
  const opt = (name) => process.argv.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3)
  const grepInvert = opt('grep-invert')
  // Quoted by hand on Windows only, where listTests goes through a shell that would split it.
  const q = (a) => (process.platform === 'win32' ? JSON.stringify(a) : a)
  let tests = listTests(grepInvert ? ['--grep-invert', q(grepInvert)] : [])
  const only = opt('files')
  const not = opt('not-files')
  if (only) tests = tests.filter((t) => new RegExp(only).test(t.file))
  if (not) tests = tests.filter((t) => !new RegExp(not).test(t.file))
  const selFile = opt('select')
  const sel = selFile ? JSON.parse(readFileSync(selFile, 'utf8')) : null
  const scoped = sel?.mode === 'scoped'
  if (scoped) {
    const chosen = new Set(sel.specs.map((s) => s.file))
    const before = tests.length
    tests = tests.filter((t) => chosen.has(t.file))
    console.log(`scoped selection (${selFile}): ${tests.length} of this pool's ${before} test(s) are in the ${chosen.size} selected spec file(s)`)
  }
  const empty = (why) => {
    console.log(`::notice title=No affected specs in this pool::${why}`)
    console.log(`no affected specs in this pool — ${why}`)
    writeFileSync(outFile, '')
    writeFileSync(`${outFile}.count`, '0\n')
    process.exit(0)
  }
  if (tests.length === 0) {
    if (scoped) empty(`shard ${i}/${n}: the selection reaches no spec in this pool`)
    console.error('shard-plan: the file filter left no tests — refusing to plan an empty pool')
    process.exit(1)
  }
  const shards = planShards(tests, n, weights)
  shards.forEach((s, k) =>
    console.log(`shard ${k + 1}/${n}: ~${Math.round(s.seconds / 60)} min of measured test time, ${s.tests} test(s), ${s.entries.length} group(s)`),
  )
  const mine = shards[i - 1]
  if (mine.tests === 0) {
    if (scoped) empty(`shard ${i}/${n}: the pool's selected specs all landed on other shards`)
    console.error(`shard-plan: shard ${i}/${n} got no tests — fewer groups than shards`)
    process.exit(1)
  }
  writeFileSync(outFile, `${mine.entries.join('\n')}\n`)
  writeFileSync(`${outFile}.count`, `${mine.tests}\n`)
  console.log(`shard ${i}/${n} → ${outFile}:\n  ${mine.entries.join('\n  ')}`)
}
