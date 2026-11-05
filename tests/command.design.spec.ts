import { test, expect, type Page } from '@playwright/test'
import { reachable, ready } from './appReady.fixture'
import { phoneLaws, readGlass } from './unfold.fixture'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COMMAND DESK TAKES THE CARD AND THE TYPE SCALE — measured at three wide glasses and a phone, in English and Korean (2026-11-05)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was better. right now
// everything is on left, too packed. this was a mistake."* (owner, 2026-11-02, row 267.) docs/dev-log/2026-11-02-stats-design.md §7
// item 6: the HQ and the Command desk "take the card and the type scale, not the split". The desk is a TRADING TERMINAL — a header
// line over three panes that use the whole glass, each pane scrolling inside itself by design (the owner's "stock trading screen",
// 2026-10-17) — so the split stays exactly as it is and its panes keep working (tests/desk.terminal.spec.ts). What changes is how it
// LOOKS: the three panes are CARDS with air between them (they were three columns divided by hairlines), the desk's title is the
// page's card-title voice (18 px, it was 14), and its two key figures are the page's 24-px figure (they were 14), the labels over them
// 14 px (they were 12).
//
// THE LAWS, from 1,024 px (the terminal; a phone keeps its Sheet, which is why it is only a guard here):
//   (a) THE PANES ARE CARDS: the three panes stand in `[data-card]` surfaces, at least 12 px apart from one another, none touching
//       the glass's edge (a margin of at least 12 px at the left and the right).
//   (c) THE HIERARCHY: the desk's title is at least 18 px, the key figures (supplies, cargo) at least 24 px, their labels at least 14.
//   (b) THE DEFECT RULES STAND (the unfold apparatus), from 1,024: no overlap, no one-letter wrap, no cut text without a way to read it, no
//       sideways scroll.
//   (g) A PHONE IS UNCHANGED: no sideways scroll and the desk still stands in its Sheet (`data-desk` absent).

const SIZES = [
  { width: 1440, height: 900 },
  { width: 1280, height: 800 },
  { width: 1024, height: 768 },
] as const

async function open(page: Page, glass: { width: number; height: number }) {
  await page.setViewportSize(glass)
  await page.goto('command')
  await ready(page)
  await expect(page.getByTestId('trade-good').first()).toBeVisible({ timeout: 120_000 })
  await page.waitForTimeout(500)
}

/** The desk's three panes, the title and the key figures, as boxes and sizes. Self-contained, shipped into the page. */
const READ = () => {
  const px = (e: Element | null) => (e ? parseFloat(getComputedStyle(e).fontSize) : 0)
  const box = (e: Element | null) => {
    if (!e) return null
    const r = e.getBoundingClientRect()
    return { l: r.left, t: r.top, r: r.right, b: r.bottom }
  }
  const panes = ['desk-pane-list', 'desk-pane-chart', 'desk-pane-ticket'].map((id) => {
    const e = document.querySelector(`[data-testid="${id}"]`)
    const card = e?.closest('[data-card]') ?? null
    return { id, inCard: card !== null, box: box(card ?? e) }
  })
  const line = document.querySelector('[data-testid="command-line"]')
  const figures = [...(line?.querySelectorAll('.tabular-nums') ?? [])].map(px)
  const labels = [...(line?.querySelectorAll('[data-desk-label]') ?? [])].map(px)
  return {
    glass: innerWidth,
    title: px(document.querySelector('[data-testid="desk-header"] h1')),
    figures,
    labels,
    panes,
  }
}

for (const locale of ['en-US', 'ko-KR'] as const) {
  test.describe(`the Command desk is a card page — ${locale}`, () => {
    test.use({ locale })

    for (const glass of SIZES) {
      test(`the desk at ${glass.width}×${glass.height}: panes as cards, the type scale, no overlap`, async ({ page, request, baseURL }) => {
        test.setTimeout(420_000)
        test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
        await open(page, glass)
        const where = `${locale} desk @${glass.width}×${glass.height}`
        const failures: string[] = []
        const d = await page.evaluate(READ)

        // (a) THE PANES ARE CARDS
        for (const p of d.panes) if (!p.inCard) failures.push(`${where}: (a) ${p.id} is not in a card`)
        const boxes = d.panes.map((p) => p.box).filter((b): b is NonNullable<typeof b> => b !== null)
        for (let i = 1; i < boxes.length; i++) {
          const gap = boxes[i].l - boxes[i - 1].r
          if (gap < 11.5) failures.push(`${where}: (a) panes ${i} and ${i + 1} stand ${Math.round(gap)} px apart — the law is 12`)
        }
        if (boxes.length > 0) {
          if (boxes[0].l < 11.5) failures.push(`${where}: (a) the first pane stands ${Math.round(boxes[0].l)} px from the glass's edge`)
          if (d.glass - boxes[boxes.length - 1].r < 11.5) failures.push(`${where}: (a) the last pane stands ${Math.round(d.glass - boxes[boxes.length - 1].r)} px from the glass's edge`)
        }

        // (c) THE HIERARCHY
        if (d.title < 17.5) failures.push(`${where}: (c) the desk's title is ${d.title} px — the card title is 18`)
        if (d.figures.length === 0 || Math.min(...d.figures) < 23.5) failures.push(`${where}: (c) a key figure is ${d.figures.join('/')} px — the law is 24`)
        if (d.labels.length === 0 || Math.min(...d.labels) < 13.5) failures.push(`${where}: (c) a label over a key figure is ${d.labels.join('/')} px — the law is 14`)

        // (b) THE DEFECT RULES
        // From 1,024, the terminal's smallest glass: the centre pane must keep its names and its Buy and Sell readable (2026-11-05: at 1,024 the
        // centre pane was ~350 px and cut to three card columns, so a name stood one letter wide and, in Korean, Buy stood over Sell).
        const flat = await readGlass(page, 'desk-pane-chart', 'trade-good', '[data-testid="command"]')
        failures.push(...phoneLaws(where, flat).map((m) => m.replace(/: \([abcd]\) /, ': (b) ')))
        const rows = await page.evaluate(() => [...document.querySelectorAll('[data-testid="trade-good"]')].slice(0, 12).map((c) => {
          const r = (id: string) => c.querySelector(`[data-testid="${id}"]`)?.getBoundingClientRect()
          const n = r('trade-good-name'), b = r('trade-buy'), s = r('trade-sell')
          return { w: Math.round(c.getBoundingClientRect().width), nameLines: n ? Math.round(n.height / parseFloat(getComputedStyle(c.querySelector('[data-testid="trade-good-name"]') as Element).lineHeight || '16')) : 0, side: !!b && !!s && Math.abs(b.top - s.top) < 4 }
        }))
        for (const c of rows) {
          if (c.nameLines > 2) failures.push(`${where}: (b) a name runs ${c.nameLines} lines in a ${c.w} px card`)
          if (!c.side) failures.push(`${where}: (b) Buy and Sell are stacked in a ${c.w} px card — they stand side by side`)
        }

        if (failures.length > 0) console.log(`LAWS ${where}: ${failures.length} lines\n  ${failures.join('\n  ')}`)
        expect(failures, 'The Command desk is not on the card and type scale').toEqual([])
      })
    }

    test('the desk at 390×844 is unchanged: still its Sheet, no sideways scroll', async ({ page, request, baseURL }) => {
      test.setTimeout(420_000)
      test.skip(!(await reachable(request, baseURL ?? '')), `nothing served at ${baseURL} — run \`npm run preview\` and re-run`)
      await open(page, { width: 390, height: 844 })
      expect(await page.locator('[data-testid="command"][data-desk]').count()).toBe(0)
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= document.documentElement.clientWidth)).toBe(true)
    })
  })
}
