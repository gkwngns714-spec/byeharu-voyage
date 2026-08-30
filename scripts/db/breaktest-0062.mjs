// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0062.mjs — watch every guard in migration 0062 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7). This applies the chain up
// to but NOT including 0062 exactly once, then runs MUTATED copies of 0062 inside begin/rollback
// and records the REAL red message each of its asserts produces. A mutation that applies cleanly
// is reported as GREEN!! and fails the run — that is a guard that would never have caught anything.
//
//   node scripts/db/breaktest-0062.mjs               # every mutation
//   node scripts/db/breaktest-0062.mjs --clean       # apply 0062 unmutated, print its receipt
//   node scripts/db/breaktest-0062.mjs --only=<sub>  # one mutation, by a substring of its name
//
// EACH MUTATION IS AIMED AT THE FIRST GUARD IT CAN REACH. 0062's asserts run in order — (a) the
// non-vacuous floor, (b) the geography is well formed, (c) the roster law, (d) no good falls out of
// the world, and so on — so a mutation that would trip two is written to trip the one it is named
// after. That is why (b) precedes (c) in the migration at all: a good with no origin region is a
// malformed row, and checking the LAW before checking that the data is WELL FORMED would have made
// (b) unreachable and therefore untestable.
//
// THREE MUTATIONS ARE LABELLED `(c)/(x)`. They target a later guard but the roster law (c) reaches
// them first, because everything they leave behind is an offer belonging to neither arm. That is the
// ordering working, not a gap — and it is written on the mutation rather than hidden, because a
// label claiming a guard bit when a different one did is the same lie as a green report nobody read.
// (l)'s own line is therefore defence in depth: it can only be reached by a stale offer that is BOTH
// native and inside the count law, which no single-hunk mutation of this file can produce.
//
// Shape copied from scripts/db/breaktest-0058.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000062_a_good_comes_from_somewhere.sql'
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
console.log('chain applied up to (not including) 0062\n')

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
    console.log(`UNMUTATED 0062 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0062: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

const MUTATIONS = [
  // ── (b) THE GEOGRAPHY IS WELL FORMED ────────────────────────────────────────────────────────
  ['(b) a good is left with no origin region at all — cloves comes from nowhere',
    "  ('cloves', '{SOU}', '{}', '{}'),",
    "  ('cloves', '{}', '{}', '{}'),"],

  ['(b) an origin names a region this world does not define',
    "  ('cloves', '{SOU}', '{}', '{}'),",
    "  ('cloves', '{ZZZ}', '{}', '{}'),"],

  ['(b) an entrepot names a port this world does not define',
    "  ('ginseng', '{CHI,KOR}', '{TSU}', '{}'),",
    "  ('ginseng', '{CHI,KOR}', '{TSU,ZZZ}', '{}'),"],

  ["(b) an entrepot names a port that already sits in the good's own origin region",
    "  ('cork', '{IBE}', '{}', '{}'),",
    "  ('cork', '{IBE}', '{LIS}', '{}'),"],

  ['(b) an entrepot names a port that does not actually offer the good — a claim nobody checks',
    "  ('amber', '{BAL}', '{}', '{}'),",
    "  ('amber', '{BAL}', '{TOK}', '{}'),"],

  // ── (c) THE ROSTER LAW ──────────────────────────────────────────────────────────────────────
  ["(c) an offer belongs to neither arm — Tokyo is given back one of 0058's hash picks (caviar)",
    'create temporary table geo_hash_picks_0062',
    "insert into public.port_specialties (port_id, good_id)\n" +
      "select (select id from public.ports where code = 'TOK'), (select id from public.goods where code = 'caviar');\n" +
      'create temporary table geo_hash_picks_0062'],

  // NOT a mutation: loosening the assert's OWN predicate (`where false`) is green by construction
  // and proves nothing — a disabled guard always passes. The valid shape is to TIGHTEN it, which
  // shows the RAISE line is live and reachable on real rows. Recorded because the first draft of
  // this file did the invalid thing and the harness reported GREEN!! — which is the harness working.
  ['(c) the law is tightened to "native only" — the RAISE line is live and the 47 entrepot offers hit it',
    '   where not (r.code = any(g.origin_regions))\n     and not (p.code = any(g.entrepot_ports));',
    '   where not (r.code = any(g.origin_regions));'],

  ['(c) every entrepot row is deleted — 47 real offers instantly belong to neither arm',
    '       entrepot_ports = v.entrepot::text[],',
    "       entrepot_ports = '{}'::text[],"],

  // (c2) is reached only when the law itself still passes, so the mutation makes EVERY good native
  // everywhere. Nothing is then an entrepot, the OR's second arm carries zero offers, and the law
  // has a dead half — which is exactly the failure (c2) exists to catch and (c) cannot see.
  ['(c2) the entrepot arm is emptied while the law still passes — the OR has a dead half',
    '   set origin_regions = v.origin::text[],\n       entrepot_ports = v.entrepot::text[],',
    "   set origin_regions = (select array_agg(code) from public.regions),\n       entrepot_ports = '{}'::text[],"],

  // ── (d) NO GOOD FALLS OUT OF THE WORLD ──────────────────────────────────────────────────────
  ["(d) 0058's own orphaning is re-created — allspice loses its only port again",
    "  ('POR', 'allspice'),",
    "  ('POR', 'tortoiseshell'),"],

  ['(d) a good survives only in re-export — coffee is grown nowhere and sold at six entrepots',
    "  ('coffee', '{ARA}', '{ALE,MRS}', '{}'),",
    "  ('coffee', '{BAL}', '{ADE,ALE,JED,MOC,MRS,SUE}', '{}'),"],

  ['(c)/(d) a sea place gains a roster — (c) reaches it first, because a sea place is in no origin region',
    'insert into public.port_specialties (port_id, good_id)\nselect t.port_id, t.good_id from geo_target_ids_0062 t',
    "insert into public.port_specialties (port_id, good_id)\n" +
      "select (select id from public.ports where kind = 'SEA_PLACE' order by code limit 1),\n" +
      "       (select id from public.goods order by code limit 1);\n" +
      'insert into public.port_specialties (port_id, good_id)\nselect t.port_id, t.good_id from geo_target_ids_0062 t'],

  // ── (e) 0058'S COUNT LAW IS STILL EXACT ─────────────────────────────────────────────────────
  ["(e) a small harbour is left with 5 goods — 0058's count law breaks",
    "  ('KAL', 'amber'),",
    "  ('KAL', 'amber'),\n  ('KAL', 'tar'),"],

  ["(e) a capital is left with 9 — the owner's ten breaks",
    "  ('TOK', 'sword-blades'),",
    "  ('TOK', 'rice'),"],

  // ── (f) / (g) THE NAMED RESTORATIONS ────────────────────────────────────────────────────────
  ['(f) lac is not restored to Syriam — 0058 left it buyable nowhere on earth',
    "  ('THA', 'lac'),",
    "  ('THA', 'sappanwood'),"],

  ["(g) Konigsberg does not get its amber back — the port's own note names the monopoly",
    "  ('KAL', 'amber'),",
    "  ('KAL', 'tar'),"],

  // ── (h) THE CULTURE MASKS ───────────────────────────────────────────────────────────────────
  ['(h) salted beef loses its mask — the seventh mask is not authored',
    "  ('salted-beef', '{ATL,BAL,BRI,CAR,EAS,FRA,NOR,STH}', '{}', '{indic,japanese}'),",
    "  ('salted-beef', '{ATL,BAL,BRI,CAR,EAS,FRA,NOR,STH}', '{}', '{}'),"],

  ['(h) a port is left producing a good its own culture refuses — the Famagusta fix is reverted',
    "update public.ports set culture = 'latin' where code in ('RHO', 'FAM');",
    "update public.ports set culture = 'latin' where code in ('RHO');"],

  ['(h) a mask names a culture no harbour holds, so the refusal can never fire',
    "  ('sake', '{JAP}', '{}', '{islamic,swahili}'),",
    "  ('sake', '{JAP}', '{}', '{islamic,swahili,aztec}'),"],

  // ── (i) THE MARKET IS RESTATED, NOT MINTED ──────────────────────────────────────────────────
  ['(i) port_goods.affinity is left stale after the roster moves',
    'update public.port_goods pg\n   set affinity = world.affinity_for(pg.port_id, pg.good_id);',
    'update public.port_goods pg\n   set affinity = pg.affinity where false;'],

  ['(i) stock is RAISED to the new target instead of clamped down — the roster move mints cargo',
    'stock           = least(pg.stock, greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity)))),',
    'stock           = greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity))) + 1,'],

  ["(i) production_rate stops restating 0005's formula",
    'production_rate = case when pg.affinity < 0.80\n                               then round(greatest(60, 200 * p.size_tier * (1.60 - pg.affinity)) * 0.05, 2)\n                               else 0 end',
    'production_rate = 1.00'],

  ['(i) dev_commerce / dev_industry are left stale after the roster moves',
    'update public.ports p\n   set dev_commerce = greatest(0, least(20, round(p.size_tier * 2.4 + coalesce(x.c_all, 0)))),\n       dev_industry = greatest(0, least(20, round(p.size_tier * 2.0 + coalesce(x.c_ind, 0) * 1.5)))',
    'update public.ports p\n   set dev_commerce = p.dev_commerce,\n       dev_industry = p.dev_industry'],

  // ── (j) THE POSITIVE CONTROL: 0058'S HASH IS RETIRED AS AN AUTHOR ───────────────────────────
  ["(c)/(j) a ninth hash pick survives — Venice keeps 0058's Virginian sassafras, and (c) reaches it first",
    "  ('VEN', 'dried-fruit'),",
    "  ('VEN', 'sassafras'),"],

  ['(j) the hash-pick control table loses a row, so the control controls less than it claims',
    "  ('ALE', 'salted-tuna'),\n  ('AMS', 'ramie-cloth'),",
    "  ('AMS', 'ramie-cloth'),"],

  // ── (k) NOTHING CASCADES OFF port_specialties ───────────────────────────────────────────────
  ['(k) a foreign key is pointed at port_specialties, so deleting an offer would cascade',
    '-- ── SELF-ASSERT ─',
    'create table public.breaktest_0062_fk (port_id uuid not null, good_id uuid not null,\n' +
      '  foreign key (port_id, good_id) references public.port_specialties(port_id, good_id));\n-- ── SELF-ASSERT ─'],

  // ── (l) IDEMPOTENCE ─────────────────────────────────────────────────────────────────────────
  ['(c)/(l) the rewrite becomes a delta instead of a target set — 56 stale offers survive, and (c) reaches them first',
    'delete from public.port_specialties s\n where s.port_id in (select distinct port_id from geo_target_ids_0062)',
    'delete from public.port_specialties s\n where false and s.port_id in (select distinct port_id from geo_target_ids_0062)'],

  // ── (m) POSTURE ─────────────────────────────────────────────────────────────────────────────
  ['(m) a client role is granted a write on the goods table',
    '-- ── SELF-ASSERT ─',
    'grant update on public.goods to authenticated;\n-- ── SELF-ASSERT ─'],
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = false
  for (let i = 0; i < hunks.length; i += 2) {
    if (!mutated.includes(hunks[i])) { missing = true; break }
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
