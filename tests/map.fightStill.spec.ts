import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { reachable, ready } from './appReady.fixture'
import { RAID_PIRATE_FLEET, serveRaidTickWorld } from './fightWorld.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// A FIGHT ON THE MAP: ITS SHIPS ARE AT IT AND STAND STILL, ITS CARD COMES FIRST, ITS RING GOES WITH IT (owner 2026-11-15:
// "when clicking the red circle, i want to see the info like before, but at top there will be watch ... ships inside the
// circle still move ... and fight was made even though there was no pirate").
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// The world is tests/fightWorld.fixture.ts `raidTickWorld`: a raid as prod fights it (read 2026-11-15). The raider lies
// DOCKED in a harbour 60 to 240 nm from the cargo ship she sets upon; the cargo ship is under sail and the server holds her.
//   1. WHILE IT IS FOUGHT both fleets are drawn inside the ring, each on the red ground, and neither moves on the glass.
//   2. A PRESS ON THE RING opens the fight's CARD (what it is, the fleets and ships, each side by name) with Watch at the
//      top, and NOT the battle screen. Watch opens the battle screen.
//   3. WHEN IT ENDS the ring goes, nobody is on a red ground, the raider is back in her harbour (outside where the ring
//      was) and the cargo ship sails on.
// Run it: npm run build && npm run preview, then `npx playwright test map.fightStill.spec.ts`.
// Screenshots go to test-results/fight-still (or FIGHT_STILL_SHOTS; FIGHT_STILL_TAG names the set).

const SHOTS = process.env.FIGHT_STILL_SHOTS ? path.resolve(process.env.FIGHT_STILL_SHOTS) : path.resolve('test-results', 'fight-still')
const TAG = process.env.FIGHT_STILL_TAG ?? 'now'

test.beforeAll(() => mkdirSync(SHOTS, { recursive: true }))

interface Mark {
  id: string
  x: number
  y: number
  red: boolean
  kind: string
}

interface Ring {
  x: number
  y: number
  r: number
}

/** The ring (centre and radius on the glass) and every ship mark drawn, by the centre of its hulls' box. */
async function scene(page: Page): Promise<{ ring: Ring | null; marks: Mark[] }> {
  return page.evaluate(() => {
    const ringEl = document.querySelector('[data-testid="map-fight-ring"] circle')
    const rb = ringEl?.getBoundingClientRect()
    const ring = rb && rb.width > 0 ? { x: rb.left + rb.width / 2, y: rb.top + rb.height / 2, r: rb.width / 2 } : null
    const marks = [...document.querySelectorAll('[data-testid="map-merchant"]')].map((el) => {
      const b = el.getBoundingClientRect()
      return {
        id: el.getAttribute('data-merchant-id') ?? '',
        x: b.left + b.width / 2,
        y: b.top + b.height / 2,
        red: el.getAttribute('data-in-fight') === 'true',
        kind: el.getAttribute('data-ship-kind') ?? 'merchant',
      }
    })
    return { ring, marks }
  })
}

const inside = (m: Mark, ring: Ring) => Math.hypot(m.x - ring.x, m.y - ring.y) <= ring.r + 1

for (const size of [
  { width: 1280, height: 800 },
  { width: 390, height: 844 },
]) {
  test.describe(`a raid on the map, at ${size.width}×${size.height}`, () => {
    test.use({ viewport: size, locale: 'en-US' })

    test('both fleets stand in the ring; the ring opens the card, Watch the battle; the ring goes when the fight ends', async ({ page, request, baseURL }) => {
      test.setTimeout(600_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` (or set PLAYWRIGHT_BASE_URL) and re-run`)
      await serveRaidTickWorld(page)
      await page.goto('map')
      await ready(page)
      await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
      const ringEl = page.getByTestId('map-fight-ring').first()
      await expect(ringEl, 'the raid the fixture opens is ringed').toBeVisible({ timeout: 90_000 })
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-1-ring-${size.width}.png`) })

      // closer, so 30 nm is wide on the glass and a ship that sails is seen to move
      const far = (await scene(page)).ring!
      await page.mouse.move(far.x, far.y)
      for (let i = 0; i < 6; i++) {
        await page.mouse.wheel(0, -400)
        await page.waitForTimeout(250)
      }
      await page.waitForTimeout(800)

      // ── 1. BOTH FLEETS ARE IN THE RING, ON THE RED GROUND, AND STAND STILL ──
      const a = await scene(page)
      expect(a.ring, 'the ring is still on the glass after the zoom').not.toBeNull()
      const redIn = a.marks.filter((m) => m.red && inside(m, a.ring!))
      const redOut = a.marks.filter((m) => m.red && !inside(m, a.ring!))
      console.log(`[${TAG} ${size.width}] ring r=${a.ring!.r.toFixed(0)}px; red marks inside ${redIn.length} (${redIn.map((m) => m.kind).join(', ')}), red marks outside ${redOut.length} (${redOut.map((m) => m.kind).join(', ')})`)
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-2-zoomed-${size.width}.png`) })
      await page.waitForTimeout(6_000)
      const b = await scene(page)
      const moved = redIn.map((m) => {
        const now = b.marks.find((x) => x.id === m.id)
        return now ? Math.hypot(now.x - m.x, now.y - m.y) : Number.NaN
      })
      console.log(`[${TAG} ${size.width}] in 6 s the fight's marks moved ${moved.map((d) => d.toFixed(1)).join(', ')} px`)
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-3-six-seconds-later-${size.width}.png`) })
      expect(redOut, 'no ship of the fight is drawn outside its ring').toHaveLength(0)
      expect(redIn.map((m) => m.kind).sort(), 'the raider and the ship she set upon are both in the ring').toEqual(['cargo', 'pirate'])
      for (const d of moved) expect(d, 'a ship in a fight does not move').toBeLessThan(1)

      // ── 2. THE RING OPENS THE CARD, NOT THE BATTLE; WATCH IS AT ITS TOP ──
      await page.mouse.click(b.ring!.x, b.ring!.y - b.ring!.r + 6)
      const sheet = page.getByTestId('fight-sheet')
      await expect(sheet).toBeVisible()
      await page.waitForTimeout(600)
      await expect(page.getByTestId('battle-screen'), 'a press on the ring does not open the battle screen').toHaveCount(0)
      await expect(page.getByTestId('fight-sheet-name')).toHaveText('Raid')
      await expect(page.getByTestId('fight-sheet-name-line')).toContainText('2 fleets')
      await expect(page.getByTestId('fight-sheet-name-line')).toContainText('Watching')
      await expect(page.getByTestId('fight-side-attacker').getByTestId('fight-side-fleet')).toHaveText(RAID_PIRATE_FLEET)
      await expect(page.getByTestId('fight-side-attacker')).toContainText('Pirate ship')
      await expect(page.getByTestId('fight-side-defender').getByTestId('fight-side-row')).toHaveCount(1)
      await expect(page.getByTestId('fight-side-defender')).toContainText('Cargo ship')
      const watch = page.getByTestId('fight-sheet-watch')
      await expect(watch).toBeVisible()
      const wy = (await watch.boundingBox())!.y
      const sy = (await page.getByTestId('fight-side-attacker').boundingBox())!.y
      expect(wy, 'Watch stands above the sides').toBeLessThan(sy)
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-4-card-${size.width}.png`) })
      await watch.click()
      await expect(page.getByTestId('battle-screen'), 'Watch opens the battle screen').toBeVisible()
      await expect(page.getByTestId('battle-body')).toBeVisible({ timeout: 30_000 })
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-5-watch-${size.width}.png`) })
      await page.getByTestId('battle-close').click()
      await expect(page.getByTestId('battle-screen')).toHaveCount(0)
      await expect(sheet, 'the card is still there under it').toBeVisible()

      // ── 3. THE FIGHT ENDS: THE RING GOES, NOBODY IS RED, THE RAIDER IS HOME, THE SHIP SAILS ON ──
      const was = b.ring!
      const ship = redIn.find((m) => m.kind === 'cargo')!
      await expect(page.getByTestId('map-fight-ring'), 'the ring goes when the fight ends').toHaveCount(0, { timeout: 120_000 })
      await page.waitForTimeout(1_500)
      const c = await scene(page)
      expect(c.marks.filter((m) => m.red), 'nobody is on a red ground once it is over').toHaveLength(0)
      const pirate = c.marks.find((m) => m.kind === 'pirate')
      if (pirate) expect(inside(pirate, was), 'the raider is back in her harbour, not where the ring was').toBe(false)
      await page.waitForTimeout(8_000)
      const d = await scene(page)
      const from = c.marks.find((m) => m.id === ship.id)
      const to = d.marks.find((m) => m.id === ship.id)
      const sailed = from && to ? Math.hypot(to.x - from.x, to.y - from.y) : Number.NaN
      console.log(`[${TAG} ${size.width}] after the fight the ship moved ${sailed.toFixed(1)} px in 8 s`)
      await page.screenshot({ path: path.join(SHOTS, `${TAG}-6-after-${size.width}.png`) })
      expect(sailed, 'the ship set upon sails on when the fight ends').toBeGreaterThan(1)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    })
  })
}
