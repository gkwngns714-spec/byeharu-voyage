// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A RAID IS FOUGHT IN ROUNDS — the battle report's seam (0189, docs/dev-log/2026-10-18-auto-fight.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The server writes a fight's rounds into the PIRATES day (voyage.settle, voyage.fight) and the
// VOYAGE_REPORT says where each belongs (`fights`: the index of its day's line in `lines`, and its
// rounds); the History tray hangs each fight under its day through `payloadFights`. This spec takes
// that seam end to end on its own in-memory world: a company founded here sails a passage whose every
// day is a raid (its OWN voyage's hazard_mult, the other kinds' share at the column's least), first
// with combat_bite lit — every raid day has its rounds, and the reader the screen uses finds each
// fight under a "Day N. Sail sighted" line — then dark, where the report carries no fights at all and
// the reader returns nothing (the report a player reads today, unchanged).

import { test, expect } from '@playwright/test'
import { openLocalDb, type LocalDb } from '../src/lib/db/localDb'
import { loadChain } from '../src/lib/db/chainSource.node.mjs'
import { builtWorldImage } from './builtWorld.fixture'
import { clearBackend, createLocalBackend, setBackend, worldLedger } from '../src/lib/rpc'
import { payloadFights, payloadLines } from '../src/features/ledger/headline'

let db: LocalDb
let fleet = ''

const one = async <T>(sql: string, params: unknown[] = []): Promise<T> =>
  (Object.values((await db.pg.query<Record<string, T>>(sql, params)).rows[0] ?? {})[0]) as T

// a passage from where the fleet lies to the other of Lisbon / Funchal, departed 30 days ago, every day a raid
async function raidedPassage(): Promise<string> {
  await db.pg.exec(`
    update public.world_config set value = '1'::jsonb where key = 'hazard_p_max';
    update public.voyage_event_kinds set mix_base = case when code = 'PIRATES' then 1 else 0.0001 end where in_sea_mix;`)
  const voyage = await one<string>(`
    select voyage.depart(f.id, voyage.segments_from_course(jsonb_build_array(
             jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))),
           a.port_id, b.port_id, now() - interval '30 days')
      from public.fleets f
      join public.sea_reaches a on a.port_id = f.port_id
      join public.sea_reaches b on b.port_id = (select id from public.ports
                                                 where code = case when (select code from public.ports where id = f.port_id) = 'FNC' then 'LIS' else 'FNC' end)
     where f.id = $1`, [fleet])
  await db.pg.query(`
    update public.voyages vo set path = (select jsonb_agg(e || jsonb_build_object('hazard_mult', 1000) order by o)
                                           from jsonb_array_elements(vo.path) with ordinality t(e, o))
     where vo.id = $1`, [voyage])
  await db.pg.query(`select voyage.settle($1, now())`, [fleet])
  return voyage
}

async function reportOf(voyage: string) {
  const page = await worldLedger(null, 200)
  expect(page.ok, 'world.ledger refused').toBe(true)
  if (!page.ok) throw new Error('unreachable')
  const report = page.value.events.find((e) => e.kind === 'VOYAGE_REPORT' && e.payload['voyage_id'] === voyage)
  expect(report, `no VOYAGE_REPORT for voyage ${voyage}`).toBeTruthy()
  return report!
}

test.beforeAll(async () => {
  test.setTimeout(360_000)
  db = await openLocalDb({ loadChain, loadImage: builtWorldImage, dataDir: 'memory://', log: () => {} })
  setBackend(createLocalBackend(db))
  await db.callAs(`select cmd.found_house('Peleja Spec', 'PRT') as result`)
  fleet = await db.callAs<string>(`select (select f.id from public.fleets f where f.player_id = public.current_player_id()
                                             order by f.created_at limit 1) as result`)
  expect(fleet, 'the founded company has no fleet').toBeTruthy()
})

test.afterAll(async () => {
  clearBackend()
  await db?.close()
})

test('lit, every raid day is fought in rounds and the report hangs each fight under its own day', async () => {
  test.setTimeout(300_000)
  await db.pg.exec(`
    update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
    update public.world_config set value = '0.5'::jsonb where key = 'armour_turns_pct';`)
  const voyage = await raidedPassage()
  const raids = (await db.pg.query<{ day: number; rounds: string[] | null; outcome: string }>(
    `select day_index as day, payload->'rounds' as rounds, payload->>'outcome' as outcome
       from public.voyage_events where voyage_id = $1 and kind = 'PIRATES' order by day_index`, [voyage])).rows
  expect(raids.length, 'the forced passage met no raid — it proves nothing').toBeGreaterThan(0)
  for (const r of raids) {
    expect(r.rounds, `day ${r.day} was not fought in rounds`).not.toBeNull()
    expect(r.rounds![0]).toMatch(/^Raiders: /)
    // 0202: below the last boarding band the crew surrenders (PLUNDERED) — a fought raid never ends STRIPPED
    expect(['EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED']).toContain(r.outcome)
  }
  const report = await reportOf(voyage)
  const lines = payloadLines(report.payload)
  const fights = payloadFights(report.payload)
  expect(fights.length, 'the report does not carry one fight per raid day').toBe(raids.length)
  fights.forEach((f, i) => {
    expect(lines[f.line], `fight ${i} points at a line that is not its day's`).toMatch(new RegExp(`^Day ${raids[i].day}\\. Sail sighted`))
    expect(f.rounds).toEqual(raids[i].rounds)
  })
})

test('dark, a raided passage reads as it always did: no rounds, no fights in the report', async () => {
  test.setTimeout(300_000)
  await db.pg.exec(`
    update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
    update public.world_config set value = '0'::jsonb where key = 'armour_turns_pct';`)
  const voyage = await raidedPassage()
  const rounds = await one<number>(`select count(*)::int from public.voyage_events where voyage_id = $1 and payload ? 'rounds'`, [voyage])
  const raids = await one<number>(`select count(*)::int from public.voyage_events where voyage_id = $1 and kind = 'PIRATES'`, [voyage])
  expect(raids, 'the forced passage met no raid — it proves nothing').toBeGreaterThan(0)
  expect(rounds).toBe(0)
  const report = await reportOf(voyage)
  expect('fights' in report.payload).toBe(false)
  expect(payloadFights(report.payload)).toEqual([])
  expect(payloadLines(report.payload).some((l) => /Sail sighted/.test(l))).toBe(true)
})
