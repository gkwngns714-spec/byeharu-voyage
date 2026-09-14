import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A PRESS AFTER A TEXT SELECTION MUST ACT — the owner, 2026-09-14, desktop Chrome:
//   "when i drag to copy paste multiple words, i can't seem to press anything else."
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHAT WAS FOUND, measured on the built app before the fix (docs/DEV_LOG.md, 2026-09-14). A mouse
// selection over the trade board, a tray, the Menu tray, the chart, the Codex, Command, Fleets,
// History, Rank and Profile — twenty-three drags in Chromium and six on the live site in the
// owner's own Chrome — never stopped a press. ONE thing did, deterministically: a drag INSIDE the
// port field (the natural place to copy a harbour's name). Its focus empties the field and stands
// ten harbour chips under it IN FLOW, so the whole board drops (the first live buy cell from
// y=330 to y=434 at 1545 px). The next press anywhere lands on that lowered board: its MOUSEDOWN
// blurs the field, the field's blur exit unmounted the chips, the board jumped back up 104 px, and
// the MOUSEUP landed on something else — Chrome fires no click across two elements, and the press
// opened nothing. One dead press per visit to the field, each time.
//
// The fix is in `src/features/port/PortField.tsx` and it is one decision: the picker folds on a
// pick, on Escape, or AFTER a press has landed outside it (`click`) — never on a blur, which is a
// mousedown-time signal. These proofs press where the control STANDS at the moment of the press,
// exactly as a hand does, and require the press to have acted.

const DESKTOP = { width: 1545, height: 900 }
test.use({ viewport: DESKTOP })

/** A person's drag: down, a first small move, the sweep, up. */
async function drag(page: Page, from: { x: number; y: number }, to: { x: number; y: number }) {
  await page.mouse.move(from.x, from.y)
  await page.mouse.down()
  await page.mouse.move(from.x + 5, from.y + 1, { steps: 3 })
  await page.mouse.move(to.x, to.y, { steps: 12 })
  await page.mouse.up()
  await page.waitForTimeout(100)
}

/** Press a control at the centre of where it stands NOW — `locator.click()` would scroll and
 *  re-measure, which is not what a hand does after the board has moved. */
async function pressWhereItStands(page: Page, target: import('@playwright/test').Locator) {
  const box = await target.boundingBox()
  expect(box, 'the control to press has no box').not.toBeNull()
  await page.mouse.click(box!.x + box!.width / 2, box!.y + box!.height / 2)
  await page.waitForTimeout(400)
}

function up() {
  return async ({ request, baseURL }: { request: { get: (url: string) => Promise<{ ok(): boolean }> }; baseURL?: string }) => {
    test.setTimeout(420_000)
    test.skip(
      !(await reachable(request, baseURL ?? '')),
      `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`,
    )
  }
}

test.beforeEach(up())

test('PORT: a drag inside the port field, then a press on a buy cell — the press acts', async ({ page }) => {
  await page.goto('port')
  await ready(page)
  const field = page.getByTestId('port-field')
  const home = await field.inputValue()
  expect(home, 'the port field names no harbour at rest').not.toBe('')

  const buy = page.locator('[data-testid="trade-row"] button:not([disabled])').first()
  const rest = await buy.boundingBox()

  // The owner's drag: across the harbour's name, inside the field.
  const f = await field.boundingBox()
  await drag(page, { x: f!.x + 42, y: f!.y + f!.height / 2 }, { x: f!.x + 140, y: f!.y + f!.height / 2 })

  // The field is open: chips stand under it and the board has moved down (the inline unfold).
  await expect(page.getByTestId('port-chip').first()).toBeVisible()
  const opened = await buy.boundingBox()
  expect(opened!.y, 'the chips did not unfold under the field').toBeGreaterThan(rest!.y)

  // Press the buy cell WHERE IT STANDS. Before the fix this press died: the mousedown folded the
  // chips, the cell jumped back up under the pointer, and the mouseup landed on another element.
  await pressWhereItStands(page, buy)
  await expect(page.getByTestId('trade-tray'), 'the press after a drag in the port field opened nothing').toBeVisible()
  await expect(buy).toHaveAttribute('aria-pressed', 'true')

  // …and the picker folded AFTER the press landed: name back, chips gone.
  await expect(field).toHaveValue(home)
  await expect(page.getByTestId('port-chip')).toHaveCount(0)
})

test('PORT: a press into the port field, then a press on a buy cell — the press acts', async ({ page }) => {
  await page.goto('port')
  await ready(page)
  const field = page.getByTestId('port-field')
  const home = await field.inputValue()
  await pressWhereItStands(page, field)
  await expect(page.getByTestId('port-chip').first()).toBeVisible()

  const buy = page.locator('[data-testid="trade-row"] button:not([disabled])').first()
  await pressWhereItStands(page, buy)
  await expect(page.getByTestId('trade-tray'), 'the press after focusing the port field opened nothing').toBeVisible()
  await expect(field).toHaveValue(home)
})

test('PORT: with the picker open, a chip still picks and Escape still leaves', async ({ page }) => {
  await page.goto('port')
  await ready(page)
  const field = page.getByTestId('port-field')
  const home = await field.inputValue()

  await pressWhereItStands(page, field)
  const other = page.getByTestId('port-chip').filter({ hasNotText: home }).first()
  const there = (await other.innerText()).trim()
  await pressWhereItStands(page, other)
  await expect(field, 'a chip press no longer picks').toHaveValue(there)
  await expect(page.getByTestId('port-chip')).toHaveCount(0)

  await pressWhereItStands(page, field)
  await expect(page.getByTestId('port-chip').first()).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(field, 'Escape no longer leaves').toHaveValue(there)
  await expect(page.getByTestId('port-chip')).toHaveCount(0)
})

test('PORT: a selection swept across the board, ending on the nav bar, then a nav press — it acts', async ({ page }) => {
  await page.goto('port')
  await ready(page)
  const first = await page.getByTestId('trade-row').nth(0).boundingBox()
  const nav = await page.getByTestId('nav-bar').boundingBox()
  await drag(page, { x: first!.x + 4, y: first!.y + 10 }, { x: nav!.x + 300, y: nav!.y + 20 })
  const selected = await page.evaluate(() => (document.getSelection()?.toString() ?? '').trim())
  expect(selected.length, 'the sweep selected nothing — this proof measured no selection').toBeGreaterThan(20)

  await pressWhereItStands(page, page.getByTestId('nav-cell-/command'))
  expect(new URL(page.url()).pathname, 'the nav press after a selection did not route').toMatch(/\/command$/)
})
