// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0056.mjs — WATCH 0056'S SELF-ASSERT FIRE, ON PURPOSE
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A self-assert nobody has seen fail is a paragraph, not a guard. This applies the chain to 0053,
// then runs MUTATED copies of 0056 inside begin/rollback and records the real red each one
// produces. It never touches the migration on disk and it commits nothing.
//
// The mutations are chosen to attack each claim the file makes separately — the value, the "one
// row" claim, the step probe, the positive control that makes the probe mean anything, and the
// derived amplitude — because a self-assert that only fails when EVERYTHING is wrong is one
// assert wearing five hats.
//
//   node scripts/db/breaktest-0056.mjs
//
// Exit 0 only if the unmutated file applies cleanly AND every mutation goes red.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'

const LAST = '20260818000056_the_noise_stops_drowning_the_geography.sql'
const sql0056 = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')

const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f === LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log('chain applied to 0053 (drift_sigma still 0.04)\n')

const PICTURE = 'select jsonb_object_agg(key, value) into v_before from public.world_config;'

const MUTATIONS = [
  // (a) THE VALUE. The knob is not moved at all: the file's own reader must catch it.
  ['(a) the knob never moves', 'set value       = to_jsonb(k_new),', 'set value       = to_jsonb(k_old),'],
  // (b) THE VALUE, moved to the WRONG place — a typo of the kind a retune actually produces.
  ['(b) the knob lands on 0.002', 'set value       = to_jsonb(k_new),', 'set value       = to_jsonb(0.002::numeric),'],
  // (c) THE "ONE ROW" CLAIM, attacked from BOTH sides of the picture the assert takes. A knob
  //     moved AFTER it must be caught by the before/after comparison; one moved BEFORE it is
  //     invisible to that comparison by construction, and has to be caught by the named guard on
  //     the two knobs this file says it does not touch. The first draft had only the second half
  //     of this pair and (d2) below walked straight through it.
  [
    '(c1) a second knob moves, after the picture',
    PICTURE,
    PICTURE + "\n  update public.world_config set value = to_jsonb(0.85::numeric) where key = 'drift_theta';",
  ],
  [
    '(c2) a second knob moves, before the picture',
    '  ' + PICTURE,
    "  update public.world_config set value = to_jsonb(0.85::numeric) where key = 'drift_theta';\n  " + PICTURE,
  ],
  [
    '(c3) the clamp is quietly widened too',
    '  ' + PICTURE,
    "  update public.world_config set value = to_jsonb(0.05::numeric) where key = 'drift_clamp';\n  " + PICTURE,
  ],
  // (c4) A knob the NAMED guard says nothing about, so only the before/after picture can catch it.
  //      Without this the picture is an assert nobody has watched bite — c1..c3 all die on the
  //      named guard first, which would leave the more general check unproven.
  [
    '(c4) an unrelated knob moves, after the picture',
    PICTURE,
    PICTURE + "\n  update public.world_config set value = to_jsonb(0.05::numeric) where key = 'spread_base';",
  ],
  // (d) THE STEP PROBE. The tick is not actually called, so nothing is measured — the classic
  //     vacuous assert, and the one docs/CORE_REUSE.md:1443 says is worse than none.
  [
    '(d) the probe never ticks',
    "    perform public.tick_market_drift(now());\n    select stddev(drift) into v_new_sd from public.port_goods;\n    raise exception 'PROBE %|%', v_new_sd, v_zeroed;",
    "    select stddev(drift) into v_new_sd from public.port_goods;\n    raise exception 'PROBE %|%', coalesce(v_new_sd, 0.02), v_zeroed;",
  ],
  // (e) THE POSITIVE CONTROL. Point it at the NEW value, so it can no longer discriminate — the
  //     control has to notice that it has stopped being a control.
  [
    '(e) the control tests nothing',
    "    update public.world_config set value = to_jsonb(k_old) where key = 'drift_sigma';\n    update public.port_goods set drift = 0, drift_slot = 0;",
    "    update public.world_config set value = to_jsonb(k_new) where key = 'drift_sigma';\n    update public.port_goods set drift = 0, drift_slot = 0;",
  ],
  // (f) THE CONTROL'S OWN CLEAN-UP. If the control probe leaked the old value into the committed
  //     world, the migration would ship 0.04 while reporting 0.02.
  [
    '(f) the control leaks the old value',
    "  if public.wc_num('drift_sigma') <> k_new then",
    "  update public.world_config set value = to_jsonb(k_old) where key = 'drift_sigma';\n  if public.wc_num('drift_sigma') <> k_new then",
  ],
]

let bad = 0

// ── the unmutated file first: it must apply, and its receipt must appear ──────────────────────
{
  const notices = []
  await db.exec('begin')
  let red = null
  try {
    await db.exec(sql0056, { onNotice: (n) => notices.push(n.message ?? String(n)) })
  } catch (e) {
    red = String(e.message).split('\n')[0]
  }
  try {
    await db.exec('rollback')
  } catch {
    /* already aborted */
  }
  const receipt = notices.find((n) => n.includes('0056 self-assert ok'))
  if (red || !receipt) {
    console.log(`RED!!    the unmutated 0056 — ${red ?? 'no self-assert receipt was printed'}`)
    bad += 1
  } else {
    console.log(`GREEN    the unmutated 0056 applies and reports\n         ${receipt}`)
  }
  console.log('')
}

// ── then each mutation ────────────────────────────────────────────────────────────────────────
for (const [name, from, to] of MUTATIONS) {
  if (!sql0056.includes(from)) {
    console.log(`SKIPPED  ${name} — mutation anchor not found, FIX THE SCRIPT`)
    bad += 1
    continue
  }
  const mutated = sql0056.replace(from, to)
  await db.exec('begin')
  let red = null
  try {
    await db.exec(mutated)
  } catch (e) {
    red = String(e.message).split('\n')[0]
  }
  try {
    await db.exec('rollback')
  } catch {
    /* already aborted */
  }
  if (!red) {
    console.log(`GREEN!!  ${name} — the mutation applied cleanly. THE GUARD IS DECORATION.`)
    bad += 1
  } else {
    console.log(`RED      ${name}\n         ${red}`)
    if (!red.includes('0056 self-assert FAIL')) {
      console.log('         ^ but that is not 0056 refusing — it is an error somewhere else.')
      bad += 1
    }
  }
}

console.log(bad === 0 ? '\n0056 PROVES ITSELF' : `\n${bad} PROBLEM(S)`)
await db.close()
process.exit(bad === 0 ? 0 : 1)
