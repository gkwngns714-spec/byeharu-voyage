import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, ROW_MAX_REM, readDesign } from './design.fixture'
import { serveVeteranWorld, VETERAN_CAPTAINS, VETERAN_HULLS } from './manyFleets.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// YOU IS A PAGE — the owner's design order, measured with a veteran's eight hulls and six captains at five glasses, in English and Korean (2026-11-05)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) Stats, the Codex, History, Rank, Routes, the HQ,
// Fleets and the Map are on the page; YOU is next, held to the SAME laws by the SAME apparatus (tests/design.fixture.ts).
//
// YOU WAS figures over ONE panel that scrolled inside itself (the sheets-grow slice). It is now a PAGE (`Sheet layout="page"`): MAIN the
// ships and the captains as two card lists, SIDE (the tray's column) the three level tracks. The page scrolls; nothing inside it does.
// A captain's tray slides over the side column and moves nothing behind it (tests/fleets.you.grow.spec.ts keeps the tray and cut-name tests).
//
// THE LAWS: (a) the width used (centred from 1,024; 80 % from 1,280) · (b) the defect rules · (c) the level figures at least 24 px
// over labels of at least 13, every ship and captain row at least 52 px and at most 36 rem · (e) the levels stand in the side column from
// 1,024, the ships and captains in the main · (f) no box scrolls inside itself · (g) the ships come first on a phone · U3 every old id stays.

const SHEET = '[data-testid="you"]'
const FIGURES = ['level-track'] as const
const ROWS = ['you-ship', 'your-captain'] as const

/** Where a block stands: inside the side column (`[data-page-side]`) or not. Self-contained, shipped into the page. */
const IN_SIDE = ({ ids }: { ids: readonly string[] }) => {
  const side = document.querySelector('[data-page-side]')
  return ids.map((id) => ({
    id,
    found: !!document.querySelector(`[data-testid="${id}"]`),
    inSide: !!side?.querySelector(`[data-testid="${id}"]`),
  }))
}

async function open(page: Page, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await serveVeteranWorld(page)
  await page.goto('you')
  await ready(page)
  await expect(page.getByTestId('you')).toBeVisible()
  await expect(page.getByTestId('you-ship')).toHaveCount(VETERAN_HULLS, {
    timeout: 120_000,
  })
  await expect(page.getByTestId('your-captain')).toHaveCount(VETERAN_CAPTAINS, {
    timeout: 120_000,
  })
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`You is a page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of DESIGN_GLASSES) {
      test(`${VETERAN_HULLS} hulls and ${VETERAN_CAPTAINS} captains, at ${glass.width}×${glass.height}: the glass used, the side used, the hierarchy, no overlap, no trap`, async ({
        page,
        request,
        baseURL,
      }) => {
        test.setTimeout(600_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)
        const where = `${locale} @${glass.width}×${glass.height}`
        const failures: string[] = []
        const d = await readDesign(page, {
          sheet: SHEET,
          figureIds: FIGURES,
          rowIds: ROWS,
        })
        const flat = await readGlass(page, 'you-ships', 'you-ship', SHEET)
        console.log(
          `DESIGN ${where}: block ${d.block ? `${Math.round(d.block.left)}..${Math.round(d.block.right)}` : '-'} · figures ${d.figures.map((f) => f.font).join('/')} · rows ${d.rows.length}x${d.rows.length ? Math.round(Math.min(...d.rows.map((r) => r.h))) : '-'}..${d.rows.length ? Math.round(Math.max(...d.rows.map((r) => r.w))) : '-'}w · scrollers ${d.scrollers.length}`,
        )

        // (a) USE THE WIDTH
        if (d.block === null) failures.push(`${where}: (a) the screen has no visible text`)
        else if (glass.width >= 1024) {
          const band = d.glass.w - d.block.right
          const share = (d.block.right - d.block.left) / d.glass.w
          if (band > d.block.left + 2)
            failures.push(`${where}: (a) ${Math.round(band)} px are empty at the right of the content and ${Math.round(d.block.left)} at its left`)
          if (glass.width >= 1280 && share < 0.8) failures.push(`${where}: (a) the content spans ${(share * 100).toFixed(0)} % of the glass — the law is 80 %`)
        }

        // (b) THE DEFECT RULES
        failures.push(...phoneLaws(where, flat).map((m) => m.replace(/: \([abcd]\) /, ': (b) ')))
        if (flat.doc.sh > flat.doc.ch + 1) failures.push(`${where}: (b) the document scrolls ${flat.doc.sh}/${flat.doc.ch}`)
        for (const c of d.smallControls) failures.push(`${where}: (b) a control under 44 px — ${c}`)

        // (c) THE HIERARCHY
        const tracks = await page.getByTestId('level-track').count()
        const waits = await page.getByTestId('combat-waits').count()
        if (tracks + waits !== 3) failures.push(`${where}: (c) ${tracks} level bars and ${waits} combat lines — the three tracks are not all there`)
        if (d.figures.length < 1) failures.push(`${where}: (c) no level figure is shown`)
        for (const f of d.figures) {
          if (f.font < 24) failures.push(`${where}: (c) the level figure is ${f.font} px — the law is 24`)
          if (f.label !== null && f.label < 13) failures.push(`${where}: (c) the level label is ${f.label} px — the law is 13`)
        }
        if (d.rows.length < VETERAN_HULLS + VETERAN_CAPTAINS)
          failures.push(`${where}: (c) ${d.rows.length} of ${VETERAN_HULLS + VETERAN_CAPTAINS} rows are visible`)
        const short = d.rows.filter((r) => r.h < 52 - 0.5)
        const wide = d.rows.filter((r) => r.w > ROW_MAX_REM * 16 + 1)
        if (short.length > 0)
          failures.push(`${where}: (c) ${short.length} rows are under 52 px — the shortest is ${Math.round(Math.min(...short.map((r) => r.h)))}`)
        if (wide.length > 0)
          failures.push(
            `${where}: (c) ${wide.length} rows are wider than ${ROW_MAX_REM} rem — the widest is ${Math.round(Math.max(...wide.map((r) => r.w)))} px`,
          )

        // (e) THE SIDE IS USED: the levels stand in it; the ships and the captains stand in the main
        if (glass.width >= 1024 && d.side === null) failures.push(`${where}: (e) the page has no side column`)
        for (const b of await page.evaluate(IN_SIDE, {
          ids: ['levels', 'you-ships', 'your-captains'],
        })) {
          if (!b.found) failures.push(`${where}: (e) the screen has no ${b.id} block`)
          else if (glass.width >= 1024 && b.id === 'levels' && !b.inSide) failures.push(`${where}: (e) the levels do not stand in the side column`)
          else if (glass.width >= 1024 && b.id !== 'levels' && b.inSide) failures.push(`${where}: (e) ${b.id} stands in the side column`)
        }

        // (f) NO SCROLL TRAP
        for (const s of d.scrollers) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

        // (g) THE SHIPS FIRST ON A PHONE: the first row begins on the first glass
        if (glass.width < 1024) {
          const top = await page.evaluate(() => document.querySelector('[data-testid="you-ship"]')?.getBoundingClientRect().top ?? null)
          if (top === null || top + 52 > glass.height)
            failures.push(`${where}: (g) the first ship begins at ${top === null ? '-' : Math.round(top)} px of a ${glass.height}-px glass`)
        }

        // U3 — NOTHING WAS REMOVED
        for (const id of ['you', 'levels', 'you-ships', 'you-ships-count', 'your-captains', 'your-captains-count']) {
          if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: U3 ${id} is gone`)
        }

        if (failures.length > 0) console.log(`LAWS ${where}: ${failures.length} lines\n  ${failures.join('\n  ')}`)
        expect(failures, 'You is not the page the owner asked for').toEqual([])
      })
    }
  })
}
