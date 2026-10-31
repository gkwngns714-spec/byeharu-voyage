import { expect, test, type Locator } from '@playwright/test'
import { PHONE, reachable, ready } from './appReady.fixture'

// THE CACHE PROOF — a tab cycle must not re-download a resource it already holds.
//
// Owner, 2026-10-31: *"make it download one time, then keep it even though you move from tab to
// tab."* The client's served reads are remembered in `src/store/resourceCache.ts`; this spec walks
// the current navigation twice and counts the RPCs each visit makes, off the one `[rpc]` line
// `src/lib/rpc/backend.ts` prints per ask (the same counter trade.ceiling.spec.ts uses). It prints
// the whole table on every run so a regression says WHICH read came back, and asserts the catalogue
// that must be cache-forever for the session:
//
//   · the world snapshot and the sea raster are asked ONCE in the whole session (open());
//   · the officer catalogue (Codex) is asked on the FIRST Codex visit and NOT again on the second;
//   · the market a Market-building visit opens is REPORTED, not asserted to zero: its kept lifetime
//     is the served drift EDGE (`msUntilEdge`), and a probe that straddles an edge is doing exactly
//     what the owner asked — refreshing prices on their normal schedule.
//
// THE CYCLE IS THE OWNER'S CURRENT IA (2026-10-31, #423): the bar is HQ · Fleets · Map · Stats ·
// Menu and the desk has no tab — its door is the CITY's Market building, whose face composes the
// trade face (`PortTrade`). So one cycle is **Market → Stats → Map → Codex → HQ → Market**: the
// market face is the desk's market read, Stats and Map are the live screens, Codex is the
// catalogue, and HQ is the City page that owns the Market door.
//
// The mount burst is measured from the press to the screen being up, not over a whole beat, so the
// shell's own read cadence (which must keep running — it is how time passes) is not counted as a
// tab-switch ask. Each cycle starts on a fresh world beat for the same reason.

interface RpcLine {
  at: number
  label: string
}

interface VisitRow {
  visit: string
  /** What was asked between the press and the screen being up — the MOUNT burst. */
  mount: Record<string, number>
  /** What was asked up to 500 ms after the screen was up — mount burst plus its first answers. */
  settle: Record<string, number>
  order: string[]
}

const counts = (lines: RpcLine[]): Record<string, number> => {
  const out: Record<string, number> = {}
  for (const l of lines) out[l.label] = (out[l.label] ?? 0) + 1
  return out
}

test('a tab cycle asks a cached resource once — Market → Stats → Map → Codex, twice', async ({ page, request, baseURL }) => {
  test.setTimeout(600_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)

  // INSTALL THE COUNTER BEFORE THE APP BOOTS, so open()'s own snapshot/raster asks are counted.
  await page.addInitScript(() => {
    const log: RpcLine[] = []
    const debug = console.debug.bind(console)
    console.debug = (...args: unknown[]) => {
      if (args[0] === '[rpc]' && typeof args[1] === 'string') {
        log.push({ at: performance.now(), label: args[1].replace(/\(.*$/, '') })
      }
      debug(...args)
    }
    ;(window as unknown as { __rpcLog: RpcLine[] }).__rpcLog = log
  })

  await page.setViewportSize(PHONE)
  // STATS is inside AppShell, so the shell's world beat is running while a cycle starts.
  await page.goto('stats')
  await ready(page)

  const mark = () => page.evaluate(() => performance.now())
  const linesBetween = (a: number, b: number) =>
    page.evaluate(
      ([x, y]) => (window as unknown as { __rpcLog: RpcLine[] }).__rpcLog.filter((e) => e.at >= x && e.at < y),
      [a, b] as const,
    )
  const allLines = () => page.evaluate(() => (window as unknown as { __rpcLog: RpcLine[] }).__rpcLog)

  const navBar = (id: string) => page.getByTestId('nav-bar').getByTestId(id)

  /** Wait for the shell's own world read, so a cycle starts at the quiet end of the beat. */
  const waitWorldBeat = async () => {
    const from = await mark()
    await expect
      .poll(async () => (await linesBetween(from, await mark())).filter((e) => e.label === 'world.fleets').length, {
        timeout: 60_000,
      })
      .toBeGreaterThan(0)
  }

  const visit = async (name: string, go: () => Promise<void>, marker: Locator): Promise<VisitRow> => {
    const t0 = await mark()
    await go()
    await expect(marker).toBeVisible({ timeout: 60_000 })
    const t1 = await mark()
    await page.waitForTimeout(500)
    const t2 = await mark()
    const all = await linesBetween(t0, t2)
    return {
      visit: name,
      mount: counts(await linesBetween(t0, t1)),
      settle: counts(all),
      order: all.map((e) => e.label),
    }
  }

  /** THE DESK'S DOOR (the current IA): the City page's Market building opens the trade face. */
  const openMarket = async () => {
    await page.getByTestId('city-building-market').click()
    await expect(page.getByTestId('city-face')).toHaveAttribute('data-building', 'market')
    // The face's own quay read may still be landing; the mount burst is already on the wire.
    await expect(page.getByTestId('quay-stores')).toBeVisible({ timeout: 60_000 })
  }
  const closeMarket = async () => {
    await page.getByTestId('city-face-back').click()
    await expect(page.getByTestId('city-face')).toHaveCount(0)
  }
  const goHq = async () => {
    await navBar('nav-cell-/city').click()
    await expect(page.getByTestId('city-rail')).toBeVisible({ timeout: 60_000 })
  }
  const goStatsFromCity = async () => {
    await page.getByTestId('city-nav').getByTestId('nav-cell-/stats').click()
  }
  const goCodex = async () => {
    await navBar('nav-cell-cabin').click()
    await page.getByTestId('nav-group-panel').getByText('Codex', { exact: true }).click()
  }

  const rows: VisitRow[] = []
  for (const cycle of [1, 2]) {
    await waitWorldBeat()
    rows.push(await visit(`c${cycle}-map`, () => navBar('nav-cell-/map').click(), page.getByTestId('map-chart')))
    rows.push(await visit(`c${cycle}-codex`, goCodex, page.getByTestId('codex')))
    rows.push(await visit(`c${cycle}-hq`, goHq, page.getByTestId('city-rail')))
    rows.push(await visit(`c${cycle}-market`, openMarket, page.getByTestId('city-face')))
    await closeMarket()
    rows.push(await visit(`c${cycle}-stats`, goStatsFromCity, page.getByTestId('stats')))
  }

  const everything = await allLines()
  // THE PROBE'S TABLE, printed on every run (pass or fail) for the dev log and for a red's diagnosis.
  for (const r of rows) {
    console.log(
      `CACHE ${r.visit.padEnd(12)} mount=${JSON.stringify(r.mount)} settle=${JSON.stringify(r.settle)} order=${r.order.join(',')}`,
    )
  }
  console.log(`CACHE totals=${JSON.stringify(counts(everything))}`)

  // THE STANDING INVARIANTS.
  const asked = (label: string) => everything.filter((e) => e.label === label).length
  expect(asked('world.snapshot'), 'the world snapshot is fetched once per session').toBe(1)
  expect(asked('world.sea_raster'), 'the sea raster is fetched once per session').toBe(1)

  const codex = rows.filter((r) => r.visit.endsWith('-codex'))
  const officerMounts = codex.map((r) => r.mount['world.officers'] ?? 0)
  expect(officerMounts[0], 'the first Codex visit asks the officer catalogue').toBeGreaterThan(0)
  expect(officerMounts[1], 'the second Codex visit must not ask the officer catalogue again').toBe(0)

  // The market is REPORTED: its kept lifetime is the served edge, and a probe that straddles one is
  // the price refresh the owner asked for. Non-vacuous: the first Market open DID ask the quay.
  const market = rows.filter((r) => r.visit.endsWith('-market')).map((r) => r.mount['world.market'] ?? 0)
  console.log(`CACHE market on Market-building opens=${JSON.stringify(market)} (kept until its edge)`)
  expect(market[0], 'the first Market open asks the quay').toBeGreaterThan(0)
  expect(asked('world.market'), 'the market read happened at least once').toBeGreaterThan(0)
})
