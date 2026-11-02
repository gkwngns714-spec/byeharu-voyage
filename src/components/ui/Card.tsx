import type { ComponentProps, ReactNode } from 'react'
import { cardSpanClass, pageGridClass, type CardSpan } from './screenLayout'
import { StatCell } from './StatCell'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE PAGE'S PIECES — a grid, a card, a stat card (2026-11-02, owner row 267)
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
//   Sheet layout="page"   the container: centred, at most 90 rem, margins 16 · 24 · 48, the title at 30 px
//   PageGrid              twelve columns from `md`, 20-24 px gutters; one column below
//   Card                  a block with ROOM: 16-px corners (`rounded-sheet`), one tone step and one hairline,
//                         16 px of padding on a phone and 24 from `lg`, a title at 16 px (18 from `md`)
//   StatCard              a card that is ONE figure: the label at 14 px above it, the figure at 24 px
//   StatCell look=…       the same figure inside a card: `stacked` (label over figure) or `line` (label left,
//                         figure right) — never a label and a figure hugging at 8 px
//   ListPanel look="card" a list as a card: rows 52-60 px, whitespace instead of a rule between rows, a gentle
//                         hover, the page scrolling (never an inner scroll)
//
// NO SECOND SKIN. A card is `surface` on the world with the `edge` hairline (docs/UI_DIRECTION.md §4.3: a
// tone step, and where a step will not do, a hairline — never a box). It holds `surface-2` insets (a picker, a
// chip) but never another card. The grid decides widths, not the card: a card takes a `span`
// (screenLayout.ts `CardSpan`), and the figure cards are never wider than 560 px at any glass.

/** THE 12-COLUMN PAGE GRID. Children are `Card`s (or anything that takes a `span` class). */
export function PageGrid({
  className = '',
  children,
  ...rest
}: {
  className?: string
  children: ReactNode
} & { 'data-testid'?: string }) {
  return (
    <div className={`${pageGridClass()} ${className}`} data-page-grid="" {...rest}>
      {children}
    </div>
  )
}

/** A ZONE OF CARDS — several cards that stand in one span of the page and lay themselves out two across
 *  (one on a phone). It is how a tall card (a log, a list) stands BESIDE a block of figure cards without a
 *  row-span stretching them: the zone is its own grid, so the tall card's height moves nothing in it. */
export function CardZone({
  span = 'zone',
  className = '',
  children,
  ...rest
}: {
  span?: CardSpan
  className?: string
  children: ReactNode
} & { 'data-testid'?: string }) {
  return (
    <div className={`${cardSpanClass(span)} grid min-w-0 grid-cols-1 content-start gap-4 sm:gap-5 md:grid-cols-2 lg:gap-6 ${className}`} {...rest}>
      {children}
    </div>
  )
}

/** THE CARD: a titled block with room around its content. `title` is the card's own words (16 px, 18 from `lg`);
 *  `aside` is the ONE small control of the title's line (a window picker); `compact` is for a card that is one
 *  figure. Without a `span` the card fills the cell it is put in (inside a `CardZone`, or a plain stack). */
export function Card({
  title,
  aside,
  span,
  compact = false,
  className = '',
  children,
  ...rest
}: {
  title?: ReactNode
  aside?: ReactNode
  span?: CardSpan
  compact?: boolean
  className?: string
  children?: ReactNode
} & { 'data-testid'?: string }) {
  return (
    <section
      className={[
        'min-w-0 rounded-sheet border border-edge bg-surface',
        compact ? 'p-4 lg:px-6 lg:py-5' : 'p-4 sm:p-5 lg:p-6',
        span === undefined ? '' : cardSpanClass(span),
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

/** A STAT CARD: one labelled figure and nothing else — the page's live band (money, at sea, trades, the world's
 *  money). The label (14 px, muted) stands over the figure (24 px, tabular) from `sm`; on a phone the card is one
 *  line, the label at its left and the figure at its right, so four of them cost 56 px each and not 84. The
 *  figure counts to its new value (`StatCell` → `Counter`). Every other prop is a `StatCell`'s. */
export function StatCard({
  span = 'quarter',
  className = '',
  ...stat
}: { span?: CardSpan } & Omit<ComponentProps<typeof StatCell>, 'look'>) {
  return (
    <Card span={span} compact>
      <StatCell
        look="stacked"
        className={`max-sm:flex-row max-sm:items-baseline max-sm:justify-between max-sm:gap-4 ${className}`}
        {...stat}
      />
    </Card>
  )
}

/** A custom `data-*` hook a caller may put on a band (a face's own test id, its span). */
type DataAttrs = { [K in `data-${string}`]?: string | number | boolean | undefined }

/** A BAND: a full-width run of the page that is itself the 12-column grid, with an optional heading line of its own
 *  (a title at 16/18 px and ONE control — a window picker). The live band (four stat cards), a face's whole body
 *  and a "Movers" row are bands; a band's children are cards, and they stand on the same columns as the page's. */
export function Band({
  title,
  aside,
  span = 'full',
  className = '',
  children,
  ...rest
}: {
  title?: ReactNode
  aside?: ReactNode
  span?: CardSpan
  className?: string
  children: ReactNode
  'aria-label'?: string
} & DataAttrs & { 'data-testid'?: string }) {
  return (
    <section className={`min-w-0 ${cardSpanClass(span)} ${className}`} data-band="" {...rest}>
      {(title !== undefined || aside !== undefined) && (
        <div className="mb-3 flex min-h-11 flex-wrap items-center justify-between gap-x-3 gap-y-2">
          {title !== undefined && <h2 className="min-w-0 text-t-body font-semibold text-ink md:text-t-card">{title}</h2>}
          {aside !== undefined && <div className="ml-auto shrink-0">{aside}</div>}
        </div>
      )}
      <div className={pageGridClass()}>{children}</div>
    </section>
  )
}
