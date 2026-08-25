// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0053.mjs — make 0053's self-assert BITE, one guard at a time
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// 0053 is a PERFORMANCE slice, which is the shape most likely to ship a guard that cannot fail:
// the migration is green the moment it applies, and "the values did not move" reads exactly the
// same whether it was checked or not. So every assert in the file is broken on purpose here and
// the RED MESSAGE IT PRODUCES is recorded.
//
// The two that matter most and that nothing else in the chain would catch:
//   * a mutated §G.1 expression — the values move, quietly, and another slice is measuring
//     balance on top of this one right now;
//   * `security definer set search_path` on world.mid_from_terms — every value stays correct, the
//     planner stops inlining it, and the 9,720 calls this file removed come straight back. That is
//     the reflex posture of every other function in this chain, so it is the mistake that will
//     actually be made.
//
// Shape copied from scripts/db/breaktest-0051.mjs: apply the chain up to but NOT including 0053
// once, then run MUTATED copies of 0053 inside begin/rollback. The mutations never touch the file
// on disk — a break-test that contaminates the migration it is proving is this repo's commit
// bfd37c7, and it is not repeated.
//
//   node scripts/db/breaktest-0053.mjs
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000053_the_quay_prices_its_neighbours_once.sql'
const sql0053 = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')

const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f === LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log('chain applied to 0052\n')

// The §G.1 product inside world.mid_from_terms, as it ships.
const G1 = `           * power(p_stock_target / greatest(p_stock, 1), p_elasticity)
           * (1 + p_drift)`

/** @type {[string, [string, string][]][]} */
const MUTATIONS = [
  [
    '(a1) the §G.1 product is mutated — every mid in the world moves',
    [[G1, `           * power(p_stock_target / greatest(p_stock, 1), p_elasticity)
           * (1 + p_drift * 1.000001)`]],
  ],
  [
    '(a2) only the §G.7.3 BAND is mutated — today’s stocks are unaffected, the sweep is not',
    [['           p_band_lo * p_base), p_band_hi * p_base), 4)', '           p_band_lo * p_base * 1.5), p_band_hi * p_base), 4)']],
  ],
  [
    '(a3) the scalar door answers off a different radius',
    [["    select public.wc_num('neighbour_radius_nm') as radius,", '    select 900::numeric as radius,']],
  ],
  [
    // (a3) is what catches this, and deliberately so: a narrowing argument that stops narrowing
    // breaks the SCALAR, which is the door with the outside callers. (a4) is the statement that
    // the two are one body; there is no mutation that breaks the seam and leaves (a3) whole.
    '(a3/a4) the narrowing argument stops narrowing (p_good ignored on the wide/narrow seam)',
    [['       and (p_good is null or pg.good_id = p_good)', '       and (p_good is null or p_good is not null)']],
  ],
  [
    // Isolates (a5): the mids are untouched, the scalar is untouched, only what MARKET serves
    // moves. Nothing else in the file's guards can see this.
    '(a5) world.market serves a different payload — %NBR is re-rounded on its way onto the wire',
    [
      [
        '    select a.good_id, a.pct from world.pct_of_neighbours_at(p_port) a\n  ),',
        '    select a.good_id, round(a.pct) as pct from world.pct_of_neighbours_at(p_port) a\n  ),',
      ],
    ],
  ],
  [
    '(b) THE WORK GUARD — world.market goes back to the per-good scalar (values all still correct)',
    [
      [
        '    select a.good_id, a.pct from world.pct_of_neighbours_at(p_port) a\n  ),',
        '    select pg.good_id, world.pct_of_neighbours(p_port, pg.good_id) as pct\n      from public.port_goods pg\n     where pg.port_id = p_port\n  ),',
      ],
      // (c) reads the same body, so it would intercept (b). Withdrawn for this mutation only.
      [
        "  select count(*) into v_n from regexp_matches(v_def, 'world\\.pct_of_neighbours_at\\(', 'g');\n  select count(*) into v_bad from regexp_matches(v_def, 'world\\.pct_of_neighbours\\(', 'g');\n  if v_n <> 1 or v_bad <> 0 then",
        "  select count(*) into v_n from regexp_matches(v_def, 'world\\.pct_of_neighbours_at\\(', 'g');\n  select count(*) into v_bad from regexp_matches(v_def, 'world\\.pct_of_neighbours\\(', 'g');\n  if false then",
      ],
    ],
  ],
  [
    '(b2) the BEFORE reading is taken AFTER the re-cut, so the ratio would pass vacuously',
    [
      [
        "  execute format('explain (analyze, buffers, format json) select world.market(%L::uuid)', v_id) into v_json;\n  insert into buffers_0053 values ('before',",
        "  execute format('explain (analyze, buffers, format json) select 1 where %L is not null', v_id) into v_json;\n  insert into buffers_0053 values ('before',",
      ],
    ],
  ],
  [
    '(c) the deployed shape check really reads the catalogue (the authority renamed under it)',
    [["  select count(*) into v_n from regexp_matches(v_def, 'world\\.pct_of_neighbours_at\\(', 'g');\n  select count(*) into v_bad from regexp_matches(v_def, 'world\\.pct_of_neighbours\\(', 'g');",
      "  select count(*) into v_n from regexp_matches(v_def, 'world\\.a_second_index_at\\(', 'g');\n  select count(*) into v_bad from regexp_matches(v_def, 'world\\.pct_of_neighbours\\(', 'g');"]],
  ],
  [
    '(c2) world.mid_price keeps a power() of its own beside the one authority',
    [
      [
        '  return world.mid_from_terms(v_base, v_aff, v_target, p_stock, v_drift, v_season, v_dev,',
        "  if power(2, 2) < 0 then raise exception 'unreachable'; end if;\n  return world.mid_from_terms(v_base, v_aff, v_target, p_stock, v_drift, v_season, v_dev,",
      ],
    ],
  ],
  [
    '(d) THE INLINE PRECONDITION — the chain’s reflex posture applied to world.mid_from_terms',
    [['language sql\nimmutable\nparallel safe\nas $$\n  -- DESIGN G.1, term by term', 'language sql\nstable\nsecurity definer\nset search_path = public, pg_temp\nas $$\n  -- DESIGN G.1, term by term']],
  ],
  [
    '(e) the posture moves — the set authority made client-executable',
    [
      [
        'revoke all on function world.pct_of_neighbours_at(uuid, uuid) from public, anon, authenticated;',
        'grant execute on function world.pct_of_neighbours_at(uuid, uuid) to authenticated;',
      ],
    ],
  ],
  [
    // `create or replace` KEEPS the existing ACL, so withdrawing the grant line alone changes
    // nothing — 0019's grant is still on the function. The revoke has to be widened with it.
    '(e2) the supersede drops authenticated’s EXECUTE on the scalar the market screen needs',
    [
      [
        'revoke all on function world.pct_of_neighbours(uuid, uuid) from public, anon;',
        'revoke all on function world.pct_of_neighbours(uuid, uuid) from public, anon, authenticated;',
      ],
      ['grant execute on function world.pct_of_neighbours(uuid, uuid) to authenticated;', '-- grant withdrawn by the break test'],
    ],
  ],
  [
    '(0) the pre-images go thin — every parity check below would pass over nothing',
    [['      (select id, code, n from nbrs order by code limit 4)', '      (select id, code, n from nbrs order by code limit 1)']],
  ],
  [
    '(0b) the subject ports stop spanning the extremes (the island is dropped for a second crowd)',
    [
      ['      (select id, code, n from nbrs order by n asc,  code limit 1)', '      (select id, code, n from nbrs order by n desc, code limit 1 offset 1)'],
      ['      (select id, code, n from nbrs order by code limit 4)', '      (select id, code, n from nbrs order by n desc, code limit 4 offset 2)'],
    ],
  ],
  [
    '(slice) the deployed world.market is not what this file was generated against',
    [['    select pg.good_id, world.pct_of_neighbours(p_port, pg.good_id) as pct\n      from public.port_goods pg\n     where pg.port_id = p_port\n  ),\',', '    select pg.good_id, world.pct_of_neighbours(p_port, pg.good_id) as pct\n      from public.port_goods pg\n     where pg.port_id = p_port_typo\n  ),\',']],
  ],
]

let bad = 0
for (const [name, edits] of MUTATIONS) {
  let mutated = sql0053
  let anchored = true
  for (const [from, to] of edits) {
    if (from !== '' && !mutated.includes(from)) {
      console.log(`SKIPPED  ${name} — mutation anchor not found, FIX THE SCRIPT:\n    ${JSON.stringify(from.slice(0, 110))}`)
      anchored = false
      bad += 1
      break
    }
    // A FUNCTION replacer, never a string: in String.replace a literal `$$` in the replacement is
    // the escape for one `$` (breaktest-0051.mjs learned this the expensive way).
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
  await db.exec(sql0053, { onNotice: (n) => notices.push(n.message ?? String(n)) })
} catch (err) {
  clean = err.message
}
await db.exec('rollback')
console.log('')
if (clean === null) {
  console.log('UNMUTATED 0053 APPLIES GREEN:')
  for (const l of notices) console.log(`  ${l}`)
} else {
  console.log(`UNMUTATED 0053 FAILED: ${clean}`)
  bad += 1
}

console.log('')
console.log(bad === 0 ? `ALL ${MUTATIONS.length} GUARDS BIT` : `${bad} PROBLEM(S)`)
await db.close()
process.exit(bad === 0 ? 0 : 1)
