import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'
import { DESIGN_GLASSES, readDesign } from './design.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PROFILE IS A PAGE — the owner's design order, measured at five glasses, in English and Korean (2026-11-05)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) The Profile was one narrow column of five
// sections kept to the left of the glass (and held to "no scroll at 320×640" by tests/profile.phone.spec.ts — the compaction row 267
// reverses; that spec is replaced by this file, which keeps its one still-true guard: the sign-out button is whole, clear of the rail).
// It is now a PAGE (`Sheet layout="page"`): MAIN the company and its country as cards, SIDE (the tray's column) the language, the
// appearance and the account (sign-out). One column on a phone, the company first. The page scrolls; nothing inside it does.
//
// THE LAWS: (a) the width used · (b) the defect rules (incl. every control 44 px) · (e) the side is used: language, appearance and
// sign-out stand in the side column from 1,024, the company and country in the main · (f) no scroll trap · (g) the company is on the
// first glass of a phone · U3 every old id stays · and the sign-out button is whole and clear of the rail once scrolled to (320×568).
// The Profile has no list and no key figure, so the hierarchy law (c) has nothing of its own to measure.

const SHEET = '[data-testid="profile"]'

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
  await page.goto('profile')
  await ready(page)
  await expect(page.getByTestId('profile')).toBeVisible()
  await expect(page.getByTestId('sign-out')).toBeVisible()
  await page.waitForFunction(() => document.querySelectorAll('.animate-pulse').length === 0, undefined, { timeout: 120_000 }).catch(() => {})
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`The Profile is a page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of DESIGN_GLASSES) {
      test(`at ${glass.width}×${glass.height}: the glass used, the side used, no overlap, no trap`, async ({ page, request, baseURL }) => {
        test.setTimeout(600_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)
        const where = `${locale} @${glass.width}×${glass.height}`
        const failures: string[] = []
        const d = await readDesign(page, {
          sheet: SHEET,
          figureIds: [],
          rowIds: [],
        })
        const flat = await readGlass(page, 'house-line', null, SHEET)
        console.log(
          `DESIGN ${where}: block ${d.block ? `${Math.round(d.block.left)}..${Math.round(d.block.right)}` : '-'} · cards ${d.cards.length} · side ${d.side ? Math.round(d.side.w) : '-'} · scrollers ${d.scrollers.length}`,
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

        // (e) THE SIDE IS USED
        if (glass.width >= 1024 && d.side === null) failures.push(`${where}: (e) the page has no side column`)
        for (const b of await page.evaluate(IN_SIDE, {
          ids: ['house-line', 'country', 'profile-language', 'profile-appearance', 'profile-account', 'sign-out'],
        })) {
          const sideBlock = b.id !== 'house-line' && b.id !== 'country'
          if (!b.found) failures.push(`${where}: (e) the screen has no ${b.id}`)
          else if (glass.width >= 1024 && sideBlock && !b.inSide) failures.push(`${where}: (e) ${b.id} does not stand in the side column`)
          else if (glass.width >= 1024 && !sideBlock && b.inSide) failures.push(`${where}: (e) ${b.id} stands in the side column`)
        }

        // (f) NO SCROLL TRAP
        for (const s of d.scrollers) failures.push(`${where}: (f) a box scrolls inside itself — ${s}`)

        // (g) THE COMPANY FIRST ON A PHONE
        if (glass.width < 1024) {
          const top = await page.evaluate(() => document.querySelector('[data-testid="house-line"]')?.getBoundingClientRect().top ?? null)
          if (top === null || top + 44 > glass.height)
            failures.push(`${where}: (g) the company line begins at ${top === null ? '-' : Math.round(top)} px of a ${glass.height}-px glass`)
        }

        // the sign-out button, scrolled to, is whole inside the sheet's box and clear of the rail
        await page.getByTestId('sign-out').scrollIntoViewIfNeeded()
        await page.waitForTimeout(300)
        const reach = await page.evaluate(() => {
          const b = document.querySelector('[data-testid="sign-out"]')?.getBoundingClientRect()
          const s = document.querySelector('[data-sheet]')?.getBoundingClientRect()
          const r = document.querySelector('[data-testid="nav-bar"]')?.getBoundingClientRect()
          return b && s && r
            ? {
                bottom: b.bottom,
                top: b.top,
                sheetBottom: s.bottom,
                // 2026-11-11 (S9): from `lg` the nav is a rail at the left edge — only a bar at the foot has a top to stay above
                railTop: r.width > r.height ? r.top : innerHeight,
              }
            : null
        })
        if (reach === null) failures.push(`${where}: (b) sign-out, the sheet or the rail is missing`)
        else if (reach.bottom > reach.sheetBottom + 0.5 || reach.bottom > reach.railTop + 0.5)
          failures.push(`${where}: (b) the sign-out button runs past the sheet or over the rail (${JSON.stringify(reach)})`)

        // U3 — NOTHING WAS REMOVED
        for (const id of ['profile', 'house-line', 'country', 'sign-out']) {
          if ((await page.getByTestId(id).count()) === 0) failures.push(`${where}: U3 ${id} is gone`)
        }

        if (failures.length > 0) console.log(`LAWS ${where}: ${failures.length} lines\n  ${failures.join('\n  ')}`)
        expect(failures, 'The Profile is not the page the owner asked for').toEqual([])
      })
    }
  })
}
