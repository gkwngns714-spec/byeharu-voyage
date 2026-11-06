import { test, expect } from '@playwright/test'
import { driftedPoint, mapFleetsOf, type MapVoyage } from '../src/chart'
import { fleetStatusTone, heldMs, heldUntilMs, inBattle } from '../src/domain/fleet'
import { fleetDue } from '../src/features/fleets/fleetLine'
import { headline } from '../src/features/ledger/headline'
import type { FleetView, RosterFleet } from '../src/lib/rpc'
import { setLocale } from '../src/lib/i18n'
import { trafficRowAt } from '../src/live/seaRoster'
import { sailingFleet } from './mapWorld.fixture'

// ═════════════════════════════════════════════════
// A SHIP HELD BY A BATTLE STANDS STILL (0323, docs/WORLD_POWERS.md 5.2). The server's half is proof 31; this is the half a client could still get wrong: it draws her between reads.
// Pure Node: no `page` fixture is used, so no browser is launched.
// ═════════════════════════════════════════════════

const iso = (ms: number): string => new Date(ms).toISOString()
function sailingOf(f: FleetView): MapVoyage {
  const m = mapFleetsOf([f])[0]
  if (m.kind !== 'sailing') throw new Error('she should be at sea')
  return m.voyage
}
const T0 = Date.UTC(2026, 10, 6, 12, 0, 0)
test.beforeAll(() => setLocale('en'))
const MIN = 60_000

function rosterRow(holds?: { from: string; until: string }[]): RosterFleet {
  return {
    id: 'm1', company: 'Casa', nation_code: 'PRT', ink: 'prt', name: 'Gaivota', status: 'SAILING', ships: 1, hulls: [], port: null, roadstead: null, anchor: null,
    next_lap_at: null,
    voyage: {
      to: 'FNC', dest_point: null, course: [[38, -9], [33, -17]], legs_nm: [500], total_nm: 500,
      // 20 minutes of sailing, and the hold on top of it
      departed_at: iso(T0), eta: iso(T0 + (holds ? 30 : 20) * MIN), ...(holds ? { holds } : {}),
    },
  } as unknown as RosterFleet
}

test('a voyage with no hold reads no hold', () => {
  expect(heldMs(undefined, T0)).toBe(0)
  expect(heldUntilMs(undefined)).toBeNull()
  expect(heldMs([], T0)).toBe(0)
})

test('the roster stands a held merchant still, and she sails on from the same point', () => {
  const held = rosterRow([{ from: iso(T0 + 5 * MIN), until: iso(T0 + 15 * MIN) }])
  const free = rosterRow()
  const at = (f: RosterFleet, ms: number) => trafficRowAt(f, ms).voyage!.position!
  // before the battle, as an unheld ship
  expect(at(held, T0 + 3 * MIN).nm_done).toBeCloseTo(at(free, T0 + 3 * MIN).nm_done, 6)
  // all through it, the point she was at when it began
  const still = at(free, T0 + 5 * MIN)
  for (const m of [5, 6, 10, 14, 15]) {
    expect(at(held, T0 + m * MIN).lat).toBeCloseTo(still.lat, 6)
    expect(at(held, T0 + m * MIN).lon).toBeCloseTo(still.lon, 6)
  }
  // after it, ten minutes behind herself, and she arrives on the served eta
  expect(at(held, T0 + 18 * MIN).nm_done).toBeCloseTo(at(free, T0 + 8 * MIN).nm_done, 6)
  expect(at(held, T0 + 30 * MIN).nm_done).toBeCloseTo(500, 6)
})

test('a roster row with no hold is placed exactly as before', () => {
  const v = trafficRowAt(rosterRow(), T0 + 5 * MIN).voyage!
  expect(v.nm_done).toBeCloseTo(125, 6)
  expect(v.holds).toBeUndefined()
})

test('the drift does not sail her through a hold, and starts when it ends', () => {
  const until = T0 + 10 * MIN
  const base = sailingFleet({ id: 'f1', name: 'Gaivota', from: 'LIS', to: 'FNC', legFrac: 0.2, segNm: 1000 })
  const v = base.voyage!
  const eta = T0 + 30 * MIN
  const fleet = { ...base, voyage: { ...v, eta: iso(eta), holds: [{ from: iso(T0 - 5 * MIN), until: iso(until) }] } } as FleetView
  const voyage = sailingOf(fleet)
  expect(voyage.heldUntilMs).toBe(until)
  const readAtMs = T0
  // inside the hold the answer is the served point, however old the read
  expect(driftedPoint(voyage, { nowMs: T0 + 5 * MIN, readAtMs })).toEqual(voyage.at)
  expect(driftedPoint(voyage, { nowMs: until, readAtMs })).toEqual(voyage.at)
  // past it she moves
  expect(driftedPoint(voyage, { nowMs: until + MIN, readAtMs })).not.toEqual(voyage.at)

  // no hold: the drift is the old sum
  const free = sailingOf({ ...base, voyage: { ...v, eta: iso(eta) } } as FleetView)
  expect(free.heldUntilMs).toBeNull()
  expect(driftedPoint(free, { nowMs: T0 + MIN, readAtMs })).not.toEqual(free.at)
})

test('the card counts the battle, in port and at sea, and only the battle', () => {
  const base = sailingFleet({ id: 'f1', name: 'Gaivota', from: 'LIS', to: 'FNC', legFrac: 0.2, segNm: 1000 })
  const sea = { ...base, busy_until: iso(T0 + 7 * MIN + 24_000) } as FleetView
  expect(inBattle(sea)).toBe(true)
  expect(fleetDue(sea, T0)).toBe('In battle 7:24')
  // past the clock she is sailing on: the countdown is her arrival again
  expect(fleetDue(sea, T0 + 8 * MIN)).not.toContain('In battle')

  const port = { ...base, voyage: null, port: 'LIS', status: 'IN_BATTLE', busy_until: iso(T0 + 90_000) } as FleetView
  expect(inBattle(port)).toBe(true)
  expect(fleetDue(port, T0)).toBe('In battle 1:30')
  expect(fleetStatusTone('IN_BATTLE')).toBe('warning')

  const yard = { ...base, voyage: null, port: 'LIS', status: 'REPAIRING', busy_until: iso(T0 + 90_000) } as FleetView
  expect(inBattle(yard)).toBe(false)
  expect(fleetDue(yard, T0)).not.toContain('In battle')
  expect(inBattle({ ...base, busy_until: null })).toBe(false)
})

test('the History tray names a battle report', () => {
  const line = headline({ id: 'e', kind: 'BATTLE_REPORT', payload: { fleet: 'Gaivota', lines: ['We broke off.'], fights: [{ line: 0, rounds: ['Round 1'] }] }, created_at: iso(T0) } as never, (c) => c)
  expect(line).toBe('Gaivota fought a battle.')
})
