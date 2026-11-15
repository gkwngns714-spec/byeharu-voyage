import type { BattleRead, BattleTicksRead, TickTimeline } from '../src/lib/rpc'

// A TICK BATTLE'S READ, WRITTEN BY HAND PER THE CONTRACT (docs/design/tick-combat.md 9.2, 9.3), for
// tests/battle.screen.spec.ts. A raid: the merchant Santa Rosa (side 0, the side set upon) runs from two raiders (side
// 1); a navy brig called at the open comes up at tick 14; the merchant's first run is caught; the brig sinks the small
// raider with a crit; the raiders break off at tick 28: DRIVEN_OFF. Every kind the screen reads is here but the
// boarding (B), the slip before a shot (L) and nothing-to-fight (O).

export const TL: TickTimeline = {
  v: 1,
  ms: 600,
  w: 20,
  n: 28,
  first: 'B',
  gcd: 3,
  k: 0,
  ranges: [
    ['LONG', 0.6],
    ['LONG', 0.6],
    ['LONG', 0.6],
    ['MEDIUM', 0.8],
    ['MEDIUM', 0.8],
    ['CLOSE', 1],
  ],
  ab: {
    BS: { kind: 'basic', cd: 15, gain: 10, mult: 0.25 },
    CH: { kind: 'basic', cd: 25, gain: 10, mult: 0.15, slow: 1.5 },
    RK: { kind: 'threshold', cd: 40, cost: 50, mult: 0.6, acc: 15 },
    GR: { kind: 'ultimate', cd: 60, cost: 100, mult: 0.5, crew: 0.15 },
    BR: { kind: 'defence', cd: 40, for: 10, cut: 0.5 },
    PT: { kind: 'defence', cd: 60, cost: 50, mend: 0.08 },
    RN: { kind: 'flee', cd: 20, for: 20 },
    PY: { kind: 'pay' },
  },
  a: [
    { n: 'Santa Rosa', fl: 'Santa Rosa', h: 400, m: 400, t: 2, r: 6, f: 0, g: true },
    { n: 'Navy brig', fl: 'Navy brig', h: 350, m: 350, t: 3, r: 7, f: 14, g: true },
  ],
  b: [
    { n: 'Black Gull', fl: 'Raiders', h: 300, m: 300, t: 2, r: 6, f: 0, g: true },
    { n: 'Sea Wolf', fl: 'Raiders', h: 120, m: 120, t: 1, r: 5, f: 0, g: true },
  ],
  ai: { a: 'FLEE', b: 'FIGHT' },
  e: [
    [2, 1, 'A', 0, 0, 24, 0, 376],
    [3, 0, 'U', 'RN', 0],
    [4, 1, 'U', 'BS', 10],
    [4, 1, 'BS', 0, 0, 31, 1, 345],
    [6, 1, 'A', 1, 0, 0, 0, 345],
    [7, 0, 'U', 'BR', 0],
    [9, 1, 'A', 0, 0, 12, 0, 333],
    [12, 1, 'U', 'CH', 20],
    [12, 1, 'CH', 0, 0, 0, 0, 333],
    [14, 0, 'J', 1],
    [16, 0, 'A', 1, 0, 40, 0, 260],
    [18, 1, 'A', 0, 1, 22, 0, 328],
    [20, 0, 'A', 1, 1, 70, 0, 50],
    [23, 0, 'X', 35, 0],
    [24, 0, 'A', 1, 0, 55, 1, 205],
    [25, 1, 'U', 'PT', 0],
    [25, 1, 'P', 0, 24, 229],
    [26, 0, 'A', 1, 1, 60, 1, 0],
    [26, 1, 'S', 1],
    [28, 1, 'K'],
    [28, -1, 'E', 'DRIVEN_OFF'],
  ],
  out: 'DRIVEN_OFF',
  r: null,
}

export const READ: BattleTicksRead = {
  on: true,
  battle: '00000000-0000-4000-8000-000000000435',
  kind: 'RAID',
  status: 'FIGHTING',
  ticks: TL,
  site: { lat: 38.7, lon: -9.4 },
  reach_nm: 30,
  sides: [
    { fleet: 'f-rosa', name: 'Santa Rosa', side: 'DEFENDER', how: 'OPENED', kind: 'MERCHANT', nation: 'PRT', company: null, mine: false },
    { fleet: 'f-navy', name: 'Navy brig', side: 'DEFENDER', how: 'CALLED', kind: 'NAVY', nation: 'PRT', company: null, mine: false },
    { fleet: 'raiders', name: 'Raiders', side: 'ATTACKER', how: 'OPENED', kind: 'PIRATE', nation: null, company: null, mine: false },
  ],
  mine: null,
  result: null,
}

export const RESULT: NonNullable<BattleTicksRead['result']> = {
  outcome: 'DRIVEN_OFF',
  fled: false,
  b_fled: true,
  paid: false,
  taken: null,
  loot: 1250,
  crew_lost: 3,
  navy: 'Navy brig',
}

/** An old round-by-round battle: `ticks` null, closed, with its result. */
export const OLD_READ: BattleTicksRead = { ...READ, status: 'RESOLVED', ticks: null, result: { ...RESULT, outcome: 'PLUNDERED', loot: 900 } }
export const OLD_FIGHT: BattleRead = { on: false }

/** 0439: the same raid, but the reader's own ship is Santa Rosa (the ship set upon) and the fight runs on to tick 100, so
 *  her action bar is live: she ran at 3 (caught at 23), braced at 7; her Fury is 0. */
export const TL_LONG: TickTimeline = { ...TL, n: 100, out: 'DRIVEN_OFF', e: [...TL.e.filter((e) => e[0] < 28), [100, -1, 'E', 'DRIVEN_OFF']] }
export const READ_MINE: BattleTicksRead = {
  ...READ,
  ticks: TL_LONG,
  mine: 'f-rosa',
  sides: (READ.sides ?? []).map((s) => (s.fleet === 'f-rosa' ? { ...s, mine: true } : s)),
}
