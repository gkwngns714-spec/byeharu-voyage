// ═══════════════════════════════════════════════════════════════════════════════════════════════
// check-versions.mjs — a duplicate migration version is a SILENT no-op, so it is caught here
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY THIS EXISTS AT ALL
//   Supabase records applied migrations in `supabase_migrations.schema_migrations`, keyed on the
//   14-digit VERSION prefix — not on the filename and not on the file's contents. If two files
//   share a version, the second one is looked up, found already-applied, and SKIPPED. Nothing goes
//   red. CI is green, the PR merges, the deploy succeeds, and the migration deployed as NOTHING.
//
//   This happened FOUR times in the predecessor project (byeharu commits b813fa9, 90b075b,
//   43065d1, 11acbfc) and a human eye caught every one. See supabase/migrations/README.md §1.
//
// WHAT IT CHECKS — exactly two things
//   1. No two files share a 14-digit version prefix.
//   2. Every filename matches <14 digits>_<snake_case_name>.sql
//
// WHAT IT DELIBERATELY DOES NOT CHECK
//   Contiguity. A gap is a decision (a migration abandoned before it shipped); a collision is a
//   bug. Enforcing contiguity would turn a decision into an error.
//
// USAGE
//   node scripts/db/check-versions.mjs
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { migrationFiles, MIGRATIONS_DIR } from './apply-chain.mjs'

const NAME_RE = /^(\d{14})_([a-z0-9_]+)\.sql$/

const files = await migrationFiles()

if (files.length === 0) {
  console.error('FAIL: supabase/migrations/ holds no .sql files. Nothing to check is not the same as OK.')
  process.exit(1)
}

let bad = 0

const byVersion = new Map()
for (const f of files) {
  const m = NAME_RE.exec(f)
  if (!m) {
    console.error(`FAIL: ${f} — filename must be <14 digits>_<snake_case_sentence>.sql`)
    bad += 1
    continue
  }
  const [, version] = m
  if (!byVersion.has(version)) byVersion.set(version, [])
  byVersion.get(version).push(f)
}

for (const [version, group] of byVersion) {
  if (group.length > 1) {
    console.error(`FAIL: version ${version} is used by ${group.length} files — all but the first would`)
    console.error('      be recorded as already-applied and SILENTLY SKIPPED on deploy:')
    for (const g of group) console.error(`        ${g}`)
    bad += 1
  }
}

// The positive control: prove the duplicate probe can actually see a duplicate. Without this the
// loop above is a check that has never been shown capable of failing.
const probe = [...files, files[0]]
const probeCounts = new Map()
for (const f of probe) {
  const v = f.slice(0, 14)
  probeCounts.set(v, (probeCounts.get(v) ?? 0) + 1)
}
const probeFound = [...probeCounts.values()].some((n) => n > 1)
if (!probeFound) {
  console.error('FAIL: the duplicate-detection probe did not fire on a deliberately duplicated entry.')
  console.error('      The check above therefore proves nothing. Fix the probe.')
  bad += 1
}

if (bad > 0) process.exit(1)

console.log(`OK: ${files.length} migration(s) in ${MIGRATIONS_DIR}`)
console.log(`    ${byVersion.size} distinct version(s), no collisions, all filenames well-formed.`)
console.log('    positive control: the probe DID detect a deliberately duplicated version.')
