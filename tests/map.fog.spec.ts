import { mkdirSync } from 'node:fs'
import path from 'node:path'
import { test, expect, type Page } from '@playwright/test'
import { PHONE, ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// THE FOG (0504, owner 2026-11-25: "The MAP itself will be black, and your fleet will provide a radius ... the location you've visited
// will show like a grey map, where you can tab on that city to not see the info, but to go there"). The shipped world is DARK
// (`chart_fog_enabled` false): the map is drawn whole, with no fog on it. A copy of the image with the switch lit, and a chart seeded
// for every company the moment her fleet exists (a course painted from her harbour by the server's own painter): the map carries the
// fog, holds only the cities she has in sight or knows, and a city she knows but does not see is named and can be sailed to, with
// nothing about it shown.
//
// THE FRAME COST IS PRINTED, NOT PINNED (tests/map.perf.spec.ts's header says why): the same drag on the phone-size glass, dark and
// lit, in one run. FOG_SHOTS=<dir> also writes the pictures there.

const SEED = `
  update public.world_config set value = 'true'::jsonb where key = 'chart_fog_enabled';
  create function public.test_fog_course(p_port uuid) returns jsonb language sql stable as $f$
    select jsonb_build_array(
             jsonb_build_object('a', jsonb_build_array(p.lat, p.lon), 'b', jsonb_build_array(p.lat - 5, p.lon - 5), 'nm', 400),
             jsonb_build_object('a', jsonb_build_array(p.lat - 5, p.lon - 5), 'b', jsonb_build_array(p.lat - 2, p.lon + 12), 'nm', 900))
      from public.ports p where p.id = p_port
  $f$;
  create function public.test_fog_seed() returns trigger language plpgsql security definer set search_path = public, pg_temp as $f$
  begin
    if new.port_id is not null and not coalesce((select pl.is_npc from public.players pl where pl.id = new.player_id), true) then
      insert into public.company_chart (player_id, cells)
      values (new.player_id, public.chart_paint(null, public.test_fog_course(new.port_id), 150))
      on conflict (player_id) do nothing;
    end if;
    return new;
  end $f$;
  create trigger test_fog_seed after insert on public.fleets for each row execute function public.test_fog_seed();
  insert into public.company_chart (player_id, cells)
  select distinct on (f.player_id) f.player_id, public.chart_paint(null, public.test_fog_course(f.port_id), 150)
    from public.fleets f join public.players pl on pl.id = f.player_id
   where not pl.is_npc and f.port_id is not null
   order by f.player_id, f.id
  on conflict (player_id) do nothing;
`

const lit = () => patchedWorldImage('chart-fog-lit', async (pg) => {
  await pg.exec(SEED)
})

const SHOTS = process.env.FOG_SHOTS ?? null
async function shot(page: Page, name: string) {
  if (!SHOTS) return
  mkdirSync(SHOTS, { recursive: true })
  await page.screenshot({ path: path.join(SHOTS, `${name}.png`) })
}

/** The harbours on the paper, with where each stands on the glass. */
async function drawnPorts(page: Page) {
  return page.evaluate(() => {
    const svg = document.querySelector('[data-testid="map-view"]') as SVGSVGElement | null
    if (!svg) return []
    const box = svg.getBoundingClientRect()
    const [vx, vy, vw, vh] = svg.getAttribute('viewBox')!.split(/\s+/).map(Number)
    return [...svg.querySelectorAll('[data-port-code][data-port-x]')].map((g) => {
      const x = Number(g.getAttribute('data-port-x'))
      const y = Number(g.getAttribute('data-port-y'))
      return { code: g.getAttribute('data-port-code')!, mark: g.getAttribute('data-port-mark'), px: box.left + ((x - vx) / vw) * box.width, py: box.top + ((y - vy) / vh) * box.height }
    })
  })
}

/** rAF gaps during a real drag of a fifth of the glass (tests/map.perf.spec.ts's apparatus). */
async function panFrames(page: Page): Promise<{ mean: number; p95: number; max: number; fps: number }> {
  const chart = (await page.locator('[data-testid="map-chart"]').boundingBox())!
  const x0 = chart.x + chart.width * 0.7
  const y = chart.y + chart.height * 0.35
  await page.evaluate(() => {
    const w = window as unknown as { __gaps: number[]; __last: number; __on: boolean }
    w.__gaps = []
    w.__last = performance.now()
    w.__on = true
    const tick = () => {
      const now = performance.now()
      w.__gaps.push(now - w.__last)
      w.__last = now
      if (w.__on) requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  })
  await page.mouse.move(x0, y)
  await page.mouse.down()
  for (let i = 1; i <= 60; i++) {
    await page.mouse.move(x0 - (chart.width * 0.4 * i) / 60, y + (chart.height * 0.1 * i) / 60)
    await page.waitForTimeout(16)
  }
  await page.mouse.up()
  return page.evaluate(() => {
    const w = window as unknown as { __gaps: number[]; __on: boolean }
    w.__on = false
    const gaps = w.__gaps.slice(1)
    const sorted = [...gaps].sort((a, b) => a - b)
    const mean = gaps.reduce((s, g) => s + g, 0) / Math.max(1, gaps.length)
    return { mean, p95: sorted[Math.floor(sorted.length * 0.95)] ?? 0, max: sorted[sorted.length - 1] ?? 0, fps: 1000 / mean }
  })
}

test.use({ viewport: PHONE })

test('dark: the map is drawn whole and carries no fog', async ({ page, request, baseURL }) => {
  test.setTimeout(480_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await page.goto('map')
  await ready(page)
  await expect(page.getByTestId('map-view')).toBeVisible()
  await expect(page.getByTestId('map-fog')).toHaveCount(0)
  await page.waitForTimeout(1500)
  await shot(page, 'phone-dark-map')
  const pan = await panFrames(page)
  console.log(`\nFOG FRAMES 390x844 dark: pan ${pan.mean.toFixed(1)} ms mean (${pan.fps.toFixed(0)} fps), p95 ${pan.p95.toFixed(1)}, max ${pan.max.toFixed(1)}`)
})

test('lit: black, grey where she has been, clear round her fleet; a known city is named and sailed to, with no information', async ({ page, request, baseURL }) => {
  test.setTimeout(900_000)
  test.skip(!(await reachable(request, baseURL ?? '')), 'no served build')
  await serveWorldImage(page, await lit())
  await page.goto('map')
  await ready(page)
  const fog = page.getByTestId('map-fog')
  await expect(fog).toBeVisible({ timeout: 60_000 })
  await expect(fog).toHaveAttribute('data-fog-sight', '150')
  await page.waitForTimeout(1500)
  await shot(page, 'phone-lit-map')

  // press her cities until one in sight and one only known have each answered
  const chart = (await page.getByTestId('map-chart').boundingBox())!
  const ports = (await drawnPorts(page)).filter((p) => p.mark === 'full' && p.px > chart.x + 20 && p.px < chart.x + chart.width - 60 && p.py > chart.y + 80 && p.py < chart.y + chart.height * 0.55)
  let seen: string | null = null
  let known: string | null = null
  const tray = page.getByTestId('map-detail-tray')
  for (const p of ports.slice(0, 40)) {
    if (seen && known) break
    await page.mouse.click(p.px, p.py)
    if (!(await tray.isVisible().catch(() => false))) continue
    const unseen = (await tray.getAttribute('data-unseen')) !== null
    if (unseen && !known) {
      known = p.code
      await expect(tray).toContainText('Out of sight')
      await expect(page.getByTestId('map-hq-here')).toHaveCount(0)
      await expect(page.getByTestId('map-harbour-skyline-band')).toHaveCount(0)
      await expect(page.getByTestId('map-send-fleet')).toBeVisible()
      await page.waitForTimeout(700)
      await shot(page, 'phone-lit-known-city')
    } else if (!unseen && !seen) {
      seen = p.code
      await expect(page.getByTestId('map-hq-here')).toBeVisible()
      await page.waitForTimeout(700)
      await shot(page, 'phone-lit-city-in-sight')
    }
    await page.getByTestId('tray-close').click()
    await expect(tray).toHaveCount(0)
  }
  expect(seen, 'a city in sight answered with its information').not.toBeNull()
  expect(known, 'a city she only knows answered with its name and the sending alone').not.toBeNull()

  const pan = await panFrames(page)
  console.log(`\nFOG FRAMES 390x844 lit: pan ${pan.mean.toFixed(1)} ms mean (${pan.fps.toFixed(0)} fps), p95 ${pan.p95.toFixed(1)}, max ${pan.max.toFixed(1)}; pressed in sight ${seen}, known ${known}`)

  // the fog is a picture: black in a far corner of the world, clear where her fleet lies. Zoomed right out, most of the glass is black.
  for (let i = 0; i < 12; i++) await page.getByLabel('Zoom out').click()
  await page.waitForTimeout(1200)
  await shot(page, 'phone-lit-world')
  const ink = await fog.evaluate((c) => {
    const canvas = c as HTMLCanvasElement
    const d = canvas.getContext('2d')!.getImageData(0, 0, canvas.width, canvas.height).data
    let black = 0
    let veil = 0
    let clear = 0
    for (let i = 3; i < d.length; i += 4) {
      if (d[i] >= 250) black++
      else if (d[i] <= 5) clear++
      else veil++
    }
    return { black, veil, clear, all: d.length / 4 }
  })
  expect(ink.black / ink.all).toBeGreaterThan(0.8)
  expect(ink.veil).toBeGreaterThan(0)
  expect(ink.clear).toBeGreaterThan(0)
  // every harbour of the world is NOT on her map: only those in sight or known
  const far = await drawnPorts(page)
  expect(far.length).toBeGreaterThan(0)
  expect(far.length).toBeLessThan(120)
  console.log(`FOG: zoomed right out, her map holds ${far.length} of the world's harbours; ${Math.round((100 * ink.black) / ink.all)} % of the glass black, ${Math.round((100 * ink.veil) / ink.all)} % grey, ${Math.round((100 * ink.clear) / ink.all)} % clear`)

  // the page stands still: nothing wider than the glass
  const wide = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(wide).toBeLessThanOrEqual(0)

  // THE TRADE MAP wears the same fog
  await page.goto('command')
  await ready(page)
  await page.getByTestId('trade-map-open').click()
  const small = page.getByTestId('trade-map')
  await expect(small.getByTestId('map-fog')).toBeVisible({ timeout: 30_000 })
  await page.waitForTimeout(1200)
  await shot(page, 'phone-lit-trade-map')
  if (SHOTS) {
    await page.setViewportSize({ width: 1440, height: 900 })
    await page.goto('map')
    await ready(page)
    await expect(page.getByTestId('map-fog')).toBeVisible({ timeout: 60_000 })
    await page.waitForTimeout(1500)
    await shot(page, 'desktop-lit-map')
  }
})
