// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE HARBOUR'S MERCHANTS — who this city concerns, and what each one is doing (owner row 121)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-11: *"By clicking the city, i get to see what trading ships started, resting,
// ending etc."* Migration 0104 serves that from facts the schema already held — the route's stops
// and cursor, its hold (0101's fortnight) and its pause, and where the fleet is — and this spec
// reads it back off the real screen.
//
// WHAT IS PROVED HERE, and what is deliberately NOT. The six words themselves and the rule that
// derives each are proved where they are derived: migration 0104's self-assert plants one fact at
// a time on probe companies and reads the word back, with positive controls that were watched go
// red. A browser cannot plant facts, so this spec proves the things only a browser can:
//   · the section is THERE, with a word and a loop on every row, in the server's order;
//   · the harbour lists merchants that are NOT in it — the half of the owner's sentence 0099
//     could not show, and the reason this is its own read rather than a filter over the chart's;
//   · a row still opens the same read-only merchant sheet;
//   · and with the shipped image — merchants dark — the section is not there at all.
//
// The merchants ship DARK, so the lit case is served the merchants-on world image by
// tests/npcOn.fixture.ts, exactly as tests/map.merchants.spec.ts is.

import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { PHONE, reachable, ready } from './appReady.fixture'
import { LAID_UP_AT_LISBON, serveNpcOn } from './npcOn.fixture'

const SHOTS = path.resolve('docs', 'npc-traders')

/** The six words, in the order the server ranks them (migration 0104). The client spells them in
 *  src/features/port/MerchantsHere.tsx; this is the same list, read as the contract it is. */
const WORDS = ['Laid up', 'Resting', 'Starting', 'Ending', 'Passing', 'Away'] as const

/** Every row of the section, as the three things a player reads on it. */
async function harbourRows(
  page: Page,
): Promise<{ title: string; line: string; doing: string; loop: string }[]> {
  return page.evaluate(() => {
    const out: { title: string; line: string; doing: string; loop: string }[] = []
    for (const row of document.querySelectorAll('[data-testid="port-merchant-row"]')) {
      const label = row.querySelector('span')
      const lines = label ? [...label.querySelectorAll(':scope > span')] : []
      out.push({
        title: (lines[0]?.textContent ?? '').trim(),
        line: (lines[1]?.textContent ?? '').trim(),
        doing: (row.querySelector('[data-testid="port-merchant-doing"]')?.textContent ?? '').trim(),
        loop: (row.querySelector('[data-testid="port-merchant-loop"]')?.textContent ?? '').trim(),
      })
    }
    return out
  })
}

test.use({ viewport: PHONE })

test('the harbour names its merchants, what each is doing, and the loop that brings her', async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  mkdirSync(SHOTS, { recursive: true })
  await serveNpcOn(page)
  await page.goto('port')
  await ready(page)

  const section = page.getByTestId('port-merchants')
  await expect(section).toBeVisible({ timeout: 60_000 })
  // THE HEADING IS A NAME, not a description of the filter: the section is no longer only the
  // merchants IN port (docs/WORDS.md law 1, docs/UI_DIRECTION.md §4).
  await expect(section.getByText('Merchants', { exact: true })).toBeAttached()

  // LISBON SITS ON SEVERAL MERCHANT LOOPS, so the list is not one row by accident.
  await expect.poll(async () => (await harbourRows(page)).length, { timeout: 60_000 }).toBeGreaterThanOrEqual(2)
  const rows = await harbourRows(page)

  // EVERY ROW CARRIES ONE OF THE SIX WORDS, AND A LOOP THAT REALLY CALLS HERE. A loop is two to
  // eight harbours and returns to the first (0101), so the `→` is always there, and Lisbon is in
  // it — that is what put her on this list.
  for (const r of rows) {
    expect(WORDS, `"${r.doing}" on ${r.title}`).toContain(r.doing)
    expect(r.loop, `the loop of ${r.title}`).toContain('→')
    expect(r.loop, `the loop of ${r.title}`).toContain('Lisbon')
    expect(r.title, 'a row names the company and the fleet').toContain(' · ')
  }

  // THE ORDER IS THE SERVER'S — the ones lying here first, then the ones coming, then the rest.
  const ranks = rows.map((r) => WORDS.indexOf(r.doing as (typeof WORDS)[number]))
  expect(ranks, `the words came back as ${rows.map((r) => r.doing).join(', ')}`).toEqual(
    [...ranks].sort((a, b) => a - b),
  )

  // THE HALF 0099 COULD NOT SHOW: a merchant whose loop calls here and who is NOT in the harbour.
  // Her line is `to <somewhere> · <when>` (she is at sea) or another harbour's name, never this
  // one's, and her word is one of the three that are not about lying at this quay.
  const elsewhere = rows.filter((r) => !r.line.startsWith('Lisbon'))
  expect(
    elsewhere.length,
    `every row was a merchant lying in Lisbon: ${rows.map((r) => `${r.doing} / ${r.line}`).join(' | ')}`,
  ).toBeGreaterThanOrEqual(1)
  for (const r of elsewhere) {
    expect(['Ending', 'Passing', 'Away'], `${r.title} is not in Lisbon but reads "${r.doing}"`).toContain(r.doing)
  }

  // THE MERCHANT THE FIXTURE LAID UP AT LISBON reads the word docs/WORDS.md keeps for a merchant
  // that cannot sail on, and her line is this harbour's.
  const laidUp = rows.find((r) => r.title.includes(LAID_UP_AT_LISBON))
  expect(laidUp, `${LAID_UP_AT_LISBON} is not on Lisbon's list`).toBeTruthy()
  expect(laidUp?.doing).toBe('Laid up')
  expect(laidUp?.line.startsWith('Lisbon')).toBe(true)
  await page.screenshot({ path: path.join(SHOTS, 'port-merchants-doing-390.png') })

  // AND A ROW STILL OPENS THE SAME READ-ONLY SHEET — one sheet, opened from the chart and from here.
  const row = section.getByTestId('port-merchant-row').filter({ hasText: LAID_UP_AT_LISBON })
  await expect(row).toHaveCount(1)
  await row.click()
  await expect(page.getByTestId('merchant-sheet')).toBeVisible()
  await expect(page.getByTestId('merchant-sheet-name')).toHaveText(LAID_UP_AT_LISBON, { timeout: 60_000 })
  await expect(page.getByTestId('merchant-sheet-body')).toBeVisible({ timeout: 60_000 })
  // READ-ONLY, here as on the chart: the only buttons are the tray's own.
  const sheet = page.getByTestId('merchant-sheet')
  const labels = await sheet
    .locator('button')
    .evaluateAll((bs) => bs.map((b) => b.getAttribute('aria-label') ?? b.textContent ?? ''))
  expect(labels.length).toBeGreaterThan(0)
  for (const l of labels) expect(l).toMatch(/^(Close|Resize)$/)
  await page.screenshot({ path: path.join(SHOTS, 'port-merchant-sheet-from-harbour-390.png') })
})

test('with the shipped image (merchants dark) a harbour names no merchants at all', async ({
  page,
  request,
  baseURL,
}) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('port')
  await ready(page)
  await expect(page.getByTestId('port')).toBeVisible()
  // longer than one of the shell's 3-s beats, so the harbour's read would have landed
  await page.waitForTimeout(7_000)
  await expect(page.getByTestId('port-merchants')).toHaveCount(0)
  await expect(page.getByTestId('port-merchant-row')).toHaveCount(0)
})
