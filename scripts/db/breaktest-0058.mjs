// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0058.mjs — watch every guard in migration 0058 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7). This applies the chain up
// to but NOT including 0058 exactly once, then runs MUTATED copies of 0058 inside begin/rollback
// and records the REAL red message each of its asserts produces. A mutation that applies cleanly
// is reported as GREEN!! and fails the run — that is a guard that would never have caught anything.
//
//   node scripts/db/breaktest-0058.mjs               # every mutation
//   node scripts/db/breaktest-0058.mjs --clean       # apply 0058 unmutated, print its receipt
//   node scripts/db/breaktest-0058.mjs --only=<sub>  # one mutation, by a substring of its name
//
// Shape copied from scripts/db/breaktest-0055.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000058_a_city_offers_what_its_size_earns.sql'
const sql = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')
const cleanOnly = process.argv.includes('--clean')
const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice('--only='.length)

const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f >= LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log('chain applied up to (not including) 0058\n')

// ── the unmutated run: it must be GREEN, and its receipt is the measurement this file reports ──
{
  const notices = []
  await db.exec('begin')
  let red = null
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
  } catch (e) {
    red = String(e.message)
  }
  await db.exec('rollback').catch(() => {})
  if (red) {
    console.log(`UNMUTATED 0058 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0058: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

const NL = '\n'
const MUTATIONS = [
  ['(b) capital does not always answer 10 — the law caps it at 9, the old ceiling',
    'if p_tier = 5 then\n    return 10;',
    'if p_tier = 5 then\n    return 9;'],

  ['(b) small does not always answer 4 — the law allows 5, the old ceiling',
    'elsif p_tier = 2 then\n    return 4;',
    'elsif p_tier = 2 then\n    return 5;'],

  ['(c) the floor breaks — small targets 3, under the owner\'s floor',
    'elsif p_tier = 2 then\n    return 4;',
    'elsif p_tier = 2 then\n    return 3;'],

  ['(c) a sea place gains a roster — an extra row is inserted for one after the fill',
    'insert into public.port_specialties (port_id, good_id)\nselect port_id, good_id from roster_fill_0058;',
    "insert into public.port_specialties (port_id, good_id)\nselect port_id, good_id from roster_fill_0058;\n" +
      "insert into public.port_specialties (port_id, good_id)\n" +
      "select (select id from public.ports where kind = 'SEA_PLACE' order by code limit 1),\n" +
      "       (select id from public.goods order by code limit 1);"],

  ['(d) the mid-tier draw stops spreading — every under-authored mid port lands at 6, not 4-8',
    'return 4 + floor(p_draw * 5)::int;',
    'return 6;'],

  ['(e) roster_rng stops being IMMUTABLE',
    "create function public.roster_rng(p_key text)\nreturns numeric\nlanguage sql\nimmutable\nparallel safe",
    "create function public.roster_rng(p_key text)\nreturns numeric\nlanguage sql\nvolatile"],

  ['(e) roster_rng stops varying with its key — always answers the same draw',
    "  select voyage.rng_raw(\n    '00000000-0000-0000-0000-000000000000'::uuid,\n    0,\n    'roster:' || p_key,",
    "  select voyage.rng_raw(\n    '00000000-0000-0000-0000-000000000000'::uuid,\n    0,\n    'roster:fixed',"],

  ['(f) the mid ceiling trim moves from 8 to 9',
    'elsif p_authored > 8 then\n      return 8;',
    'elsif p_authored > 8 then\n      return 9;'],

  ['(f) the mid preserve-band widens to admit 9',
    'if p_authored between 4 and 8 then\n      return p_authored;',
    'if p_authored between 4 and 9 then\n      return p_authored;'],

  ['(f) an invalid tier stops raising — tier 1 silently falls through to small\'s answer',
    "else\n    raise exception '0058: roster_target_count asked for tier % — capital/mid/small map onto size_tier 5/3/2 only (scripts/lib/world-derive.mjs:16), and no HARBOUR in this world carries any other tier', p_tier;\n  end if;",
    'else\n    return 4;\n  end if;'],

  ['(g) the retired band is reproduced exactly — capital 9 / mid trim 7 / small 4-5',
    'if p_tier = 5 then\n    return 10;',
    'if p_tier = 5 then\n    return 9;'],

  ['(h) an already-legal small harbour is touched anyway — a drop fires even at target',
    'where t.authored_n > t.target_n\n  ) r\n where r.rk <= (r.authored_n - r.target_n);',
    'where t.authored_n >= t.target_n\n  ) r\n where r.rk <= greatest(1, r.authored_n - r.target_n);'],

  ['(j) port_goods.affinity is left stale after the roster moves',
    'update public.port_goods pg\n   set affinity = world.affinity_for(pg.port_id, pg.good_id);',
    "update public.port_goods pg\n   set affinity = pg.affinity where false;"],

  ['(j) production_rate stops restating 0005\'s formula — a flat rate is written instead',
    'production_rate = case when pg.affinity < 0.80\n                               then round(greatest(60, 200 * p.size_tier * (1.60 - pg.affinity)) * 0.05, 2)\n                               else 0 end',
    'production_rate = 1.00'],

  ['(k) dev_commerce/dev_industry are left stale after the roster moves',
    'update public.ports p\n   set dev_commerce = greatest(0, least(20, round(p.size_tier * 2.4 + coalesce(x.c_all, 0)))),\n       dev_industry = greatest(0, least(20, round(p.size_tier * 2.0 + coalesce(x.c_ind, 0) * 1.5)))',
    'update public.ports p\n   set dev_commerce = p.dev_commerce,\n       dev_industry = p.dev_industry'],

  ['(l) the rarity apex guard\'s multiplier is corrupted — proving the RAISE line is live, not decoration',
    'if v_exotic * 4 > v_n then',
    'if v_exotic * 100 > v_n then'],

  ['(m) a client role is granted execute on the roster hash',
    'revoke all on function public.roster_rng(text) from public, anon, authenticated;',
    'revoke all on function public.roster_rng(text) from public, anon, authenticated;\ngrant execute on function public.roster_rng(text) to authenticated;'],
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = false
  for (let i = 0; i < hunks.length; i += 2) {
    if (!mutated.includes(hunks[i])) {
      missing = true
      break
    }
    mutated = mutated.replace(hunks[i], hunks[i + 1])
  }
  if (missing) {
    console.log(`SKIPPED  ${name} — mutation anchor not found, FIX THE SCRIPT`)
    bad += 1
    continue
  }
  await db.exec('begin')
  let red = null
  try {
    await db.exec(mutated)
  } catch (e) {
    red = String(e.message).split('\n')[0]
  }
  await db.exec('rollback').catch(() => {})
  if (!red) {
    console.log(`GREEN!!  ${name} — the mutation applied cleanly. THE GUARD IS DECORATION.`)
    bad += 1
  } else {
    console.log(`RED      ${name}\n         ${red.slice(0, 420)}`)
  }
}
console.log(bad === 0 ? '\nALL GUARDS BITE' : `\n${bad} GUARD(S) DID NOT BITE`)
process.exit(bad === 0 ? 0 : 1)
