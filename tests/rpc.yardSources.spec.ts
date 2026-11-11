// ═══════════════════════════════════════════════════════════════════════════════════════════════
// S8 — A YARD A PLAYER CAN FINISH (0349, world.yard_sources; owner rows 180 and 305).
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PURE UNIT SPEC, against the build's own world (tests/builtWorld.fixture.ts). It proves the server half of the yard sheet:
//   1. world.yard_sources names, for each material of a hull, the NEAREST harbour where the verb would hand it over —
//      a good where cmd.do_buy sells it (the roster and the culture), a fitting where cmd.do_make makes it — with the
//      sailed miles from the yard (0 for the yard itself);
//   2. the end of the path the sheet points down: with every material ashore here and the labour in the purse, the yard
//      read says nothing is short, the hull is buildable, and BUILD lays her down — the materials leave the city.
// RED before 0349 (the reader is not in the world), GREEN with it.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import {
  clearBackend,
  cmdIssue,
  createLocalBackend,
  expectOk,
  setBackend,
  worldBuildingYard,
  worldSnapshot,
  worldYardSources,
} from '../src/lib/rpc'

let db: LocalDb

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

async function one<T>(sql: string, params: unknown[] = []): Promise<T> {
  return (await db.pg.query<T>(sql, params)).rows[0]
}

test('each material of a hull is named with the nearest harbour that hands it over', async () => {
  const snap = expectOk(await worldSnapshot())
  const lis = snap.ports.find((p) => p.code === 'LIS')!
  const yard = expectOk(await worldBuildingYard(lis.id))
  // the hull a new company can build here and now, chosen from the served list, never named
  const hull = yard.hulls.find((h) => h.buildable && h.goods.length > 0 && h.items.length > 0)!
  expect(hull, 'no hull with goods and fittings is buildable at Lisbon').toBeDefined()

  const src = expectOk(await worldYardSources(lis.id, hull.class))
  expect(src.class).toBe(hull.class)
  expect(src.goods.map((g) => g.code).sort()).toEqual(hull.goods.map((g) => g.code).sort())
  expect(src.items.map((i) => i.code).sort()).toEqual(hull.items.map((i) => i.code).sort())

  for (const g of src.goods) {
    expect(g.port, `${g.code} has no seller`).not.toBeNull()
    // the seller sells it: the very two gates cmd.do_buy applies
    const sells = await one<{ ok: boolean }>(
      `select public.port_offers(p.id, g.id) and not public.culture_refuses(p.culture, g.culture_mask) as ok
         from public.ports p, public.goods g where p.code = $1 and g.code = $2`,
      [g.port, g.code],
    )
    expect(sells.ok, `${g.port} does not sell ${g.code}`).toBe(true)
    // and none nearer does (the sailed miles of public.sea_reaches)
    const nearer = await one<{ n: number }>(
      `select count(*)::int as n from public.ports p join public.goods g on g.code = $2
         left join public.sea_reaches sr on sr.port_id = $1
        where p.kind = 'HARBOUR' and public.port_offers(p.id, g.id) and not public.culture_refuses(p.culture, g.culture_mask)
          and round(case when p.id = $1 then 0 else (sr.reaches ->> p.code)::numeric end) < $3`,
      [lis.id, g.code, g.miles],
    )
    expect(nearer.n, `a harbour nearer than ${g.port} sells ${g.code}`).toBe(0)
    expect(g.miles === 0).toBe(g.port === 'LIS')
  }
  for (const i of src.items) {
    expect(i.port, `${i.code} has no maker`).not.toBeNull()
    const makes = await one<{ ok: boolean }>(
      `select exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'workstation' and b.tier >= k.ws_tier)
              and public.made_only_in(k.code, p.id) is null as ok
         from public.ports p, public.item_kinds k where p.code = $1 and k.code = $2`,
      [i.port, i.code],
    )
    expect(makes.ok, `${i.port} cannot make ${i.code}`).toBe(true)
  }
  // the reader is a read
  expect(await db.callAs<boolean>(`select provolatile = 's' as result from pg_proc where oid = 'world.yard_sources(uuid, text)'::regprocedure`)).toBe(true)
})

test('with every material ashore here, nothing is short and BUILD lays her down', async () => {
  const snap = expectOk(await worldSnapshot())
  const lis = snap.ports.find((p) => p.code === 'LIS')!
  const hull = expectOk(await worldBuildingYard(lis.id)).hulls.find((h) => h.buildable && h.goods.length > 0 && h.items.length > 0)!
  const player = await one<{ id: string }>('select id from public.players where auth_uid = $1', [db.authUid])
  const fleet = await one<{ id: string }>(
    "select id from public.fleets where player_id = $1 and port_id = $2 and status = 'DOCKED' limit 1",
    [player.id, lis.id],
  )
  const shipsBefore = await one<{ n: number }>('select count(*)::int as n from public.ships where player_id = $1', [player.id])

  // Put each material ashore through the one storage rule (as a superuser probe would), the fittings into the store, and the labour in the purse.
  for (const g of hull.goods) {
    await db.pg.query(
      'select public.storage_put($1::uuid, $2::uuid, (select id from public.goods where code = $3), $4::numeric, 1)',
      [player.id, lis.id, g.code, g.qty],
    )
  }
  for (const i of hull.items) {
    await db.pg.query(
      `insert into public.player_items (player_id, port_id, item_code, qty) values ($1, $2, $3, $4)
       on conflict (player_id, port_id, item_code) do update set qty = excluded.qty`,
      [player.id, lis.id, i.code, i.qty],
    )
  }
  await db.pg.query("select public.credit($1::uuid, 'SPEC', $2::bigint)", [player.id, hull.ducats * 4])

  const ready = expectOk(await worldBuildingYard(lis.id)).hulls.find((h) => h.class === hull.class)!
  expect(ready.buildable).toBe(true)
  for (const m of [...ready.goods, ...ready.items]) expect(m.have, `${m.code} is still short`).toBeGreaterThanOrEqual(m.qty)

  expectOk(await cmdIssue(fleet.id, `BUILD ${hull.class} Yardling`))
  const ship = await one<{ class_code: string } | undefined>(
    'select c.code as class_code from public.ships s join public.ship_classes c on c.id = s.class_id where s.player_id = $1 and s.name = $2',
    [
      player.id,
      'Yardling',
    ],
  )
  expect(ship?.class_code).toBe(hull.class)
  expect((await one<{ n: number }>('select count(*)::int as n from public.ships where player_id = $1', [player.id])).n).toBe(shipsBefore.n + 1)
  // the materials left the city
  const after = expectOk(await worldBuildingYard(lis.id)).hulls.find((h) => h.class === hull.class)!
  for (const m of [...after.goods, ...after.items]) expect(m.have, `${m.code} did not leave the city`).toBe(0)
})
