import { test, expect, type Page } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'
import { patchedWorldImage, serveWorldImage } from './worldImage.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE DRIVE AUDIT, 2026-11-08 — THE TABS, THE CACHE AND A FLEET OF SEVEN, DRIVEN AS THE OWNER WOULD
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/OWNER_REQUESTS.md row 250 (*"make it download one time, then keep it even though you move
// from tab to tab"*): cache.once.spec.ts counts the static reads over Map → Codex → HQ → Market →
// Stats; the bar the owner presses is HQ · Fleets · Map · Stats, and Fleets was never in the cycle.
// Row 180 (*"assign multiple ships (total of 7). Show stats of individual ship and also as a fleet"*):
// the suite's veteran world is eight fleets of ONE hull each; nobody has opened ONE fleet of seven.
// Rows 249 / 252 / 246: every cell both ways (A → B → A) from the HQ, at a phone and at the owner's
// 1440 laptop, with the document's scroll read on each screen.

const OUT = 'docs/dev-log/2026-11-08-drive-audit'
const WIDE = { width: 1280, height: 800 }
const LAPTOP = { width: 1440, height: 900 }
const PHONE = { width: 390, height: 844 }
const SEVEN = ['Andorinha', 'Boa Viagem', 'Conceição', 'Esperança', 'Flor do Mar', 'Gaivota II'] as const

test.use({ deviceScaleFactor: 2 })

async function shot(page: Page, name: string) {
  await page.waitForTimeout(300)
  await page.screenshot({ path: `${OUT}/${name}.png` })
}

function hookAsks(page: Page) {
  return page.addInitScript(() => {
    const w = window as unknown as { __rpcLog: { at: number; label: string }[] }
    w.__rpcLog = []
    const orig = console.debug
    console.debug = (...args: unknown[]) => {
      if (args[0] === '[rpc]' && typeof args[1] === 'string') w.__rpcLog.push({ at: performance.now(), label: args[1].replace(/\(.*$/, '') })
      orig.apply(console, args)
    }
  })
}

const cell = (page: Page, to: string) => page.getByTestId(`nav-cell-${to}`).first()

/** Stats lives in the Menu (S1, 2026-11-11), so it is reached through the cabin's tray, the one door every member has. */
const press = async (page: Page, to: string) => {
  if (to !== '/stats') return cell(page, to).click()
  await cell(page, 'cabin').click()
  await page.getByTestId('nav-group-panel').getByRole('link', { name: 'Stats' }).click()
}

// ── ROW 250: DOWNLOAD ONCE, KEEP IT ACROSS THE TABS THE OWNER PRESSES ────────────────────────────
test('Tabs: HQ → Fleets → Map → Stats → HQ, twice — the world and the sea are asked once, the second cycle asks no more than the first and shows no skeleton (row 250)', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await hookAsks(page)
  await page.setViewportSize(WIDE)
  await page.goto('city')
  await ready(page)
  await expect(page.getByTestId('city-rail')).toBeVisible({ timeout: 120_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })

  const steps: [string, string][] = [
    ['/fleets', 'fleets'],
    ['/map', 'map-chart'],
    ['/stats', 'stats'],
    ['/city', 'city-rail'],
  ]
  const counts: Record<string, number>[] = []
  const skeletons: Record<string, number>[] = []
  for (let cycle = 0; cycle < 2; cycle++) {
    const t0 = await page.evaluate(() => performance.now())
    const pulses: Record<string, number> = {}
    for (const [to, marker] of steps) {
      await press(page, to)
      await expect(page.getByTestId(marker)).toBeVisible({ timeout: 120_000 })
      // what the owner sees right after the press: a skeleton means it is downloading again
      await page.waitForTimeout(150)
      pulses[to] = await page.locator('.animate-pulse').count()
      await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
      await page.waitForTimeout(400)
    }
    const t1 = await page.evaluate(() => performance.now())
    const log = await page.evaluate(({ a, b }) => (window as unknown as { __rpcLog: { at: number; label: string }[] }).__rpcLog.filter((l) => l.at >= a && l.at < b).map((l) => l.label), { a: t0, b: t1 })
    const byLabel: Record<string, number> = {}
    for (const l of log) byLabel[l] = (byLabel[l] ?? 0) + 1
    counts.push(byLabel)
    skeletons.push(pulses)
    console.log(`cycle ${cycle + 1}: ${JSON.stringify(byLabel)}; skeletons after the press: ${JSON.stringify(pulses)}`)
  }
  const all = await page.evaluate(() => (window as unknown as { __rpcLog: { at: number; label: string }[] }).__rpcLog.map((l) => l.label))
  const total = (name: string) => all.filter((l) => l === name).length
  console.log(`whole session: snapshot ${total('world.snapshot')}, sea_raster ${total('world.sea_raster')}, fleets ${total('world.fleets')}, stats_overview ${total('world.stats_overview')}`)
  expect(total('world.snapshot'), 'the world was downloaded more than once').toBeLessThanOrEqual(1)
  expect(total('world.sea_raster'), 'the sea was downloaded more than once').toBeLessThanOrEqual(1)
  // the second cycle asks no static read again
  for (const name of ['world.snapshot', 'world.sea_raster', 'world.reaches', 'world.sea_conditions']) {
    expect(counts[1][name] ?? 0, `${name} was asked again on the second cycle`).toBe(0)
  }
  // and nothing is drawn as a skeleton on the way back to a screen already seen (Stats included: its live reads `keep` their
  // last answer across a remount, src/live/liveRead.ts, and draw it at once while the next ask is on the wire)
  for (const [to] of steps) expect(skeletons[1][to], `${to} showed a loading skeleton on its second visit`).toBe(0)
})

// ── ROW 180: ONE FLEET OF SEVEN, EACH SHIP'S STATS AND THE FLEET'S ───────────────────────────────
function sevenWorld(): Promise<Buffer> {
  return patchedWorldImage('drive-seven', async (pg) => {
    const names = `array[${SEVEN.map((n) => `'${n.replace(/'/g, "''")}'`).join(', ')}]`
    // THE CAP: the shipped world lets a fleet sail 2 ships (`fleet_ship_max`; E_FLEET_SHIP_MAX refused the third hull on the
    // first run of this spec). The owner's row says seven; the room past two is the unbuilt F3-F7 (slots by gold and level).
    const cap = await pg.query(`update public.world_config set value = to_jsonb(7) where key = 'fleet_ship_max' returning key`)
    if (cap.rows.length !== 1) throw new Error('world_config has no fleet_ship_max row')
    // Since 0107 the cap a fleet sails under is EARNED (public.earned_caps: level and academy), not the knob — a new company
    // gets 2. The room for seven is the unbuilt F3-F7 of row 180, so this copy of the world grants it outright.
    await pg.exec(`
      alter function public.earned_caps(uuid) rename to earned_caps_drive_orig;
      create function public.earned_caps(p_player uuid) returns jsonb
      language sql stable security definer set search_path = public, pg_temp as $f$
        select public.earned_caps_drive_orig(p_player)::jsonb || jsonb_build_object('fleet_ship_max', 7)
      $f$;
    `)
    await pg.exec(`
      create function public.spec_seven_hulls() returns trigger
      language plpgsql security definer set search_path = public, pg_temp as $fn$
      declare v_name text;
      begin
        if pg_trigger_depth() > 1 then return null; end if;
        if exists (select 1 from public.players p where p.id = new.player_id and p.is_npc) then return null; end if;
        if (select count(*) from public.ships s where s.fleet_id = new.fleet_id) > 1 then return null; end if;
        -- (p_flagship false: the founding flagship is already in this fleet; p_crewed true)
        foreach v_name in array ${names} loop
          perform public.commission_ship(new.player_id, new.fleet_id, 'barca', v_name, false, true);
        end loop;
        return null;
      end $fn$;
      create trigger spec_seven_hulls after insert on public.ships
        for each row when (new.is_flagship) execute function public.spec_seven_hulls();
    `)
  })
}

test('Fleets: one fleet of seven ships — the company counts 7 hulls, her page lists each ship with its own stats, and the fleet\'s own figures (row 180)', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
  await serveWorldImage(page, await sevenWorld())
  await page.setViewportSize(WIDE)
  await page.goto('fleets')
  await ready(page)
  await expect(page.getByTestId('fleets')).toBeVisible({ timeout: 120_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
  const hulls = (await page.getByTestId('fleets-hulls').innerText()).replace(/\s+/g, ' ')
  const rows = page.getByTestId('fleet-row')
  console.log(`company: ${hulls}; fleet rows ${await rows.count()}`)
  expect(hulls).toMatch(/7/)
  await expect(rows).toHaveCount(1)
  await shot(page, 'fleets-seven-1280@2x')

  await rows.first().click()
  const fleetPage = page.getByTestId('fleet-page')
  await expect(fleetPage).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 60_000 })
  const tiles = page.getByTestId('fleet-ship-tile')
  await expect(tiles).toHaveCount(7, { timeout: 60_000 })
  const powers = await page.getByTestId('ship-power').allInnerTexts()
  console.log(`ship tiles: ${await tiles.count()}; power lines: ${powers.length}; first: ${(powers[0] ?? '').replace(/\s+/g, ' ')}`)
  expect(powers.length, 'not every ship shows its stats').toBe(7)
  for (const p of powers) expect(p).toMatch(/\d/)
  // the fleet's own figures: her stores and her hold, as one fleet
  const fleetFigures = await page.evaluate(() => {
    const t = (sel: string) => (document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim()
    return { stores: t('[data-testid="fleet-stores-days"]'), hold: t('[data-testid="hold-breakdown"]'), passage: t('[data-testid="fleet-passage"]') }
  })
  console.log(`fleet figures: ${JSON.stringify(fleetFigures)}`)
  expect(fleetFigures.hold || fleetFigures.stores, 'the fleet page has no fleet-wide figure').not.toBe('')
  // slots to unlock by gold or level (the rest of the row): is there any such control?
  const unlock = await page.locator('[data-testid*="slot"], [data-testid*="unlock"]').count()
  console.log(`slot / unlock controls on the fleet page: ${unlock}`)
  await shot(page, 'fleet-seven-page-1280@2x')
  await page.locator('[data-detail-back]').last().click()
  await expect(page.locator('[data-detail-page]')).toHaveCount(0)
})

// ── ROWS 249 / 252 / 246: EVERY CELL BOTH WAYS, FROM THE HQ ──────────────────────────────────────
for (const size of [PHONE, LAPTOP]) {
  test(`Tabs @${size.width}: from the HQ each cell goes and comes back; the bar is HQ · Trade · Fleets · Map · Menu; the document never scrolls sideways`, async ({ page, request, baseURL }) => {
    test.setTimeout(600_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
    await page.setViewportSize(size)
    await page.goto('city')
    await ready(page)
    await expect(page.getByTestId('city-rail')).toBeVisible({ timeout: 120_000 })
    const labels = (await page.getByTestId('city-rail').locator('[data-testid^="nav-label-"]').allInnerTexts()).map((s) => s.trim())
    console.log(`@${size.width} rail: ${labels.join(' · ')}`)
    expect(labels).toEqual(['HQ', 'Trade', 'Fleets', 'Map', 'Menu'])
    const scrolls: Record<string, string> = {}
    const read = async (name: string) => {
      scrolls[name] = await page.evaluate(() => {
        const d = document.documentElement
        return `doc ${d.scrollHeight}/${d.clientHeight} wide ${d.scrollWidth}/${d.clientWidth}`
      })
      const sideways = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)
      expect(sideways, `${name} scrolls sideways`).toBe(false)
    }
    await read('HQ')
    for (const [to, marker] of [
      ['/fleets', 'fleets'],
      ['/map', 'map-chart'],
      ['/stats', 'stats'],
    ] as const) {
      await press(page, to)
      await expect(page.getByTestId(marker)).toBeVisible({ timeout: 120_000 })
      await expect(page.locator('.animate-pulse')).toHaveCount(0, { timeout: 120_000 })
      await read(to)
      await cell(page, '/city').click()
      await expect(page.getByTestId('city-rail')).toBeVisible({ timeout: 120_000 })
      await expect(page.getByTestId('city-building-grid')).toBeVisible()
    }
    // the Menu reveals the cabin and a member comes back too
    await page.getByTestId('nav-bar').getByText('Menu').click()
    const panel = page.getByTestId('nav-group-panel')
    await expect(panel).toBeVisible()
    await expect(panel.getByRole('link')).toHaveCount(7)
    await panel.getByRole('link', { name: /History|기록/ }).click()
    await expect(page.getByTestId('ledger')).toBeVisible({ timeout: 120_000 })
    await cell(page, '/city').click()
    await expect(page.getByTestId('city-rail')).toBeVisible({ timeout: 120_000 })
    console.log(`@${size.width} scroll: ${JSON.stringify(scrolls)}`)
    await shot(page, `tabs-hq-${size.width}@2x`)
  })
}
