// PURE UNIT SPEC — the wide-table class contract. No browser, runs anywhere, runs in a second.
//
// It cannot measure pixels. What it CAN do is pin the four structural guarantees that the pixel
// defect came from, so that deleting one of them fails here rather than in a screenshot three days
// later. The measurement itself lives in tests/layout.spec.ts, which needs a served app.
//
// The defect this is the tripwire for: Table.tsx puts `w-full` on the <table>, which pins it to its
// wrapper's width. A six-column manifest on a 390px phone was then crushed to min-content — values
// broke mid-figure ("4.1 / t") — and still overflowed the box by 31-101px, sheared, with no
// affordance. `[&>table]:w-auto` is the single class that fixes it, and it is easy to lose.

import { test, expect } from '@playwright/test'
import { TABLE_SCROLL_HINT, scrollTableClass } from '../src/components/ui/tableLayout'

test('the table sizes to its CONTENT, never to the box — the class that fixes the shear', () => {
  const c = scrollTableClass()
  // Without this, `w-full` from Table.tsx wins and the table is crushed and then clipped.
  expect(c).toContain('[&>table]:w-auto')
  // ... but it still fills the box when the content is narrow enough to.
  expect(c).toContain('[&>table]:min-w-full')
})

test('no cell breaks a value across lines — a figure is one token', () => {
  const c = scrollTableClass()
  expect(c).toContain('[&_th]:whitespace-nowrap')
  expect(c).toContain('[&_td]:whitespace-nowrap')
})

test('the first column is sticky, so the row identity and its tap target stay reachable', () => {
  const c = scrollTableClass()
  expect(c).toContain(':first-child:not([colspan])]:sticky')
  expect(c).toContain(':first-child:not([colspan])]:left-0')
  // `:not([colspan])` is load-bearing: MARKET's full-width band rows ("▾ BUY (< 90%)") must NOT
  // be pinned, or they stay put and paint over the columns sliding underneath them. Measured: with
  // the naive selector the goods table failed its own reachability check.
  expect(c).not.toMatch(/\[&_tr>\*:first-child\]:sticky/)
})

test('scrollbar-width is NOT set, because the standard property selects an overlay scrollbar', () => {
  // Measured in Chromium at 390x844: with `scrollbar-width: thin` the wrapper reported
  // `offsetHeight - clientHeight === 0` — no gutter, nothing painted at rest, no affordance.
  // The ::-webkit-scrollbar rules are the ones that can draw something, and the standard property
  // overrides them. So the words carry the affordance instead (TABLE_SCROLL_HINT).
  expect(scrollTableClass()).not.toContain('scrollbar-width')
  expect(scrollTableClass()).toContain('[&::-webkit-scrollbar]:h-1.5')
})

test('the sticky column paints the surface it sits on, or the columns show through it', () => {
  // Pin moved deliberately 2026-08-22: the DEFAULT is now `panel`, because that is what a Card's
  // body has been painted since D12 and a sticky column must match the surface under it. The two
  // older options still resolve, so a caller that needs them has not been taken away.
  expect(scrollTableClass()).toContain(':bg-panel')
  expect(scrollTableClass('surface')).toContain(':bg-surface')
  expect(scrollTableClass('surface-2')).toContain(':bg-surface-2')
})

test('there is ONE wording for "there is more to the right"', () => {
  // Pin moved deliberately 2026-08-22 with the wordiness pass ("this is a game, make it so").
  // The words are shorter and, more to the point, WHEN they appear is no longer the caller's
  // choice: `<Table scrollHint>` measures its own overflow (Table.tsx) so the line is absent under
  // a table that fits. PORT's Alongside face printed it under a five-column table with room to
  // spare, which is a hint that is false.
  expect(TABLE_SCROLL_HINT).toBe('Swipe the table for the rest.')
})
