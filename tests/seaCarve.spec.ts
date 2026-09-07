// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE CARVE IS AN INVENTORY, NOT A HABIT — nothing turns land into sea without someone saying so
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// PURE UNIT SPEC. No `page` fixture, no database: this reads the same module that builds the raster
// the game sails on and counts what it does.
//
// ── WHY THIS EXISTS ────────────────────────────────────────────────────────────────────────────
// `scripts/sea-grid.mjs` opens named narrow waters the 0.25° raster is too coarse to see, and its
// carve is "the cells between CONSECUTIVE points". So an entry's points must lie along ONE water,
// in order. On 2026-09-06 one did not: `irrawaddy-sittaung` named the Yangon river AND the Chao
// Phraya, 330 nm apart, and the jump between them cut a canal through the Tenasserim mountains —
// 29 land cells, the deepest 89.3 nm inland. **309 real port pairs were sold a route across it**,
// worst Thanlyin → Ayutthaya at 323 nm against 1,977 nm of actual sea. The owner's law is absolute
// (`OWNER_REQUESTS.md` row 41: "i don't want the fleet to ever touch land").
// `docs/LAND_CARVE_RECON.md` carries the measurements and the method.
//
// ── WHAT THIS CAN AND CANNOT DO, STATED HONESTLY ───────────────────────────────────────────────
// It is NOT an automatic classifier, and the numbers say why one is not possible. Sorted by the
// longest hop between consecutive points, the canal sits first at 330.5 nm — but the Bab-el-Mandeb
// (277.6), Hormuz (142.3) and Malacca (124.8) are right behind it and every one of them is real
// water. Sorted by how far inland a carve reaches, the Gulf of Suez (97.1 nm), the St Lawrence
// (76.7) and the Severn (67.6) all sit ABOVE legitimate river carves, because a river IS far from
// open sea. **No threshold separates a strait from a canal.** A person has to look.
//
// So this is a REVIEW GATE, and it works the way a review gate can: the inventory is PINNED. Every
// entry, and exactly how many cells of dry land it opens. Change the carve and a number moves and
// this goes red — and then a human decides whether the new water is real, which is the only place
// that decision can honestly be made. It would have caught the canal on the day it was written.
//
// The counts below are TODAY'S, canal included. They are a baseline, not an endorsement: the
// `irrawaddy-sittaung` row is the defect, it is named as such, and the number moves when it is
// repaired.

import { test, expect } from '@playwright/test'
import { CHANNELS, buildSeaGrid, gcNm, rowOf, colOf, COLS } from '../scripts/sea-grid.mjs'
import type { Channel } from '../scripts/sea-grid.mjs'

/** Every cell an entry opens — its own points and the cells between consecutive points, which is
 *  exactly what `sea-grid.mjs:222-234` does. Duplicated here on purpose: a guard that called the
 *  code it guards would go green on any change they made together. */
function cellsOpenedBy(ch: Channel): Set<number> {
  const s = new Set<number>()
  for (let i = 0; i < ch.points.length; i++) {
    const [la, lo] = ch.points[i]
    s.add(rowOf(la) * COLS + colOf(lo))
    if (i + 1 < ch.points.length) {
      const [lb, lb2] = ch.points[i + 1]
      const steps = Math.ceil(gcNm(la, lo, lb, lb2) / 5)
      for (let st = 1; st < steps; st++) {
        s.add(rowOf(la + ((lb - la) * st) / steps) * COLS + colOf(lo + ((lb2 - lo) * st) / steps))
      }
    }
  }
  return s
}

/** The land the carve overwrote: the built raster with every carved cell closed again. */
function preChannelLand(): Uint8Array {
  const carved = buildSeaGrid()
  const pre = Uint8Array.from(carved)
  for (const ch of CHANNELS) for (const k of cellsOpenedBy(ch)) pre[k] = 0
  return pre
}

const landOpenedBy = (pre: Uint8Array, ch: Channel) =>
  [...cellsOpenedBy(ch)].filter((k) => pre[k] !== 1).length

// id → how many cells of DRY LAND it opens. Measured 2026-09-06 against main @ 728da87.
const PINNED: Record<string, number> = {
  // ⚠ WAS THE DEFECT, AND IS REPAIRED. One record named two rivers 330 nm apart and opened 37
  // cells of dry land; it is now two records opening 8 between them. The 29 cells it stops opening
  // are the canal through the Tenasserim mountains — 23 of which public.sea_cells had NAMED as
  // sea, because 0040 was cut from the carved grid. Those 23 are scripts/sea-grid.mjs's RECLAIMED
  // 'tenasserim' entry, and migration 0079 zeroes their membership. docs/LAND_CARVE_RECON.md.
  'yangon': 3, 'chao-phraya': 5,

  'bab-el-mandeb': 84, 'malacca': 52, 'hormuz': 48, 'saint-lawrence': 33, 'baltic-gulfs': 31,
  'thames-scheldt': 26, 'danish-straits': 24, 'seto': 22, 'gironde': 20, 'turkish-straits': 20,
  'white-sea': 20, 'gulf-of-suez': 17, 'elbe-weser': 16, 'gambia-senegal': 14,
  'rio-de-la-plata': 12, 'hooghly': 12, 'sunda': 11, 'yangtze': 10, 'pearl-river': 8, 'severn': 7,
  'amazon-para': 6, 'shatt-al-arab': 6, 'khambhat': 6, 'kerch': 4, 'guadalquivir': 4,
}
const PINNED_TOTAL = 521

test('every channel opens exactly the land it is on record for', () => {
  const pre = preChannelLand()
  const channels = CHANNELS

  // THE SET FIRST. An entry added or removed must be seen even if the totals happen to agree.
  expect(channels.map((c) => c.id).sort()).toEqual(Object.keys(PINNED).sort())

  const actual: Record<string, number> = {}
  for (const ch of channels) actual[ch.id] = landOpenedBy(pre, ch)
  expect(actual).toEqual(PINNED)

  // The total is not redundant: it is the number a reviewer can hold in their head, and it is what
  // makes "the world grew some water" a sentence rather than a diff of twenty-six rows.
  expect(Object.values(actual).reduce((a, b) => a + b, 0)).toBe(PINNED_TOTAL)
})

test('the pin BITES — a planted canal changes the count it is pinned to', () => {
  const pre = preChannelLand()
  const real = CHANNELS.find((c) => c.id === 'severn') as Channel
  const before = landOpenedBy(pre, real)

  // A deliberate canal: the Severn, and then a jump inland to the middle of England. This is the
  // shape of the defect that was shipped — one record, two unrelated waters — and the guard has to
  // notice it. Nothing is mutated: the planted entry is a copy.
  const planted: Channel = { ...real, points: [...real.points, [52.5, -1.9]] }
  const after = landOpenedBy(pre, planted)

  // EXACT, not "more than some number". The hop from the head of the Avon (51.45, -2.6) to
  // Birmingham (52.5, -1.9) is 68.2 nm and opens SEVEN cells of dry England — measured, and pinned
  // for the same reason every other number in this file is: a control asserted loosely drifts into
  // being satisfied by rounding. The first draft of this line guessed "> 10" and went red against a
  // real 7, which is the guard catching its own author.
  expect(after).toBeGreaterThan(before)
  expect(after - before).toBe(7)
})

test('a channel that names two waters is a canal waiting to happen', () => {
  // NOT an assertion about correctness — it cannot be, because "the Dardanelles and the Bosphorus"
  // and "the Bristol Channel and the Avon" are single continuous waterways whose names join two
  // proper nouns. It is an assertion about REVIEW: the entries whose names read as two waters are
  // exactly the population the canal came from, and this pins which ones have been looked at.
  const twoWaters = CHANNELS
    .filter((c) => / and /.test(c.name))
    .map((c) => c.id)
    .sort()

  expect(twoWaters).toEqual([
    'amazon-para',         // the Pará and the Amazon mouth — one delta
    'baltic-gulfs',        // ⚠ two gulfs; worth 41 nm on tallinn→riga (LAND_CARVE_RECON §3)
    'elbe-weser',          // ⚠ two rivers; shortens no route between the ports it joins
    'gambia-senegal',      // ⚠ two rivers; shortens no route between the ports it joins
    'gironde',             // ⚠ two rivers; worth 11 nm on bordeaux→nantes
    'seto',                // the Kii and Bungo channels — both open onto the Inland Sea
    'severn',              // the Bristol Channel and the Avon — one continuous waterway
    'thames-scheldt',      // ⚠ two rivers; shortens no route between the ports it joins
    'turkish-straits',     // the Dardanelles and the Bosphorus — one continuous waterway
    'yangtze',             // the Yangtze and the Grand Canal mouth — one estuary
  ])
})
