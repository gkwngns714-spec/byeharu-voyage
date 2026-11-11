// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A ROUTE IS JUDGED LEG BY LEG — world.route_legs (0346, owner row 209, docs/ROUTE_BUILDER.md B1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The map's route builder asks this read as each city is tapped. This spec reads it off a real PostgreSQL (the build's
// own world) through the CLIENT wrapper (`worldRouteLegs`) as a company founded at Lisbon, and holds it to its one
// promise: every leg's verdict IS voyage.leg_refusal's (the one leg judge), its supplies ARE public.supply_needs', and
// the trip it calls open is queued by cmd.issue_lines as the builder's Final sends it. It names route_legs and
// issue_lines so CI's rule S selects it whenever a migration re-defines either.

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, cmdIssueLines, createLocalBackend, setBackend, worldRouteLegs } from '../src/lib/rpc'

let db: LocalDb
let fleet: string
/** The nearest harbour to Lisbon her leg to is open, and the farthest one (past her navigation). */
let near: { code: string; nm: number }
let far: { code: string }

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Rota Spec', 'PRT') as result`)
  fleet = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id = public.current_player_id() limit 1`)
  near = await db.callAs<{ code: string; nm: number }>(
    `select jsonb_build_object('code', r.code, 'nm', r.nm) as result
       from voyage.reach_from((select id from public.ports where code = 'LIS')) r join public.ports p on p.id = r.port_id
      where p.kind = 'HARBOUR' and r.nm > 0 and voyage.leg_refusal($1::uuid, r.port_id, r.nm, null) is null
      order by r.nm limit 1`,
    [fleet],
  )
  far = await db.callAs<{ code: string }>(
    `select jsonb_build_object('code', r.code) as result
       from voyage.reach_from((select id from public.ports where code = 'LIS')) r join public.ports p on p.id = r.port_id
      where p.kind = 'HARBOUR' order by r.nm desc limit 1`,
  )
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('an open leg: no shut, the miles reach_from serves, and the supplies supply_needs serves', async () => {
  const r = await worldRouteLegs(fleet, [{ from: 'LIS', to: near.code, course: null }])
  expect(r.ok).toBe(true)
  if (!r.ok || !r.value) throw new Error('no answer')
  const [leg] = r.value.legs
  expect(leg.shut).toBeNull()
  expect(leg.to).toBe(near.code)
  expect(leg.nm).toBeCloseTo(near.nm, 1)
  expect(leg.days).toBeGreaterThan(0)
  const need = await db.callAs<{ days: number; cost: number; fits: boolean }>(
    `select jsonb_build_object('days', round(n.days, 1), 'cost', n.cost, 'fits', n.fits) as result from public.supply_needs($1::uuid, array[$2::numeric]) n`,
    [fleet, near.nm],
  )
  expect(leg.supplies).toEqual(need)
})

test('a leg past her navigation is shut E_LEG_TOO_FAR — the very refusal leg_refusal gives — and names the harbours between', async () => {
  const r = await worldRouteLegs(fleet, [
    { from: 'LIS', to: near.code, course: null },
    { from: near.code, to: far.code, course: null },
  ])
  if (!r.ok || !r.value) throw new Error('no answer')
  const [open, shut] = r.value.legs
  expect(open.shut).toBeNull()
  expect(shut.shut?.code).toBe('E_LEG_TOO_FAR')
  const judge = await db.callAs<{ code: string; sentence: string }>(
    `select voyage.leg_refusal($1::uuid, (select id from public.ports where code = $3),
            (select r.nm from voyage.reach_from((select id from public.ports where code = $2)) r where r.code = $3), null) as result`,
    [fleet, near.code, far.code],
  )
  expect(shut.shut).toEqual(judge)
})

test('a fleet not yours reads null, and an unknown harbour is shut by its own code', async () => {
  const other = await db.callAs<string>(`select f.id as result from public.fleets f where f.player_id <> public.current_player_id() order by f.id limit 1`)
  const mine = await worldRouteLegs(fleet, [{ from: 'LIS', to: 'NOWHERE', course: null }])
  if (!mine.ok || !mine.value) throw new Error('no answer')
  expect(mine.value.legs[0].shut?.code).toBe('E_NO_SUCH_PORT')
  if (other) {
    const theirs = await worldRouteLegs(other, [])
    expect(theirs.ok && theirs.value).toBeNull()
  }
})

test('the open trip is queued by issue_lines as Final sends it: one SAIL a stop, all of them', async () => {
  const back = await worldRouteLegs(fleet, [
    { from: 'LIS', to: near.code, course: null },
    { from: near.code, to: 'LIS', course: null },
  ])
  if (!back.ok || !back.value) throw new Error('no answer')
  expect(back.value.legs.map((l) => l.shut)).toEqual([null, null])
  const r = await cmdIssueLines(fleet, [{ text: `SAIL ${near.code}` }, { text: 'SAIL LIS' }])
  expect(r.ok).toBe(true)
  const queued = await db.callAs<string[]>(
    `select jsonb_agg(raw_text order by seq) as result from public.orders where fleet_id = $1::uuid`,
    [fleet],
  )
  expect(queued).toEqual([`SAIL ${near.code}`, 'SAIL LIS'])
})
