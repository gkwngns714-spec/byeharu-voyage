import { test, expect, type Page } from '@playwright/test'
import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { ready, reachable, WORLD_BOOT_MS } from './appReady.fixture'
import { SECOND_FLEET, serveArmadaWorld } from './armada.fixture'
import { armadaMarks } from '../src/features/map/armadaMarks'
import type { MapFleet } from '../src/chart'
import type { ArmadaView } from '../src/lib/rpc'
import { parseFightLog } from '../src/live/fightLines'
import { RAID_LOG } from './raidWorld.fixture'

// ═════════════════════════════════════════════════
// AN ARMADA, ON THE GLASS (0367, docs/ARMADA.md; owner row 323: "with more than one fleet, max 6 fleet - an armada"). The path a player walks, on the built world with a
// company of two fleets in one port (tests/armada.fixture.ts): form her on the Fleets page, send her from the map on one press, see her as one mark on the chart, disband her.
// And the look laws at the phone widths in both languages: no name cut, nothing ending in dots, nothing off the glass, no sideways scroll.
// ═════════════════════════════════════════════════

const NAME = 'Grande Armada do Sul'
const GLASSES = [
  { width: 390, height: 844 },
  { width: 1280, height: 800 },
] as const

/** Pictures are written only when ARMADA_SHOTS names a folder. */
async function shot(page: Page, name: string) {
  const to = process.env.ARMADA_SHOTS
  if (!to) return
  mkdirSync(path.resolve(to), { recursive: true })
  await page.screenshot({ path: path.join(path.resolve(to), `armada-${name}.png`) })
}

async function served(request: Parameters<typeof reachable>[0], baseURL: string | undefined) {
  expect(await reachable(request, baseURL ?? ''), `nothing is served at ${baseURL}: run a preview of this build first`).toBe(true)
}

async function openFleets(page: Page) {
  await page.goto('fleets')
  await ready(page)
  await expect(page.getByTestId('fleet-row')).toHaveCount(2)
  await expect(page.getByTestId('armadas-list')).toBeVisible()
}

/** THE LOOK LAWS, read off the glass: nothing scrolls sideways, no text is cut or ends with dots, nothing stands outside the glass. */
async function laws(page: Page, where: string) {
  const broken = await page.evaluate(() => {
    const out: string[] = []
    const root = document.documentElement
    if (root.scrollWidth > root.clientWidth) out.push(`the page scrolls sideways (${root.scrollWidth} > ${root.clientWidth})`)
    const scopes = [...document.querySelectorAll('[data-testid="armadas-list"], [data-detail-page], [data-testid="map-send-armada"]')]
    for (const scope of scopes) {
      for (const el of scope.querySelectorAll<HTMLElement>('*')) {
        if (el.children.length > 0 || el.getClientRects().length === 0) continue
        const text = (el.textContent ?? '').trim()
        if (text === '') continue
        if (text.includes('…')) out.push(`"${text}" ends with dots`)
        for (let box: HTMLElement | null = el; box && box !== scope; box = box.parentElement) {
          const style = getComputedStyle(box)
          if (style.textOverflow === 'ellipsis' && box.scrollWidth > box.clientWidth + 1) {
            out.push(`"${text}" is cut (${box.scrollWidth} > ${box.clientWidth})`)
            break
          }
        }
        const r = el.getBoundingClientRect()
        if (r.width > 0 && (r.right > window.innerWidth + 1 || r.left < -1)) out.push(`"${text}" stands outside the glass`)
      }
    }
    return out
  })
  expect(broken, `${where}: ${broken.join(' | ')}`).toEqual([])
}

/** Form the armada of both fleets from the Fleets page. */
async function form(page: Page) {
  await page.getByTestId('armada-new').click()
  await expect(page.getByTestId('armada-new-page')).toBeVisible()
  const rows = page.getByTestId('armada-new-fleet')
  await expect(rows).toHaveCount(2)
  // nothing is offered until two are picked and she has a name
  await expect(page.getByTestId('armada-new-form')).toBeDisabled()
  await rows.nth(0).click()
  await rows.nth(1).click()
  await expect(page.locator('[data-testid="armada-new-fleet"][data-picked="true"]')).toHaveCount(2)
  await page.getByTestId('armada-new-name').fill(NAME)
  await expect(page.getByTestId('armada-new-form')).toBeEnabled()
}

test('the chart folds an armada at sea into one mark under her name, with every hull; in port, and with one fleet at sea, nothing is folded', () => {
  const voyage = {} as Extract<MapFleet, { kind: 'sailing' }>['voyage']
  const sea = (id: string, hulls: string[]): MapFleet => ({ kind: 'sailing', id, name: id, enduranceDays: 9, hulls, voyage })
  const quay = (id: string): MapFleet => ({ kind: 'docked', id, name: id, enduranceDays: 9, hulls: ['barca'], portCode: 'LIS' })
  const armada = (fleets: string[]): ArmadaView => ({ id: 'a', name: NAME, flagship: fleets[0], fleets, state: 'SEA', port: null, speed_kn: 5 })
  const all = [sea('one', ['nau', 'barca']), sea('two', ['barca']), sea('other', ['barca'])]
  const folded = armadaMarks(all, [armada(['one', 'two'])])
  expect(folded.map((f) => [f.id, f.name, f.hulls])).toEqual([
    ['one', NAME, ['nau', 'barca', 'barca']],
    ['other', 'other', ['barca']],
  ])
  // no armada: the very list; all in port: untouched; one at sea, one in port: untouched
  expect(armadaMarks(all, [])).toBe(all)
  const inPort = [quay('one'), quay('two')]
  expect(armadaMarks(inPort, [armada(['one', 'two'])])).toBe(inPort)
  const split = [sea('one', ['barca']), quay('two')]
  expect(armadaMarks(split, [armada(['one', 'two'])])).toBe(split)
})

test("a raid's log names the fleets of an armada above their own ships; a log with no fleets, or fleets that do not add up to its ships, names none", () => {
  const two = { ...RAID_LOG, you: [['Gaivota', 400, 400, 8], ['Andorinha do Sul', 400, 400, 8]], after: [['Gaivota', 332.1], ['Andorinha do Sul', 400]] }
  expect(parseFightLog(RAID_LOG)!.fleets).toBeNull()
  expect(parseFightLog({ ...two, fleets: [['Frota do Norte', 1], [SECOND_FLEET, 1]] })!.fleets).toEqual([
    { name: 'Frota do Norte', ships: 1 },
    { name: SECOND_FLEET, ships: 1 },
  ])
  // never a guess: three ships claimed of two, or a shape that is not [name, count]
  expect(parseFightLog({ ...two, fleets: [['Frota do Norte', 2], [SECOND_FLEET, 1]] })!.fleets).toBeNull()
  expect(parseFightLog({ ...two, fleets: [['Frota do Norte'], [SECOND_FLEET, 1]] })!.fleets).toBeNull()
})

for (const glass of GLASSES) {
  test(`${glass.width}: an armada is formed, sent on one press, drawn as one mark, and disbanded`, async ({ page, request, baseURL }) => {
    test.setTimeout(WORLD_BOOT_MS + 420_000)
    await served(request, baseURL)
    await page.setViewportSize(glass)
    await serveArmadaWorld(page)
    await openFleets(page)

    // ── FORM ──
    await form(page)
    await laws(page, 'the New armada page')
    await shot(page, `${glass.width}-1-new`)
    await page.getByTestId('armada-new-form').click()
    await expect(page.getByTestId('armada-new-page')).toHaveCount(0)
    const row = page.getByTestId('armada-row')
    await expect(row).toHaveCount(1)
    // her name and her fleets' names stand whole
    await expect(row).toContainText(NAME)
    await expect(row.getByTestId('armada-row-fleets')).toContainText(SECOND_FLEET)
    await expect(row.getByTestId('armada-total-fleets')).toContainText('2')
    await expect(row.getByTestId('armada-total-ships')).toContainText('2')
    await laws(page, 'the Fleets page with an armada')
    await shot(page, `${glass.width}-2-fleets`)
    // her page: both fleets, the flagship fleet marked, the Disband press
    await row.click()
    await expect(page.getByTestId('armada-page')).toBeVisible()
    await expect(page.getByTestId('armada-fleet')).toHaveCount(2)
    await expect(page.getByTestId('armada-disband')).toBeVisible()
    await laws(page, 'the armada page')
    await shot(page, `${glass.width}-3-page`)
    await page.locator('[data-detail-back]').last().click()

    // ── SEND, on the map ──
    await page.goto('map')
    await ready(page)
    await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: WORLD_BOOT_MS })
    const chart = (await page.getByTestId('map-chart').boundingBox())!
    for (let i = 0; i < 3; i++) {
      await page.mouse.move(chart.x + chart.width / 2, chart.y + chart.height / 2)
      await page.mouse.wheel(0, 500)
      await page.waitForTimeout(700)
    }
    // the nearest harbours of Lisbon; the first one on the glass that takes a tap
    let opened = false
    for (const code of ['CAD', 'SEV', 'OPO', 'FNC', 'TNG', 'CEU']) {
      const at = await page.evaluate((c) => {
        const g = document.querySelector(`[data-port-code="${c}"]`)
        if (!g) return null
        const r = g.getBoundingClientRect()
        return { x: r.x + r.width / 2, y: r.y + r.height / 2 }
      }, code)
      if (!at) continue
      await page.mouse.click(at.x, at.y)
      if (await page.getByTestId('map-send-fleet').isVisible().catch(() => false)) {
        opened = true
        break
      }
    }
    expect(opened, 'no harbour near Lisbon took a tap').toBe(true)
    await page.getByTestId('map-send-fleet').click()
    const armada = page.getByTestId('map-send-armada')
    await expect(armada).toHaveCount(1)
    await expect(armada).toContainText(NAME)
    await expect(armada.getByTestId('map-send-armada-fleets')).toContainText(SECOND_FLEET)
    // her fleets are not listed again under her
    await expect(page.getByTestId('map-send-row')).toHaveCount(0)
    // the order's own figures: the time, and what it costs for both fleets
    await expect(armada.getByTestId('map-send-armada-passage')).toBeVisible({ timeout: 180_000 })
    await expect(armada.getByTestId('map-send-armada-cost')).toBeVisible()
    await laws(page, 'the send list')
    await shot(page, `${glass.width}-4-send`)
    await armada.getByTestId('map-send-armada-head').click()
    await page.getByTestId('map-send-armada-send').click()
    await expect(armada).toHaveAttribute('data-state', 'SENT', { timeout: 120_000 })
    await shot(page, `${glass.width}-5-sent`)

    // ── ON THE CHART: ONE mark for both fleets (how many of her hulls a mark draws is the chart's own rule by zoom, glyphs.ts hullGroup; the fold itself is proved below) ──
    await page.getByTestId('map-detail-tray').getByTestId('tray-close').click()
    await expect.poll(async () => page.locator('[data-testid="map-fleets"] [data-hulls]').count(), { timeout: 60_000 }).toBe(1)
    await shot(page, `${glass.width}-6-chart`)

    // ── DISBAND, at sea ──
    await page.goto('fleets')
    await ready(page)
    await expect(page.getByTestId('armada-row')).toHaveCount(1)
    await page.getByTestId('armada-row').click()
    await page.getByTestId('armada-disband').click()
    await expect(page.getByTestId('armada-page')).toHaveCount(0)
    await expect(page.getByTestId('armada-row')).toHaveCount(0)
    await expect(page.getByTestId('fleet-row')).toHaveCount(2)
  })
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  for (const width of [390, 320] as const) {
    test.describe(`${locale} ${width}`, () => {
      test.use({ locale })
      test('the armada stands whole on a phone: her row, her page and the New armada page', async ({ page, request, baseURL }) => {
        test.setTimeout(WORLD_BOOT_MS + 240_000)
        await served(request, baseURL)
        await page.setViewportSize({ width, height: width === 390 ? 844 : 640 })
        await serveArmadaWorld(page)
        await openFleets(page)
        await form(page)
        await laws(page, 'the New armada page')
        await shot(page, `${locale}-${width}-new`)
        await page.getByTestId('armada-new-form').click()
        await expect(page.getByTestId('armada-row')).toHaveCount(1)
        await expect(page.getByTestId('armada-row')).toContainText(NAME)
        await laws(page, 'the Fleets page with an armada')
        await shot(page, `${locale}-${width}-fleets`)
        await page.getByTestId('armada-row').click()
        await expect(page.getByTestId('armada-page')).toBeVisible()
        await laws(page, 'the armada page')
        await shot(page, `${locale}-${width}-page`)
        if (locale === 'ko-KR') {
          // the Korean word for an armada is 대함대, apart from 선단 (a fleet)
          await expect(page.getByTestId('armada-disband')).toHaveText('해산')
          await page.locator('[data-detail-back]').last().click()
          await expect(page.getByTestId('armadas-list')).toContainText('대함대')
        }
      })
    })
  }
}
