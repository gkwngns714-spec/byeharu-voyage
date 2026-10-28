// Applies src/lib/db/frozenAsserts.ts (the ONE patch list, via sqlToApply) to the runner's WORKING COPY
// of supabase/migrations, so a from-zero `supabase start` on real Postgres reads the same self-asserts
// PGlite does. CI workspace only: never commit its output; restore with `git checkout -- supabase/migrations`
// BEFORE anything hashes the files (the snapshot manifest/key). Touches only rolled-back self-assert text.
import { readdirSync, readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { FROZEN_ASSERT_PATCHES, sqlToApply } from '../../src/lib/db/frozenAsserts.ts'

const dir = process.argv[2] ?? 'supabase/migrations'
const names = new Set(readdirSync(dir))
for (const p of FROZEN_ASSERT_PATCHES) {
  if (!names.has(p.file)) throw new Error(`patched file missing from ${dir}: ${p.file}`)
  const full = path.join(dir, p.file)
  const sql = readFileSync(full, 'utf8')
  const out = sqlToApply({ name: p.file, sql })
  if (out === sql) throw new Error(`patch changed nothing: ${p.file}`)
  writeFileSync(full, out)
  console.log(`patched ${p.file}: ${p.why}`)
}
