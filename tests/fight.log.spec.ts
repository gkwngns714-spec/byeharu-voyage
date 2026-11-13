import { test, expect } from '@playwright/test'
import { rolldown } from 'rolldown'
import { pathToFileURL } from 'node:url'
import path from 'node:path'
import { payloadFights } from '../src/features/ledger/headline'
import { translate } from '../src/lib/i18n'
import type { FightEnd } from '../src/lib/rpc'
import { BAR_EMPTY as O, BAR_FULL as X, barCells, fightHull, fightRows, parseFightLog, parseFightLoss } from '../src/live/fightLines'
import { OLD_ROUNDS, RAID_LOG, RAID_ROUNDS } from './raidWorld.fixture'

// ═════════════════════════════════════════════════════════════════════════════════════════════════
// A RAID'S LOG, READ AND DRAWN (0353, owner row 315; docs/COMBAT_LOG.md 1.1, 1.4, 1.5, 1.6). Pure Node: no browser.
// The server's half is proof 56. This is the half a client could still get wrong: the positions of the compact log,
// the strict parse that falls back to sentences, which figure each cell prints, how a bar rounds, and every word in
// English and Korean. The fixed fight is a real one (orders-scene.sql): a barca under Flee, away in round 6.
// ═════════════════════════════════════════════════════════════════════════════════════════════════

const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v)) as T

// The real FightLog, bundled for node (tests/fightLog.entry.ts says why it is not imported directly).
let render: { renderLog: (props: Record<string, unknown>) => string; setLocale: (l: 'en' | 'ko') => void }
test.beforeAll(async () => {
  const file = path.resolve('test-results', 'fight-log-render.mjs')
  const bundle = await rolldown({
    input: path.resolve('tests', 'fightLog.entry.ts'),
    platform: 'node',
    external: ['react', 'react-dom/server'],
    transform: { jsx: { runtime: 'automatic' } },
    logLevel: 'silent',
  })
  await bundle.write({ file, format: 'esm' })
  render = (await import(pathToFileURL(file).href)) as typeof render
})
const html = (props: Record<string, unknown>) => render.renderLog(props).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()

test('the log is read by position: six rounds she ran, the hit in round 6, her hull before and after', () => {
  const log = parseFightLog(RAID_LOG)!
  expect(log).not.toBeNull()
  expect(log.order).toBe('FLEE')
  expect(log.first).toBe('THEY')
  expect(log.end).toBe('FLED')
  expect(log.foe).toEqual({ name: 'Şebek (xebec)', ships: 1.42, crew: 50, hull: 751.2, ship: null })
  expect(log.you).toEqual([{ name: 'Gaivota', hull: 400, full: 400, crew: 8 }])
  expect(log.after).toEqual([{ name: 'Gaivota', hull: 332.11 }])
  expect(log.board).toBeNull()
  expect(log.noPay).toBeNull()

  const rows = fightRows(log)
  expect(rows.map((r) => r.round)).toEqual([1, 2, 3, 4, 5, 6])
  expect(rows.map((r) => r.range)).toEqual(['L', 'L', 'L', 'M', 'M', 'C'])
  // she ran every round (never "caught unready", though they saw first), and the slip chance is the server's 6 %
  expect(rows.every((r) => r.you.kind === 'run' && r.slipPct === 6)).toBe(true)
  // they fired two shots a round, missed five rounds and hit twice in the sixth for 67.9
  expect(rows[0].them).toEqual({ kind: 'shots', hits: 0, fired: 2, dealt: 0 })
  expect(rows[5].them).toEqual({ kind: 'shots', hits: 2, fired: 2, dealt: 67.9 })
  expect(rows.map((r) => r.hullPct)).toEqual([100, 100, 100, 100, 100, 83])
  expect(rows.every((r) => r.foePct === 100)).toBe(true)
  expect(fightHull(log)).toEqual({ before: 400, after: 332.11, lost: 400 - 332.11, lostPct: 17, full: 400 })
})

test('a cell says the reason there is no shot: no guns, out of range, caught unready', () => {
  const raw = clone(RAID_LOG) as unknown as { order?: string; first: string; end: string; r: unknown[][]; board?: number[] }
  delete raw.order
  raw.end = 'TAKEN'
  raw.board = [8, 50, 0.31]
  // round 1: she has a gun but they saw first; round 2: her gun cannot reach; round 3: she fires; they have no gun in round 3
  raw.r = [
    [1, 'L', 1, 0, 0, 0, 1, 2, 1, 41.2, 358.8, 751.2, [[1, 10]], null],
    [2, 'L', 1, 0, 0, 0, 1, 2, 0, 0, 358.8, 751.2, [], null],
    [3, 'M', 1, 1, 1, 30.4, 0, 0, 0, 0, 358.8, 720.8, [], null],
  ]
  const log = parseFightLog(raw)!
  expect(log.order).toBe('FIGHT')
  expect(log.board).toEqual({ crew: 8, foeCrew: 50, ratio: 0.31 })
  const rows = fightRows(log)
  expect(rows.map((r) => r.you.kind)).toEqual(['unready', 'outOfRange', 'shots'])
  expect(rows.map((r) => r.them.kind)).toEqual(['shots', 'shots', 'noGuns'])
  expect(rows.map((r) => r.slipPct)).toEqual([null, null, null])
  expect(rows[2].foePct).toBe(96)
  // and when SHE saw first, they are the side caught unready
  const hers = fightRows(parseFightLog({ ...raw, first: 'YOU' })!)
  expect(hers[0].them.kind).toBe('unready')
  expect(hers[0].you.kind).toBe('outOfRange')
})

test('the parse is strict: anything it does not know is no log, and the sentences are drawn', () => {
  expect(parseFightLog(undefined)).toBeNull()
  expect(parseFightLog(null)).toBeNull()
  expect(parseFightLog('log')).toBeNull()
  expect(parseFightLog({ ...RAID_LOG, v: 2 }), 'a version this bundle does not know').toBeNull()
  expect(parseFightLog({ ...RAID_LOG, end: 'SUNK' }), 'an ending it has no word for').toBeNull()
  expect(parseFightLog({ ...RAID_LOG, order: 'RAM' })).toBeNull()
  expect(parseFightLog({ ...RAID_LOG, first: 'NOBODY' })).toBeNull()
  expect(parseFightLog({ ...RAID_LOG, r: [[1, 'L', 0, 0, 0, 0, 1, 2, 0, 0, 400, 751.2, []]] }), 'a round of 13 cells').toBeNull()
  expect(parseFightLog({ ...RAID_LOG, r: [[1, 'X', 0, 0, 0, 0, 1, 2, 0, 0, 400, 751.2, [], null]] }), 'a range it does not know').toBeNull()
  expect(parseFightLog({ ...RAID_LOG, r: [[1, 'L', 0, 0, 0, '0', 1, 2, 0, 0, 400, 751.2, [], null]] }), 'a figure that is not a number').toBeNull()
  expect(parseFightLog({ ...RAID_LOG, after: [] }), 'a hull with no after').toBeNull()
  expect(parseFightLog({ ...RAID_LOG, you: [['Gaivota', 400, 400]] })).toBeNull()
  expect(parseFightLog({ ...RAID_LOG, board: [8, 50] })).toBeNull()
  expect(parseFightLog({ ...RAID_LOG, foe: { n: 'Şebek (xebec)', k: 1.42, crew: 50 } })).toBeNull()

  // the report's reader: a fight with a log carries it and the day's losses; a fight without one is as it always was
  const report = {
    fights: [
      { line: 0, rounds: RAID_ROUNDS, log: RAID_LOG, loss: { crew_before: 8, crew: 0, cargo: {}, ransom: 0 } },
      { line: 1, rounds: OLD_ROUNDS },
      { line: 2, rounds: OLD_ROUNDS, log: { ...RAID_LOG, v: 9 }, loss: { crew_before: 8, crew: 1, cargo: { wine: 3 }, ransom: 0 } },
    ],
  }
  const fights = payloadFights(report)
  expect(fights).toHaveLength(3)
  expect(fights[0].log?.end).toBe('FLED')
  expect(fights[0].loss).toEqual({ crewBefore: 8, crew: 0, cargo: {}, ransom: 0 })
  expect(fights[0].rounds).toEqual(RAID_ROUNDS)
  expect(fights[1]).toEqual({ line: 1, rounds: OLD_ROUNDS, log: null, loss: null })
  expect(fights[2], 'an unknown version falls back whole: no log, no loss, the sentences').toEqual({ line: 2, rounds: OLD_ROUNDS, log: null, loss: null })
  expect(parseFightLoss({ crew_before: 8, crew: 1, cargo: { wine: 3, bad: 'x' }, ransom: 1600 })).toEqual({ crewBefore: 8, crew: 1, cargo: { wine: 3 }, ransom: 1600 })
  expect(parseFightLoss(null)).toBeNull()
})

test('a bar rounds DOWN, is full only at 100 %, and is never empty while anything is left', () => {
  expect(barCells(100, 5)).toBe(X.repeat(5))
  expect(barCells(90, 5)).toBe(X.repeat(4) + O)
  expect(barCells(70, 5)).toBe(X.repeat(3) + O.repeat(2))
  expect(barCells(99, 10)).toBe(X.repeat(9) + O)
  expect(barCells(83, 10)).toBe(X.repeat(8) + O.repeat(2))
  expect(barCells(83, 5)).toBe(X.repeat(4) + O)
  expect(barCells(1, 5)).toBe(X + O.repeat(4))
  expect(barCells(0, 5)).toBe(O.repeat(5))
  expect(barCells(140, 5)).toBe(X.repeat(5))
  expect(barCells(-3, 10)).toBe(O.repeat(10))
  for (const w of [5, 10]) for (let p = 0; p <= 100; p++) expect([...barCells(p, w)]).toHaveLength(w)
})

// a raid's endings; a battle she started has its own (tests/battle.card.spec.ts)
const WORDS: Record<'en' | 'ko', Record<Exclude<FightEnd, `A_${string}` | 'OPEN'>, string>> = {
  en: { STOOD: 'Stood off', SLIP: 'Slipped away', BROKE: 'Drove off', THREW: 'Threw back', TERMS: 'Paid off', TAKEN: 'Plundered', GAVE: 'Surrendered', FLED: 'Fled', PAID: 'Paid' },
  ko: { STOOD: '대치', SLIP: '따돌림', BROKE: '격퇴', THREW: '격퇴', TERMS: '몸값 지불', TAKEN: '약탈당함', GAVE: '항복', FLED: '도주 성공', PAID: '지불함' },
}

for (const lang of ['en', 'ko'] as const) {
  test(`the log drawn, ${lang}: every line of the fixed fight, in the dictionary's words`, () => {
    render.setLocale(lang)
    const text = html({ log: parseFightLog(RAID_LOG)!, loss: parseFightLoss({ crew_before: 8, crew: 0, cargo: {}, ransom: 0 }) })
    const want =
      lang === 'en'
        ? [
            'Raid · 1 Şebek (xebec) · 50 crew',
            'Order Flee · They saw first',
            '1 Long You Run · Slip 6% Them 0/2',
            '6 Close You Run · Slip 6% Them 2/2 −68',
            `${X.repeat(4)}${O} ${X.repeat(8)}${O.repeat(2)} 83%`,
            `Foe ${X.repeat(5)} ${X.repeat(10)} 100%`,
            'Result Fled, round 6',
            'Lost Hull −68 (17%) · Crew 0 · Cargo 0',
            'Gaivota Hull 400 → 332',
          ]
        : [
            '습격 · Şebek (xebec) 1척 · 선원 50',
            '명령 도주 · 먼저 들킴',
            '1 원거리 아군 도주 중 · 이탈 6% 적 0/2',
            '6 근거리 아군 도주 중 · 이탈 6% 적 2/2 −68',
            `적 ${X.repeat(5)} ${X.repeat(10)} 100%`,
            '결과 도주 성공, 6라운드',
            '손실 선체 −68 (17%) · 선원 0 · 화물 0',
            'Gaivota 선체 400 → 332',
          ]
    for (const line of want) expect(text, `the log does not say: ${line}`).toContain(line)
    // nothing of the other language, and no key left untranslated
    expect(text).not.toMatch(/fight\.[a-zA-Z_]+/)
    if (lang === 'ko') expect(text).not.toMatch(/\b(Raid|Order|Flee|Result|Lost|Hull|Crew|Cargo|Long|Close|Run|Slip|You|Them|Foe)\b/)
  })

  test(`every ending has its word, ${lang}, and a ransom, a boarding and a refused Pay are said`, () => {
    render.setLocale(lang)
    for (const end of Object.keys(WORDS[lang]) as (keyof (typeof WORDS)[typeof lang])[]) {
      expect(translate(lang, `fight.end_${end}`)).toBe(WORDS[lang][end])
      const boarded = end === 'THREW' || end === 'TERMS' || end === 'TAKEN' || end === 'GAVE'
      const log = parseFightLog({ ...RAID_LOG, end, order: end === 'PAID' ? 'PAY' : undefined, r: end === 'PAID' || end === 'STOOD' || end === 'SLIP' ? [] : RAID_LOG.r, board: boarded ? [8, 50, 0.31] : undefined })!
      const text = html({ log, loss: parseFightLoss({ crew_before: 8, crew: 1, cargo: { wine: 12 }, ransom: end === 'PAID' ? 1600 : 0 }) })
      expect(text).toContain(`${translate(lang, 'fight.result')} ${WORDS[lang][end]}`)
      expect(text.includes(translate(lang, 'fight.boarding')), `${end}: the boarding line`).toBe(boarded)
      expect(text).toContain(`${translate(lang, 'fight.crew')} −1`)
      expect(text).toContain(`${translate(lang, 'fight.cargo')} −12`)
      expect(text.includes(`${translate(lang, 'fight.ransom')} −1,600`)).toBe(end === 'PAID')
      if (end === 'PAID') expect(text).toContain(`${translate(lang, 'fight.order')} ${translate(lang, 'fight.orderPay')}`)
    }
    const refused = html({ log: parseFightLog({ ...RAID_LOG, order: undefined, end: 'TAKEN', no_pay: 'EMPTY', board: [8, 50, 0.31] })!, loss: null })
    expect(refused).toContain(`${translate(lang, 'fight.orderFight')} · ${lang === 'en' ? 'Empty hold' : '화물 없음'}`)
    expect(translate(lang, 'fight.noPay_NO_PAYEE')).toBe(lang === 'en' ? 'No taker' : '받는 이 없음')
    // the picker's words (docs/COMBAT_LOG.md 1.6)
    expect([translate(lang, 'fight.orderFight'), translate(lang, 'fight.orderFlee'), translate(lang, 'fight.orderPay')]).toEqual(lang === 'en' ? ['Fight', 'Flee', 'Pay'] : ['전투', '도주', '지불'])
    expect(['poor', 'fair', 'good'].map((w) => translate(lang, `fight.oddsSlip_${w}` as 'fight.oddsSlip_poor'))).toEqual(lang === 'en' ? ['Poor', 'Fair', 'Good'] : ['낮음', '보통', '높음'])
    expect(translate(lang, 'fight.oddsFoe')).toBe(lang === 'en' ? 'Raiders' : '해적')
    expect(translate(lang, 'codes.E_BAD_ORDER')).toBe(lang === 'en' ? 'No such order.' : '그런 명령 없음.')
  })
}

