// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0061.mjs — watch every guard in migration 0061 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7). This applies the chain up
// to but NOT including 0061 exactly once, then runs MUTATED copies of 0061 inside begin/rollback
// and records the REAL red message each of its asserts produces. A mutation that applies cleanly
// is reported as GREEN!! and fails the run — that is a guard that would never have caught anything.
//
//   node scripts/db/breaktest-0061.mjs               # every mutation
//   node scripts/db/breaktest-0061.mjs --clean       # apply 0061 unmutated, print its receipt
//   node scripts/db/breaktest-0061.mjs --only=<sub>  # one mutation, by a substring of its name
//
// The pre-0061 chain is CACHED as a PGlite data directory keyed on the bytes of every file before
// 0061, so re-running this costs seconds rather than the seven minutes the chain takes. A changed
// earlier migration changes the key, so the cache can never be stale. Shape copied from
// scripts/db/breaktest-0059.mjs.
//
// It lives in scripts/, never in the migration: commit bfd37c7 of this repo is where a break-test
// harness was written INTO a migration and had to be taken out again.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { tmpdir } from 'node:os'
import path from 'node:path'

const LAST = '20260818000061_a_city_sells_only_what_its_roster_names.sql'
const sql = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')
const cleanOnly = process.argv.includes('--clean')
const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice('--only='.length)

const { PGlite } = await import('@electric-sql/pglite')

// ── the cached pre-0061 world, keyed on the bytes that built it ───────────────────────────────
const before = (await migrationFiles()).filter((f) => f < LAST)
const preamble = await readFile(PREAMBLE_PATH, 'utf8')
const key = createHash('sha256').update(preamble)
const sources = []
for (const f of before) {
  const raw = (await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n')
  key.update(f).update(raw)
  sources.push(raw)
}
const cacheDir = path.join(tmpdir(), 'byeharu-voyage-breaktest')
const cacheFile = path.join(cacheDir, `pre-0061-${key.digest('hex').slice(0, 16)}.tar.gz`)

let db
if (existsSync(cacheFile)) {
  db = await PGlite.create({ loadDataDir: new Blob([await readFile(cacheFile)]) })
  console.log(`chain restored from cache: ${cacheFile}\n`)
} else {
  db = await new PGlite()
  await db.exec(preamble)
  for (const raw of sources) await db.exec(raw)
  await mkdir(cacheDir, { recursive: true })
  await writeFile(cacheFile, Buffer.from(await (await db.dumpDataDir('gzip')).arrayBuffer()))
  console.log(`chain applied up to (not including) 0061, cached to ${cacheFile}\n`)
}

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
    console.log(`UNMUTATED 0061 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0061: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// Each entry is [name, ...[find, replace]] — a mutation may need more than one hunk to be a LEGAL
// wrong migration rather than a syntax error, and a mutation that merely fails to compile proves
// nothing about the guard it was aimed at.
const MUTATIONS = [
  // ── THE RULE ITSELF (assert b) ──────────────────────────────────────────────────────────────
  ['(b) port_offers really reads the roster — it answers TRUE for every pair instead',
    `  select exists (select 1 from public.port_specialties s
                  where s.port_id = p_port and s.good_id = p_good)`,
    `  select true`],

  ['(b) port_offers really reads the roster — it answers FALSE for every pair instead',
    `  select exists (select 1 from public.port_specialties s
                  where s.port_id = p_port and s.good_id = p_good)`,
    `  select false`],

  ['(b) port_offers reads the roster of the WRONG port — a legal-looking transposition',
    `                  where s.port_id = p_port and s.good_id = p_good)`,
    `                  where s.port_id = p_good and s.good_id = p_port)`],

  ['(b) a sea place is given a quay — port_offers stops scoping to a real roster row',
    `  select exists (select 1 from public.port_specialties s
                  where s.port_id = p_port and s.good_id = p_good)`,
    `  select exists (select 1 from public.port_specialties s
                  where s.port_id = p_port and s.good_id = p_good)
      or exists (select 1 from public.ports p where p.id = p_port and p.kind <> 'HARBOUR')`],

  // ── THE OWNER'S BAND (assert c) ─────────────────────────────────────────────────────────────
  ['(c) the owner\'s 4..10 band is live — the ceiling is dropped to 9 and a capital must break it',
    `   where c < 4 or c > 10;`,
    `   where c < 4 or c > 9;`],

  ['(c) the owner\'s 4..10 band is live — the floor is raised to 5 and every small harbour breaks it',
    `   where c < 4 or c > 10;`,
    `   where c < 5 or c > 10;`],

  // ── THE MARKET READ (assert d) ──────────────────────────────────────────────────────────────
  ['(d) world.market really is narrowed — the quay_shows restriction is not applied',
    `     cross join lateral world.price(pg.port_id, pg.good_id) q
     where pg.port_id = p_port
       and public.quay_shows(pg.port_id, pg.good_id)),$m3$);`,
    `     cross join lateral world.price(pg.port_id, pg.good_id) q
     where pg.port_id = p_port),$m3$);`],

  ['(d) the `offered` flag is the roster\'s answer — it is hard-coded true instead',
    `        'offered', public.port_offers(pg.port_id, pg.good_id),$m1$,`,
    `        'offered', true,$m1$,`],

  // ── THE BUY GATE (assert e) ─────────────────────────────────────────────────────────────────
  ['(e) the roster gate is actually IN cmd.do_buy — the slice adds only a comment',
    `  if not public.port_offers(f.port_id, g.id) then
    raise exception 'E_UNAVAILABLE: % is not traded in this port', g.name using errcode = 'P0001';
  end if;

  select stock into v_stock`,
    `  -- (a gate that is only a comment)

  select stock into v_stock`],

  ['(e) the gate is the right way round — it refuses exactly the goods the city DOES trade',
    `  if not public.port_offers(f.port_id, g.id) then`,
    `  if public.port_offers(f.port_id, g.id) then`],

  ['(e) a refused order is RECORDED as failed — cmd.do_buy raises a bare exception with no E_ code',
    `    raise exception 'E_UNAVAILABLE: % is not traded in this port', g.name using errcode = 'P0001';
  end if;

  select stock into v_stock`,
    `    raise exception 'this port does not trade %', g.name using errcode = 'P0001';
  end if;

  select stock into v_stock`],

  // ── SELL MUST NOT BE GATED (asserts f and i) ────────────────────────────────────────────────
  ['(f/i) SELL is NOT restricted to the roster — the same gate is added to cmd.do_sell',
    `-- ── 4. THE MARKET READ SERVES THE QUAY`,
    `select pg_temp.recut('cmd.do_sell(uuid, jsonb)'::regprocedure, false,
  $x0$  v_have := public.fleet_cargo_qty(p_fleet, g.code);$x0$,
  $x1$  if not public.port_offers(f.port_id, g.id) then
    raise exception 'E_UNAVAILABLE: % is not traded in this port', g.name using errcode = 'P0001';
  end if;
  v_have := public.fleet_cargo_qty(p_fleet, g.code);$x1$);

-- ── 4. THE MARKET READ SERVES THE QUAY`],

  // NOT `or exists (select 1 where false) or exists (...)` — that leaves the real branch standing
  // and applied CLEANLY the first time it was tried. A mutation must actually remove the thing it
  // is aimed at (docs/DEV_LOG.md D28 records the same mistake made three ways in 0059).
  ['(f) the quay SHOWS her what she carries — quay_shows drops its cargo half',
    `  select public.port_offers(p_port, p_good)
      or exists (
           select 1
             from public.fleets f
             join public.goods  g on g.id = p_good
            where f.player_id = public.current_player_id()
              and f.port_id   = p_port
              and f.status    = 'DOCKED'
              and public.fleet_cargo_qty(f.id, g.code) > 0
         )`,
    `  select public.port_offers(p_port, p_good)`],

  // ── THE ASYMMETRY IS ASSERTED, NOT ASSUMED (assert i) ───────────────────────────────────────
  // The mutation above ((f/i)) goes red inside the SELL probe, which fires before assert (i) ever
  // reads cmd.do_sell's body — so that assert would still be decoration. This one names the gate
  // in do_sell's text and CHANGES NOTHING the verb does, so only assert (i) can catch it.
  ['(i) cmd.do_sell is read back and must not name the roster gate — a comment alone is enough',
    `-- ── 4. THE MARKET READ SERVES THE QUAY`,
    `select pg_temp.recut('cmd.do_sell(uuid, jsonb)'::regprocedure, false,
  $y0$  v_have := public.fleet_cargo_qty(p_fleet, g.code);$y0$,
  $y1$  -- public.port_offers is deliberately not asked here
  v_have := public.fleet_cargo_qty(p_fleet, g.code);$y1$);

-- ── 4. THE MARKET READ SERVES THE QUAY`],

  // ── THE QUAY NEVER NAMES A CARGO THE VERB WOULD REFUSE (assert k) ───────────────────────────
  // This is the defect scripts/db/proofs/04 caught in this file's first draft. The mutation puts
  // the draft back: world.trade_routes goes on shortlisting goods the origin does not trade.
  ['(k) world.trade_routes is narrowed at the ORIGIN — the roster gate is dropped from its scan',
    `       -- 0061: and she can only LOAD what this city trades. Same authority cmd.do_buy asks, so the
       -- shortlist cannot name a cargo the order would refuse. The destination is NOT filtered:
       -- selling is not gated by the roster (see this file's header).
       and public.port_offers(p_from, pg.good_id)$r1$);`,
    `$r1$);`],

  // ... and the gate must be on the BUY end. Narrowing the destination instead both fails to fix
  // the defect and deletes the owner's own point ("a purpose to go to a city that is far away").
  ['(k) the gate is on the ORIGIN, not the destination',
    `       and public.port_offers(p_from, pg.good_id)$r1$);`,
    `       and public.port_offers(p_from, p_from)$r1$);`],

  // ── THE MARKET TABLE IS UNTOUCHED (assert g) ────────────────────────────────────────────────
  // ONE good's worth of rows, not all 53,144: deleting every un-offered row empties one of
  // assert (b)'s two populations, so (b) speaks first and (g)'s own row count is never reached.
  ['(g) public.port_goods really is untouched — un-offered rows are deleted after all',
    `delete from public.price_history h
 where not public.port_offers(h.port_id, h.good_id);`,
    `delete from public.price_history h
 where not public.port_offers(h.port_id, h.good_id);
delete from public.port_goods pg
 where not public.port_offers(pg.port_id, pg.good_id)
   and pg.good_id = (select id from public.goods order by code limit 1);`],

  // ── THE RECORD (assert h) ───────────────────────────────────────────────────────────────────
  ['(h) the snapshot really is narrowed — the where clause is dropped from tick_price_snapshot',
    `    from public.port_goods pg
   -- 0061: a price nobody can be shown is not a record worth keeping. The chart is drawn on the
   -- MARKET screen, which serves world.market — the quay. 97.6% of this table was pairs no client
   -- could ever ask for. 0057's window law and its 600 MiB budget are UNTOUCHED.
   where public.port_offers(pg.port_id, pg.good_id)
  on conflict (port_id, good_id, slot) do nothing;$t1$);`,
    `    from public.port_goods pg
  on conflict (port_id, good_id, slot) do nothing;$t1$);`],

  ['(h) what the record already wrote goes too — the delete is dropped',
    `delete from public.price_history h
 where not public.port_offers(h.port_id, h.good_id);`,
    `delete from public.price_history h
 where not public.port_offers(h.port_id, h.good_id) and false;`],

  ['(h) the delete keeps the RIGHT half — its predicate is inverted',
    `delete from public.price_history h
 where not public.port_offers(h.port_id, h.good_id);`,
    `delete from public.price_history h
 where public.port_offers(h.port_id, h.good_id);`],

  // ── THE SLICES LANDED (assert i) ────────────────────────────────────────────────────────────
  ['(i) the deployed bodies are re-read — world.market keeps its grant when re-cut',
    `revoke all on function world.market(uuid) from public, anon;
grant execute on function world.market(uuid) to authenticated;`,
    `revoke all on function world.market(uuid) from public, anon, authenticated;`],

  // ── POSTURE (assert j) ──────────────────────────────────────────────────────────────────────
  ['(j) a client role is granted execute on the quay predicate',
    `revoke all on function public.port_offers(uuid, uuid) from public, anon, authenticated;`,
    `revoke all on function public.port_offers(uuid, uuid) from public, anon, authenticated;
grant execute on function public.port_offers(uuid, uuid) to authenticated;`],

  ['(j) a client role is granted execute on quay_shows',
    `revoke all on function public.quay_shows(uuid, uuid) from public, anon, authenticated;`,
    `revoke all on function public.quay_shows(uuid, uuid) from public, anon, authenticated;
grant execute on function public.quay_shows(uuid, uuid) to authenticated;`],

  // ── THE SLICE TOOL ITSELF ───────────────────────────────────────────────────────────────────
  ['(slice) a hunk that does not match the DEPLOYED body refuses rather than half-applies',
    `  $t0$    from public.port_goods pg
  on conflict (port_id, good_id, slot) do nothing;$t0$,`,
    `  $t0$    from public.port_goods pg
  ON CONFLICT (port_id, good_id, slot) do nothing;$t0$,`],
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
    console.log(`RED      ${name}\n         ${red.slice(0, 460)}`)
  }
}
console.log(bad === 0 ? '\nALL GUARDS BITE' : `\n${bad} GUARD(S) DID NOT BITE`)
process.exit(bad === 0 ? 0 : 1)
