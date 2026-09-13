import { useRef, useState, type ReactNode } from 'react'
import { sheetBodyClass, sheetColumnClass } from './screenLayout'

// THE SHEET — the one scrolling surface of a tab, and the end of the admin document.
//
// docs/UI_DIRECTION.md §3 rule 1 named the shape this replaces: every screen in this game is
//     Screen → PageHeader(eyebrow, title, ⓘ, actions) → N × Card(head: CardHeader(eyebrow, title,
//     ⓘ, aside Badge)) → SectionLabel → dl of StatRow/DetailRow → fine-print footer
// — thirty-three `<Card>`s and nine `PageHeader`s of it, boxes inside boxes five borders deep on
// one tap target. That is the Bootstrap-era "page with panels" template, and it is what the owner
// meant by *"old fashioned component structure."*
//
// A SHEET IS ONE SURFACE. Sections are separated by 24px of space and a `t-label` heading — never
// by a box, never by a border, never by a header bar. §4.3 states the rule this enforces: "never a
// surface inside a surface". `Tile` and `Row` are the one level of nesting allowed, and they sit
// ON the sheet rather than in a card on it.
//
// ── THE TITLE STARTS LARGE AND PINS SMALL ──────────────────────────────────────────────────────
// §5: "Title (t-title) that starts large and pins small on scroll; one optional trailing control".
// Implemented with a sentinel and a scroll handler on the sheet's own scroll box rather than with
// `position: sticky` alone, because sticky can pin the title but cannot tell it to shrink — and a
// 20px title that stays 20px while the content slides under it is a header bar, which is the thing
// being deleted. The pinned bar carries the same title at `t-body`, so nothing is lost and 26px of
// a 844px screen is given back.
//
// NO EYEBROW. The nine `ORDERS` / `ASSETS` / `HARBOUR` / `TRADE` / `RECORD` / `STANDINGS` /
// `REFERENCE` / `ACCOUNT` micro-designators are 31 of the 31 uppercase letter-spaced labels §2
// item 15 counts, and the strongest single "2008 dashboard" signal on the screen. The tab you are
// on is named in the nav; naming it twice is the document talking about itself.
//
// NO ⓘ ON A TITLE. §5's `Hint` budget: one per section, none on titles.

export function Sheet({
  title,
  trailing,
  children,
  className = '',
  ...rest
}: {
  /** The tab's name, in the player's words. One or two words. */
  title: ReactNode
  /** ONE control, on the title's line — a `Segmented`, a `Chip`, a `Button`. Never two. */
  trailing?: ReactNode
  children: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  const [pinned, setPinned] = useState(false)
  const box = useRef<HTMLDivElement | null>(null)

  return (
    <div
      ref={box}
      onScroll={(e) => {
        // One threshold, and it is the height the large title gives up: 26px is `t-title`'s own
        // line box. Above it the title is the page; below it, it is a label on a bar.
        const next = (e.currentTarget.scrollTop ?? 0) > 26
        if (next !== pinned) setPinned(next)
      }}
      className={`h-full overflow-y-auto ${className}`}
      {...rest}
    >
      <header
        data-testid="sheet-header"
        data-pinned={pinned}
        className={[
          'sticky top-0 z-10 flex items-center justify-between gap-3 px-gutter pb-2 pt-4',
          sheetColumnClass(),
          // AT REST THE TITLE STANDS ON THE WORLD; PINNED, IT IS A BAR. Measured on the gallery at
          // 390×844 (shots dark-1/light-1): an always-opaque header reads as a title bar even at
          // scrollTop 0, which is a header bar — the thing §3 rule 1 deletes — reintroduced by the
          // one primitive that replaced it. Opaque only when it is actually holding content back.
          pinned ? 'bg-surface' : '',
        ].join(' ')}
      >
        <h1 className={pinned ? 'truncate text-t-body' : 'truncate text-t-title'}>{title}</h1>
        {trailing !== undefined && <div className="shrink-0">{trailing}</div>}
      </header>
      {/* THE READABLE COLUMN. On a phone it is the glass; from `lg` it is SHEET_REM at most with
          the tray's space kept clear at its right — screenLayout.ts, "the wide glass". */}
      <div className={sheetBodyClass()}>{children}</div>
    </div>
  )
}

/** A section of a sheet: 24px of air above it and a `t-label` heading, and no box of any kind.
 *  `heading` is optional — an unnamed section is the commonest kind, and a label nobody needs is
 *  §2 item 15 growing back. */
export function SheetSection({
  heading,
  trailing,
  children,
  className = '',
  ...rest
}: {
  heading?: ReactNode
  /** One control belonging to this section — a filter chip, a count. */
  trailing?: ReactNode
  children: ReactNode
  className?: string
} & { 'data-testid'?: string }) {
  return (
    <section className={`mt-6 first:mt-2 ${className}`} {...rest}>
      {(heading !== undefined || trailing !== undefined) && (
        <div className="mb-2 flex min-h-8 items-center justify-between gap-3">
          {heading !== undefined && <h2 className="text-t-label text-ink-muted">{heading}</h2>}
          {trailing !== undefined && <div className="shrink-0">{trailing}</div>}
        </div>
      )}
      {children}
    </section>
  )
}
