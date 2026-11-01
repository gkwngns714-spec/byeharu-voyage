import { expect, test } from '@playwright/test'
import { ready, reachable } from './appReady.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PROFILE ON A PHONE — the sign-out control stands clear of the rail, and the page needs no scroll (2026-11-02)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The brief (the HQ-on-a-phone slice, docs/dev-log/2026-11-02-city-phone.md §1 (e)): *the logout control overlaps something at phone width*.
// What it was, measured on `98a75c04`: the page is a Sheet of five sections and it was 572 px tall in a 551-px glass at 320×640 (558 in 551 at 360×640) —
// 21 px of scroll INSIDE the Sheet, which the unfold laws forbid at 320×640 — and at 320×568 (the smallest glass the repo measures) the sign-out row's box
// lay 22 px over the rail's Stats and Menu cells, the Sheet clipping it so it read as cut. Language and Appearance were 92 px each for a 44-px control: the
// word on one line and its switch on the next. They now stand on ONE line (`SheetSection inline`: the switch right behind its word, dropping under it only
// when the two do not fit), 80 px back.
//
// WHAT IT HOLDS, at 390×844, 360×640 and 320×640: the Sheet does not scroll, and the sign-out button lies wholly inside the Sheet, clear of the rail. At
// 320×568 (a glass that cannot show the whole page) the button still lies wholly inside the Sheet and clear of the rail — only the Sheet's own 24 px of
// bottom padding scrolls. And at every glass each switch stands on its word's line when the two fit one.

const ONE_PAGE = [
  { width: 390, height: 844 },
  { width: 360, height: 640 },
  { width: 320, height: 640 },
] as const
const SHORT = { width: 320, height: 568 } as const

async function read(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const box = (e: Element | null) => {
      if (!e) return null
      const r = e.getBoundingClientRect()
      return { left: r.left, top: r.top, right: r.right, bottom: r.bottom }
    }
    const sheet = document.querySelector('[data-sheet]') as HTMLElement | null
    const button = document.querySelector('[data-testid="sign-out"]')
    const rail = document.querySelector('[data-testid="nav-bar"]')
    // each switch and its word: the Segmented's tablist and the h2 before it
    const lines = [...document.querySelectorAll('[data-sheet] section h2')]
      .map((h) => {
        const control = h.closest('section')?.querySelector('[role="tablist"]') ?? null
        return control ? { word: h.textContent, wordY: (box(h)!.top + box(h)!.bottom) / 2, switchY: (box(control)!.top + box(control)!.bottom) / 2, wordRight: box(h)!.right, switchLeft: box(control)!.left } : null
      })
      .filter((x): x is NonNullable<typeof x> => x !== null)
    return {
      sheet: sheet ? { scrollH: sheet.scrollHeight, clientH: sheet.clientHeight, box: box(sheet) } : null,
      button: box(button),
      rail: box(rail),
      lines,
    }
  })
}

async function open(page: import('@playwright/test').Page, size: { width: number; height: number }) {
  await page.setViewportSize(size)
  await page.goto('profile')
  await ready(page)
  await page.waitForTimeout(400)
  return read(page)
}

function standsClear(m: Awaited<ReturnType<typeof read>>, where: string) {
  expect(m.button, `${where}: no sign-out button`).not.toBeNull()
  expect(m.sheet, `${where}: no Sheet`).not.toBeNull()
  expect(m.rail, `${where}: no rail`).not.toBeNull()
  // wholly inside the Sheet's box…
  expect(m.button!.bottom, `${where}: the sign-out button runs past the Sheet's bottom (${m.button!.bottom} > ${m.sheet!.box!.bottom})`).toBeLessThanOrEqual(m.sheet!.box!.bottom + 0.5)
  // …and so clear of the rail, which stands under it
  expect(m.button!.bottom, `${where}: the sign-out button lies over the rail (${m.button!.bottom} > ${m.rail!.top})`).toBeLessThanOrEqual(m.rail!.top + 0.5)
}

function switchesBesideTheirWords(m: Awaited<ReturnType<typeof read>>, where: string) {
  expect(m.lines.length, `${where}: the Language and Appearance switches were not found`).toBeGreaterThanOrEqual(2)
  for (const l of m.lines) {
    expect(Math.abs(l.wordY - l.switchY), `${where}: "${l.word}" and its switch are not on one line (${Math.round(l.wordY)} / ${Math.round(l.switchY)})`).toBeLessThanOrEqual(6)
    expect(l.switchLeft - l.wordRight, `${where}: "${l.word}" and its switch are not close (${Math.round(l.switchLeft - l.wordRight)} px)`).toBeLessThanOrEqual(24)
  }
}

for (const size of ONE_PAGE) {
  test(`the Profile at ${size.width}×${size.height}: no scroll, the sign-out stands clear of the rail, each switch beside its word`, async ({ page, request, baseURL }) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    const m = await open(page, size)
    const where = `${size.width}×${size.height}`
    expect(m.sheet!.scrollH, `${where}: the Sheet scrolls (${m.sheet!.scrollH} in ${m.sheet!.clientH})`).toBeLessThanOrEqual(m.sheet!.clientH + 1)
    standsClear(m, where)
    switchesBesideTheirWords(m, where)
    console.log(`PROFILE ${where}: sheet ${m.sheet!.scrollH}/${m.sheet!.clientH}, sign-out bottom ${Math.round(m.button!.bottom)} · rail top ${Math.round(m.rail!.top)}`)
  })
}

test(`the Profile at ${SHORT.width}×${SHORT.height}: it cannot all stand, but the sign-out button is whole and clear of the rail`, async ({ page, request, baseURL }) => {
  test.setTimeout(300_000)
  test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
  const m = await open(page, SHORT)
  standsClear(m, '320×568')
  switchesBesideTheirWords(m, '320×568')
  // only the Sheet's own bottom padding (24 px) is out of the glass
  expect(m.sheet!.scrollH - m.sheet!.clientH, `320×568: more than the Sheet's padding scrolls (${m.sheet!.scrollH} in ${m.sheet!.clientH})`).toBeLessThanOrEqual(24)
  console.log(`PROFILE 320×568: sheet ${m.sheet!.scrollH}/${m.sheet!.clientH}, sign-out bottom ${Math.round(m.button!.bottom)} · rail top ${Math.round(m.rail!.top)}`)
})

test.describe('in Korean', () => {
  test.use({ locale: 'ko-KR' })
  test('the Profile at 320×640: no scroll, the sign-out stands clear of the rail, each switch beside its word', async ({ page, request, baseURL }) => {
    test.setTimeout(300_000)
    test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL}`)
    const m = await open(page, { width: 320, height: 640 })
    expect(m.sheet!.scrollH, `320×640 ko: the Sheet scrolls (${m.sheet!.scrollH} in ${m.sheet!.clientH})`).toBeLessThanOrEqual(m.sheet!.clientH + 1)
    standsClear(m, '320×640 ko')
    switchesBesideTheirWords(m, '320×640 ko')
  })
})
