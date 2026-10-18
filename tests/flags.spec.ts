import { test, expect, type Locator, type Page } from '@playwright/test'
import { mkdirSync, readdirSync, readFileSync, statSync } from 'node:fs'
import path from 'node:path'
import { FLAG_ADVANCE_EM, mapLabelRequests, planLabels } from '../src/chart/labels'
import { buildChartModel } from '../src/chart/chartModel'
import type { MapPort } from '../src/chart/mapTypes'
import { PHONE, reachable, ready } from './appReady.fixture'
import { openCityFace } from './desk.fixture'
import { openCityPanel } from './openCity.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE FLAGS (the owner, 2026-10-18): "flag images for each city … find country flags, apply to our
// game to make the game more visual. like beside the name show flag that are influenced by, when
// pressing a ship or city, also show flag".
//
//   * every nation the migrations seed has a bundled flag (public/flags/<code>.svg), and every flag
//     there belongs to a nation and is listed with its source and licence in SOURCES.md; each file
//     is small and carries no script, no stylesheet and no reference outside itself;
//   * a harbour's name on the chart carries its holder's flag, and the planner keeps room for it;
//   * driven at 1440×900 and 390×844: the chart's names, a pressed city (its name, its holder, the
//     Town Hall's standings), a pressed fleet and her ship, and a merchant's sheet each draw the
//     flag through the design system's Flag, and the picture loads.
//
// Screenshots: docs/dev-log/2026-10-18-flags/. Run it: npm run build && npx vite preview --port 4280,
// then PLAYWRIGHT_BASE_URL=http://localhost:4280/byeharu-voyage/ npx playwright test flags.spec.ts
// ═══════════════════════════════════════════════════════════════════════════════════════════════

const ROOT = process.cwd()
const FLAGS = path.join(ROOT, 'public', 'flags')
const SHOTS = path.join(ROOT, 'docs', 'dev-log', '2026-10-18-flags')
const WIDE = { width: 1440, height: 900 }

/** Every nation code the migration chain seeds (`insert into public.nations … values ('PRT', …)`). */
function seededNations(): string[] {
  const dir = path.join(ROOT, 'supabase', 'migrations')
  const codes = new Set<string>()
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.sql'))) {
    const sql = readFileSync(path.join(dir, f), 'utf8')
    for (const block of sql.matchAll(/insert into public\.nations\b[\s\S]*?on conflict/gi)) {
      for (const m of block[0].matchAll(/\(\s*'([A-Z]{3})'\s*,/g)) codes.add(m[1])
    }
  }
  return [...codes].sort()
}

test('every nation has a bundled, listed, small and clean flag — and every flag has a nation', () => {
  const nations = seededNations()
  expect(nations.length, 'the chain seeds the nations').toBeGreaterThanOrEqual(23)
  const files = readdirSync(FLAGS).filter((f) => f.endsWith('.svg')).map((f) => f.replace(/\.svg$/, '')).sort()
  expect(files).toEqual(nations)
  const sources = readFileSync(path.join(FLAGS, 'SOURCES.md'), 'utf8')
  let total = 0
  for (const code of nations) {
    expect(sources, `${code} has a row in SOURCES.md`).toMatch(new RegExp(`^\\| ${code} \\|.*\\| ${code}\\.svg \\|`, 'm'))
    const file = path.join(FLAGS, `${code}.svg`)
    const bytes = statSync(file).size
    total += bytes
    expect(bytes, `${code}.svg is small`).toBeLessThanOrEqual(24 * 1024)
    const svg = readFileSync(file, 'utf8')
    expect(svg, `${code}.svg is an svg with a viewBox`).toMatch(/^<svg [^>]*viewBox="/)
    expect(svg, `${code}.svg has no script, style, image or foreign object`).not.toMatch(/<(script|style|image|foreignObject)\b/i)
    expect(svg, `${code}.svg has no event handler`).not.toMatch(/\son[a-z]+=/i)
    expect(svg, `${code}.svg points at nothing outside itself`).not.toMatch(/(href="[^#]|url\((?!#))/i)
  }
  expect(total, 'the whole set').toBeLessThanOrEqual(80 * 1024)
})

test('a harbour\'s name on the chart carries its holder\'s code, and the planned box makes room for the flag', () => {
  const ports: MapPort[] = [
    { code: 'LIS', name: 'Lisbon', lat: 38.7, lon: -9.1, sizeTier: 3 } as MapPort,
    { code: 'OPO', name: 'Porto', lat: 41.1, lon: -8.6, sizeTier: 3 } as MapPort,
  ]
  const model = buildChartModel([], ports)
  const requests = mapLabelRequests(model, ports, null, true, new Map([['LIS', 'PRT']]))
  const lis = requests.find((r) => r.id === 'port:LIS')
  expect(lis?.text).toBe('Lisbon')
  expect(lis?.flag).toBe('PRT')
  expect(requests.find((r) => r.id === 'port:OPO')?.flag).toBeUndefined()
  const viewBox = { x: -2000, y: -2000, width: 4000, height: 4000 }
  const opts = { viewBox, unitsPerPx: 1, fontSizePx: 10 }
  const flagged = planLabels([lis!], opts)[0]
  const bare = planLabels([{ ...lis!, flag: undefined }], opts)[0]
  expect(flagged.flag).toBe('PRT')
  expect(flagged.box.width - bare.box.width).toBeCloseTo(FLAG_ADVANCE_EM * 10, 5)
})

test('every flag is recognisable at 14 px: its picture is not near-uniform (a pixel-variance check, border excluded)', async ({ browser }) => {
  // THE DEFECT (the owner, 2026-10-18: "france flag looks shit"): France's royal white flag with
  // tiny fleurs-de-lis rasterised to a blank cream chip at 12–16 px (σ 12–27), Morocco's thin gold
  // lines to a red chip (σ 15–29), Ayutthaya's plain red to a red chip (σ 0). Each flag is drawn at
  // 21×14 CSS px at DPR 1 and 2, its outer 2 device px (the hairline edge) cropped off, and the
  // RGB standard deviation of what is left must be at least 35 — a flag with a design you can see.
  const sigma: Record<string, number> = {}
  for (const dpr of [1, 2]) {
    const context = await browser.newContext({ viewport: { width: 600, height: 400 }, deviceScaleFactor: dpr })
    const page = await context.newPage()
    for (const code of seededNations()) {
      const uri = `data:image/svg+xml;base64,${readFileSync(path.join(FLAGS, `${code}.svg`)).toString('base64')}`
      await page.setContent(`<body style="margin:0;background:#f4f1e8"><img id="f" src="${uri}" width="21" height="14" style="object-fit:contain;display:block">`)
      await page.locator('#f').evaluate((i: HTMLImageElement) => i.decode())
      const png = await page.locator('#f').screenshot()
      sigma[`${code}@${dpr}`] = await page.evaluate(async ([b64, crop]) => {
        const img = new Image()
        img.src = `data:image/png;base64,${b64}`
        await img.decode()
        const c = new OffscreenCanvas(img.width, img.height)
        const g = c.getContext('2d')!
        g.drawImage(img, 0, 0)
        const d = g.getImageData(crop, crop, img.width - 2 * crop, img.height - 2 * crop).data
        const n = d.length / 4
        const m = [0, 0, 0]
        for (let i = 0; i < d.length; i += 4) for (let k = 0; k < 3; k++) m[k] += d[i + k] / n
        let v = 0
        for (let i = 0; i < d.length; i += 4) for (let k = 0; k < 3; k++) v += (d[i + k] - m[k]) ** 2
        return Math.round(Math.sqrt(v / n))
      }, [png.toString('base64'), 2 * dpr] as const)
    }
    await context.close()
  }
  console.log('flag σ at 14 px:', JSON.stringify(sigma))
  for (const [k, s] of Object.entries(sigma)) expect(s, `${k} is not a blank chip`).toBeGreaterThanOrEqual(35)
})

/** Every Flag under `scope` names a nation and its picture has loaded (not a broken image). */
async function expectFlags(scope: Locator, nation?: string): Promise<void> {
  const flags = scope.locator('img[data-testid="flag"]')
  await expect(flags.first()).toBeVisible({ timeout: 60_000 })
  if (nation) await expect(scope.locator(`img[data-testid="flag"][data-nation="${nation}"]`).first()).toBeVisible()
  await expect
    .poll(async () => flags.evaluateAll((imgs) => imgs.every((i) => (i as HTMLImageElement).complete && (i as HTMLImageElement).naturalWidth > 0)), { timeout: 30_000 })
    .toBe(true)
  const titles = await flags.evaluateAll((imgs) => imgs.map((i) => i.getAttribute('title') ?? ''))
  for (const t of titles) expect(t.length, 'a flag says whose it is').toBeGreaterThan(2)
}

async function openMap(page: Page) {
  await page.goto('map')
  await ready(page)
  await page.waitForSelector('[data-testid="map-ports"] > g', { timeout: 300_000 })
}

for (const [glass, size] of [['1440', WIDE], ['390', PHONE]] as const) {
  test(`${glass}: the chart's names, a pressed city and a pressed fleet and ship all fly their flags`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    mkdirSync(SHOTS, { recursive: true })
    await page.setViewportSize(size)
    await openMap(page)

    // THE CHART: harbour names carry an <image> of their holder's flag, and it is a served file.
    await expect.poll(() => page.locator('[data-testid="map-labels"] [data-label-flag]').count(), { timeout: 120_000 }).toBeGreaterThan(0)
    const href = await page.locator('[data-testid="map-labels"] [data-label-flag] image').first().getAttribute('href')
    expect(href).toMatch(/flags\/[A-Z]{3}\.svg$/)
    expect((await request.get(new URL(href!, page.url()).toString())).ok()).toBe(true)
    await page.waitForTimeout(800)
    await page.screenshot({ path: path.join(SHOTS, `map-${glass}.png`) })

    // A CITY PRESSED: Lisbon's name carries Portugal's flag; the line under it names the holder.
    await openCityPanel(page, 'LIS', 'Lisbon')
    await expectFlags(page.getByTestId('map-place-name'), 'PRT')
    await expect(page.getByTestId('city-flag').first()).toContainText('Portugal')
    await page.waitForTimeout(400)
    await page.screenshot({ path: path.join(SHOTS, `city-${glass}.png`) })
    // …and its Town Hall's holder (and standings, when any) draw flags through the same Flag.
    await page.getByTestId('map-send-fleet').click()
    await page.getByTestId('map-city-tabs').getByText('Town Hall', { exact: true }).click()
    await expectFlags(page.getByTestId('townhall-holder'), 'PRT')
    await page.waitForTimeout(400)
    await page.screenshot({ path: path.join(SHOTS, `city-townhall-${glass}.png`) })
    await page.keyboard.press('Escape')

    // A FLEET PRESSED: your fleet's tray carries your company's flag, and so does her ship's panel.
    await openMap(page)
    const pill = page.getByTestId('map-fleets-corner').locator('button[aria-expanded]')
    await pill.click()
    await page.getByTestId('map-fleet-row').first().click()
    const tray = page.getByTestId('map-detail-tray')
    await expect(tray).toBeVisible()
    await expectFlags(tray.getByTestId('fleet-tray-flag'), 'PRT')
    await page.waitForTimeout(400)
    await page.screenshot({ path: path.join(SHOTS, `fleet-${glass}.png`) })
    await page.getByTestId('tray-ship').first().click()
    const panel = page.getByTestId('map-ship-panel')
    await expect(panel).toBeVisible()
    await expectFlags(panel.getByTestId('ship-panel-flag'), 'PRT')
    await page.waitForTimeout(400)
    await page.screenshot({ path: path.join(SHOTS, `ship-${glass}.png`) })
  })
}

// 2026-10-18 (docs/COMMAND_DESK.md D8): PORT's title is the desk City's heading now. A merchant's sheet flag is
// checked where her sheet opens from — the map's city list (map.merchants.spec, the Porto test).
test('the desk City\'s title flies its city\'s flag', async ({ page, request, baseURL }) => {
  test.setTimeout(420_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  mkdirSync(SHOTS, { recursive: true })
  for (const [glass, size] of [['1440', WIDE], ['390', PHONE]] as const) {
    await page.setViewportSize(size)
    await page.goto('command')
    await ready(page)
    await openCityFace(page)
    await expectFlags(page.getByTestId('desk-city').locator('h2').first())
    await page.screenshot({ path: path.join(SHOTS, `city-${glass}.png`) })
  }
})
