import { test, expect } from '@playwright/test'
import { rolldown } from 'rolldown'
import { pathToFileURL } from 'node:url'
import path from 'node:path'
import { payloadFights } from '../src/features/ledger/headline'
import { translate } from '../src/lib/i18n'
import type { BattleRead, FightEnd } from '../src/lib/rpc'
import { fightRows, parseFightLog } from '../src/live/fightLines'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE BATTLE CARD, READ AND DRAWN (0357, owner row 315; docs/COMBAT_LOG.md 3.4, 5.2). Pure Node: no browser.
// The server's half is proof 60, and the seam is tests/rpc.battle.spec.ts. This is the half a client could still get
// wrong: a log with no ending is read only where one is expected, a battle she started speaks from her deck with its
// own endings, the card shows the clock, the next round and her two buttons while it is fought and the result once
// it is not, and every word is there in English and Korean.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// A battle she started, from her deck, as public.battle_log serves it: two rounds fought, the second under Flee.
const OPEN_LOG = {
  v: 1,
  atk: true,
  first: 'BOTH',
  foe: { n: 'Mercante', k: 1, crew: 8, hull: 400 },
  you: [['Ronda', 400, 400, 8]],
  r: [
    [1, 'L', 1, 2, 1, 31.5, 1, 2, 0, 0, 400, 368.5, [], null],
    [2, 'L', 0, 0, 0, 0, 1, 2, 1, 22, 378, 368.5, [[1, 6]], 0.15],
  ],
  after: [['Ronda', 378]],
}
const READ: BattleRead = {
  on: true,
  battle: '00000000-0000-4000-8000-000000000357',
  status: 'FIGHTING',
  side: 'ATTACKER',
  foe: 'Mercante',
  word: 'even',
  started_at: '2026-11-13T00:00:00Z',
  resolves_at: '2026-11-13T00:07:00Z',
  now: '2026-11-13T00:02:18Z',
  round_seconds: 60,
  rounds: 6,
  rounds_done: 2,
  next_at: '2026-11-13T00:03:00Z',
  next_range: 'LONG',
  stance: 'FLEE',
  may: ['FIGHT', 'FLEE'],
  log: OPEN_LOG,
}
const NOW = Date.parse('2026-11-13T00:02:18Z')

let render: { renderBattle: (props: Record<string, unknown>) => string; renderLog: (props: Record<string, unknown>) => string; setLocale: (l: 'en' | 'ko') => void }
test.beforeAll(async () => {
  const file = path.resolve('test-results', 'battle-card-render.mjs')
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
const text = (html: string) => html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim()

test('a log with no ending is a fight still open, and only where one is expected', () => {
  // History and the arrival card ask for a finished fight: a log with no ending is not a shape they know
  expect(parseFightLog(OPEN_LOG)).toBeNull()
  const log = parseFightLog(OPEN_LOG, { open: true })!
  expect(log).not.toBeNull()
  expect(log.end).toBe('OPEN')
  expect(log.attacker).toBe(true)
  // the server never sends OPEN as a word, and a deck that is not a yes or a no is refused
  expect(parseFightLog({ ...OPEN_LOG, end: 'OPEN' }, { open: true })).toBeNull()
  expect(parseFightLog({ ...OPEN_LOG, atk: 'yes' }, { open: true })).toBeNull()
  // a raid's log says no deck: it is hers as the side set upon
  expect(parseFightLog({ ...OPEN_LOG, atk: undefined, end: 'FLED' })!.attacker).toBe(false)
  // round 2 she ran: her cell says so and carries the chance the server rolled
  const rows = fightRows(log)
  expect(rows.map((r) => r.you.kind)).toEqual(['shots', 'run'])
  expect(rows.map((r) => r.slipPct)).toEqual([null, 15])
})

test("a battle's report in History reads its log from her deck, and an old report still reads its sentences", () => {
  const withLog = payloadFights({ fights: [{ line: 0, rounds: ['Round 1 ...'], log: { ...OPEN_LOG, end: 'A_TOOK', board: [8, 6, 1.4] } }] })
  expect(withLog[0].log?.end).toBe('A_TOOK')
  expect(withLog[0].log?.attacker).toBe(true)
  const old = payloadFights({ fights: [{ line: 0, rounds: ['Round 1 ...'] }] })
  expect(old[0].log).toBeNull()
  expect(old[0].rounds).toEqual(['Round 1 ...'])
})

for (const lang of ['en', 'ko'] as const) {
  test(`while it is fought: the foe, the word, the next round and its clock, Fight and Flee, the log so far and no result, ${lang}`, () => {
    render.setLocale(lang)
    const html = render.renderBattle({ read: READ, nowMs: NOW })
    const said = text(html)
    expect(html).toContain('data-testid="battle-card"')
    expect(html).toContain('data-status="FIGHTING"')
    expect(html).toContain('data-stance="FLEE"')
    expect(said).toContain(`${translate(lang, 'fight.battle')} Mercante`)
    expect(said).toContain(translate(lang, 'map.attackWord_even'))
    // round 3 is next, at long range, 42 seconds away on the SERVER's clock
    expect(said).toContain(`${translate(lang, 'fight.round')} 3 · ${translate(lang, 'fight.rangeL')}`)
    expect(html).toMatch(/data-testid="battle-clock"[^>]*>0:42</)
    // two buttons, and what a press does is said
    expect(html).toContain('data-testid="battle-stance-FIGHT"')
    expect(html).toContain('data-testid="battle-stance-FLEE"')
    expect(html).not.toContain('data-testid="battle-stance-PAY"')
    expect(said).toContain(translate(lang, 'fight.nextRound'))
    // the one log, from her deck, both rounds at once, and nothing told before its round
    expect(html).toContain('data-testid="fight-log"')
    expect(html).toContain('data-deck="attacker"')
    expect(html).toContain('data-rounds="2"')
    expect(html).not.toContain('data-testid="fight-log-result"')
    expect(html).not.toContain('data-testid="battle-loot"')
    expect(said).not.toContain(translate(lang, 'fight.raid') + ' ·')
    expect(said).not.toContain(translate(lang, 'fight.order') + ' ')
    expect(said).toContain(translate(lang, 'fight.run'))
    expect(said).not.toMatch(/fight\.[a-zA-Z_]+|map\.[a-zA-Z_]+/)
    if (lang === 'ko') expect(said).not.toMatch(/\b(Battle|Stance|Round|Fight|Flee|Long|Foe|Run|Slip|You|Them)\b/)
  })

  test(`the boarding is next: no range, and the clock runs to the battle's end, ${lang}`, () => {
    render.setLocale(lang)
    const html = render.renderBattle({ read: { ...READ, rounds_done: 6, next_at: READ.resolves_at, next_range: null, now: '2026-11-13T00:06:30Z' }, nowMs: Date.parse('2026-11-13T00:06:30Z') })
    expect(text(html)).toContain(translate(lang, 'fight.boarding'))
    expect(html).toMatch(/data-testid="battle-clock"[^>]*>0:30</)
  })

  test(`closed: no clock and no buttons; the result, the loot and the hands, ${lang}`, () => {
    render.setLocale(lang)
    const ends: Record<Extract<FightEnd, `A_${string}` | 'FLED'>, string> =
      lang === 'en'
        ? { A_NONE: 'No fight', A_LOST: 'They escaped', A_BROKE: 'Broke off', A_THROWN: 'Thrown back', A_TERMS: 'They paid', A_TOOK: 'Boarded', FLED: 'Fled' }
        : { A_NONE: '전투 없음', A_LOST: '적 도주', A_BROKE: '이탈', A_THROWN: '격퇴당함', A_TERMS: '몸값 받음', A_TOOK: '나포', FLED: '도주 성공' }
    for (const end of Object.keys(ends) as (keyof typeof ends)[]) {
      const boarded = end === 'A_THROWN' || end === 'A_TOOK'
      const read: BattleRead = {
        ...READ,
        status: end === 'FLED' ? 'BROKEN_OFF' : 'RESOLVED',
        next_at: null,
        next_range: null,
        outcome: 'PLUNDERED',
        loot: end === 'A_TOOK' ? 60000 : 0,
        crew_lost: 3,
        log: { ...OPEN_LOG, end, board: boarded ? [8, 6, 1.4] : undefined },
      }
      const html = render.renderBattle({ read, nowMs: NOW })
      const said = text(html)
      expect(html, end).not.toContain('data-testid="battle-clock"')
      expect(html, end).not.toContain('data-testid="battle-stance-FLEE"')
      expect(said, end).toContain(`${translate(lang, 'fight.result')} ${ends[end]}`)
      expect(said.includes(translate(lang, 'fight.boardingLine', { you: '8', them: '6' })), `${end}: the boarding line`).toBe(boarded)
      expect(html, end).toMatch(end === 'A_TOOK' ? /data-testid="battle-loot"[^>]*>[^<]*60,000/ : /data-testid="battle-loot"/)
      expect(html, end).toMatch(/data-testid="battle-crew-lost"[^>]*>3</)
      expect(translate(lang, `fight.end_${end}`)).toBe(ends[end])
    }
    expect(translate(lang, 'fight.end_OPEN')).toBe(lang === 'en' ? 'Fighting' : '전투 중')
  })

  test(`a side set upon is offered Pay as well; a navy line is said; a refusal reads in words, ${lang}`, () => {
    render.setLocale(lang)
    const html = render.renderBattle({ read: { ...READ, side: 'DEFENDER', may: ['FIGHT', 'FLEE', 'PAY'], stance: 'FIGHT' }, nowMs: NOW })
    expect(html).toContain('data-testid="battle-stance-PAY"')
    const closed = render.renderBattle({ read: { ...READ, status: 'RESOLVED', next_at: null, log: { ...OPEN_LOG, end: 'A_BROKE' }, navy: 'A navy ship came up.' }, nowMs: NOW })
    expect(text(closed)).toContain('A navy ship came up.')
    for (const code of ['E_BAD_STANCE', 'E_NO_BATTLE', 'E_NOT_YOUR_BATTLE', 'E_BATTLE_OVER', 'E_NOT_IN_USE'] as const) expect(translate(lang, `codes.${code}`), code).toBeTruthy()
  })
}

test('dark, or no battle of hers: the card draws nothing', () => {
  expect(render.renderBattle({ read: { on: false }, nowMs: NOW })).toBe('')
  expect(render.renderBattle({ read: { on: true }, nowMs: NOW })).toBe('')
})
