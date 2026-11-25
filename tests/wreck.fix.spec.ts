import { test, expect } from '@playwright/test'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { refusalWords } from '../src/components/ui/refusalWords'
import { cargoPort, wreckFix } from '../src/domain/fleet'

// ═════════════════════════════════════════════════════════════════════════════════════════════════
// A WRECK IN A PORT HAS ONE NEXT PRESS (0497 `a-wreck-can-sell`; branch `wreck-client`)
// ═════════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner's own company, 25 Nov: her fleet UNABLE_TO_SAIL at Diego Garcia (no shipyard), purse 0, 899 black coral aboard, and HQ
// offered her nothing. THE LAW:
//   * a fleet that cannot sail, lies in a port and has a ship asks for the wreck's press (Sell cargo, then Tow: the server names
//     which, live/WreckFix.tsx); towed to a yard with a dead flagship she asks for Repair; an empty fleet and a wreck at sea, nothing;
//   * her cargo is landed where she lies: the sell face reads "is she here" from `cargoPort`, never from DOCKED alone;
//   * Sell cargo is drawn only when the SERVER runs a wreck's sale (its dry run does not answer `queued`), and the tow's act stays
//     the tow note's (one importer of `cmdTow`);
//   * the day's allowance wholly spent reads "Sold today's limit", not "Day limit 0 / 1 tons".
// Plain Node. The whole way, from her exact state to the yard, was driven headless at 390 and 1440 (not a CI spec: it needs 0497 in
// the image).

const ship = (over: object) => ({ is_flagship: true, durability: 0, ...over })
const src = (p: string) => readFileSync(path.resolve('src', p), 'utf8')

test("her served state names the press: a wreck in port, a towed hull at a yard, nothing for an empty fleet or a wreck at sea", () => {
  expect(wreckFix({ status: 'UNABLE_TO_SAIL', port: 'DGA', ships: [ship({})] })).toBe('wreck')
  expect(wreckFix({ status: 'UNABLE_TO_SAIL', port: null, ships: [ship({})] })).toBeNull()
  expect(wreckFix({ status: 'UNABLE_TO_SAIL', port: 'DGA', ships: [] }), 'an empty fleet is no wreck (0321)').toBeNull()
  expect(wreckFix({ status: 'DOCKED', port: 'COL', ships: [ship({})] })).toBe('repair')
  expect(wreckFix({ status: 'DOCKED', port: 'COL', ships: [ship({ durability: 0 }), ship({ is_flagship: false, durability: 80 })] }), 'a live escort is not a live flagship').toBe('repair')
  expect(wreckFix({ status: 'DOCKED', port: 'COL', ships: [ship({ durability: 60 })] })).toBeNull()
  expect(wreckFix({ status: 'REPAIRING', port: 'COL', ships: [ship({})] })).toBeNull()
  expect(wreckFix({ status: 'SAILING', port: null, ships: [ship({ durability: 60 })] })).toBeNull()
  expect(wreckFix(null)).toBeNull()
})

test('her cargo is landed where she lies: docked, or a wreck with a ship in a port', () => {
  expect(cargoPort({ status: 'DOCKED', port: 'LIS', ships: [ship({})] })).toBe('LIS')
  expect(cargoPort({ status: 'UNABLE_TO_SAIL', port: 'DGA', ships: [ship({})] })).toBe('DGA')
  expect(cargoPort({ status: 'UNABLE_TO_SAIL', port: 'DGA', ships: [] })).toBeNull()
  expect(cargoPort({ status: 'UNABLE_TO_SAIL', port: null, ships: [ship({})] })).toBeNull()
  expect(cargoPort({ status: 'SAILING', port: null, ships: [ship({})] })).toBeNull()
  expect(cargoPort({ status: 'REPAIRING', port: 'COL', ships: [ship({})] })).toBeNull()
  // the sell faces read it, not DOCKED alone
  expect(src('app/HqSheet.tsx')).toContain('const here = cargoPort(fleet) === city')
  expect(src('features/command/buysell/tradeCity.ts')).toContain('cargoPort(fleet)')
  expect(src('features/command/buysell/CargoBest.tsx')).toContain('cargoPort(fleet)')
})

test("the day's limit, spent, reads as what happened; a limit partly left keeps the server's figures", () => {
  expect(refusalWords('en', 'E_DAILY_CAP', { have: 0, need: 1, unit: 't' }, 'Day limit 0 / 1 tons')).toBe("Sold today's limit")
  expect(refusalWords('en', 'E_DAILY_CAP', { have: 0, need: 899, unit: 't' }, null)).toBe("Sold today's limit")
  // something of the allowance is left: English is the server's own sentence (null: the caller prints it)
  expect(refusalWords('en', 'E_DAILY_CAP', { have: 12, need: 40, unit: 't' }, 'Day limit 12 / 40 tons')).toBeNull()
  expect(refusalWords('en', 'E_HOLD_FULL', { have: 0, need: 5, unit: 't' }, 'Hold 0 / 5 tons')).toBeNull()
})

test('one press at a time, each the server\'s: the tow keeps its act, Sell cargo is asked of the server, no code is read to draw it', () => {
  const wreck = src('live/WreckFix.tsx').replace(/\/\/.*$/gm, '').replace(/\/\*[\s\S]*?\*\//g, '')
  // the tow's act is the tow note's: the one importer of cmdTow
  expect(wreck).not.toMatch(/cmdTow\b|cmdPreviewTow\b/)
  expect(src('live/TowNote.tsx')).toContain('export function TowNow')
  // Sell cargo is drawn only when the server's own dry run of her SELL is not `queued`
  expect(wreck).toMatch(/cmdPreview\(fleet\.id, `SELL \$\{good\} ALL`/)
  expect(wreck).toContain('queued !== true')
  // and only when the tow is refused for coin: the server's refusal, by its code, read in this one file
  expect(wreck.match(/\bE_[A-Z_]+/g)).toEqual(['E_TOW_FUNDS'])
  // her row, her sheet: the same step
  expect(src('features/city/corp/WorkerFix.tsx')).toContain('<WreckNow fleet={fleet}>')
  expect(src('live/FixButton.tsx')).toContain('<WreckNow fleet={fleet}>')
})
