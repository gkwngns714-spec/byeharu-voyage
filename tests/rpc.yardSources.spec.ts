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
//   3. (0358, S1 of docs/SECOND_SHIP.md) the read plans the build: a good's row carries the recipe's count, the good's
//      weight and the seller's price now (world.price, the one price authority); a part's row carries the goods it is
//      made of, one row per item_recipes row, each with its nearest seller; at Lisbon the Caravela latina's sails name
//      flax at Riga. (Since 0363 the Barca takes no part: the read serves her four goods and an empty list of parts.)
// RED before 0349 (the reader is not in the world), GREEN with it; test 3 is RED before 0358 (no `qty`, no `inputs`).

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

test('0358: a good carries its count, weight and price now; a part carries the goods it is made of, each with a seller', async () => {
  const snap = expectOk(await worldSnapshot())
  const lis = snap.ports.find((p) => p.code === 'LIS')!
  const hull = expectOk(await worldBuildingYard(lis.id)).hulls.find((h) => h.class === 'carlat')!
  const src = expectOk(await worldYardSources(lis.id, 'carlat'))
  expect(src.items.length, 'the Caravela latina lost her parts').toBeGreaterThan(0)

  // every key 0349 served is still there, beside the new ones
  for (const g of src.goods) expect(Object.keys(g).sort()).toEqual(['ask', 'bulk', 'code', 'miles', 'name', 'port', 'qty'])
  for (const i of src.items) expect(Object.keys(i).sort()).toEqual(['code', 'inputs', 'miles', 'name', 'port'])

  const priceAt = async (port: string, good: string) =>
    Number(
      (
        await one<{ ask: string }>(
          `select pr.ask from public.ports p join public.goods g on g.code = $2 cross join lateral world.price(p.id, g.id) pr where p.code = $1`,
          [port, good],
        )
      ).ask,
    )
  for (const g of src.goods) {
    const line = hull.goods.find((m) => m.code === g.code)!
    expect(g.qty, `${g.code}: not the recipe's count`).toBe(line.qty)
    const good = await one<{ bulk: string }>('select bulk from public.goods where code = $1', [g.code])
    expect(g.bulk).toBe(Number(good.bulk))
    expect(g.ask, `${g.code}: the ask is not world.price's at ${g.port}`).toBe(await priceAt(g.port!, g.code))
  }

  const seen = new Set(src.goods.map((g) => g.code))
  for (const i of src.items) {
    const recipe = (
      await db.pg.query<{ code: string; name: string; qty: string; bulk: string }>(
        `select g.code, g.name, (ir.qty * hi.qty)::text as qty, g.bulk::text as bulk
           from public.hull_recipe_items hi join public.item_recipes ir on ir.item_code = hi.item_code join public.goods g on g.id = ir.good_id
          where hi.class_code = 'carlat' and hi.item_code = $1 order by g.code`,
        [i.code],
      )
    ).rows
    expect(recipe.length, `${i.code} has no recipe`).toBeGreaterThan(0)
    expect(i.inputs!.map((u) => u.code)).toEqual(recipe.map((r) => r.code))
    for (const u of i.inputs!) {
      const r = recipe.find((x) => x.code === u.code)!
      expect(u.good).toBe(r.name)
      expect(u.qty).toBe(Number(r.qty))
      expect(u.bulk).toBe(Number(r.bulk))
      expect(u.port, `${u.code} of ${i.code} has no seller`).not.toBeNull()
      expect(u.ask).toBe(await priceAt(u.port!, u.code))
      // a good that is also a hull good is sent to the same seller
      const same = src.goods.find((g) => g.code === u.code)
      if (same) expect([u.port, u.name, u.miles, u.ask]).toEqual([same.port, same.name, same.miles, same.ask])
      seen.add(u.code)
    }
  }
  // the errand is more goods than the hull's own: flax, hemp and iron are only in the parts; the sails name flax at Riga
  expect([...seen]).toEqual(expect.arrayContaining(['cordage', 'flax', 'hemp', 'iron', 'ships-nails', 'tar', 'timber']))
  for (const only of ['flax', 'hemp', 'iron']) expect(src.goods.map((g) => g.code)).not.toContain(only)
  const flax = src.items.find((i) => i.code === 'suit-of-sails')!.inputs!.find((u) => u.code === 'flax')!
  expect(flax.port).toBe('RIG')
  expect(flax.name).toBe('Riga')
  expect(flax.miles).toBeGreaterThan(0)
  // a hull with no part still serves its goods with the new keys, and no inputs anywhere
  const plain = expectOk(await worldBuildingYard(lis.id)).hulls.find((h) => h.goods.length > 0 && h.items.length === 0)!
  const plainSrc = expectOk(await worldYardSources(lis.id, plain.class))
  expect(plainSrc.items).toEqual([])
  for (const g of plainSrc.goods) expect(typeof g.qty).toBe('number')
  // 0363: the Barca takes four goods and no part, and the read says so
  const barca = expectOk(await worldYardSources(lis.id, 'barca'))
  expect(barca.items).toEqual([])
  expect(barca.goods.map((g) => g.code).sort()).toEqual(['cordage', 'ships-nails', 'tar', 'timber'])
  for (const g of barca.goods) expect(g.port, `${g.code} has no seller`).not.toBeNull()
  expect(expectOk(await worldBuildingYard(lis.id)).hulls.find((h) => h.class === 'barca')!.items).toEqual([])
  // still a read
  expect(await db.callAs<boolean>(`select provolatile = 's' and prosecdef as result from pg_proc where oid = 'world.yard_sources(uuid, text)'::regprocedure`)).toBe(true)
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
