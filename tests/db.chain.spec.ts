// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LOCAL ENGINE — the real chain, applied in this process, by the code the browser runs
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PURE UNIT SPEC. No `page` fixture, so Playwright runs it as a plain Node process and no browser
// binary is needed — but the Postgres is real: PGlite is PostgreSQL 18 compiled to WebAssembly,
// with the real planner, real plpgsql, real constraints and real triggers.
//
// WHAT THIS FILE IS FOR, given that `npm run db:apply` already applies the chain:
//   db:apply proves the SQL. This proves THE CLIENT'S COPY OF THE PROCEDURE — that src/lib/db
//   orders the files the way Postgres will see them, refuses a chain it should refuse, notices
//   when the chain has changed, and rebuilds rather than layering new migrations onto an old
//   database. Those are the failure modes that cannot be seen from the SQL side at all.

import { test, expect } from '@playwright/test'
import {
  assertChainIsSane,
  describeChain,
  fingerprintChain,
  orderChain,
  type MigrationFile,
} from '../src/lib/db/chain'
import { applyChain, MigrationFailure } from '../src/lib/db/applyChain'
import { createBootChannel, progressFor, type BootPhase } from '../src/lib/db/bootState'
import { openLocalDb, humanMigration, LOCAL_AUTH_UID } from '../src/lib/db/localDb'
import {
  loadChain,
  loadChainWithEdit,
  removeScratchDataDir,
  scratchDataDir,
} from '../src/lib/db/chainSource.node.mjs'

const FIRST = '20260818000001_the_world_is_read_only_to_everyone_but_the_server.sql'
// Moved deliberately 2026-08-22 with 0019 (the quay names the port that pays) and 0020 (the verbs
// speak to a captain, not to a schema): the read that ranks reachable ports by what a trade would
// be worth, the three folds it needed first — voyage.reach_from, voyage.sail_refusal, and one %NBR
// walk per good instead of four — and the verb help text the Command tab now prints to players.
//
// Moved again, deliberately, 2026-08-23 with 0025-0027: the table of captains (a board settled from
// the ledger, carrying deeds and never another house's purse), the fair at the quay (the first
// TIMED modifier, taken on the port's published cut because voyage.depart freezes speed and a
// modifier cannot honestly reach a frozen number), and the wiring of the last three inert
// coefficients — SURGEON into voyage.settle's crew loss, ACCOUNTING into the daily allowance, and
// NAVIGATION composed THROUGH voyage.fleet_speed rather than beside it.
//
// Moved again, deliberately, 2026-08-23 with 0028: the buff calendar is now wound by world.fleets()
// — the read AppShell makes every thirty seconds — instead of only by world.buffs(), whose one
// caller was the PORT tab, so a fair happens because the game is being played rather than because
// one screen was opened; and world.snapshot() gains the two things the wire was missing, DESIGN
// D.1's CALENDAR clock (`game_day_seconds`, without which no client could honestly print a figure
// counted in game-days) and a `nations` catalogue (without which a nation crossed the wire as a
// code nothing could turn back into a name).
//
// Moved again, deliberately, 2026-08-23 with 0029-0031. 0029: world.market() serves the prices'
// own clock — `clock.now` and `clock.next_change_at`, from the new named authority
// public.next_drift_change_at — and WINDS public.tick_market_drift before pricing, so a screen's
// countdown is subtraction against a served instant (never client arithmetic over slot_seconds)
// and the re-ask at zero is itself what steps the market where pg_cron is absent. 0030: the
// owner's word — "hands" becomes "crew" in every served refusal, report line, verb card and
// blurb, sliced out of the live definitions with the surroundings byte-identical by construction.
// 0031 (authored in a parallel session, verified green here — 31 migrations, 31 receipts): the
// world secret is rotated off the published 0001 literal and the table now refuses it by CHECK.
// Pin moved deliberately 2026-08-23 with 0032: every good now carries a served RARITY tier —
// derived on the server from how many ports produce it (public.good_rarity, one threshold law),
// served on snapshot.goods[] and market.goods[], asserted inhabited in all four tiers and a
// declared no-op on both payloads but for the field. 32 migrations, 32 receipts, verified green.
// Pin moved deliberately 2026-08-23 again with 0033: the owner asked "what is yard?" — the two
// repair refusals and the REPAIR card now say "shipyard", sliced out of the live definitions
// 0030-style with the surroundings byte-identical by construction. 33 migrations, 33 receipts.
// Pin moved deliberately 2026-08-23 with 0034: the STANDING PROVISION ORDER — house-owned
// presets ("keep her at N days of stores") a fleet points at by reference, fired by
// voyage.settle's arrival arm (sliced, byte-parity proven) through the one provisioning rule
// cmd.do_provision, sized at fire time from the crew aboard. 34 migrations, 34 receipts,
// verified green locally (db:apply + db:proof, twice).
// Pin moved deliberately 2026-08-23 with 0035: WHAT CAN BEFALL A FLEET AT SEA IS A TABLE — the set
// of things that can happen on a voyage-day was stated in THREE functions (hazard_roll's CASE,
// settle's arms, and report_line's CASE, whose `else` printed the raw schema code at the player)
// and is now ONE catalogue, public.voyage_event_kinds, with voyage_events.kind a foreign key into
// it, so a kind nobody named cannot be written. Declared a no-op and proven one: the draw agrees
// with 0006's CASE on 50,000 (r_kind, piracy) pairs and all eleven after-action lines are
// byte-identical. This is the foundation of docs/PLATFORM.md — it builds no combat, no exploration
// and no NPC, only the seam they will need. 35 migrations, 35 receipts, verified green locally
// (db:apply + db:proof, twice) with all nine of its new asserts break-tested red first.
const LAST = '20260818000035_what_can_befall_a_fleet_at_sea_is_a_table.sql'

// ── the chain, as data ─────────────────────────────────────────────────────────────────────────

test('the chain the client loads is the chain on disk, in apply order, LF-only', async () => {
  const files = await loadChain()
  expect(files.length).toBeGreaterThanOrEqual(10)
  expect(files[0].name).toBe(FIRST)
  expect(files[files.length - 1].name).toBe(LAST)
  for (const f of files) {
    expect(f.sql.includes('\r'), `${f.name} must be LF-only`).toBe(false)
    expect(f.sql.length).toBeGreaterThan(1000)
  }
  // Sorting is idempotent and is what Postgres/Supabase will see.
  expect(orderChain(files).map((f) => f.name)).toEqual(files.map((f) => f.name))
})

test('a chain that could apply half a world is refused before a statement runs', async () => {
  const files = await loadChain()
  expect(() => assertChainIsSane([])).toThrow(/EMPTY CHAIN/)
  expect(() => assertChainIsSane([{ name: files[0].name, sql: 'select 1;\r\n' }])).toThrow(/CRLF/)
  expect(() => assertChainIsSane([{ name: 'no_version.sql', sql: 'select 1;' }])).toThrow(
    /14-digit version/,
  )
  const dup: MigrationFile[] = [files[0], { name: `${FIRST.slice(0, 14)}_other.sql`, sql: 'select 1;' }]
  expect(() => assertChainIsSane(dup)).toThrow(/DUPLICATE VERSION/)
})

test('the fingerprint moves when a migration changes, and only then', async () => {
  const files = await loadChain()
  const base = fingerprintChain(files)

  // Deterministic: the same bytes twice, and order-independent input.
  expect(fingerprintChain(await loadChain())).toBe(base)
  expect(fingerprintChain([...files].reverse())).toBe(base)

  // ONE CHARACTER of ONE migration — the case that matters, because it is the shape of a real
  // edit and the shape a weak hash misses.
  const edited = await loadChainWithEdit(LAST, (sql) => `${sql}\n-- one added comment\n`)
  expect(fingerprintChain(edited)).not.toBe(base)

  const renamed = files.map((f, i) => (i === 3 ? { name: '20260818000099_renamed.sql', sql: f.sql } : f))
  expect(fingerprintChain(renamed)).not.toBe(base)

  const dropped = files.slice(0, files.length - 1)
  expect(fingerprintChain(dropped)).not.toBe(base)

  expect(describeChain(files)).toContain(`${files.length} migration(s)`)
})

// ── applying it ────────────────────────────────────────────────────────────────────────────────

test('every migration applies, in order, and every one prints its self-assert receipt', async () => {
  const { PGlite } = await import('@electric-sql/pglite')
  const db = await PGlite.create()
  try {
    const files = await loadChain()
    const seen: string[] = []
    const result = await applyChain(db, files, (step) => {
      seen.push(step.name)
      expect(step.total).toBe(files.length)
    })
    expect(seen).toEqual(files.map((f) => f.name))
    expect(result.applied.map((a) => a.name)).toEqual(files.map((f) => f.name))
    // The non-vacuity floor apply-chain.mjs enforces: a migration that stopped printing its
    // receipt is a migration whose self-assert may have stopped asserting.
    expect(result.receipts).toBe(files.length)

    // The world is seeded, and it is the REAL world — not a number this spec remembers. Pinning
    // 12 (or 214) would make adding a port a test failure, which it is not.
    const ports = await db.query<{ n: number }>('select count(*)::int as n from public.ports')
    expect(ports.rows[0].n).toBeGreaterThan(100)
    const lisbon = await db.query<{ n: number }>(
      "select count(*)::int as n from public.ports where code = 'LIS'",
    )
    expect(lisbon.rows[0].n).toBe(1)
  } finally {
    await db.close()
  }
})

test('a migration that fails names the FILE and carries the SQLSTATE', async () => {
  const { PGlite } = await import('@electric-sql/pglite')
  const db = await PGlite.create()
  try {
    const broken: MigrationFile[] = [
      { name: '20260818000001_ok.sql', sql: "do $$ begin raise notice 'self-assert ok: fine'; end $$;" },
      { name: '20260818000002_boom.sql', sql: 'select * from public.a_table_that_is_not_there;' },
    ]
    const err = await applyChain(db, broken).catch((e: unknown) => e)
    expect(err).toBeInstanceOf(MigrationFailure)
    const failure = err as MigrationFailure
    expect(failure.migration).toBe('20260818000002_boom.sql')
    expect(failure.sqlstate).toBe('42P01') // undefined_table — the real one, from the real backend
    expect(failure.message).toContain('MIGRATION FAILED: 20260818000002_boom.sql')
  } finally {
    await db.close()
  }
})

// ── booting the world ──────────────────────────────────────────────────────────────────────────

test('a cold boot ends ready, seeded with the K.1 first session, and reports every phase', async () => {
  const channel = createBootChannel()
  const phases: BootPhase[] = []
  const migrations: string[] = []
  const stop = channel.subscribe(() => {
    const s = channel.get()
    if (phases[phases.length - 1] !== s.phase) phases.push(s.phase)
    if (s.phase === 'applying' && s.migration && migrations[migrations.length - 1] !== s.migration) {
      migrations.push(s.migration)
    }
  })

  expect(channel.get().phase).toBe('idle')
  const db = await openLocalDb({ loadChain, dataDir: 'memory://', channel, log: () => {} })
  stop()

  expect(phases).toEqual(['booting', 'applying', 'seeding', 'ready'])
  expect(migrations).toEqual((await loadChain()).map((f) => f.name))
  const state = channel.get()
  expect(state.error).toBeNull()
  expect(state.progress).toBe(1)
  expect(state.fingerprint).toBe(db.fingerprint)
  expect(state.elapsedMs).toBeGreaterThan(0)
  expect(db.bootMs).toBeGreaterThan(0)

  try {
    // §K.1, 0:00 — "You are the Casa de Aveiro. One Barca, 'Gaivota', docked at Lisboa. 8,000
    // ducats." Seeded by the chain's own public.new_house(), so the purse arrived through the
    // ledger and the founding event exists.
    const house = await db.pg.query<{ company_name: string; ducats: number; n_events: number }>(
      `select p.company_name, p.ducats::int as ducats,
              (select count(*)::int from public.events e where e.player_id = p.id) as n_events
         from public.players p where p.auth_uid = $1`,
      [LOCAL_AUTH_UID],
    )
    expect(house.rows).toHaveLength(1)
    expect(house.rows[0].company_name).toBe('Casa de Aveiro')
    expect(house.rows[0].ducats).toBe(8000)
    expect(house.rows[0].n_events).toBe(1)

    const fleet = await db.pg.query<{ name: string; status: string; port: string; ships: number }>(
      `select f.name, f.status, pt.code as port,
              (select count(*)::int from public.ships s where s.fleet_id = f.id) as ships
         from public.fleets f join public.ports pt on pt.id = f.port_id
         join public.players p on p.id = f.player_id where p.auth_uid = $1`,
      [LOCAL_AUTH_UID],
    )
    expect(fleet.rows[0]).toMatchObject({ name: 'Gaivota', status: 'DOCKED', port: 'LIS', ships: 1 })

    // The purse invariant the chain enforces with deferrable constraint triggers.
    const recon = await db.pg.query<{ ducats: number; sum: number }>(
      `select p.ducats::int as ducats, coalesce(sum(l.ducats_delta), 0)::int as sum
         from public.players p left join public.ledger l on l.player_id = p.id
        where p.auth_uid = $1 group by p.ducats`,
      [LOCAL_AUTH_UID],
    )
    expect(recon.rows[0].ducats).toBe(recon.rows[0].sum)
  } finally {
    await db.close()
  }
})

test('a chain change rebuilds the stored world instead of layering onto it', async () => {
  // THIS TEST BUILDS THE WHOLE WORLD TWICE, so its cost grows with every migration added and the
  // 120 s global timeout is not sized for it. Measured 2026-08-23 at 34 migrations: ~1.9 min ALONE,
  // and failing on every full run under parallel load — a gate that is red on a correct chain gates
  // nothing, which is the same defect this file's own LAST pin had a fortnight ago.
  //
  // Raised rather than sharded because the two full builds ARE the assertion: the point is that a
  // chain change rebuilds instead of layering, and you cannot prove that with one build. If this
  // starts timing out again the answer is a lighter fixture, not a bigger number — a test that
  // needs ten minutes will be one nobody runs.
  test.setTimeout(360_000)
  const dir = await scratchDataDir('rebuild')
  try {
    // 1. Build a world and put a mark in it that only survives if the data survives.
    const first = await openLocalDb({ loadChain, dataDir: dir, log: () => {} })
    const fingerprint = first.fingerprint
    await first.pg.query("update public.players set company_name = 'Casa Marcada' where auth_uid = $1", [
      LOCAL_AUTH_UID,
    ])
    await first.close()

    // 2. Reopen with the SAME chain: no rebuild, and the mark is still there. This is the reload
    //    case, and it is the one that decides whether a player keeps their game.
    const again = await openLocalDb({ loadChain, dataDir: dir, log: () => {} })
    expect(again.rebuilt).toBe(false)
    expect(again.fingerprint).toBe(fingerprint)
    const kept = await again.pg.query<{ company_name: string }>(
      'select company_name from public.players where auth_uid = $1',
      [LOCAL_AUTH_UID],
    )
    expect(kept.rows[0].company_name).toBe('Casa Marcada')
    await again.close()

    // 3. Reopen with a CHANGED chain: rebuilt from 0001, so the mark is gone and the world is
    //    whole. Half a chain applied over an old database would be a schema in no repository.
    const changed = () => loadChainWithEdit(LAST, (sql) => `${sql}\n-- a later build changed this\n`)
    const rebuilt = await openLocalDb({ loadChain: changed, dataDir: dir, log: () => {} })
    expect(rebuilt.rebuilt).toBe(true)
    expect(rebuilt.fingerprint).not.toBe(fingerprint)
    const fresh = await rebuilt.pg.query<{ company_name: string }>(
      'select company_name from public.players where auth_uid = $1',
      [LOCAL_AUTH_UID],
    )
    expect(fresh.rows[0].company_name).toBe('Casa de Aveiro')
    // A rebuild means the world came back WHOLE, not that it came back at a remembered size.
    const ports = await rebuilt.pg.query<{ n: number }>('select count(*)::int as n from public.ports')
    expect(ports.rows[0].n).toBeGreaterThan(100)
    const grants = await rebuilt.pg.query<{ n: number }>(
      'select count(*)::int as n from public.client_write_grants()',
    )
    expect(grants.rows[0].n).toBe(0)
    await rebuilt.close()
  } finally {
    await removeScratchDataDir(dir)
  }
})

// ── the small stuff that a progress bar is made of ─────────────────────────────────────────────

test('progress never goes backwards and never claims done before it is', () => {
  expect(progressFor('idle', 0, 0)).toBe(0)
  expect(progressFor('booting', 0, 0)).toBeLessThan(progressFor('applying', 0, 10))
  expect(progressFor('applying', 0, 10)).toBeLessThan(progressFor('applying', 9, 10))
  expect(progressFor('applying', 9, 10)).toBeLessThan(progressFor('seeding', 0, 0))
  expect(progressFor('seeding', 0, 0)).toBeLessThan(1)
  expect(progressFor('ready', 0, 0)).toBe(1)
})

// THE SENTENCE IS DERIVED FROM `LAST`, NOT REMEMBERED BESIDE IT. This spec was pinned to the
// literal 'a bargain worth striking' (0024) and stayed pinned there while `LAST` moved twice — so
// it was RED on an entirely correct chain, which is a guard that has stopped guarding (the
// permanently-red-proof failure, docs/NO_SPAGHETTI.md §7). What it is actually for is the
// TRANSFORM: strip the version, strip the extension, underscores become spaces. Deriving the
// expectation from the same constant the rest of the file uses means it can never go stale again,
// and the second case below is what keeps it non-vacuous — a broken transform cannot satisfy both.
test('a migration filename reads as a sentence', () => {
  expect(humanMigration(LAST)).toBe(
    LAST.replace(/^\d+_/, '').replace(/\.sql$/, '').replace(/_/g, ' '),
  )
  expect(humanMigration(LAST)).not.toContain('_')
  expect(humanMigration(LAST)).not.toMatch(/^\d/)
  expect(humanMigration('20260818000024_a_bargain_worth_striking.sql')).toBe(
    'a bargain worth striking',
  )
})
