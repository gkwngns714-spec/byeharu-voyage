// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0051.mjs — make 0051's self-assert BITE, one guard at a time
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has watched fail reads exactly like a guard that cannot fail, and 0032's 60%
// dominance cap is the proof: it was green for the whole life of the defect it existed to catch.
// So every assert in 0051 is broken on purpose here and the RED MESSAGE IT PRODUCES is recorded.
//
// Shape copied from scripts/db/breaktest-0050.mjs: apply the chain up to but NOT including 0051
// once, then run MUTATED copies of 0051 inside begin/rollback. The mutations never touch the file
// on disk — a break-test that contaminates the migration it is proving is this repo's commit
// bfd37c7, and it is not repeated.
//
//   node scripts/db/breaktest-0051.mjs
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000051_the_world_says_how_rare_rare_is.sql'
const sql0051 = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')

const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f === LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log('chain applied to 0050\n')

// The whole `(c)` pin loop, so a mutation aimed at a LATER guard is not intercepted by it.
const PIN_LOOP_START = '  for v_pin in\n    select * from (values\n      (8.0,  0,'
const pinLoop = sql0051.slice(
  sql0051.indexOf(PIN_LOOP_START),
  sql0051.indexOf('  end loop;', sql0051.indexOf(PIN_LOOP_START)) + '  end loop;\n'.length,
)

// 0032's absolute rule, hand-inlined into good_rarity — the defect itself, restored.
const GOOD_RARITY_BODY = `  select public.rarity_from_producers(
    (select count(*)::int from public.port_specialties ps where ps.good_id = p_good),
    public.rarity_scale())`
const GOOD_RARITY_0032 = `  select case
    when (select count(*) from public.port_specialties ps where ps.good_id = p_good) <= 2 then 'exotic'
    when (select count(*) from public.port_specialties ps where ps.good_id = p_good) <= 5 then 'rare'
    when (select count(*) from public.port_specialties ps where ps.good_id = p_good) <= 12 then 'uncommon'
    else 'common' end`

/** @type {[string, [string, string][]][]} */
const MUTATIONS = [
  [
    '(b) the yardstick is PINNED instead of derived',
    [
      [
        "  select count(*)::numeric / nullif(count(distinct good_id), 0)\n    from public.port_specialties\n$$;",
        '  select 12::numeric\n$$;',
      ],
    ],
  ],
  [
    '(c) one rung is off by one',
    [['when p_producers <= greatest(2, p_mean / 2) then', 'when p_producers <= greatest(2, p_mean / 2 + 1) then']],
  ],
  [
    '(d) the law goes back to absolute thresholds (pin loop removed, so (d) is what catches it)',
    [
      [pinLoop, ''],
      ['when p_producers <= greatest(1, p_mean / 4) then', 'when p_producers <= 2 then'],
      ['when p_producers <= greatest(2, p_mean / 2) then', 'when p_producers <= 5 then'],
      ['when p_producers <= greatest(3, p_mean)     then', 'when p_producers <= 12 then'],
    ],
  ],
  [
    '(d2) the scale-freedom sweep goes BLIND (control)',
    [
      ['when p.n * 17 <= 2 then', 'when p.n * 1 <= 2 then'],
      ["when p.n * 17 <= 5 then 'rare'", "when p.n * 1 <= 5 then 'rare'"],
      ['when p.n * 17 <= 12 then', 'when p.n * 1 <= 12 then'],
    ],
  ],
  [
    '(e) the floor is removed, so the apex empties in a sparse world (pin loop removed)',
    [
      [pinLoop, ''],
      ['when p_producers <= greatest(1, p_mean / 4) then', 'when p_producers <=          (p_mean / 4) then'],
    ],
  ],
  [
    '(f) THE DEFECT ITSELF — 0032 absolute tiering restored inside good_rarity',
    [[GOOD_RARITY_BODY, GOOD_RARITY_0032]],
  ],
  [
    '(h) 0032 rarity_from_producers(int) left alive beside the new law',
    [['drop function public.rarity_from_producers(int);', '-- drop removed by the break test']],
  ],
  [
    '(i) the deployed body is really read back (the authority renamed under the check)',
    [
      [
        "  v_def := pg_get_functiondef('world.snapshot()'::regprocedure);\n  select count(*) into v_n from regexp_matches(v_def, 'public\\.good_rarity\\(', 'g');",
        "  v_def := pg_get_functiondef('world.snapshot()'::regprocedure);\n  select count(*) into v_n from regexp_matches(v_def, 'public\\.a_second_tiering\\(', 'g');",
      ],
    ],
  ],
  [
    '(j) the wire check quantifies over real rows (one of the four words withdrawn)',
    [
      [
        "      or elem ->> 'rarity' not in ('common', 'uncommon', 'rare', 'exotic');\n  if v_bad <> 0 then\n    raise exception '0051 self-assert FAIL: % snapshot",
        "      or elem ->> 'rarity' not in ('common', 'uncommon', 'rare');\n  if v_bad <> 0 then\n    raise exception '0051 self-assert FAIL: % snapshot",
      ],
    ],
  ],
  [
    '(k) the catalogue does not actually re-tier (defect restored, dominance caps disabled)',
    [
      [GOOD_RARITY_BODY, GOOD_RARITY_0032],
      ['  if v_exotic * 4 > v_goods then', '  if false then'],
      ['  if v_top * 5 > v_goods * 2 then', '  if false then'],
    ],
  ],
  [
    '(l) the no-op parity comparison is live (a second field dropped from one side only)',
    [
      [
        "  select jsonb_set(v_snap, '{goods}',\n           (select jsonb_agg(elem - 'rarity' order by idx)",
        "  select jsonb_set(v_snap, '{goods}',\n           (select jsonb_agg(elem - 'rarity' - 'bulk' order by idx)",
      ],
    ],
  ],
  [
    '(n) the posture moves — the yardstick made client-executable',
    [
      [
        'revoke all on function public.rarity_scale()                     from public, anon, authenticated;',
        'grant execute on function public.rarity_scale() to authenticated;',
      ],
    ],
  ],
]

let bad = 0
for (const [name, edits] of MUTATIONS) {
  let mutated = sql0051
  let anchored = true
  for (const [from, to] of edits) {
    if (from !== '' && !mutated.includes(from)) {
      console.log(`SKIPPED  ${name} — mutation anchor not found, FIX THE SCRIPT:\n    ${JSON.stringify(from.slice(0, 90))}`)
      anchored = false
      bad += 1
      break
    }
    // A FUNCTION replacer, never a string: in String.replace a literal `$$` in the replacement is
    // the escape for one `$`, which silently unbalanced the dollar-quoted function body in
    // mutation (b) and produced a SQL syntax error dressed up as a guard biting.
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
    console.log(`RED      ${name}\n           ${red.replace(/\s+/g, ' ').trim()}`)
  }
}

// And the file exactly as it ships must still apply, or the mutations proved nothing about it.
await db.exec('begin')
let clean = null
const notices = []
try {
  await db.exec(sql0051, { onNotice: (n) => notices.push(n.message ?? String(n)) })
} catch (err) {
  clean = err.message
}
await db.exec('rollback')
console.log('')
if (clean === null) {
  console.log('UNMUTATED 0051 APPLIES GREEN:')
  for (const l of notices) console.log(`  ${l}`)
} else {
  console.log(`UNMUTATED 0051 FAILED: ${clean}`)
  bad += 1
}

console.log('')
console.log(bad === 0 ? `ALL ${MUTATIONS.length} GUARDS BIT` : `${bad} PROBLEM(S)`)
await db.close()
process.exit(bad === 0 ? 0 : 1)
