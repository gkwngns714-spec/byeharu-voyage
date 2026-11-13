import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// PROOF 56 REBUILDS THE OLD BODIES FROM 0353'S OWN HUNKS — and this holds that they ARE 0353's. Pure Node, no browser.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// Proof 56 (scripts/db/proofs/56_combat_log.sql) fights the old engine and skin against the new by REVERSING the 20
// hunks of migration 0353 on the live bodies. It used to hold each rebuilt body to a fixed digest; a later migration
// that legitimately re-cut one of those bodies (0354 added a row to the registry) then turned the proof red on its own
// PR (2026-11-12, #602). The rebuild is now judged as a round trip on the live body, whatever later files made of it.
// A round trip cannot tell whether the proof's COPY of a hunk is the migration's, so that is held here, statically,
// and for ever: migration 0353 is applied and frozen, and every one of its hunks must stand in the proof word for word.
// No digest of any body is held anywhere in the proof.

const MIG = path.resolve('supabase', 'migrations', '20260818000353_a_fight_keeps_its_log.sql')
const PROOF = path.resolve('scripts', 'db', 'proofs', '56_combat_log.sql')
const NAMES: Record<string, string> = {
  c_eng: 'public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)',
  c_rep: 'voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)',
}

test('every hunk of migration 0353 stands in proof 56 word for word, and the proof pins no body by digest', () => {
  const mig = readFileSync(MIG, 'utf8').replaceAll('\r', '')
  const proof = readFileSync(PROOF, 'utf8').replaceAll('\r', '')
  const re = /\((c_eng|c_rep|'[a-z_.]+\([a-z ,]*\)'), (\d+),\n\$o\$([\s\S]*?)\$o\$,\n\$n\$([\s\S]*?)\$n\$\)/g
  const hunks = [...mig.matchAll(re)].map((m) => ({ fn: NAMES[m[1]] ?? m[1].slice(1, -1), n: m[2], old: m[3], new: m[4] }))
  expect(hunks, 'migration 0353 holds 20 hunks').toHaveLength(20)
  const missing = hunks.filter((h) => !proof.includes(`('${h.fn}', ${h.n}, $h$${h.old}$h$, $h$${h.new}$h$)`)).map((h) => `${h.fn} #${h.n}`)
  expect(missing, `proof 56 does not hold these hunks of 0353 word for word: ${missing.join(', ')}`).toEqual([])
  // and no more rows than those: a hunk of the proof that is not the migration's would rebuild a body that never was
  expect(proof.match(/^ {2}\('[a-z_.]+\([a-z ,]*\)', \d+, \$h\$/gm) ?? []).toHaveLength(20)
  // the rule: a body other slices may re-cut is never held to a fixed digest
  expect(proof.match(/'[0-9a-f]{32}'/g) ?? [], 'proof 56 pins a body by an md5 literal').toEqual([])
  // the rebuild is a round trip, and the registry is left out of it
  expect(proof).toContain("where x.fn <> 'public.client_rpc_entry_points()'")
  expect(proof).toContain('does not come back to the live body')
})
