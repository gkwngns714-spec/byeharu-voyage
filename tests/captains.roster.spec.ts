import { test, expect } from '@playwright/test'
import { PHONE, closeDetail, reachable, ready } from './appReady.fixture'
import { GLASSES, readTray, trayViolations } from './trayLaw.fixture'

// YOU → CAPTAINS (0160, docs/SKILLS_AND_CAPTAINS.md K6; the roster moved from FLEETS to the YOU tab
// on 2026-10-20 with owner row 181, which asked for a personal tab and named captains in it — the same
// one face, src/live/YourCaptains.tsx, mounted on one screen): world.captains / worldCaptains serves YOUR
// captains (levels in three tracks, homesickness, the traits each uses; cmdCaptainTraitsSet chooses them).
// A freshly founded company keeps none, so the section must say so in the server-fed list's own empty
// state — and it must be there: a roster that never renders is a door nobody opens. What a captain's levels,
// cap line, homesick line and traits verb do is 0160's own self-assert (a rolled-back probe house).

test.use({ viewport: PHONE })

test('You shows your captains — none yet for a new company, with where to find one', async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('you')
  await ready(page)
  const section = page.getByTestId('your-captains')
  await expect(section).toBeVisible({ timeout: 60_000 })
  await expect(section.getByTestId('your-captains-none')).toContainText('Hire one at an inn')
  await expect(section.getByTestId('your-captain')).toHaveCount(0)
})

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A HIRED CAPTAIN'S TRAY KEEPS EACH TRAIT'S NAME ON ONE LINE (the layout sweep of 2026-11-02, row 10)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The sweep could not reach this tray: the canary house keeps no captain, so `YourCaptains` drew its one empty row and the
// code at YourCaptains.tsx:115 — a trait's sentence passed as the row's `value` — was judged by reading it. It IS reachable:
// the Inn hires, in the local world, with the purse the house starts with. Measured that way on origin/main 9a97051e (a
// captain with "Ship-supplies trader: +3% better prices on ship supplies"): the name was 79 px wide over 3 lines at 390,
// 9 px over 18 lines (one letter a line) at 320, 105 px over 2 lines at 1280. The sentence is line 2 now; this hires through
// the Inn's own screens, opens the tray at the three glasses and holds the same law the Codex's tray is held to
// (tests/trayLaw.fixture.ts). It reaches You through the Menu, which is the other half of this slice.

test("You → a hired captain's tray keeps every trait's name on one line and the tray its width — at 390×844, 320×640 and 1280×800", async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await page.goto('city')
  await ready(page)
  // HIRE: HQ → Inn → Captains → the first guest → the tray's one button. The tray closes on the server's yes.
  await page.getByTestId('city-building-inn').click()
  await page.getByTestId('city-inn-captains').click()
  const guests = page.locator('[data-testid^="guest-"]')
  await expect(guests.first(), 'the Inn seats no captain — nobody to hire').toBeVisible({ timeout: 60_000 })
  await guests.first().click()
  const inn = page.getByTestId('inn-tray')
  await inn.locator('[data-testid^="sign-"]').click()
  await expect(inn, "the hire did not land: the Inn's tray is still open").toHaveCount(0, { timeout: 60_000 })
  // YOU, by the Menu (no reload: the hire is in the tab's own world). The Captains PAGE still stands over the rail: its Back first.
  await closeDetail(page)
  await page.locator('[data-testid="nav-bar"] > button').first().click()
  await page.getByTestId('nav-group-panel').locator('a[href$="/you"]').click()
  const tile = page.getByTestId('your-captain')
  await expect(tile, 'a hired captain is not on the You tab').toHaveCount(1, { timeout: 60_000 })

  const broken: string[] = []
  let traitRows = 0
  for (const glass of GLASSES) {
    await page.setViewportSize(glass)
    await tile.click()
    const tray = page.getByTestId('your-captain-tray')
    await expect(tray.locator('[data-testid^="captain-trait-"]').first()).toBeVisible()
    const read = await readTray(page, 'your-captain-tray')
    // her trait rows and her level rows are the rows with a name and a figure; the rest (the homesick line, the promotion's
    // sentence) are SENTENCES in the label slot, which wrap by design — but nothing may stand past the tray's edge.
    broken.push(...trayViolations(read, `${glass.width}×${glass.height}`, (r) => !/^captain-(trait|level)-/.test(r.id)))
    traitRows += read.rows.filter((r) => r.id.startsWith('captain-trait-')).length
    await tray.getByTestId('tray-close').click()
    await expect(tray).toHaveCount(0)
  }
  expect(traitRows, 'no trait row was measured — the tray draws none, so nothing was proved').toBeGreaterThan(0)
  expect(broken, `a hired captain's tray is wider than itself, or a trait's name wrapped:\n${broken.join('\n')}`).toEqual([])
})
