import { test, expect } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

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
