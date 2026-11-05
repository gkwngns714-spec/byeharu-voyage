import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, readDesign } from './design.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE THREE DOORS ARE PAGES — the owner's design order, measured at five glasses, in English and Korean (2026-11-05)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) Three screens no tab shows were still the
// packed column kept to the left: the BOOK a new captain signs (`SignTheBook`), the WORLD OPENING and the WORLD REFUSING
// (`WorldGate`). Each is now a PAGE (`Sheet layout="page"`) on the pattern Stats set, so a tab's skeleton and its screen stand on
// the same grid and nothing jumps when the world arrives. They cannot be reached on demand in local play, so they are read at
// `/ui/gates/found | loading | failed` (src/features/gallery/GatesGalleryScreen.tsx), with the same apparatus as every page spec.
//
// THE LAWS: (a) the width used · (b) the defect rules (incl. every control 44 px) · (e) the side is used: from 1,024 each door has a
// second block standing in the side column · (f) no scroll trap · (g) on a phone the door's first block begins on the first glass.

const DOORS = [
  { state: 'found', main: 'found-form', side: ['found-begin', 'found-language'], ids: ['#house-name', '[data-testid="nation-picker"]'] },
  { state: 'loading', main: 'gate-loading', side: ['gate-loading-side'], ids: [] },
  { state: 'failed', main: 'gate-failed', side: ['gate-detail'], ids: [] },
] as const

/** Where a block stands: inside the side column (`[data-page-side]`) or not. Self-contained, shipped into the page. */
const IN_SIDE = ({ ids }: { ids: readonly string[] }) => {
  const side = document.querySelector('[data-page-side]')
  return ids.map((id) => ({ id, found: !!document.querySelector(`[data-testid="${id}"]`), inSide: !!side?.querySelector(`[data-testid="${id}"]`) }))
}

async function open(page: Page, state: string, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await page.goto(`ui/gates/${state}`)
  if (state === 'found') await ready(page)
  await expect(page.getByTestId('gates')).toBeVisible()
  await expect(page.getByTestId(DOORS.find((d) => d.state === state)!.main)).toBeVisible({ timeout: 120_000 })
  await page.waitForTimeout(400)
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`The three doors are pages — ${locale}`, () => {
    test.use({ locale })

    for (const door of DOORS) {
      for (const glass of DESIGN_GLASSES) {
        test(`${door.state} at ${glass.width}×${glass.height}: the glass used, the side used, no overlap, no trap`, async ({ page, request, baseURL }) => {
          test.setTimeout(600_000)
          test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
          await open(page, door.state, glass)
          const where = `${locale} ${door.state} @${glass.width}×${glass.height}`
          const failures: string[] = []
          const sheet = '[data-sheet]'
          const d = await readDesign(page, { sheet, figureIds: [], rowIds: [] })
          const flat = await readGlass(page, door.main, null, sheet)
          console.log(
            `DESIGN ${where}: block ${d.block ? `${Math.round(d.block.left)}..${Math.round(d.block.right)}` : '-'} · cards ${d.cards.length} · side ${d.side ? Math.round(d.side.w) : '-'} · scrollers ${d.scrollers.length}`,
          )

          // (a) USE THE WIDTH
          if (d.block === null) failures.push(`${where}: (a) the door has no visible text`)
          else if (glass.width >= 1024) {
            const band = d.glass.w - d.block.right
            const share = (d.block.right - d.block.left) / d.glass.w
            if (band > d.block.left + 2) failures.push(`${where}: (a) ${Math.round(band)} px are empty at the right of the content and ${Math.round(d.block.left)} at its left`)
            if (glass.width >= 1280 && share < 0.8) failures.push(`${where}: (a) the content spans ${(share * 100).toFixed(0)} % of the glass — the law is 80 %`)
          }

          // (b) THE DEFECT RULES
          failures.push(...phoneLaws(where, flat).map((m) => m.replace(/: \([abcd]\) /, ': (b) ')))
          if (flat.doc.sh > flat.doc.ch + 1) failures.push(`${where}: (b) the document scrolls ${flat.doc.sh}/${flat.doc.ch}`)
          for (const c of d.smallControls) failures.push(`${where}: (b) a control under 44 px — ${c}`)

          // (e) THE SIDE IS USED
          if (glass.width >= 1024 && d.side === null) failures.push(`${where}: (e) the door has no side column`)
          for (const b of await page.evaluate(IN_SIDE, { ids: door.side })) {
            if (!b.found) failures.push(`${where}: (e) the door has no ${b.id}`)
            else if (glass.width >= 1024 && !b.inSide) failures.push(`${where}: (e) ${b.id} does not stand in the side column`)
          }

          // (f) NO SCROLL TRAP
          for (const s of d.scrollers) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

          // (g) THE FIRST BLOCK ON THE FIRST GLASS OF A PHONE
          if (glass.width < 1024) {
            const top = await page.evaluate((id) => document.querySelector(`[data-testid="${id}"]`)?.getBoundingClientRect().top ?? null, door.main)
            if (top === null || top + 44 > glass.height) failures.push(`${where}: (g) the first block begins at ${top === null ? '-' : Math.round(top)} px of a ${glass.height}-px glass`)
          }

          // U3 — NOTHING WAS REMOVED
          for (const sel of door.ids) {
            if ((await page.locator(sel).count()) === 0) failures.push(`${where}: U3 ${sel} is gone`)
          }

          if (failures.length > 0) console.log(`LAWS ${where}: ${failures.length} lines\n  ${failures.join('\n  ')}`)
          expect(failures, 'This door is not the page the owner asked for').toEqual([])
        })
      }
    }
  })
}
