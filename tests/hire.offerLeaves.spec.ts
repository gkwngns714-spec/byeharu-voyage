import { test, expect, type Page } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'
import { serveHqLit } from './hqLit.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A HIRED CAPTAIN'S OFFER LEAVES AT ONCE (owner, 2026-11-24: *"if i hire a captain by pressing a tab, that tab should then disappear"*)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Every face that offers a captain for hire, pressed in the local world, and the offer gone after the server's yes:
//   · the Inn (PortInn's room: the City page's Inn, the Office's City face and the map's city panel mount the same face). world.inn serves
//     everybody in the room with `signed`; a guest you keep is drawn no more. Before this, her tile stayed, muted.
//   · the Inn's room on HQ: hired there, HQ's crew card leaves too (her fleet has a captain now).
//   · HQ's crew card, served (0480 lit): its press hires her. Before this, world.hq_board was never asked again (a hire moves no fleet's
//     version, the board's question), so the card stayed.
// The owner's UI law: nothing above the room moves, and nothing scrolls sideways.

test.use({ viewport: PHONE })

const sideScroll = (page: Page) =>
  page.evaluate(() => {
    const over = [...document.querySelectorAll('[data-sheet], body, html')].some((el) => el.scrollWidth > el.clientWidth + 1)
    return over || document.documentElement.scrollWidth > window.innerWidth
  })

test('the Inn on HQ → hire: her tile leaves the room, and the crew card leaves HQ', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveHqLit(page, { served: true })
  await page.goto('city')
  // The room turns over on the quarter hour (0119): a press across the edge is refused E_NOT_IN_THE_ROOM (captains.roster.spec.ts).
  await ready(page, { quietMs: 60_000 })
  await expect(page.getByTestId('hq-board')).toBeVisible({ timeout: 180_000 })
  // the board draws three cards; the Crew chip (drawn only while there is such a card) brings hers up
  const crewChip = page.getByTestId('hq-filter-crew')
  await expect(crewChip, 'HQ has no Crew chip: no captain is offered').toHaveCount(1, { timeout: 180_000 })
  await crewChip.click()
  const crewCard = page.locator('[data-testid="hq-move"][data-kind="crew"]')
  await expect(crewCard, 'a fresh company has a fleet with no captain: HQ offers to hire one').toHaveCount(1, { timeout: 180_000 })
  await page.getByTestId('city-building-inn').click()
  await page.getByTestId('city-inn-captains').click()

  const guests = page.locator('[data-testid^="guest-"]:not([data-testid="guest-job-figure"])')
  await expect(guests.first(), 'the Inn seats no captain — nobody to hire').toBeVisible({ timeout: 120_000 })
  const before = await guests.count()
  const id = (await guests.first().getAttribute('data-testid'))!
  const head = page.getByTestId('inn-room-head')
  // where the room's head stands in the Inn (the page may scroll under the press; this is the layout, not the scroll)
  const headAt = async () => (await head.boundingBox())!.y - (await page.getByTestId('port-inn').boundingBox())!.y
  const headY = await headAt()
  await guests.first().click()
  const tray = page.getByTestId('inn-tray')
  await tray.locator('[data-testid^="sign-"]').click()
  await expect(tray, "the hire did not land: the Inn's tray is still open").toHaveCount(0, { timeout: 60_000 })
  await expect(page.getByTestId(id), 'the hired captain is still offered in the room').toHaveCount(0, { timeout: 30_000 })
  await expect(guests).toHaveCount(before - 1)
  expect(await headAt(), 'the hire moved what stands above the room').toBe(headY)
  expect(await sideScroll(page), 'the room scrolls sideways').toBe(false)

  // back to HQ: her fleet has a captain, so the card that offered one is gone
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('hq-board')).toBeVisible({ timeout: 180_000 })
  await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
  await expect(crewChip, 'HQ still offers to hire a captain for the fleet she joined').toHaveCount(0, { timeout: 60_000 })
  await expect(crewCard, 'HQ still offers to hire a captain for the fleet she joined').toHaveCount(0, { timeout: 60_000 })
})

test('HQ crew card (served, 0480 lit): one press hires her and the card leaves', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveHqLit(page, { served: true })
  await page.goto('city')
  await ready(page, { quietMs: 60_000 })
  await expect(page.getByTestId('hq-board')).toHaveAttribute('data-source', 'served', { timeout: 180_000 })
  // the board draws three cards; the Crew chip (drawn only while there is such a card) brings hers up
  const crewChip = page.getByTestId('hq-filter-crew')
  await expect(crewChip, 'HQ has no Crew chip: no captain is offered').toHaveCount(1, { timeout: 180_000 })
  await crewChip.click()
  const crewCard = page.locator('[data-testid="hq-move"][data-kind="crew"]')
  await expect(crewCard, 'the served board offers a captain for the fleet with none').toHaveCount(1, { timeout: 180_000 })
  await expect(crewCard).toHaveAttribute('data-act', 'cmd.hire_officer')
  await crewCard.scrollIntoViewIfNeeded()
  await crewCard.click()
  await expect(crewCard, 'the hired captain is still offered on HQ').toHaveCount(0, { timeout: 60_000 })
  await expect(page.getByTestId('hq-move-refusal')).toHaveCount(0)
  expect(await sideScroll(page), 'HQ scrolls sideways').toBe(false)
})
