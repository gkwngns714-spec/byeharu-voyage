import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { causeMended, fleetNewRefusal, fleetRefusedOrder, fleetSignal, refusalIsNews } from '../src/domain/fleet'
import type { FleetView, QueuedOrder } from '../src/lib/rpc'

// ═════════════════════════════════════════════════════════════════════════════════════════════════
// A REFUSAL THAT IS NO LONGER NEWS IS NOT ANNOUNCED AS NEWS (0499 `fit-to-sail`; branch `stale-refusal`)
// ═════════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-24, about 23:43 UTC: *"Order 200 was refused: the flagship is not fit to sail. Anything that depended on it was
// cancelled; Gaivota is free."* Order 200 had failed at 17:40; she had been repaired at 23:36.
// WHERE IT WAS SHOWN: the note at the head of a fleet's queue (src/features/command/Queue.tsx), on her sheet over HQ and on the Trade
// desk. WHY "HOURS LATE": it was never late. A refused order stays in her served queue until it is dismissed (0186: cmd.queue serves
// pending, active and FAILED rows), and the note announced whichever failed row stood there, every time the sheet opened, with no
// time and no regard for what had happened since. So a six-hour-old record read as news seven minutes after the repair.
// THE LAW (domain/fleet `refusalIsNews`, `fleetNewRefusal`):
//   * a refusal whose cause is mended (the flagship has a hull again; no ship lacks hands) is not news;
//   * a refusal older than her standing job (the order's `at`, served by 0499) is not news;
//   * it stays a row of her queue (`fleetRefusedOrder` still finds it), with its time;
//   * a fresh one names the FLEET, never the order's number, and carries the one press that mends it.
// Plain Node: the rule is a pure reading of the served fleet; the note's shape is read in its source.

type Ship = FleetView['ships'][number]
const ship = (over: Partial<Ship>): Ship => ({ is_flagship: true, durability: 80, max_durability: 100, crew: 8, crew_required: 8, crew_max: 12, ...over }) as Ship
const order = (over: Partial<QueuedOrder>): QueuedOrder => ({ id: 'o200', seq: 200, text: 'SAIL SOF', verb: 'SAIL', status: 'failed', error_code: 'E_FLAGSHIP_DISABLED', error_message: 'the flagship is not fit to sail', figures: null, result: null, ...over })
const fleet = (ships: Ship[], queue: QueuedOrder[]) => ({ ships, queue, status: 'DOCKED', voyage: null }) as unknown as FleetView
const src = (p: string) => readFileSync(path.resolve('src', p), 'utf8')

test("the owner's case: refused at 17:40, repaired at 23:36: at 23:43 it is a record, not news", () => {
  const o = order({ at: '2026-11-24T17:40:00Z' })
  const wrecked = fleet([ship({ durability: 0 })], [o])
  const mended = fleet([ship({ durability: 100 })], [o])
  // while she lay wrecked it was news, and she read as stuck
  expect(refusalIsNews(wrecked, o)).toBe(true)
  expect(fleetNewRefusal(wrecked)?.id).toBe('o200')
  expect(fleetSignal(wrecked)).toBe('stuck')
  // repaired: the same row is still in her queue, and is no longer announced; she is not "stuck" for it
  expect(causeMended(mended, 'E_FLAGSHIP_DISABLED')).toBe(true)
  expect(refusalIsNews(mended, o)).toBe(false)
  expect(fleetNewRefusal(mended)).toBeNull()
  expect(fleetRefusedOrder(mended)?.id, 'the record left her queue').toBe('o200')
  expect(fleetSignal(mended)).toBe('waiting')
})

test('short of crew: news while a ship lacks hands, a record once she is manned', () => {
  const o = order({ error_code: 'E_CREW_SHORT', error_message: 'Crew 7 / 8' })
  expect(refusalIsNews(fleet([ship({ crew: 7 })], [o]), o)).toBe(true)
  expect(refusalIsNews(fleet([ship({ crew: 8 })], [o]), o)).toBe(false)
  // a live escort beside a dead flagship is not a mended flagship
  expect(causeMended(fleet([ship({ durability: 0 }), ship({ is_flagship: false, durability: 90 })], []), 'E_FLAGSHIP_DISABLED')).toBe(false)
})

test('older than her standing job: not news; newer, or of no known time, it is', () => {
  const since = Date.parse('2026-11-24T23:40:00Z')
  const f = fleet([ship({})], [])
  const hold = { error_code: 'E_HOLD_FULL', error_message: 'the hold is full' }
  expect(refusalIsNews(f, order({ ...hold, at: '2026-11-24T17:40:00Z' }), since)).toBe(false)
  expect(refusalIsNews(f, order({ ...hold, at: '2026-11-24T23:41:00Z' }), since)).toBe(true)
  // a server before 0499 serves no time, and a fleet with no job has no start: the refusal stands as before
  expect(refusalIsNews(f, order(hold), since)).toBe(true)
  expect(refusalIsNews(f, order({ ...hold, at: '2026-11-24T17:40:00Z' }), null)).toBe(true)
  // a code her hulls do not answer is never called mended
  expect(causeMended(f, 'E_HOLD_FULL')).toBe(false)
  // an order that was not refused is never news
  expect(refusalIsNews(f, order({ status: 'pending', error_code: null }))).toBe(false)
})

test("the queue's note: the fresh refusal only, the fleet's name, no order number, and the press that mends it", () => {
  const q = src('features/command/Queue.tsx')
  const code = q.replace(/\/\/.*$/gm, '').replace(/\{\/\*[\s\S]*?\*\/\}/g, '')
  expect(code, 'the note still announces whichever failed row stands').not.toContain('fleetRefusedOrder(')
  expect(code).toContain('fleetNewRefusal(fleet,')
  expect(code, 'the note prints an order number').not.toMatch(/Order \{|failed\?\.seq|failed\.seq/)
  expect(code).toContain(`t('command.refusedNews', { fleet: fleet.name`)
  expect(code).toContain('<WorkerFixButton fix={fixOf(failedRefusal.code)} worker={fleet.id}')
  // the record keeps its time
  expect(code).toContain('queue-refused-at')
  expect(src('lib/i18n/dict/command.ts')).toMatch(/refusedNews: '\{fleet\}: \{why\}\./)
})
