// Design-system WIDE-TABLE layout logic — pure (no React), beside Table.tsx exactly as
// screenLayout.ts sits beside Screen.tsx and overlayLayout.ts beside OverlayPanel.tsx.
//
// It does not replace <Table> and does not restyle it. It CONFIGURES the one table primitive for
// the case the primitive's own rule is about: a table too wide for a phone.
//
// ── THE DEFECT THIS FILE EXISTS TO CLOSE ────────────────────────────────────────────────────────
// Table.tsx puts `w-full min-w-full` on the <table>. `w-full` pins the table to its wrapper's
// width, so a six-column manifest on a 390px phone is CRUSHED to min-content — values break
// mid-figure ("4.1 / t", "→ Las / Palmas") — and, because min-content still does not fit, the table
// then overflows the wrapper anyway. Measured at 390x844 before this file existed:
//
//   fleets roster   table 359px in a 332px box  → 31px of the ENDURANCE column off the edge
//   fleets ships    table 429px in a 332px box  → 101px off the edge
//   market goods    table 379px in a 332px box  → 51px off the edge
//
// The wrapper is `overflow-x-auto`, so the content was technically reachable — but with overlay
// scrollbars there was no affordance, the header read as a bare "E", and a value that has been
// sheared is indistinguishable from a value that is missing. HIDDEN DATA IS WORSE THAN A SCROLLBAR.
//
// ── THE RULE ────────────────────────────────────────────────────────────────────────────────────
//   1. The table sizes to its CONTENT (`w-auto`), never to the box; `min-w-full` keeps it filling
//      the box when it is narrow enough to.
//   2. No cell breaks a value across lines. A figure is one token.
//   3. The FIRST column is sticky, so the thing a row is ABOUT stays on screen while its numbers
//      scroll. That is also the reach law: the first cell is the tap target on every table in this
//      game, and it may never be scrolled out of reach.
//   4. The scrollbar is drawn, thin and permanent, so "there is more to the right" is visible
//      rather than discovered.
//
// The page still never scrolls sideways: the scroll happens INSIDE this box, which is the whole
// point of Table.tsx's first structural rule.

/** Classes for the <Table> wrapper of a table that may be wider than a phone.
 *  @param stickyBg the token background the sticky first column paints over. IT MUST MATCH THE
 *  SURFACE THE TABLE SITS ON, or the scrolling columns show through the pinned one.
 *
 *  THE DEFAULT CHANGED ON 2026-08-22, and it was a real regression: D12 made a Card's body
 *  `bg-panel` (`--color-panel` is `color-mix(surface 88%, #3a2a1c)` — warmer than `--color-surface`,
 *  not equal to it) while this default still painted `bg-surface`. Every table in the game sits in
 *  a Card, so every sticky first column was painting the wrong colour and the columns sliding under
 *  it were faintly visible. Found by reading the tokens, not the screen — which is why the default
 *  now names the surface that actually exists rather than the one that used to. */
export function scrollTableClass(stickyBg: 'panel' | 'surface' | 'surface-2' = 'panel'): string {
  return [
    // 1. content-sized, never crushed
    '[&>table]:w-auto [&>table]:min-w-full',
    // 2. one value, one line
    '[&_th]:whitespace-nowrap [&_td]:whitespace-nowrap',
    // 3. the identity column stays put (and stays tappable)
    // `:not([colspan])` matters: a full-width band row (MARKET's "▾ BUY (< 90%)" heading spans
    // every column) must NOT be pinned, or it stays put and paints over the columns sliding under
    // it. Only real first cells are sticky.
    '[&_tr>*:first-child:not([colspan])]:sticky [&_tr>*:first-child:not([colspan])]:left-0 [&_tr>*:first-child:not([colspan])]:z-10',
    stickyBg === 'panel'
      ? '[&_tr>*:first-child:not([colspan])]:bg-panel'
      : stickyBg === 'surface'
        ? '[&_tr>*:first-child:not([colspan])]:bg-surface'
        : '[&_tr>*:first-child:not([colspan])]:bg-surface-2',
    // 4. a visible, thin, always-present scrollbar
    // NOTE: no `scrollbar-width: thin`. The standard property wins over the ::-webkit-scrollbar
    // pseudo-elements in Chromium and selects an OVERLAY scrollbar, which paints nothing at rest —
    // measured: `offsetHeight - clientHeight === 0`, i.e. no gutter, i.e. no affordance. Styling
    // the pseudo-element alone gives a classic scrollbar that reserves 6px and is always visible.
    'overscroll-x-contain',
    '[&::-webkit-scrollbar]:h-1.5',
    '[&::-webkit-scrollbar-track]:rounded [&::-webkit-scrollbar-track]:bg-surface-2',
    '[&::-webkit-scrollbar-thumb]:rounded [&::-webkit-scrollbar-thumb]:bg-edge',
  ].join(' ')
}

/** The one-line hint that belongs under a table wide enough to need scrolling. One authority for
 *  the words, so five screens cannot invent five ways of saying it.
 *
 *  WHEN it is printed is NOT the caller's decision any more — `<Table scrollHint>` measures its own
 *  overflow and prints this only while there really is something to the right (Table.tsx). Three
 *  screens used to print it unconditionally and PORT's Alongside face printed it under a table
 *  that fitted. */
// Pin moved deliberately 2026-08-22 with the wordiness pass: nine words carried the same
// affordance as fifteen, and the line now appears under tables where it is true, so it is read
// rather than skipped. tests/tableLayout.spec.ts holds the matching pin.
export const TABLE_SCROLL_HINT = 'Swipe the table for the rest.'
