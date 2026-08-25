// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-balance.mjs — WATCH THE BALANCE GATE GO RED, ON PURPOSE
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A gate nobody has seen bite is decoration, and a gate made stable by being made vacuous is worse
// than the lottery it replaced (docs/CORE_REUSE.md:1443). `scripts/db/proofs/05_first_voyage_balance.sql`
// was pinned to a deterministic market on 2026-08-25 so it would stop crying wolf; this file is the
// other half of that change — it breaks the economy in named ways and records the RED each break
// produces, and it proves the unmutated file is identical twice over.
//
// Every mutation is a world_config UPDATE inside a transaction that is rolled back. Nothing here
// touches a migration, and nothing here can leave a mark on the applied chain.
//
//   node scripts/db/breaktest-balance.mjs
//
// Exit 0 only if the clean run is green AND repeatable AND every named break went red.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { applyChain, REPO_ROOT } from './apply-chain.mjs'
import { installMarketFixture } from './market-fixture.mjs'

const PROOF = path.join(REPO_ROOT, 'scripts', 'db', 'proofs', '05_first_voyage_balance.sql')
const sql = (await readFile(PROOF, 'utf8')).replace(/\r\n/g, '\n')

const { db } = await applyChain({ quiet: true, log: () => {} })
await installMarketFixture(db, { log: console.log })
console.log('chain applied; proof 05 loaded\n')

/** Run the proof under a mutation, inside a transaction that is thrown away. */
async function run(setup) {
  const notices = []
  await db.exec('begin;')
  let red = null
  try {
    if (setup) await db.exec(setup)
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
  } catch (e) {
    red = String(e.message).split('\n')[0]
  } finally {
    try {
      await db.exec('rollback;')
    } catch {
      /* the proof may have aborted the transaction already */
    }
  }
  return { red, pass: notices.filter((n) => /^PASS:/.test(n)) }
}

const knob = (key, value) =>
  `update public.world_config set value = to_jsonb(${value}::numeric) where key = '${key}';`

// Each break names the marker it is expected to redden. A break that goes green is a marker that
// was not measuring what its name claims.
const BREAKS = [
  ['drift doubled — a noisier market pays more', knob('drift_sigma', 0.08), 'BALANCE_MEDIAN_IN_BAND'],
  ['drift quartered — the printer turned off', knob('drift_sigma', 0.01), 'BALANCE_MEDIAN_IN_BAND'],
  ['the quay takes a fifth of every trade', knob('spread_base', 0.2), 'BALANCE_EVERY_PORT_HAS_A_TRADE'],
  // NOT the `affinity_*` knobs: `port_goods.affinity` is DERIVED ONCE at seed time (0005/0041), so
  // moving the knobs afterwards moves nothing and the first version of this break went green
  // against a gate that was working perfectly. Measured, 2026-08-25 — recorded because the next
  // person to write a balance break-test will reach for the knobs too.
  [
    'the authored gradient flattened away (the column, not the knob)',
    'update public.port_goods set affinity = 1.0;',
    'BALANCE_EVERY_PORT_HAS_A_TRADE',
  ],
  [
    'the shortlist is blinded to two goods',
    knob('route_scan_goods', 2),
    'BALANCE_EVERY_PORT_HAS_A_TRADE',
  ],
  // `route_scan_keep = 1` IS NOT HERE, AND THAT IS A MEASUREMENT, NOT AN OVERSIGHT. It was tried
  // (2026-08-25) and every marker stayed green — because keeping one destination per good did NOT
  // drop the best trade at the sampled port, which is precisely what
  // BALANCE_QUAY_FINDS_THE_BEST asserts. A "break" the gate is right not to notice is not a hole
  // in the gate; listing it as one would teach the next reader the opposite of the truth.
]

let bad = 0

// ── 1. THE CLEAN RUN, TWICE — the lottery is dead or it is not ────────────────────────────────
const a = await run(null)
const b = await run(null)
if (a.red) {
  console.log(`RED (unexpected)  the clean chain\n                  ${a.red}`)
  bad += 1
} else if (a.pass.join('\n') !== b.pass.join('\n')) {
  console.log('DIFFERS!!  two clean runs of the same bytes disagree — STILL A LOTTERY')
  for (let i = 0; i < Math.max(a.pass.length, b.pass.length); i += 1) {
    if (a.pass[i] !== b.pass[i]) console.log(`  run 1: ${a.pass[i]}\n  run 2: ${b.pass[i]}`)
  }
  bad += 1
} else {
  console.log(`GREEN    the clean chain — ${a.pass.length} marker(s), IDENTICAL on both runs`)
  for (const line of a.pass) console.log(`         ${line}`)
}
console.log('')

// ── 2. THE BREAKS ─────────────────────────────────────────────────────────────────────────────
for (const [name, setup, expected] of BREAKS) {
  const r = await run(setup)
  if (!r.red) {
    console.log(`GREEN!!  ${name} — the economy moved and the gate did not notice. DECORATION.`)
    bad += 1
    continue
  }
  const hit = r.red.includes('PROOF 5 FAILED')
  const marker = expected && !r.pass.some((p) => p.includes(expected))
  console.log(`RED      ${name}\n         ${r.red}`)
  if (!hit) {
    console.log('         ^ but that is not proof 5 refusing — it is an error somewhere else.')
    bad += 1
  } else if (!marker) {
    console.log(`         ^ but ${expected} still PASSED, so a different marker caught it.`)
  }
}

// ── 3. THE DRIFT SWEEP — not a test, a TABLE for whoever retunes this ─────────────────────────
//
// The settled economy pays 37 per cent of the stake on a first voyage, which is over twice the
// designed pace, and no affinity knob moves it (proof 05's header has the measurement). The knob
// that does is `drift_sigma`. This prints what each setting pays, so the decision can be made on
// numbers. Reds here are EXPECTED — the band is pinned to today's reality, so every setting but
// the current one is out of it by construction.
console.log('\n── what drift_sigma pays (band-red is expected off the current setting) ──')
const MEDIAN = /returns %?([\d.]+) (?:per cent )?of the stake/
for (const sigma of [0.01, 0.015, 0.02, 0.03, 0.04, 0.06]) {
  const r = await run(knob('drift_sigma', sigma))
  const line = r.red ?? r.pass.find((p) => p.includes('BALANCE_MEDIAN_IN_BAND')) ?? ''
  const m = MEDIAN.exec(line)
  const flat = /noise taken out the median first voyage returns ([\d.]+)/.exec(
    r.pass.find((p) => p.includes('BALANCE_GRADIENT_IN_BAND')) ?? '',
  )
  console.log(
    `  drift_sigma ${String(sigma).padEnd(6)} median ${(m ? m[1] : '?').padStart(5)} per cent` +
      (flat ? `   (flat control ${flat[1]})` : '') +
      (r.red && !line.includes('median') ? `   ${r.red}` : ''),
  )
}

console.log(bad === 0 ? '\nTHE GATE BITES, AND IT DOES NOT CRY WOLF' : `\n${bad} PROBLEM(S)`)
await db.close()
process.exit(bad === 0 ? 0 : 1)
