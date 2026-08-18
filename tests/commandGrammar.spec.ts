// PURE UNIT SPEC — the F.1 grammar, the F.5 static check, and EVERY error code the V0 validator
// can raise. No browser.
//
// The refusals are a TABLE, evaluated at module scope, not accumulated across tests. That is on
// purpose: Playwright restarts a worker after a failure, so a set built up test-by-test silently
// under-reports the moment anything else in the file goes red — which is exactly the shape of
// "a proof that lies by staying green" (CORE_REUSE 5.4).

import { test, expect } from '@playwright/test'
import { ERROR_CODES, errorSentence, isErrorCode } from '../src/features/command/errors'
import type { ErrorCode } from '../src/features/command/errors'
import { VERBS, V0_VERBS, isV0Verb, verbSpec } from '../src/features/command/grammar'
import { fold, parseNumber, parseOrder, tokenize } from '../src/features/command/parse'
import { checkCommand } from '../src/features/command/validate'
import type { CheckErr, CheckOk } from '../src/features/command/validate'
import type { WorldModel } from '../src/features/command/worldModel'
import { buildStaticWorld, deriveWorld } from '../src/features/command/worldModel'
import type { V0World } from '../src/fixtures/types'
import { FIXTURE_INSTANT_MS, buildV0World } from '../src/fixtures/v0'

const BASE = buildV0World(FIXTURE_INSTANT_MS)
const model = deriveWorld(buildStaticWorld(BASE), FIXTURE_INSTANT_MS)

const GAIVOTA = 'fleet-gaivota' // 1 Barca, DOCKED at Lisboa, 9.4 d endurance, 8,000 ducats
const AURORA = 'fleet-aurora' // 2 ships, SAILING Lisboa -> Las Palmas

/** A world that differs from the fixture in one stated way, so a precondition can be reached. */
function variant(change: Partial<V0World>): WorldModel {
  return deriveWorld(buildStaticWorld({ ...BASE, ...change }), FIXTURE_INSTANT_MS)
}

function refuse(raw: string, fleetId = GAIVOTA, world: WorldModel = model): CheckErr {
  const r = checkCommand(raw, world, fleetId)
  if (r.ok) throw new Error(`expected "${raw}" to be refused, but it parsed: ${r.summary}`)
  return r
}

function accept(raw: string, fleetId = GAIVOTA, world: WorldModel = model): CheckOk {
  const r = checkCommand(raw, world, fleetId)
  if (!r.ok) throw new Error(`expected "${raw}" to parse; got ${r.code}: ${r.sentence}`)
  return r
}

// ── the primitives ───────────────────────────────────────────────────────────────────────────

test('F.1 folding: case and diacritics collapse', () => {
  expect(fold('Cádiz')).toBe('cadiz')
  expect(fold('cortiça')).toBe('cortica')
  expect(fold('lã')).toBe('la')
  expect(fold('AÇÚCAR')).toBe('acucar')
})

test('F.1 numbers accept _ and , separators', () => {
  expect(parseNumber('200_000')).toBe(200000)
  expect(parseNumber('1,500')).toBe(1500)
  expect(parseNumber('60')).toBe(60)
  expect(parseNumber('sal')).toBeNull()
})

test('comparators tokenise whether or not they are spaced', () => {
  expect(tokenize('BUY sal 60 AT<=34')).toEqual(['BUY', 'sal', '60', 'AT', '<=', '34'])
  expect(tokenize('BUY sal 60 AT <= 34')).toEqual(['BUY', 'sal', '60', 'AT', '<=', '34'])
})

test('the verb table is F.1s EBNF: 27 verbs, 8 of them in V0', () => {
  expect(VERBS).toHaveLength(27)
  expect(V0_VERBS).toHaveLength(8)
  for (const v of V0_VERBS) {
    expect(isV0Verb(v)).toBe(true)
    // Every V0 verb has a tap-builder schema, or the phone cannot compose it (F.4).
    expect(verbSpec(v), `${v} has no slot schema`).toBeTruthy()
  }
  expect(isV0Verb('INVEST')).toBe(false)
})

// ── valid commands ───────────────────────────────────────────────────────────────────────────

test('SAIL parses in every shape F.1 allows', () => {
  expect(accept('SAIL Gaivota TO Cádiz').summary).toContain('188 nm')
  // Case-insensitive, diacritic-folded, port CODE, keyword omitted, prefix-unique names.
  expect(checkCommand('sail gaivota to cadiz', model, GAIVOTA).ok).toBe(true)
  expect(checkCommand('SAIL Gaivota TO CAD', model, GAIVOTA).ok).toBe(true)
  expect(checkCommand('SAIL Gaivota Cádiz', model, GAIVOTA).ok).toBe(true)
  expect(checkCommand('SAIL Gai TO Cad', model, GAIVOTA).ok).toBe(true)
})

test('SAIL resolves multi-word ports and VIA waypoints', () => {
  expect(accept('SAIL Gaivota TO Funchal').summary).toContain('525 nm')
  const via = accept('SAIL Gaivota TO Las Palmas VIA Funchal')
  // 524.9 + 282.0 = 806.9, longer than the 708.7 direct leg — which is what a VIA is for.
  expect(via.summary).toContain('807 nm')
  expect(via.summary).toContain('2 legs')
})

test('the two clocks both appear on a SAIL check line (D.3)', () => {
  const eta = accept('SAIL Gaivota TO Cádiz').details.find((d) => d.startsWith('ETA'))!
  expect(eta).toContain('real')
  expect(eta).toContain('voyage-days')
})

test('BUY and SELL parse with quantities, limits and an explicit fleet', () => {
  expect(accept('BUY sal 50').summary).toContain('BUY 50 t sal')
  accept('BUY sal 50 AT <= 9')
  accept('BUY sal 50 AT 9')
  accept('buy cortiça 20 FOR Gaivota')
  accept('BUY cork 20') // the English name resolves too
  expect(accept('SELL trigo ALL', AURORA).summary).toContain('120 t')
  accept('SELL trigo HALF', AURORA)
  accept('SELL trigo 50%', AURORA)
  accept('SELL trigo ALL AT >= 5', AURORA)
})

test('a BUY for a fleet at sea is queued for arrival, not refused (F.2)', () => {
  const r = accept('BUY açúcar 40 FOR Aurora', AURORA)
  // Aurora is bound for Las Palmas, so the market checked is Las Palmas.
  expect(r.summary).toContain('Las Palmas')
  expect(r.warnings.join(' ')).toContain('at sea')
})

test('PROVISION, HIRE, REPAIR, CANCEL and CLEAR all parse', () => {
  expect(accept('PROVISION Gaivota FULL').summary).toContain('PROVISION')
  accept('PROVISION Gaivota 15 DAYS')
  expect(accept('HIRE 4 CREW FOR Gaivota').summary).toContain('4 hands')
  expect(accept('REPAIR Gaivota').summary).toContain('REPAIR')
  accept('REPAIR Gaivota TO 100')
  expect(accept('CANCEL Aurora 2', AURORA).summary).toContain('SELL trigo ALL')
  expect(accept('CLEAR Aurora', AURORA).summary).toContain('3 pending orders')
  accept('CLEAR Aurora ALL', AURORA)
})

test('CANCEL on an ACTIVE voyage says it is a recall (F.3)', () => {
  const r = accept('CANCEL Aurora 1', AURORA)
  expect(r.details.join(' ')).toContain('RECALL')
  expect(r.warnings.join(' ')).toContain('recall')
})

// ── EVERY V0 ERROR CODE, as one table ────────────────────────────────────────────────────────
// Each row: what the player typed, the code it must raise, and the substrings that prove the
// sentence and the fixes really carry this fleet's numbers rather than a generic apology.

interface RefusalCase {
  label: string
  code: ErrorCode
  result: CheckErr
  /** Substrings the SPECIFIC sentence must contain. */
  sentenceHas?: readonly string[]
  /** Substrings at least one insertable fix must contain. */
  fixHas?: readonly string[]
}

/** Aurora, alongside at Lisboa — the only way to reach a rule that needs a docked deep hull. */
const AURORA_DOCKED = variant({
  fleets: BASE.fleets.map((f) =>
    f.id === AURORA ? { ...f, status: 'DOCKED' as const, portCode: 'LIS' as const, voyage: null } : f,
  ),
})

/** Gaivota with a Nau's hold and a fortune, so the money and volume rules can be reached. */
const RICH_AND_ROOMY = variant({
  player: { ...BASE.player, ducats: 50_000_000 },
  ships: BASE.ships.map((s) => (s.id === 'ship-gaivota' ? { ...s, classCode: 'nau' as const } : s)),
})

const CASES: readonly RefusalCase[] = [
  {
    label: 'E_PARSE — an unknown word is not an order',
    code: 'E_PARSE',
    result: refuse('FLY Gaivota TO Cádiz'),
    sentenceHas: ['FLY'],
  },
  {
    label: 'E_PARSE — an empty line',
    code: 'E_PARSE',
    result: refuse(''),
  },
  {
    label: 'E_PARSE — a stray token at the end of a SAIL',
    code: 'E_PARSE',
    result: refuse('SAIL Gaivota TO Cádiz sideways'),
  },
  {
    label: 'E_AMBIGUOUS — "C" is both Cádiz and Ceuta, and both are offered',
    code: 'E_AMBIGUOUS',
    result: refuse('SAIL Gaivota TO C'),
    sentenceHas: ['Cádiz', 'Ceuta'],
    fixHas: ['Cádiz'],
  },
  {
    label: 'E_AMBIGUOUS — "co" is cortiça, couro, cobre and coral',
    code: 'E_AMBIGUOUS',
    result: refuse('BUY co 20'),
  },
  {
    label: 'E_NO_SUCH_FLEET — you own no Ponente',
    code: 'E_NO_SUCH_FLEET',
    result: refuse('SAIL Ponente TO Cádiz'),
    sentenceHas: ['Ponente'],
  },
  {
    label: 'E_NO_SUCH_PORT — Amsterdam is a V1 port',
    code: 'E_NO_SUCH_PORT',
    result: refuse('SAIL Gaivota TO Amsterdam'),
    sentenceHas: ['Amsterdam'],
  },
  {
    label: 'E_NO_SUCH_GOOD — pepper is not in the V0 twelve',
    code: 'E_NO_SUCH_GOOD',
    result: refuse('BUY pimenta 40'),
  },
  {
    label: 'E_NOT_DOCKED — a fleet at sea cannot be given a new course',
    code: 'E_NOT_DOCKED',
    result: refuse('SAIL Aurora TO Lisboa', AURORA),
    sentenceHas: ['at sea'],
    fixHas: ['CANCEL Aurora'],
  },
  {
    label: 'E_NOT_DOCKED — nor put in a yard, provisioned or manned',
    code: 'E_NOT_DOCKED',
    result: refuse('REPAIR Aurora', AURORA),
  },
  {
    label: 'E_NOT_SAILING — CLEAR ALL recalls a voyage, and there is none',
    code: 'E_NOT_SAILING',
    result: refuse('CLEAR Gaivota ALL'),
    fixHas: ['CLEAR Gaivota'],
  },
  {
    label: 'E_ENDURANCE — Tunis is beyond 9.4 days of stores, plus the 15% margin',
    code: 'E_ENDURANCE',
    result: refuse('SAIL Gaivota TO Tunis'),
    sentenceHas: ['9.4 d', 'fifteen per cent'],
    fixHas: ['PROVISION Gaivota FULL', 'DAYS'],
  },
  {
    label: 'E_DRAFT — Sevilla is up the Guadalquivir and will not take the Nau',
    code: 'E_DRAFT',
    result: refuse('SAIL Aurora TO Sevilla', AURORA, AURORA_DOCKED),
    sentenceHas: ['Bom Jesus', 'Sevilla'],
  },
  {
    label: 'E_CREW_SHORT — a hull below its required complement cannot sail',
    code: 'E_CREW_SHORT',
    result: refuse(
      'SAIL Gaivota TO Cádiz',
      GAIVOTA,
      variant({ ships: BASE.ships.map((s) => (s.id === 'ship-gaivota' ? { ...s, crew: 2 } : s)) }),
    ),
    sentenceHas: ['Gaivota'],
    fixHas: ['HIRE'],
  },
  {
    label: 'E_FLAGSHIP_DISABLED — C.4s hard stop',
    code: 'E_FLAGSHIP_DISABLED',
    result: refuse(
      'SAIL Gaivota TO Cádiz',
      GAIVOTA,
      variant({ ships: BASE.ships.map((s) => (s.id === 'ship-gaivota' ? { ...s, durability: 0 } : s)) }),
    ),
    fixHas: ['REPAIR Gaivota'],
  },
  {
    label: 'E_HOLD_FULL — a Barca holds 60 tuns and 4.1 of them are stores',
    code: 'E_HOLD_FULL',
    result: refuse('BUY sal 200'),
    sentenceHas: ['55.9 t'],
    fixHas: ['BUY sal 55'],
  },
  {
    label: 'E_INSUFFICIENT_FUNDS — 8,000 ducats does not buy 60 tuns of coral',
    code: 'E_INSUFFICIENT_FUNDS',
    result: refuse(
      'BUY coral 60',
      GAIVOTA,
      variant({ ships: BASE.ships.map((s) => (s.id === 'ship-gaivota' ? { ...s, classCode: 'nau' as const } : s)) }),
    ),
    sentenceHas: ['8,000 d.'],
  },
  {
    label: 'E_NO_CARGO — you cannot sell what is not aboard',
    code: 'E_NO_CARGO',
    result: refuse('SELL coral ALL'),
  },
  {
    label: 'E_UNAVAILABLE — B.4 culture mask: no wine on a Maghrebi quay',
    code: 'E_UNAVAILABLE',
    result: refuse(
      'BUY vinho 20',
      GAIVOTA,
      variant({ fleets: BASE.fleets.map((f) => (f.id === GAIVOTA ? { ...f, portCode: 'TUN' as const } : f)) }),
    ),
    sentenceHas: ['Tunis'],
  },
  {
    label: 'E_DAILY_CAP — G.7 rule 1 caps one house at 35% of the stock target',
    code: 'E_DAILY_CAP',
    result: refuse('BUY sal 5000', GAIVOTA, RICH_AND_ROOMY),
  },
  {
    label: 'E_NO_STOCK — the port has none to sell',
    code: 'E_NO_STOCK',
    result: refuse(
      'BUY sal 400',
      GAIVOTA,
      variant({
        player: { ...BASE.player, ducats: 50_000_000 },
        ships: BASE.ships.map((s) => (s.id === 'ship-gaivota' ? { ...s, classCode: 'nau' as const } : s)),
        portGoods: BASE.portGoods.map((r) => (r.port === 'LIS' && r.good === 'sal' ? { ...r, stock: 5 } : r)),
      }),
    ),
  },
  {
    label: 'E_PRICE_LIMIT — a buy limit under the market halts the queue (F.5)',
    code: 'E_PRICE_LIMIT',
    result: refuse('BUY sal 50 AT <= 3'),
    sentenceHas: ['the queue would stop here'],
    fixHas: ['BUY sal 50'],
  },
  {
    label: 'E_PRICE_LIMIT — and so does a sell limit over it',
    code: 'E_PRICE_LIMIT',
    result: refuse('SELL trigo ALL AT >= 900', AURORA),
    fixHas: ['AT >='],
  },
  {
    label: 'E_CREW_POOL — the town has not got the men at any price',
    code: 'E_CREW_POOL',
    result: refuse('HIRE 5000 CREW FOR Gaivota'),
  },
  {
    label: 'E_CREW_MAX — a Barca berths 20 and already carries 12',
    code: 'E_CREW_MAX',
    result: refuse('HIRE 40 CREW FOR Gaivota'),
    fixHas: ['HIRE 8 CREW FOR Gaivota'],
  },
  {
    label: 'E_NO_YARD — hulls are mended where there are shipwrights',
    code: 'E_NO_YARD',
    result: refuse(
      'REPAIR Gaivota',
      GAIVOTA,
      variant({ fleets: BASE.fleets.map((f) => (f.id === GAIVOTA ? { ...f, portCode: 'CEU' as const } : f)) }),
    ),
    fixHas: ['SAIL Gaivota TO'],
  },
  {
    label: 'E_QUEUE_FULL — twelve orders is the ceiling (F.3)',
    code: 'E_QUEUE_FULL',
    result: refuse(
      'BUY sal 10',
      GAIVOTA,
      variant({
        orders: Array.from({ length: 12 }, (_, i) => ({
          id: `x${i}`,
          fleetId: GAIVOTA,
          seq: i + 1,
          raw: 'BUY sal 10',
          status: 'pending' as const,
        })),
      }),
    ),
    fixHas: ['CLEAR Gaivota'],
  },
  {
    label: 'E_RANK_LOCKED — a real verb outside the V0 slice is explained, not called gibberish',
    code: 'E_RANK_LOCKED',
    result: refuse('INVEST 50000 IN Lisboa AS trade'),
    sentenceHas: ['INVEST', 'SAIL, BUY, SELL, PROVISION, HIRE, REPAIR, CANCEL, CLEAR'],
  },
  {
    label: 'E_RANK_LOCKED — SPLIT and EXPLORE likewise',
    code: 'E_RANK_LOCKED',
    result: refuse('EXPLORE Gaivota DAYS 3'),
  },
]

for (const c of CASES) {
  test(c.label, () => {
    expect(c.result.code).toBe(c.code)
    // F.5's contract, on EVERY refusal: a code, a sentence, and at least one insertable fix.
    expect(isErrorCode(c.result.code)).toBe(true)
    expect(c.result.sentence.length).toBeGreaterThan(10)
    expect(c.result.sentence.trim().endsWith('.')).toBe(true)
    expect(c.result.fixes.length).toBeGreaterThan(0)
    for (const fix of c.result.fixes) expect(fix.command.trim().length).toBeGreaterThan(0)
    for (const s of c.sentenceHas ?? []) expect(c.result.sentence).toContain(s)
    for (const s of c.fixHas ?? []) {
      expect(c.result.fixes.some((f) => f.command.includes(s)), `no fix contains "${s}"`).toBe(true)
    }
  })
}

test('THE RAISE-SET: every code the V0 validator can produce is covered by the table above', () => {
  const covered = [...new Set(CASES.map((c) => c.code))].sort()
  expect(covered).toEqual(
    [
      'E_AMBIGUOUS',
      'E_CREW_MAX',
      'E_CREW_POOL',
      'E_CREW_SHORT',
      'E_DAILY_CAP',
      'E_DRAFT',
      'E_ENDURANCE',
      'E_FLAGSHIP_DISABLED',
      'E_HOLD_FULL',
      'E_INSUFFICIENT_FUNDS',
      'E_NO_CARGO',
      'E_NO_STOCK',
      'E_NO_SUCH_FLEET',
      'E_NO_SUCH_GOOD',
      'E_NO_SUCH_PORT',
      'E_NO_YARD',
      'E_NOT_DOCKED',
      'E_NOT_SAILING',
      'E_PARSE',
      'E_PRICE_LIMIT',
      'E_QUEUE_FULL',
      'E_RANK_LOCKED',
      'E_UNAVAILABLE',
    ].sort(),
  )
})

// ── the copy map ─────────────────────────────────────────────────────────────────────────────

test('F.5s full code list is present and every code has a real sentence', () => {
  expect(ERROR_CODES).toHaveLength(46)
  for (const code of ERROR_CODES) {
    const s = errorSentence(code)
    expect(s.length).toBeGreaterThan(10)
    expect(s.endsWith('.')).toBe(true)
    // A sentence that merely restates the code is not a sentence.
    expect(s).not.toContain(code)
  }
})

test('an unmapped reason degrades to English, never to a token (CORE_REUSE 2.1)', () => {
  expect(errorSentence('some_server_reason_we_never_saw')).toBe('That order cannot be carried out.')
  expect(isErrorCode('E_NOPE')).toBe(false)
})

test('the parser never throws, whatever is typed at it', () => {
  const junk = ['', '   ', '!!!', 'SAIL', 'BUY', 'SAIL TO TO TO', '1234', 'SELL 40 sal', 'AT <= <= 9']
  for (const raw of junk) {
    expect(() => parseOrder(raw, model.parseContext)).not.toThrow()
    expect(() => checkCommand(raw, model, GAIVOTA)).not.toThrow()
  }
})
