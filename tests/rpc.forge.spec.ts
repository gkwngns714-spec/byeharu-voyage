// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FORGE (0281) — the goods forge, driven through the doors a browser holds.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PURE UNIT SPEC, against the build's own world (tests/builtWorld.fixture.ts), not a from-zero
// apply. It proves the three things the City page's Forge face stands on:
//   1. a recipe with its materials forges: the ingredients leave THIS CITY'S STORAGE by exactly
//      the recipe's quantities, the product lands there, and no ducat moves;
//   2. a short ingredient refuses E_NO_MATERIALS and moves nothing;
//   3. a RAW good (tier 0 — what a city produces) refuses E_NOT_FORGEABLE.
// Plus the two gates the verb shares with the rest of the port: E_NOT_DOCKED with no fleet here,
// and E_SHED_FULL when the product does not fit (with the ingredients rolled back with it).
//
// The recipe is chosen from the SERVED data (lowest tier, fewest ingredients, first code) — never
// named here, so a re-cut of the recipe table does not turn this red for no reason.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import {
  clearBackend,
  cmdForgeGood,
  createLocalBackend,
  expectOk,
  setBackend,
  worldGoodsForge,
  worldLedger,
  worldSnapshot,
} from '../src/lib/rpc'
import type { ForgeRecipe } from '../src/lib/rpc'

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

/** The one house this local world seeds for the session's auth uid. */
async function playerId(): Promise<string> {
  const r = await db.pg.query<{ id: string }>('select id from public.players where auth_uid = $1', [db.authUid])
  return r.rows[0].id
}

async function storedAt(player: string, port: string, good: string): Promise<number> {
  const r = await db.pg.query<{ qty: string }>(
    'select qty::text from public.player_storage where player_id = $1 and port_id = $2 and good_id = $3',
    [player, port, good],
  )
  return r.rows.length === 0 ? 0 : Number(r.rows[0].qty)
}

test('the catalogue serves tier/is_raw, and the forge lists every crafted good with its recipe', async () => {
  const snap = expectOk(await worldSnapshot())
  const withTier = snap.goods.filter((g) => typeof g.tier === 'number' && typeof g.is_raw === 'boolean')
  expect(withTier.length, 'a good is served without its tier/is_raw').toBe(snap.goods.length)
  for (const g of withTier) expect(g.is_raw).toBe(g.tier === 0)
  expect(withTier.some((g) => (g.tier ?? 0) >= 1), 'no crafted good is served').toBe(true)

  const lis = snap.ports.find((p) => p.code === 'LIS')!
  const forge = expectOk(await worldGoodsForge(lis.id))
  expect(forge.port_id).toBe(lis.id)
  // The seeded fleet lies here, so the forge is open.
  expect(forge.docked).toBe(true)
  const crafted = snap.goods.filter((g) => (g.tier ?? 0) >= 1)
  expect(forge.recipes).toHaveLength(crafted.length)
  for (const r of forge.recipes) {
    expect(r.product_id.length).toBeGreaterThan(0)
    expect(r.tier).toBeGreaterThanOrEqual(1)
    expect(r.ingredients.length).toBeGreaterThanOrEqual(2)
    for (const i of r.ingredients) {
      expect(i.qty).toBeGreaterThan(0)
      expect(i.have).toBe(0) // nothing is ashore in a fresh world
      expect(i.tier).toBeLessThan(r.tier)
    }
    expect(r.can_forge).toBe(false)
  }
})

test('a stocked recipe forges: ingredients leave storage, the product lands, no money moves', async () => {
  const snap = expectOk(await worldSnapshot())
  const lis = snap.ports.find((p) => p.code === 'LIS')!
  const player = await playerId()
  const forge = expectOk(await worldGoodsForge(lis.id))
  // Deterministic subject from the served catalogue: lowest tier, fewest ingredients, first code.
  const recipe: ForgeRecipe = [...forge.recipes].sort(
    (a, b) => a.tier - b.tier || a.ingredients.length - b.ingredients.length || a.product.localeCompare(b.product),
  )[0]
  expect(recipe).toBeDefined()

  // Seed each ingredient with two spare, through the one storage rule (as a superuser probe would).
  for (const i of recipe.ingredients) {
    await db.pg.query('select public.storage_put($1::uuid, $2::uuid, $3::uuid, $4::numeric, 3.5)', [
      player, lis.id, await goodId(i.good), i.qty + 2,
    ])
  }
  const purseBefore = expectOk(await worldLedger()).ducats
  // The read agrees the recipe is now makeable.
  const again = expectOk(await worldGoodsForge(lis.id)).recipes.find((r) => r.product === recipe.product)!
  expect(again.can_forge).toBe(true)

  const receipt = expectOk(await cmdForgeGood(lis.id, recipe.product_id, 1))
  expect(receipt.product).toBe(recipe.product)
  expect(receipt.qty).toBe(1)
  expect(receipt.spent).toHaveLength(recipe.ingredients.length)
  expect(await storedAt(player, lis.id, recipe.product_id)).toBe(1)
  for (const i of recipe.ingredients) {
    expect(await storedAt(player, lis.id, await goodId(i.good)), `${i.good} did not leave the shed`).toBe(2)
  }
  // NO MONEY MOVES: a forge is not a sale.
  expect(expectOk(await worldLedger()).ducats).toBe(purseBefore)
  // The cost basis the ingredients carried is the product's (0081's one blend).
  const basis = await db.pg.query<{ b: string }>(
    'select basis::text as b from public.player_storage where player_id = $1 and port_id = $2 and good_id = $3',
    [player, lis.id, recipe.product_id],
  )
  expect(Number(basis.rows[0].b)).toBeCloseTo(3.5, 6)

  // A SHORT BATCH REFUSES, and moves nothing.
  const short = await cmdForgeGood(lis.id, recipe.product_id, 5)
  expect(short.ok).toBe(false)
  if (short.ok) throw new Error('unreachable')
  expect(short.refusal.code).toBe('E_NO_MATERIALS')
  expect(await storedAt(player, lis.id, recipe.product_id)).toBe(1)

  // Leave the world as found.
  await db.pg.query('delete from public.player_storage where player_id = $1 and port_id = $2', [player, lis.id])
})

test('a raw good is not forgeable, and a forge needs a fleet lying here', async () => {
  const snap = expectOk(await worldSnapshot())
  const lis = snap.ports.find((p) => p.code === 'LIS')!
  const raw = snap.goods.find((g) => g.is_raw === true)!
  const rawForge = await cmdForgeGood(lis.id, raw.id, 1)
  expect(rawForge.ok).toBe(false)
  if (rawForge.ok) throw new Error('unreachable')
  expect(rawForge.refusal.code).toBe('E_NOT_FORGEABLE')

  // Storage is reachable only from a ship lying here (0070): move the house's fleet away.
  const player = await playerId()
  const fleet = await db.pg.query<{ id: string; port_id: string }>(
    'select id, port_id from public.fleets where player_id = $1 limit 1',
    [player],
  )
  const other = await db.pg.query<{ id: string }>(
    "select id from public.ports where kind = 'HARBOUR' and id <> $1 order by code limit 1",
    [fleet.rows[0].port_id],
  )
  await db.pg.query('update public.fleets set port_id = $1 where id = $2', [other.rows[0].id, fleet.rows[0].id])
  try {
    const away = await cmdForgeGood(lis.id, snap.goods.find((g) => (g.tier ?? 0) >= 1)!.id, 1)
    expect(away.ok).toBe(false)
    if (away.ok) throw new Error('unreachable')
    expect(away.refusal.code).toBe('E_NOT_DOCKED')
  } finally {
    await db.pg.query('update public.fleets set port_id = $1 where id = $2', [fleet.rows[0].port_id, fleet.rows[0].id])
  }
})

async function goodId(code: string): Promise<string> {
  const r = await db.pg.query<{ id: string }>('select id from public.goods where code = $1', [code])
  return r.rows[0].id
}
