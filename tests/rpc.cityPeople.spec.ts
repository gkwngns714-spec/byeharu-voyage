import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldStatsCityPeople, worldTownHall } from '../src/lib/rpc'

// 0305 — world.stats_city_people: the Stats city page's people block. RED before 0305 (the reader is not in the catalog's world), GREEN with it.
// It serves the hall's own block (one authority: it CALLS town_hall_people), plus the rank among all harbours and the kept day of steps.

let db: LocalDb
let lon: string
let ams: string

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('People Spec', 'PRT') as result`)
  lon = await db.callAs<string>(`select id as result from public.ports where code = 'LON'`)
  ams = await db.callAs<string>(`select id as result from public.ports where code = 'AMS'`)
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('the reader serves the hall block, a rank of all harbours and the day of steps', async () => {
  // two steps, ten minutes apart, so the series has points (the step is the server's own job)
  await db.callAs(`select public.population_tick('2030-01-01 00:03:00+00'::timestamptz)::text as result`)
  await db.callAs(`select public.population_tick('2030-01-01 00:13:00+00'::timestamptz)::text as result`)
  const r = await worldStatsCityPeople(lon)
  expect(r.ok).toBe(true)
  if (!r.ok) return
  const hall = await worldTownHall(lon)
  expect(hall.ok).toBe(true)
  if (!hall.ok) return
  const p = r.value
  const h = hall.value.people!
  for (const k of ['population', 'baseline', 'year', 'per_day', 'kind', 'reason', 'day_change'] as const) expect(p[k]).toEqual(h[k])
  const total = Number(await db.callAs<number>(`select count(*)::int as result from public.port_population`))
  expect(p.of).toBe(total)
  expect(p.rank!).toBeGreaterThanOrEqual(1)
  expect(p.rank!).toBeLessThanOrEqual(total)
  expect(p.series!.length).toBe(2)
  expect(p.series![0].at < p.series![1].at).toBe(true)
  expect(p.series![1].population).toBe(p.population)
  // the rank is the count of harbours with more people, plus one
  const above = Number(await db.callAs<number>(`select count(*)::int as result from public.port_population where population > (select population from public.port_population where port_id = '${lon}')`))
  expect(p.rank).toBe(above + 1)
})

test('rank follows population between two harbours', async () => {
  const a = await worldStatsCityPeople(lon)
  const b = await worldStatsCityPeople(ams)
  if (!a.ok || !b.ok) throw new Error('the reader failed')
  expect((a.value.population! > b.value.population!) === (a.value.rank! < b.value.rank!) || a.value.population === b.value.population).toBe(true)
})

test('an unknown harbour serves nothing, and the reader writes nothing', async () => {
  const none = await worldStatsCityPeople('00000000-0000-0000-0000-000000000000')
  expect(none.ok).toBe(true)
  if (none.ok) expect(none.value).toEqual({})
  expect(await db.callAs<boolean>(`select provolatile = 's' as result from pg_proc where oid = 'world.stats_city_people(uuid)'::regprocedure`)).toBe(true)
})
