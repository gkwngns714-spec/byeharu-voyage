import type { ComponentProps, ReactNode } from 'react'
import { PAGE_GAP, pageSplitClass } from './screenLayout'
import { StatCell } from './StatCell'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PAGE'S PIECES — a split, a card, a stat card (2026-11-02, owner row 267)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"i want you to redesign the looks of the game. for example stats, it looks so wrong. The past was
// better. right now everything is on left, too packed. this was a mistake."*
//
// The unfold slice (2026-11-01) answered *"make it compact showing everything possible"* with one packed
// column on the left, 44-52 px rows divided by thin rules, 8-12 px between a label and its figure, and a
// 26-rem column kept clear at the right for a tray that is usually shut. This is the other shape, and it is
// the PATTERN every screen takes in its turn (docs/dev-log/2026-11-02-stats-design.md has the measured
// numbers and what the next screen copies):
//
//   Sheet layout="page"   the container: centred, content at most 80 rem, margins 16 · 24 · 32 · 40, the title 30 px
//   StatStrip             a row of stat cards across the page (the live band): 1 · 2 · 4 across
//   PageSplit             MAIN | SIDE from 1,024 px; the SIDE is the tray's column and is always used
//   CardRow               two cards across inside a column (from 768; one under it at 1,024-1,279, where main is 584)
//   Card                  a block with ROOM: 12-px corners, one tone step and one hairline, 16 px of padding on a
//                         phone, 20 from 768 and 24 from 1,280, a title at 16 px (18 from 768)
//   StatCard              a card that is ONE figure: the label at 14 px over the figure at 24 px
//   StatCell look=…       the same figure inside a card: `stacked` (label over figure) or `line` (label left,
//                         figure right) — never a label and a figure hugging at 8 px
//   ListPanel look="card" a list as a card: rows 52-60 px, whitespace and not a rule between rows, a gentle hover,
//                         figures on the row's right edge, the page scrolling (never an inner scroll)
//
// NO SECOND SKIN. A card is `surface` on the world with the `edge` hairline (docs/UI_DIRECTION.md §4.3: a tone step,
// and where a step will not do, a hairline — never a box). It holds `surface-2` insets (a picker, a chip) but never
// another card. The grid decides widths, not the card: no card is wider than a column of the page, and a figure card is
// never wider than 560 px at any glass (408 px in a CardRow at 1,440).

/** A custom `data-*` hook a caller may put on a split (a face's own test id, its span). */
type DataAttrs = { [K in `data-${string}`]?: string | number | boolean | undefined }

/** THE STAT STRIP: a row of `StatCard`s across the whole page — one column on a phone (each a line), two from 640, four from
 *  1,280 (302 px a card at 1,440: the world's money, nine digits and a coin, is 188 px at 24 px and fits it with its padding). */
export function StatStrip({
  className = '',
  children,
  ...rest
}: {
  className?: string
  children: ReactNode
  'aria-label'?: string
} & { 'data-testid'?: string }) {
  return (
    <section className={`grid grid-cols-1 ${PAGE_GAP} sm:grid-cols-2 xl:grid-cols-4 ${className}`} data-stat-strip="" {...rest}>
      {children}
    </section>
  )
}

/** MAIN | SIDE — the page's one split (screenLayout.ts "THE PAGE"). From 1,024 px `main` stands left and `side` stands in the
 *  tray's column (352 · 384 · 416 px), top-aligned (neither is stretched to the other's height, so a short side leaves its
 *  space under it rather than padding a card); below 1,024 px they are one column. `sideFirst` puts the side ABOVE main
 *  there (a screen whose side holds what the main list is read with: the filters, the day's figures) and leaves the
 *  wide order alone. A tray opened from either slides over the side column. */
export function PageSplit({
  main,
  side,
  sideFirst = false,
  stickySide = false,
  className = '',
  ...rest
}: {
  main: ReactNode
  side: ReactNode
  sideFirst?: boolean
  /** From 1,024 px the side follows the scroll (a short side beside a long list: the day's figures and the movers beside 629 goods),
   *  stopping under the pinned title. Off, it stands where it is. */
  stickySide?: boolean
  className?: string
} & DataAttrs & { 'data-testid'?: string }) {
  return (
    <div className={`${pageSplitClass()} ${className}`} data-page-split="" {...rest}>
      <div className={`flex min-w-0 flex-col ${PAGE_GAP} ${sideFirst ? 'lg:order-1' : ''}`} data-page-main="">
        {main}
      </div>
      <aside className={`flex min-w-0 flex-col ${PAGE_GAP} ${sideFirst ? 'order-first lg:order-2' : ''} ${stickySide ? 'lg:sticky lg:top-16' : ''}`} data-page-side="">
        {side}
      </aside>
    </div>
  )
}

/** TWO CARDS ACROSS: inside a column of the page, two from 768 (a page of one column is 720 px there), one at 1,024-1,279
 *  (main is 584 px: two would be 280 each), two again from 1,280 (384 · 408 px). */
export function CardRow({
  className = '',
  children,
  ...rest
}: {
  className?: string
  children: ReactNode
} & { 'data-testid'?: string }) {
  return (
    <div className={`grid grid-cols-1 ${PAGE_GAP} md:grid-cols-2 lg:grid-cols-1 xl:grid-cols-2 ${className}`} {...rest}>
      {children}
    </div>
  )
}

/** THE CARD: a titled block with room around its content. `title` is the card's own words (16 px, 18 from 768); `aside` is
 *  the ONE small control of the title's line (a window picker); `compact` is for a card that is one figure. */
export function Card({
  title,
  aside,
  compact = false,
  className = '',
  children,
  ...rest
}: {
  title?: ReactNode
  aside?: ReactNode
  compact?: boolean
  className?: string
  children?: ReactNode
} & { 'data-testid'?: string }) {
  return (
    <section
      className={[
        'min-w-0 rounded-tile border border-edge bg-surface',
        compact ? 'p-4 md:px-5 md:py-4 xl:px-6 xl:py-5' : 'p-4 md:p-5 xl:p-6',
        className,
      ].join(' ')}
      data-card=""
      {...rest}
    >
      {(title !== undefined || aside !== undefined) && (
        <header className="mb-4 flex min-h-8 flex-wrap items-center justify-between gap-x-3 gap-y-2">
          {title !== undefined && <h2 className="min-w-0 text-t-body font-semibold text-ink md:text-t-card">{title}</h2>}
          {aside !== undefined && <div className="ml-auto shrink-0">{aside}</div>}
        </header>
      )}
      {children}
    </section>
  )
}

/** A STAT CARD: one labelled figure and nothing else — the page's live band (money, at sea, trades, the world's money). The
 *  label (14 px, muted) stands over the figure (24 px, tabular); on a phone the card is one line, the label at its left and
 *  the figure at its right (the figure drops under its label only where the two do not fit one line), so four of them cost
 *  56 px each and not 84. The figure counts to its new value (`StatCell` → `Counter`). Every other prop is a `StatCell`'s. */
export function StatCard({ className = '', ...stat }: Omit<ComponentProps<typeof StatCell>, 'look'>) {
  return (
    <Card compact>
      <StatCell
        look="stacked"
        className={`max-sm:flex-row max-sm:flex-wrap max-sm:items-baseline max-sm:justify-between max-sm:gap-x-4 ${className}`}
        {...stat}
      />
    </Card>
  )
}
