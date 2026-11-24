import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fixOf, jobCode } from '../src/features/city/corp/workerRows'
import type { FleetJobRow } from '../src/lib/rpc'

// ═════════════════════════════════════════════════════════════════════════════════════════════════
// THE ONE PRESS THAT MENDS A JOB (0499 `fit-to-sail`; the lead, 2026-11-25)
// ═════════════════════════════════════════════════════════════════════════════════════════════════
//
// Prod, 24 Nov: a company's one fleet lay wrecked at Island of Mozambique, her job stopped on E_FLAGSHIP_DISABLED, and HQ showed no
// way to mend it. THE LAW: a worker row / a stopped job whose code has a fix shows ONE press that does it in place:
//   E_FLAGSHIP_DISABLED  Repair, at the server's price (the Shipyard's own dry run and issue)
//   E_CREW_SHORT         Hire crew, at the server's price (the Inn's own dry run and issue), for the hands she lacks
//   E_LEG_TOO_FAR        Assign
//   E_SHED_FULL          Storage
//   any other code       none
// and the code itself is never printed. This file holds the table and where it is read (plain Node: no browser, no build).
// DRIVEN ONCE BY HAND, NOT HERE: headless at 390 and 1440 against a world with 0499, a wrecked fleet and an undermanned one
// (docs/dev-log/2026-11-25-fit-to-sail.md on the `fit-to-sail` branch); this branch's image has no 0499, so no browser spec stands here.

const job = (over: Partial<FleetJobRow>): Pick<FleetJobRow, 'state' | 'paused' | 'last'> => ({ state: 'working', paused: null, last: null, ...over })
const src = (p: string) => readFileSync(path.resolve('src', p), 'utf8')

test('a code has one fixing press, or none', () => {
  expect(fixOf('E_FLAGSHIP_DISABLED')).toBe('repair')
  expect(fixOf('E_CREW_SHORT')).toBe('hire')
  expect(fixOf('E_LEG_TOO_FAR')).toBe('assign')
  expect(fixOf('E_SHED_FULL')).toBe('storage')
  for (const code of ['E_ENDURANCE', 'E_NO_COURSE', 'E_REFUSED', 'E_INSUFFICIENT_FUNDS', 'low', 'nothing', '', null, undefined]) expect(fixOf(code), `${code}`).toBeNull()
})

test('the code of a job: what it stopped on, or (0499) what it waits on; a plain wait has none', () => {
  // prod's row before 0499: stopped on the code
  expect(jobCode(job({ state: 'stopped', paused: 'E_FLAGSHIP_DISABLED', last: { at: '2026-11-24T17:42:00Z', ok: false, code: 'E_FLAGSHIP_DISABLED', sentence: 'the flagship is not fit to sail' } }))).toBe('E_FLAGSHIP_DISABLED')
  // 0499: she waits for her repair; the job is not stopped and `last.wait` carries the server's code
  expect(jobCode(job({ state: 'waiting', last: { at: '2026-11-25T01:00:00Z', wait: 'E_FLAGSHIP_DISABLED', sentence: 'the flagship is not fit to sail' } }))).toBe('E_FLAGSHIP_DISABLED')
  expect(jobCode(job({ state: 'waiting', last: { at: '2026-11-25T01:00:00Z', wait: 'E_CREW_SHORT', sentence: 'Crew 7 / 8' } }))).toBe('E_CREW_SHORT')
  expect(jobCode(job({ state: 'stopped', paused: 'E_CREW_SHORT', last: { at: '2026-11-25T01:00:00Z', ok: false, code: 'E_CREW_SHORT', sentence: 'Crew 7 / 8' } }))).toBe('E_CREW_SHORT')
  // 0497's waits are not codes
  for (const wait of ['low', 'nothing', 'unpriced', 'identity']) expect(jobCode(job({ state: 'waiting', last: { at: '2026-11-25T01:00:00Z', wait } })), wait).toBeNull()
  expect(jobCode(job({ state: 'working', last: { at: '2026-11-25T01:00:00Z', ok: true } }))).toBeNull()
  expect(jobCode(job({ state: 'stopped', paused: null }))).toBeNull()
})

test('ONE table: only workerRows.ts reads a code to pick a press, and no HQ worker file prints one', () => {
  for (const f of ['features/city/corp/WorkerFix.tsx', 'features/city/corp/WorkerRow.tsx', 'features/city/corp/WorkerList.tsx', 'features/city/board/JobsAway.tsx']) {
    const code = src(f).replace(/\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '')
    expect(code.match(/\bE_[A-Z_]+/g) ?? [], `${f} names a server code: the table is workerRows.ts fixOf`).toEqual([])
  }
  // the repair's act stays the Shipyard's and the hire's the Inn's (tests/verbHomes.spec.ts): the fix draws their quotes, it does not
  // preview or issue
  expect(src('live/PortShipyard.tsx')).toContain('export function RepairNow')
  expect(src('live/PortInn.tsx')).toContain('export function HireNow')
  expect(src('features/city/corp/WorkerFix.tsx')).not.toMatch(/useStepOrder|\bpreview\(|\bissue\(/)
  // her row, her sheet and While away all draw the press
  expect(src('features/city/corp/WorkerList.tsx')).toContain('FixableRow')
  expect(src('features/city/corp/AssignSheet.tsx')).toContain('WorkerFixButton')
  expect(src('features/city/board/JobsAway.tsx')).toContain('WorkerFixButton')
})
