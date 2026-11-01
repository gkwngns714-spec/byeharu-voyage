import { readFileSync } from 'node:fs'
import { expect, test } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { GLASSES, phoneLaws, readGlass } from './unfold.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HQ WITH NO CITY IN HAND (2026-11-02, the HQ-on-a-phone slice: docs/dev-log/2026-11-02-city-phone-nocity.md)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Sweep row 8: when the fleet in hand is bound for a cape or open water there is no harbour to stand in, and the HQ was ONE line — "No city in hand." — over 740 px of
// nothing at 390 (536 at 320), with no header, no doors and no way to pick another fleet. The page now says what it can: that line and YOUR FLEETS, each with what she is
// doing, the one in hand in gold, a press on one SELECTING her (bring a fleet that lies in a harbour into hand and the page is that harbour).
//
// The state is reached the way the page itself is asked for a place — `/city?port=<code>` — with a SEA_PLACE (data/sea-places.json: Cape St Vincent, `CSV`), which is
// exactly what a fleet bound for the cape makes `fleetPortCode` answer. WHAT IT HOLDS at 390×844, 320×640 and 1280×800 (and 390 / 320 in Korean): the state stands
// (the note, a row for every fleet of the house, each ≥ 44 px and saying where she is), the rail stays, the page does not scroll, it is clean by the HQ's laws
// (tests/city.phone.spec.ts), and a press moves the gold to the fleet pressed.

const cape = (JSON.parse(readFileSync('data/sea-places.json', 'utf8')) as { places: { code: string }[] }).places[0].code

async function walk(page: import('@playwright/test').Page, glass: { width: number; height: number }) {
  const at = `${glass.width}×${glass.height}`
  await page.setViewportSize(glass)
  await page.goto(`city?port=${cape}`)
  await ready(page)
  await expect(page.getByTestId('city-nocity'), `${at}: the no-city state is not on the page`).toBeVisible()
  const rows = page.getByTestId('city-nocity-fleet')
  const n = await rows.count()
  expect(n, `${at}: no fleet is listed`).toBeGreaterThanOrEqual(1)
  const found: string[] = []
  // every fleet is a pressable row, at least the 44-px floor, with a second line saying where she is
  const shape = await rows.evaluateAll((els) =>
    els.map((e) => ({
      h: e.getBoundingClientRect().height,
      // what is on the row besides her name: the where-line
      second: (e.textContent ?? '').trim().length - (e.querySelector('[data-row-cell="label"]')?.textContent ?? '').trim().length,
    })),
  )
  shape.forEach((r, i) => {
    if (r.h < 44) found.push(`${at}: fleet row ${i} is ${Math.round(r.h)} px (under 44)`)
    if (r.second === 0) found.push(`${at}: fleet row ${i} does not say what she is doing`)
  })
  // the rail stays, and the page never scrolls
  await expect(page.getByTestId('city-rail'), `${at}: the rail is gone`).toBeVisible()
  const f = await readGlass(page, 'city-nocity', null, '[data-testid="city-nocity"]')
  if (f.doc.sh > f.doc.ch) found.push(`${at}: the page scrolls (${f.doc.sh} in ${f.doc.ch})`)
  found.push(...phoneLaws(`${at} no city`, f))
  // a press selects: the gold moves to the fleet pressed
  if (n >= 2) {
    const gold = (i: number) => rows.nth(i).evaluate((e) => e.className.includes('text-accent'))
    await rows.nth(1).click()
    if (!(await gold(1))) found.push(`${at}: pressing the second fleet did not put her in hand (no gold)`)
    if (await gold(0)) found.push(`${at}: the first fleet is still in gold after the second was pressed`)
  }
  return found
}

for (const glass of GLASSES) {
  test(`the HQ with no city in hand lists your fleets and what they do, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    const found = await walk(page, glass)
    expect(found, `the no-city HQ is not right at ${glass.width}×${glass.height}:\n${found.join('\n')}`).toEqual([])
  })
}

test.describe('in Korean', () => {
  test.use({ locale: 'ko-KR' })
  for (const glass of GLASSES.filter((g) => g.width < 400)) {
    test(`the HQ with no city in hand lists your fleets and what they do, at ${glass.width}×${glass.height}`, async ({ page, request, baseURL }) => {
      test.setTimeout(300_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
      const found = await walk(page, glass)
      expect(found, `the no-city HQ is not right at ${glass.width}×${glass.height} in Korean:\n${found.join('\n')}`).toEqual([])
    })
  }
})
