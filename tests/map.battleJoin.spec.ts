import { test, expect } from '@playwright/test'
import { rolldown } from 'rolldown'
import { pathToFileURL } from 'node:url'
import path from 'node:path'
import { fightCountRadiusPx, fightRing } from '../src/chart/fightRings'
import { mapFightsOf } from '../src/chart/liveWorld'
import type { FleetOnChart, TrafficOnChart } from '../src/chart/chartModel'
import { project } from '../src/lib/geo'
import { translate } from '../src/lib/i18n'
import type { FightCard, FightSide } from '../src/lib/rpc'
import { BATTLE_JOIN_REFUSALS } from '../src/lib/rpc/battleJoin'
import { fleetsInFight, joinOffers, joinRefusalKey, joinSides, type JoinFleet } from '../src/live/battle/joinOffers'
import { KOREAN_PAUSED, LANGS } from './korean.paused'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// TICK COMBAT ON THE MAP (docs/design/tick-combat.md 8, 9.4; the owner: "every ship currently in a fight is drawn red";
// "joining is OPTIONAL"). Pure Node: no browser. The real layers and the real Join bar are server-rendered through
// tests/battleMap.entry.ts, from a fights fixture shaped as `world.fights()` serves it after 0435.
//   · RED: every fleet on a FIGHTING card that is there is drawn on a red ground; one on her way, one of a battle that
//     is over and one in no battle are not.
//   · THE RING of a tick battle is its join circle: centred on the site, `reach_nm` across, never under half a touch.
//   · JOIN is ONE button (owner 2026-11-15: "simplify all"); pressed, it offers only her fleets in reach that are free (not
//     in a battle, not held, not at peace), nearest first; a side against a player is never offered (no PvP), and a raid is
//     joined only on the side set upon.
//   · THE REFUSALS: every code `cmd.battle_join` answers has its own short word, in English and Korean.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

let render: {
  renderFleets: (props: Record<string, unknown>) => string
  renderRings: (props: Record<string, unknown>) => string
  renderJoin: (props: Record<string, unknown>) => string
  setLocale: (l: 'en' | 'ko') => void
}
test.beforeAll(async () => {
  const file = path.resolve('test-results', 'battle-map-render.mjs')
  const bundle = await rolldown({
    input: path.resolve('tests', 'battleMap.entry.ts'),
    platform: 'node',
    external: ['react', 'react-dom/server'],
    transform: { jsx: { runtime: 'automatic' } },
    logLevel: 'silent',
  })
  await bundle.write({ file, format: 'esm' })
  render = (await import(pathToFileURL(file).href)) as typeof render
})

const NOW = Date.parse('2026-11-15T12:00:00Z')
const LATER = '2026-11-15T12:05:00Z'
const EARLIER = '2026-11-15T11:55:00Z'

function side(fleet: string, s: FightSide['side'], kind: FightSide['kind'], here = true, name = fleet): FightSide {
  return { fleet, name, side: s, how: 'OPENED', kind, company: null, nation: null, ships: 1, here, ...(here ? { at: [0, 0] as [number, number] } : {}) }
}

function card(id: string, sides: FightSide[], extra: Partial<FightCard> = {}): FightCard {
  return {
    id,
    kind: 'BATTLE',
    status: 'FIGHTING',
    lat: 0,
    lon: 0,
    started_at: '2026-11-15T11:59:00Z',
    resolves_at: '2026-11-15T12:01:30Z',
    rounds_done: 0,
    next_at: null,
    fleets: sides.length,
    ships: sides.length,
    mine: null,
    sides,
    reach_nm: 30,
    ticks: true,
    ...extra,
  }
}

// THE FIGHTS FIXTURE: a raid being fought (a pirate on a merchant, a second pirate still on her way), an attack by
// ANOTHER player on a cargo ship, and a battle that is over.
const RAID = card('raid-1', [side('m1', 'DEFENDER', 'MERCHANT'), side('p1', 'ATTACKER', 'PIRATE'), side('p2', 'ATTACKER', 'PIRATE', false)])
const ATTACK = card('attack-1', [side('c1', 'ATTACKER', 'COMPANY'), side('k1', 'DEFENDER', 'CARGO_SHIP')], { lat: 10, lon: 10 })
const OVER = card('over-1', [side('r1', 'ATTACKER', 'NAVY'), side('r2', 'DEFENDER', 'PIRATE')], { status: 'RESOLVED', lat: 20, lon: 20 })
const CARDS = [RAID, ATTACK, OVER]

function chartFleet(id: string, lat = 0, lon = 0): FleetOnChart {
  return { fleet: { id, hulls: ['nau'] }, at: { lat, lon }, voyage: null, track: null, heading: 0, destinationCode: null, dockedAtCode: null } as unknown as FleetOnChart
}
function chartTraffic(id: string): TrafficOnChart {
  return { ...chartFleet(id), merchant: { ink: 'prt' }, loopD: null, laneD: null } as unknown as TrafficOnChart
}

test('every ship in a battle being fought is drawn red; one on her way, one of a battle that is over and one in no battle are not', () => {
  const inFight = fleetsInFight(CARDS)
  expect([...inFight].sort()).toEqual(['c1', 'k1', 'm1', 'p1'])
  const html = render.renderFleets({
    fleets: [chartFleet('c1'), chartFleet('mine-free')],
    traffic: ['m1', 'p1', 'p2', 'k1', 'r1', 'quiet'].map(chartTraffic),
    selectedId: null,
    unitsPerPx: 0.01,
    sun: { lat: 90, lon: 0 },
    inFight,
  })
  const red = [...html.matchAll(/<g[^>]*data-in-fight="true"[^>]*>/g)].map((m) => /data-merchant-id="([^"]+)"/.exec(m[0])?.[1] ?? 'yours')
  expect(red.sort()).toEqual(['k1', 'm1', 'p1', 'yours'])
  // each red group carries the red ground itself, once
  expect((html.match(/data-fight-ground=""/g) ?? []).length).toBe(4)
  // a chart that is handed no battle draws no red at all (the map as it was)
  const plain = render.renderFleets({ fleets: [chartFleet('c1')], traffic: [chartTraffic('m1')], selectedId: null, unitsPerPx: 0.01, sun: { lat: 90, lon: 0 } })
  expect(plain).not.toContain('data-in-fight')
})

test('a tick battle’s ring is its join circle: centred on the site, reach_nm across, never under half a touch', () => {
  const [raid] = mapFightsOf([RAID])
  const close = fightRing(raid, 0.001)
  expect(close.centre).toEqual(project({ lat: 0, lon: 0 }))
  expect(close.r).toBeCloseTo(0.5, 6) // 30 nm = half a degree
  expect(close.rPx).toBeCloseTo(500, 3)
  const wide = fightRing(raid, 1)
  expect(wide.rPx, 'zoomed out, the count of its fleets sets it (three here)').toBe(fightCountRadiusPx(raid.fleets))
  expect(fightRing({ ...raid, fleets: 2 }, 1).rPx, 'two fleets: half a touch').toBe(22)
  // …and never under what the count of fleets gives (owner row 321: more fleets, a bigger circle): seven fleets, zoomed out
  expect(fightRing({ ...raid, fleets: 7 }, 1).rPx).toBe(fightCountRadiusPx(7))
  expect(fightRing({ ...raid, fleets: 7 }, 0.001).rPx).toBeCloseTo(500, 3)
  const html = render.renderRings({ rings: [close], selectedId: null, unitsPerPx: 0.001 })
  expect(html).toContain('data-fight="raid-1"')
  expect(html).toContain('r="0.5"')
  // a card from before 0435 (no reach_nm) keeps the old ring round its fleets
  const [old] = mapFightsOf([{ ...RAID, reach_nm: undefined, ticks: undefined }])
  expect(fightRing(old, 0.001).rPx).toBeLessThan(100)
})

// HER FLEETS, round the raid's site (lat 0, lon 0; reach 30 nm = half a degree).
const FLEETS: JoinFleet[] = [
  { id: 'near', name: 'Santa Clara', at: { lat: 0.3, lon: 0 }, status: 'SAILING', busyUntil: null, peaceUntil: null },
  { id: 'nearer', name: 'Boa Esperança', at: { lat: 0.1, lon: 0 }, status: 'ANCHORED', busyUntil: EARLIER, peaceUntil: EARLIER },
  { id: 'far', name: 'Far Away', at: { lat: 1, lon: 0 }, status: 'SAILING', busyUntil: null, peaceUntil: null },
  { id: 'held', name: 'Held', at: { lat: 0.2, lon: 0 }, status: 'SAILING', busyUntil: LATER, peaceUntil: null },
  { id: 'peace', name: 'At Peace', at: { lat: 0.2, lon: 0 }, status: 'SAILING', busyUntil: null, peaceUntil: LATER },
  { id: 'fighting', name: 'Fighting', at: { lat: 0.2, lon: 0 }, status: 'IN_BATTLE', busyUntil: null, peaceUntil: null },
  { id: 'c1', name: 'On Another Card', at: { lat: 0.2, lon: 0 }, status: 'SAILING', busyUntil: null, peaceUntil: null },
  { id: 'lost', name: 'No Place', at: null, status: 'SAILING', busyUntil: null, peaceUntil: null },
]

test('Join is one button; pressed, it offers her fleets in reach that are free, nearest first, each with the sides she may take', () => {
  const offers = joinOffers(RAID, FLEETS, NOW, CARDS)
  expect(offers.map((o) => o.fleet.id)).toEqual(['nearer', 'near'])
  // a raid is joined only on the side set upon, against the pirates
  expect(offers.every((o) => o.sides.join() === 'DEFENDER')).toBe(true)
  render.setLocale('en')
  // SHUT: one button, Join, and no other word
  const shut = render.renderJoin({ card: RAID, fleets: FLEETS, nowMs: NOW, allCards: CARDS })
  expect((shut.match(/data-testid="join-open"/g) ?? []).length).toBe(1)
  expect(shut).toContain('data-fleets="nearer near"')
  expect(shut.replace(/<[^>]+>/g, '').trim()).toBe('Join')
  // PRESSED: one button a fleet, names whole; one side only, so no side word
  const html = render.renderJoin({ card: RAID, fleets: FLEETS, nowMs: NOW, allCards: CARDS, startOpen: true })
  expect([...html.matchAll(/data-testid="join-press" data-fleet="([^"]+)" data-side="([^"]+)"/g)].map((m) => `${m[1]} ${m[2]}`)).toEqual(['nearer DEFENDER', 'near DEFENDER'])
  expect(html).toContain('Boa Esperança')
  expect(html).toContain('Santa Clara')
  expect(html).not.toContain('Far Away')
  expect(html).not.toContain('Attacker')
  expect(html).not.toContain('join-open')
  render.setLocale('ko')
  const ko = render.renderJoin({ card: RAID, fleets: FLEETS, nowMs: NOW, allCards: CARDS })
  expect(ko.replace(/<[^>]+>/g, '').trim()).toBe('참전')
  render.setLocale('en')
})

test('no PvP: a side against a player is never offered; a battle she may not join draws no bar', () => {
  // another player attacks a cargo ship: only the attacking side (against the cargo ship) is offered, never the cargo
  // ship's side, which would set her against that player
  expect(joinSides(ATTACK)).toEqual(['ATTACKER'])
  const near = { ...FLEETS[0], id: 'n2', at: { lat: 10.2, lon: 10 } }
  const html = render.renderJoin({ card: ATTACK, fleets: [near], nowMs: NOW, allCards: CARDS, startOpen: true })
  expect(html).toContain('data-side="ATTACKER"')
  expect(html).not.toContain('data-side="DEFENDER"')
  expect(html).not.toContain('Defender')
  // players on both sides: nothing to offer, no bar
  const both = card('pvp', [side('x1', 'ATTACKER', 'COMPANY'), side('x2', 'DEFENDER', 'COMPANY')])
  expect(joinSides(both)).toEqual([])
  expect(render.renderJoin({ card: both, fleets: FLEETS, nowMs: NOW })).toBe('')
  // a battle that is over, a card from before 0435 (no reach_nm), a raid card of the old kind: no bar
  expect(render.renderJoin({ card: { ...RAID, status: 'RESOLVED' }, fleets: FLEETS, nowMs: NOW })).toBe('')
  expect(render.renderJoin({ card: { ...RAID, reach_nm: undefined }, fleets: FLEETS, nowMs: NOW })).toBe('')
  expect(render.renderJoin({ card: { ...RAID, kind: 'RAID' }, fleets: FLEETS, nowMs: NOW })).toBe('')
  // no fleet of hers in reach: no bar
  expect(render.renderJoin({ card: RAID, fleets: [FLEETS[2]], nowMs: NOW })).toBe('')
})

test('every refusal of cmd.battle_join has its own short word, in English and Korean', () => {
  const words = { en: new Set<string>(), ko: new Set<string>() }
  for (const code of BATTLE_JOIN_REFUSALS) {
    expect(joinRefusalKey(code)).toBe(`join.${code}`)
    for (const locale of LANGS) {
      const word = translate(locale, joinRefusalKey(code))
      expect(word, `${locale} ${code}`).not.toBe(joinRefusalKey(code))
      expect(word.split(/\s+/).length, `${locale} ${code}: "${word}" is one or two words`).toBeLessThanOrEqual(2)
      words[locale].add(word)
    }
  }
  expect(words.en.size).toBe(BATTLE_JOIN_REFUSALS.length)
  if (!KOREAN_PAUSED) expect(words.ko.size).toBe(BATTLE_JOIN_REFUSALS.length)
  expect(translate('en', 'join.E_HUMAN_TARGET')).toBe('No PvP')
  expect(translate('en', 'join.E_NOT_IN_REACH')).toBe('Too far')
  if (!KOREAN_PAUSED) expect(translate('ko', 'join.E_AT_PEACE')).toBe('휴전 중')
  // a code the contract does not name still says something short, never nothing
  expect(joinRefusalKey('E_SOMETHING_NEW')).toBe('join.E_OTHER')
  expect(translate('en', 'join.E_OTHER')).toBe('Refused')
  for (const k of ['join.join', 'join.joined', 'join.watch', 'join.vs'] as const) {
    for (const locale of LANGS) expect(translate(locale, k).split(/\s+/).length).toBeLessThanOrEqual(2)
  }
})
