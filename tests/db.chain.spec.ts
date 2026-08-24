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
// Pin moved deliberately 2026-08-23 with 0036: THE SEA HAS PLACES IN IT — the owner chose "the
// sea has places in it" over free steering, and 14 named waters (the Grand Banks, the Dogger
// Bank, the straits of Gibraltar, Hormuz and Malacca, the Roaring Forties, Drake Passage…) are
// now rows in public.ports with kind = 'SEA_PLACE': nodes of the ONE leg graph, joined by 42
// generated sailed spur legs, sailed to by the one router and arrived at by the one settle,
// whose arrival writes a LANDFALL event through 0035's catalogue so the report speaks the
// place's authored approach line. No chandler, no fair, no market out there — each refusal is
// structural and was shown biting — and the stores gate requires the round trip, so a place
// with no quay can never brick a fleet. GENERATED by scripts/build-sea-places.mjs from
// data/sea-places.json. 36 migrations, 36 receipts, all nine 0036 guards break-tested red.
// Pin moved deliberately 2026-08-23 with 0037: SHE ANSWERS HER HELM AT SEA — cmd.divert, the
// owner's "i should be able to change direction easily": a SAILING fleet's destination changes
// mid-passage. She finishes the leg under her keel, the voyage TRUNCATES at its far node (the one
// ETA authority recomputes; kept legs and frozen speeds byte-identical, so no past position, no
// settled day and no rolled hazard moves — asserted on a real diverted voyage), the stale queue
// is cancelled, and the onward passage is a SAIL queued through the one parser and gated at the
// node by the one refusal authority. Every leg of a diverted passage is an authored row of
// public.legs — the never-touch-land law holds by construction, with no from-a-point router
// built. A direct act beside cancel_at and clear, catalogued in client_rpc_entry_points (re-cut
// proven pre-image + exactly one row). 37 migrations, 37 receipts.
// Pin moved deliberately 2026-08-24 with 0041: TEN ISLANDS AND A RICHER CATALOGUE — the repair of
// the one edited-after-applied migration. 0003 was regenerated in place AFTER production applied
// it (the 243-good edit), so production kept 70 goods while fresh rebuilds got 243, and the ten
// island ports lived in no database at all. 0003 is reverted to the exact bytes production ran
// (git blob eee9091, byte-proven), and 0041 — GENERATED by scripts/build-world-growth.mjs against
// the applied chain — carries the growth: +10 harbours, +173 goods, the roster rebalance, the
// regenerated leg graph, port_goods re-derived for every (harbour, good) pair, and the affinity
// knobs reconciled. Its self-assert pins the end state to data/*.json by SET EQUALITY, and
// scripts/db/world-guard.mjs now fails ANY db:apply/db:proof whose world is not the data.
// NOTE the version gap: 0038/0039 belong to the helm worktree and 0040 to the seas worktree;
// growth deliberately took 0041 (npm run db:check-versions arbitrates collisions).
//
// Moved again in the SAME merge for 0040: EVERY WATER ANSWERS ITS SEA — every navigable cell of
// the 0.25-degree raster carries seas.raster_ordinal, with boundaries from Natural Earth's marine
// polygons rather than the unsurveyed label centroids, and unnamed water joined to its nearest sea
// BY WATER so nothing leaks across land. voyage.sea_at(lat, lon) is the one lookup, server-private.
// It is the ground the free-water mover, the hazard system and the by-sea NPC design (row 43) all
// key on: a fleet in open water belonged to no sea before this, which would have switched off the
// spatial dimension of all three silently.
//
// AND THE PIN ITSELF WAS WRONG BEFORE THIS MERGE. Main already carried 0045 (the world runs twenty
// times faster) while this constant still named 0041 — I added a migration and did not move the
// pin, which is the exact staleness this convention exists to prevent. It names the true last file
// now. The gap 0042-0044 is deliberate: 0038/0039 are the mover's, and versions are arbitrated by
// npm run db:check-versions, never by counting.
const LAST = '20260818000045_the_world_runs_twenty_times_faster.sql'

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
  // One full build of the 243-good world: ~2-3 min in Node PGlite (the 52,002-row price seed is
  // 53 s of it alone — measured 2026-08-23, D21), more under parallel workers. The 120 s global
  // timeout was sized for a smaller world and failed a correct chain.
  test.setTimeout(360_000)
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
  // chain change rebuilds instead of layering, and you cannot prove that with one build. The last
  // revision of this comment said "if this starts timing out again the answer is a lighter
  // fixture, not a bigger number" — and then the OWNER grew the world to 243 goods (D21), which
  // is not a fixture that can be lightened: the fixture IS the real chain, and two builds are now
  // ~6 min alone (one build measured 2-3 min in Node PGlite). So the number moves with the world
  // it measures, and the standing answer to "a test nobody runs" is the pre-built database image
  // D21 names, which would collapse both builds to a copy.
  test.setTimeout(720_000)
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

// ── growing the world under a live house ───────────────────────────────────────────────────────

// THE PRODUCTION PATH, REHEARSED. Production applied the ORIGINAL 0003 (70 goods, 214 harbours)
// and real houses have sailed and traded in that world ever since; every migration from 0041 on
// lands ON them, not on an empty database. This test is that path: build the pre-growth chain,
// found a house through the chain's own door, buy real cargo on the quay, and only THEN apply the
// growth — then prove the house, the fleet, the cargo and the ledger did not move by one ducat
// while the world doubled around them.
//
// GROWTH_SPLIT is the frozen production baseline of 2026-08-24 — everything below it had been
// applied to production before the growth shipped. It does NOT move when later growth migrations
// land (they simply join the `growth` half); it would only ever move with a documented new
// baseline, which is a deploy-history fact, not a preference.
const GROWTH_SPLIT = '20260818000041'

test('the world grows under a live house: player rows survive the growth to the ducat', async () => {
  // One full pre-growth build (~2 min) plus the growth itself. Sized like the cold-boot test.
  test.setTimeout(360_000)
  const files = await loadChain()
  const before = files.filter((f) => f.name.slice(0, 14) < GROWTH_SPLIT)
  const growth = files.filter((f) => f.name.slice(0, 14) >= GROWTH_SPLIT)
  expect(growth.length).toBeGreaterThanOrEqual(1)

  const { PGlite } = await import('@electric-sql/pglite')
  const db = await PGlite.create()
  try {
    await applyChain(db, before)

    // The world production actually holds below the split: the ORIGINAL 0003. These two literals
    // are safe to pin because the pre-split chain is frozen history — if they ever fail, an
    // applied migration was edited, which is the exact disease this file exists to catch.
    const w0 = await db.query<{ goods: number; harbours: number }>(
      `select (select count(*) from public.goods)::int as goods,
              (select count(*) from public.ports where kind = 'HARBOUR')::int as harbours`,
    )
    expect(w0.rows[0]).toMatchObject({ goods: 70, harbours: 214 })

    // A real house, through the chain's own door, holding real cargo bought on the quay.
    const uid = '00000000-0000-4000-8000-000000000041'
    await db.query(`select public.new_house($1, $2, $3)`, [uid, 'Casa Prova', 'PRT'])
    const fleet = await db.query<{ id: string; port: string }>(
      `select f.id, pt.code as port from public.fleets f
         join public.players p on p.id = f.player_id
         join public.ports pt on pt.id = f.port_id
        where p.auth_uid = $1`,
      [uid],
    )
    expect(fleet.rows).toHaveLength(1)
    const good = await db.query<{ code: string }>(
      `select g.code from public.port_specialties s
         join public.goods g on g.id = s.good_id
         join public.ports p on p.id = s.port_id
        where p.code = $1 order by g.code limit 1`,
      [fleet.rows[0].port],
    )
    await db.exec(`
      begin;
      select cmd.assume_identity('${uid}');
      select cmd.issue('${fleet.rows[0].id}'::uuid, 'BUY ${good.rows[0].code} 10');
      commit;
    `)

    const snapshot = async () =>
      (await db.query<Record<string, unknown>>(
        `select p.ducats::int as ducats, p.company_name,
                coalesce((select sum(l.ducats_delta) from public.ledger l where l.player_id = p.id), 0)::int as ledger_sum,
                (select count(*)::int from public.ships s where s.player_id = p.id) as ships,
                (select jsonb_agg(s.cargo order by s.id) from public.ships s where s.player_id = p.id) as cargo,
                f.status as fleet_status, pt.code as fleet_port
           from public.players p
           join public.fleets f on f.player_id = p.id
           join public.ports pt on pt.id = f.port_id
          where p.auth_uid = $1`,
        [uid],
      )).rows[0]

    const lived = await snapshot()
    // The buy LANDED — a rehearsal over an empty hold rehearses nothing.
    expect(JSON.stringify(lived.cargo)).toContain(good.rows[0].code)
    expect(Number(lived.ducats)).toBeLessThan(8000)
    expect(lived.ducats).toBe(lived.ledger_sum)

    // ── THE GROWTH LANDS ON THEM ───────────────────────────────────────────────────────────────
    const grown = await applyChain(db, growth)
    expect(grown.receipts).toBe(growth.length)

    // The house did not move by one ducat, one tun, or one ship.
    const after = await snapshot()
    expect(after).toEqual(lived)

    // The world around them grew, and the market covers ALL of it — including their own port and
    // their own cargo good, which must still quote a positive price.
    const w1 = await db.query<{ goods: number; harbours: number; market: number }>(
      `select (select count(*) from public.goods)::int as goods,
              (select count(*) from public.ports where kind = 'HARBOUR')::int as harbours,
              (select count(*) from public.port_goods)::int as market`,
    )
    expect(w1.rows[0].goods).toBeGreaterThan(w0.rows[0].goods)
    expect(w1.rows[0].harbours).toBeGreaterThan(w0.rows[0].harbours)
    expect(w1.rows[0].market).toBe(w1.rows[0].goods * w1.rows[0].harbours)
    const quote = await db.query<{ ask: string; bid: string }>(
      `select q.ask::text, q.bid::text
         from public.ports p, public.goods g,
              lateral world.price(p.id, g.id) q
        where p.code = $1 and g.code = $2`,
      [fleet.rows[0].port, good.rows[0].code],
    )
    expect(Number(quote.rows[0].ask)).toBeGreaterThan(0)
    expect(Number(quote.rows[0].bid)).toBeGreaterThan(0)
  } finally {
    await db.close()
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
