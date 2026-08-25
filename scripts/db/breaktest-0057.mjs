// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0057.mjs — make 0057's self-assert BITE, one guard at a time
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// 0057 replaced a disk-outage-causing constant with a derived budget. A guard nobody has watched
// fail reads exactly like a guard that cannot fail — and 0013's own `price_history_slots = 288`
// was exactly that: green for years while the world outgrew it. So every assert in 0057 is broken
// on purpose here and the RED MESSAGE IT PRODUCES is recorded.
//
// Shape copied from scripts/db/breaktest-0053.mjs: apply the chain up to but NOT including 0057
// once, then run MUTATED copies of 0057 inside begin/rollback. The mutations never touch the file
// on disk — a break-test that contaminates the migration it is proving is this repo's commit
// bfd37c7, and it is not repeated.
//
//   node scripts/db/breaktest-0057.mjs
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000057_the_record_keeps_only_what_the_disk_can_afford.sql'
const sql0057 = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')

const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f === LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log('chain applied to 0056\n')

// The law's whole return line, so a mutation can replace it cleanly in one piece.
const LAW_RETURN = '  return greatest(48, floor(629145600::numeric / (p_pairs::numeric * 201))::int);'

// The two recut calls, each as (old-hunk, new-hunk) — copied verbatim so mutations can retarget
// just the NEW half without breaking `pg_temp.recut`'s "occurs exactly once" precondition on OLD.
const TICK_OLD = "  '  v_keep  int    := public.wc_int(''price_history_slots'');',"
const TICK_NEW = "  '  v_keep  int    := public.price_history_window();');"
const READ_OLD =
  "  '  v_slots int := least(greatest(coalesce(p_slots, 48), 1), public.wc_int(''price_history_slots''));',"
const READ_NEW =
  "  '  v_slots int := least(greatest(coalesce(p_slots, 48), 1), public.price_history_window());');"

/** @type {[string, [string, string][]][]} */
const MUTATIONS = [
  [
    // Drops the second "recent" slot entirely (not a duplicate — a duplicate would collide on the
    // (port_id, good_id, slot) primary key before the self-assert ever runs). One recent slot plus
    // the ancient one (invisible to a p_slots=48 read) leaves the served payload with exactly one
    // distinct slot, which is what guard (0) exists to refuse.
    '(0) the seeded precondition collapses to one distinct served slot',
    [
      [
        ' cross join lateral (values\n   (public.drift_slot_of(now()) - 3),    -- recent: inside every window this law can produce\n   (public.drift_slot_of(now()) - 10),   -- recent: inside every window this law can produce\n   (public.drift_slot_of(now()) - 100)   -- ancient: inside 0013\'s old window (288), outside the new one\n ) as s(slot);',
        ' cross join lateral (values\n   (public.drift_slot_of(now()) - 3),    -- recent: inside every window this law can produce\n   (public.drift_slot_of(now()) - 100)   -- ancient: inside 0013\'s old window (288), outside the new one\n ) as s(slot);',
      ],
    ],
  ],
  [
    '(1) the floor is dropped from the law — the sweep at k=17 exposes a sub-48 window',
    [[LAW_RETURN, '  return floor(629145600::numeric / (p_pairs::numeric * 201))::int;']],
  ],
  [
    '(1) the budget is ignored — the law grows WITH the world instead of shrinking',
    [[LAW_RETURN, '  return greatest(48, p_pairs);']],
  ],
  [
    '(1b) the positive control is blinded — its own budget constant is neutered',
    [
      [
        "if v_real_pairs::bigint * 288 * 201 <= 629145600 then\n    raise exception '0057 self-assert FAIL: the positive control is BLIND",
        "if v_real_pairs::bigint * 288 * 201 <= 99999999999999 then\n    raise exception '0057 self-assert FAIL: the positive control is BLIND",
      ],
    ],
  ],
  [
    "(1b) \"today's derived window still exceeds budget\" forced, to prove the raise is reachable",
    [['if v_win * v_real_pairs * 201 > 629145600 and v_win > 48 then', 'if true then']],
  ],
  [
    '(2) tick_price_snapshot no longer names the new authority (reverted to a bare literal)',
    [[TICK_NEW, "  '  v_keep  int    := 57;');"]],
  ],
  [
    '(2) world.price_history no longer names the new authority (reverted to a bare literal)',
    [[READ_NEW, "  '  v_slots int := least(greatest(coalesce(p_slots, 48), 1), 57);');"]],
  ],
  [
    '(2b) the retired knob name leaks into a THIRD function the two named checks never look at',
    [
      [
        '  select public.price_history_window_for((select count(*)::int from public.port_goods))',
        "  select public.price_history_window_for((select count(*)::int from public.port_goods)) -- price_history_slots",
      ],
    ],
  ],
  [
    // Deliberately does NOT touch the recut hunks (that would be caught by (2) first, before this
    // guard even runs) — it asks the AFTER capture for a narrower window than the BEFORE capture,
    // which excludes the -10 synthetic point and isolates the comparison itself.
    '(3) value parity — the AFTER capture asks a different p_slots than the BEFORE capture',
    [
      [
        'create temporary table payload_after_recut_0057 as\n  select world.price_history(sub.id, 48) as hist from subject_0057 sub;',
        'create temporary table payload_after_recut_0057 as\n  select world.price_history(sub.id, 5) as hist from subject_0057 sub;',
      ],
    ],
  ],
  [
    '(4) the real prune never runs — the excess is left standing',
    [['select public.tick_price_snapshot(now());', 'select 1;']],
  ],
  [
    '(5) the bounded-table check forced, to prove the raise is reachable',
    [['if v_max_slot - v_min_slot >= public.price_history_window() then', 'if true then']],
  ],
  [
    '(6) the retention law is made client-executable',
    [
      [
        'revoke all on function public.price_history_window_for(int) from public, anon, authenticated;',
        'grant execute on function public.price_history_window_for(int) to authenticated;',
      ],
    ],
  ],
  [
    "(6) world.price_history's authenticated EXECUTE is dropped by the recut",
    [
      [
        "  'window''s source moved to public.price_history_window() (0057).';",
        "  'window''s source moved to public.price_history_window() (0057).';\nrevoke execute on function world.price_history(uuid, int) from authenticated;",
      ],
    ],
  ],
  [
    '(6) the retired knob is never deleted from world_config',
    [["delete from public.world_config where key = 'price_history_slots';", 'select 1;']],
  ],
  [
    '(slice) the deployed tick_price_snapshot is not what this file was generated against',
    [[TICK_OLD, "  '  v_keep  int    := public.wc_int(''price_history_slots_typo'');',"]],
  ],
]

let bad = 0
for (const [name, edits] of MUTATIONS) {
  let mutated = sql0057
  let anchored = true
  for (const [from, to] of edits) {
    if (from !== '' && !mutated.includes(from)) {
      console.log(`SKIPPED  ${name} — mutation anchor not found, FIX THE SCRIPT:\n    ${JSON.stringify(from.slice(0, 110))}`)
      anchored = false
      bad += 1
      break
    }
    // A FUNCTION replacer, never a string: in String.replace a literal `$$` in the replacement is
    // the escape for one `$`, which silently unbalances a dollar-quoted body (0051/0053 both learned
    // this the expensive way).
    mutated = mutated.replace(from, () => to)
  }
  if (!anchored) continue

  await db.exec('begin')
  let red = null
  try {
    await db.exec(mutated)
  } catch (err) {
    red = err.message
  }
  await db.exec('rollback')

  if (red === null) {
    console.log(`GREEN    ${name}  <<< THE GUARD DID NOT BITE`)
    bad += 1
  } else {
    console.log(`RED      ${name}\n           ${red.replace(/\s+/g, ' ').trim().slice(0, 400)}`)
  }
}

// And the file exactly as it ships must still apply, or the mutations proved nothing about it.
await db.exec('begin')
let clean = null
const notices = []
try {
  await db.exec(sql0057, { onNotice: (n) => notices.push(n.message ?? String(n)) })
} catch (err) {
  clean = err.message
}
await db.exec('rollback')
console.log('')
if (clean === null) {
  console.log('UNMUTATED 0057 APPLIES GREEN:')
  for (const l of notices) console.log(`  ${l}`)
} else {
  console.log(`UNMUTATED 0057 FAILED: ${clean}`)
  bad += 1
}

console.log('')
console.log(bad === 0 ? `ALL ${MUTATIONS.length} GUARDS BIT` : `${bad} PROBLEM(S)`)
await db.close()
process.exit(bad === 0 ? 0 : 1)
