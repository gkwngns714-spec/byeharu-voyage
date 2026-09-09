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
// Phraya, 330 nm apart, and the jump between them cut a canal through the Tenasserim mountains.
// **309 real port pairs were sold a route across it**, worst Thanlyin → Ayutthaya at 323 nm against
// 1,977 nm of actual sea. The owner's law is absolute (`OWNER_REQUESTS.md` row 41: "i don't want
// the fleet to ever touch land"). `docs/LAND_CARVE_RECON.md` carries the measurements.
//
// ── THIS FILE USED TO PIN A NUMBER THAT WAS NOT THE NUMBER IT SAID IT WAS ──────────────────────
// Until 2026-09-08 it built its "pre-channel land" by taking the FINISHED raster and closing every
// carved cell in it. That makes every carved cell read as land by construction, so the figure it
// pinned as "cells of DRY LAND opened" was the carve's own SIZE — 521 — for all 27 entries, and
// the per-entry table was identical to the carve inventory. It still bit on any change, so it was
// a working review gate; but the thing a reviewer was asked to review was the wrong quantity, and
// it ranked the entries in almost the reverse of the honest order:
//
//   * `bab-el-mandeb` headed the old table at 84. It opens **2** cells of dry land.
//   * `hormuz` sat third at 48. It opens **3**. `malacca` sat second at 52; it opens **11**.
//   * `saint-lawrence` sat fourth at 33 and is in truth the **largest land carve in the world**, 22.
//   * The canal, as shipped, carved 37 — fifth on the old table — and opened **30** cells of land,
//     which is FIRST by a wide margin. The honest measure puts the defect at the top of the page.
//
// `preCarveGrid()` now exists (scan-fill + ICE, no carve), so the question can actually be asked,
// and `assertCarveDeclared` refuses to BUILD a raster whose carve is undeclared — the generator-
// side guard `docs/LAND_CARVE_RECON.md` §5 asked for, which is where it has to live: a course over
// a carved canal is water by the raster's own account, so every SQL guard passes it and always
// would. This spec is now the second reader of that one declaration, not a second opinion about it.
//
// ── WHAT THIS CAN AND CANNOT DO, STATED HONESTLY ───────────────────────────────────────────────
// It is NOT an automatic classifier, and the numbers still say why one is not possible. Sorted by
// land opened, the St Lawrence (22), the Thames-Scheldt (17), the Gironde (15) and the Elbe-Weser
// and Gambia-Senegal (14 each) all sit ABOVE either half of the repaired river pair, because a
// river IS a line of land turned into water. **No threshold separates a strait from a canal.** A
// person has to look. So this stays a REVIEW GATE: the inventory is PINNED, a number moves when
// the carve moves, and a human decides whether the new water is real.

import { test, expect } from '@playwright/test'
import { CHANNELS, preCarveGrid, carveInventory, assertCarveDeclared, gcNm, rowOf, colOf, COLS }
  from '../scripts/sea-grid.mjs'
import type { Channel } from '../scripts/sea-grid.mjs'

/** Every cell an entry opens — its own points and the cells between consecutive points, which is
 *  exactly what `sea-grid.mjs`'s `channelCells` does. Duplicated here on purpose: a guard that
 *  called the code it guards would go green on any change they made together. The LAND DATA below
 *  is not duplicated, and must not be — "the land the raster was built from" has exactly one
 *  author, and the whole point of the slice is that the carve is checked against it. */
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

const landOpenedBy = (pre: Uint8Array, ch: Channel) =>
  [...cellsOpenedBy(ch)].filter((k) => pre[k] !== 1).length

/** Cells of DRY LAND opened, in total, across the whole list. Measured 2026-09-08. This is the
 *  number a reviewer can hold in their head, and it is what makes "the world grew some water" a
 *  sentence rather than a diff of twenty-seven rows. */
const LAND_TOTAL = 202

/** Cells CARVED in total — land and water together. A different fact, kept because it is the
 *  figure `docs/DEV_LOG.md` D39 and `docs/LAND_CARVE_RECON.md` quote, and because a carve that
 *  grew only over existing water still changed. Named separately so the two can never be confused
 *  again, which is the whole history of this file. */
const CARVE_TOTAL = 521

test('every channel opens exactly the land it declares', () => {
  const pre = preCarveGrid()

  // THE DECLARATION IS THE DATA. Recomputed here from an independent walk of the points, and
  // compared against what each entry says about itself — so this is a second reader of one number,
  // never a second copy of it.
  const actual: Record<string, number> = {}
  const declared: Record<string, number> = {}
  for (const ch of CHANNELS) {
    actual[ch.id] = landOpenedBy(pre, ch)
    declared[ch.id] = ch.opensLand
  }
  expect(actual).toEqual(declared)
  expect(Object.values(actual).reduce((a, b) => a + b, 0)).toBe(LAND_TOTAL)

  // The carve's SIZE, the other fact. 521 cells opened, of which 202 are land.
  const carved = CHANNELS.reduce((n, ch) => n + cellsOpenedBy(ch).size, 0)
  expect(carved).toBe(CARVE_TOTAL)
  expect(LAND_TOTAL).toBeLessThan(CARVE_TOTAL) // a channel is mostly water it merely re-states
})

test('the generator itself refuses an undeclared carve — the raster cannot be built', () => {
  // This is the half that lives where it matters. `assertCarveDeclared` is what `buildSeaGrid`
  // calls, so a planted canal does not produce a raster at all, in any of the five generators.
  const { opened } = carveInventory()
  expect(() => assertCarveDeclared(opened)).not.toThrow()

  const planted = new Map(opened)
  planted.set('severn', (opened.get('severn') as number) + 7)
  expect(() => assertCarveDeclared(planted)).toThrow(/severn: opens 12 cells of land, declares 5/)

  // A channel that declares nothing is refused too — otherwise a new entry could be added with the
  // field simply left off, which is exactly how a guard becomes optional.
  const missing = new Map(opened)
  missing.delete('kerch')
  expect(() => assertCarveDeclared(missing)).toThrow(/kerch: opens undefined cells of land/)
})

test('the pin BITES — a planted canal changes the count it is pinned to', () => {
  const pre = preCarveGrid()
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
  // being satisfied by rounding.
  expect(before).toBe(5)
  expect(after).toBe(12)
  expect(after - before).toBe(7)
})

test('the canal that shipped would have been the top row of this table', () => {
  // The defect, reconstructed exactly as `irrawaddy-sittaung` stood: the Yangon river's three
  // points followed by the Chao Phraya's three, one record, 330 nm between them. It is not in
  // CHANNELS any more — 0079 filled it in — so this plants it to keep the measurement that says
  // WHY the honest quantity is the one worth pinning.
  const pre = preCarveGrid()
  const canal: Channel = {
    id: 'irrawaddy-sittaung',
    name: 'the Irrawaddy and the Sittaung',
    points: [[16.3, 96.3], [16.6, 96.2], [16.8, 96.2], [13.3, 100.6], [13.6, 100.6], [14.4, 100.6]],
    opensLand: 0, // it declared nothing, which is the point
  }
  expect(cellsOpenedBy(canal).size).toBe(37)
  expect(landOpenedBy(pre, canal)).toBe(30)

  // FIRST by a wide margin against every entry that survives, where the old measure ranked it
  // fifth. That gap is the value of the slice, and it is asserted rather than described.
  const worst = Math.max(...CHANNELS.map((c) => c.opensLand))
  expect(worst).toBe(22)           // saint-lawrence
  expect(landOpenedBy(pre, canal)).toBeGreaterThan(worst)
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
