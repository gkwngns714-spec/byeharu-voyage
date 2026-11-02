import { useEffect, useRef, useState, type ReactNode } from 'react'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE LIST PANEL — a list that is ON the screen, not behind a press (owner, 2026-11-01)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"everything is folded in stats this is soo wrong. make it compact showing everything possible."*
// *"make things unfolded, minimize scrolling, everything compact with full info."*
//
// The one-page slice (2026-10-31) turned every list into ONE 44-px `SummaryRow` that opened a page:
// the Codex was `Goods 629 · Open` and 75 % of the glass under it was empty; the same for the
// Ledger, Rank, Routes and the Stats lists. docs/dev-log/2026-11-01-ui-unfold.md U1 reverses it: a
// press that opens a page is for ONE ITEM's detail, never for revealing the list itself.
//
// WHAT THIS IS. A panel with a FIXED HEADER (title, count, the filters and sort the list already has)
// and a BODY that scrolls inside it — the page never does (U2). The rows are the shared `Row`,
// packed: a pressable row stands on the 44-px reach floor, a read-only row on its text line (the
// floor is for what is pressed, U3). The panel is as tall as the glass leaves it (`flex-1`), so a
// tall phone shows ten rows and a desktop shows fourteen, never one.
//
// THE CUT EDGE IS VISIBLE. While more rows lie below, the last 1.25 rem of the body fades — a list
// that ends at a hard line reads as the whole list. At the end of the list the fade is gone.
//
// (`above` — the figures of a Stats face over or beside the panel, with a 12-rem floor and a figure block that scrolled inside
// itself on a short glass — stood here until 2026-11-02, when the owner called the packed Stats a mistake; a face's figures are
// cards on the page now, `look="card"` below, and nothing else ever used it.)
//
// WHAT IT DECIDES NOTHING ABOUT. The rows, the filters and what a press opens are the caller's.
//
// ═══ THE OTHER LOOK: `look="card"` (2026-11-02, owner row 267 — *"too packed … this was a mistake"*) ═══
// The panel above is the owner's compaction: a fixed-height box that scrolls inside itself, its rows packed to their text
// line and divided by a rule. The CARD is the pattern that replaces it, screen by screen (Stats first; Card.tsx has the
// whole pattern): the same header (title, count, sort, filters) on a `Card`'s surface with its room, and under it rows that
// stand 52 px on a phone and 60 from `lg`, parted by whitespace and not by a rule, a gentle hover on a desktop, and
// NO INNER SCROLL — the page scrolls, the card is as tall as its rows. Opt-in: `look` defaults to `panel`, so every screen
// that has not been redone is exactly what it was. `columns="fit"` lays the rows out in as many columns of at least 20 rem
// as the card holds (1 on a phone, 2 at 768 and 1,024, 3 at 1,280 and 1,440), each row its own query container, so a row is never
// wider than a column and a list never stretches name-to-price across the page. `footer` is where "Show all" stands.

/** A cell may carry the caller's own data-* hooks (a span, a view name) — typed once, as TileGrid does. */
type DataAttrs = { [K in `data-${string}`]?: string | number | boolean | undefined }

/** THE PACKING A LIST'S ROWS SHARE. `Row` is a 52-px band; a list that stands on the glass needs
 *  more rows than that allows. A read-only row (a `div`) keeps its 24-px text line and 4 px of air;
 *  a pressable one (`button`, `a`) keeps the 44-px reach floor. The selector, not the caller, says
 *  which is which — a row that gains an `onClick` gains its floor and cannot forget it. */
const PACKED =
  '[&_div[data-row-line]]:min-h-0 [&_div[data-row-line]]:py-1 [&_button[data-row-line]]:min-h-11 [&_a[data-row-line]]:min-h-11'

/** THE ROWS OF A CARD LIST (`look="card"`): no rule under a row, a row 52 px on a phone and 60 from `lg` (a button or a link
 *  keeps its 44-px reach inside that), 8 px of its own side padding with the body's `-mx-2` handing it back — so the hover
 *  fills a rounded band while the text stays on the card's padding line. The selector, not the caller, says so: a row that
 *  passes `hairline` still draws no rule here.
 *
 *  THE FIGURE STANDS AT THE ROW'S RIGHT EDGE (the `Row`'s tracks re-cut: mark · label 1fr · value · chevron). The unfold slice
 *  hugged the figure to its label (`Row`'s slack track) because a row was then 750 px wide and its price 700 px from its name.
 *  A row of a card list is one COLUMN wide (20 rem at the least), so the figures of a list stand on one edge
 *  and the eye runs down them — the label never shrinks below its own text (it wraps). */
const CARD_ROWS =
  '[&_[data-row-line]]:grid-cols-[auto_minmax(0,1fr)_max-content_0px_auto]! [&_[data-row-line]]:rounded-control [&_[data-row-line]]:border-b-0 [&_[data-row-line]]:px-2 lg:[&_[data-row-line]]:min-h-15 [@media(hover:hover)]:[&_[data-row-line]:hover]:bg-surface-2'

/** THE COLUMNS OF A `columns="fit"` CARD LIST: as many as hold 20 rem each (1 on a phone, 2 from 768, 3 from 1,152 of card);
 *  every row is its own query container, so a row asks the column it stands in and never the page. */
const CARD_COLUMNS = 'grid grid-cols-[repeat(auto-fill,minmax(min(100%,20rem),1fr))] gap-x-4 [&>*]:@container'

/** A BOUNDED SCROLL THAT KNOWS WHETHER MORE LIES BELOW. Private: `ScrollPane` is the bare bound; this adds
 *  the one thing the cut edge needs — `onMore(true)` while rows lie below the fold, and `data-more` on the
 *  box. `data-scroll-pane` stays the one hook that says "this is allowed to scroll" (ScrollPane.tsx).
 *
 *  NO MASK, EVER (found 2026-11-02 at 1280×707): the fade was a `mask-image` on this box, and a mask clips
 *  EVERYTHING in its subtree — including a `position: fixed` tray opened from a chart inside it, which stood
 *  at the right of the glass drawn nowhere and pressable by nothing. The fade is a sibling overlay. */
function CutEdge({
  className = '',
  onMore,
  children,
  ...rest
}: {
  className?: string
  onMore?: (more: boolean) => void
  children: ReactNode
} & DataAttrs) {
  const box = useRef<HTMLDivElement | null>(null)
  const [more, setMore] = useState(false)
  useEffect(() => {
    const el = box.current
    if (el === null) return
    const measure = () => {
      const below = el.scrollHeight - el.scrollTop - el.clientHeight > 2
      setMore(below)
      onMore?.(below)
    }
    measure()
    el.addEventListener('scroll', measure, { passive: true })
    // its own box changing size (a rotation, a taller glass) and its rows changing (a live feed's new
    // moves) both move the edge; neither fires a scroll event
    const resized = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(measure)
    resized?.observe(el)
    const grown = typeof MutationObserver === 'undefined' ? null : new MutationObserver(measure)
    grown?.observe(el, { childList: true, subtree: true })
    return () => {
      el.removeEventListener('scroll', measure)
      resized?.disconnect()
      grown?.disconnect()
    }
    // `onMore` is the caller's state setter: stable for the life of the box
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  return (
    <div
      ref={box}
      data-more={more}
      data-scroll-pane=""
      className={`bv-scroll min-h-0 overflow-y-auto ${className}`}
      {...rest}
    >
      {children}
    </div>
  )
}

/** ROWS PACKED LIKE A LIST PANEL'S, OUTSIDE A PANEL — a short board of five rows on a face's figure
 *  block (the best and worst day, the movers). One packing, one authority: `ListPanel` composes it. */
export function DenseRows({
  className = '',
  children,
  ...rest
}: {
  className?: string
  children: ReactNode
} & { 'data-testid'?: string }) {
  return (
    <div className={`${PACKED} ${className}`} {...rest}>
      {children}
    </div>
  )
}

export function ListPanel({
  title,
  count,
  trailing,
  controls,
  look = 'panel',
  columns = 1,
  footer,
  children,
  className = '',
  ...rest
}: {
  /** What the list is, in the player's word ("Every good"). Omit it where the screen's own tab already says it. */
  title?: ReactNode
  /** How many rows the list holds — hugs the title (or stands alone when there is no title). */
  count?: ReactNode
  /** THE ONE CONTROL OF THE TITLE'S LINE — the sort. It stands at the right of the title, so a list with a
   *  sort and one filter has a header of two lines, not four. */
  trailing?: ReactNode
  /** The filters and the view switch: one wrapping line under the title, fixed over the rows. */
  controls?: ReactNode
  /** `panel` (default): the fixed-height box that scrolls inside itself, as every list screen but Stats has it. `card`:
   *  the page layout's list (see the header). */
  look?: 'panel' | 'card'
  /** `card` only. `1`: one column of rows (a feed beside figure cards). `fit`: as many columns of at least 20 rem as fit. */
  columns?: 1 | 'fit'
  /** `card` only: what stands under the rows — the "Show all" that reveals the rest. */
  footer?: ReactNode
  /** The rows — `Row`s, or a `RankBars` — and nothing that is not a row of this list. */
  children: ReactNode
  className?: string
} & DataAttrs & { 'data-testid'?: string }) {
  const named = typeof title === 'string' ? title : undefined
  // WHETHER ROWS LIE BELOW THE FOLD — the cut edge draws itself only then (a list that ends does not fade).
  const [more, setMore] = useState(false)
  if (look === 'card') {
    return (
      <section
        data-list-panel=""
        data-list-look="card"
        aria-label={named}
        className={`min-w-0 rounded-tile border border-edge bg-surface p-4 md:p-5 xl:p-6 ${className}`}
        {...rest}
      >
        {(title !== undefined || count !== undefined || trailing !== undefined || controls !== undefined) && (
          <header className="mb-4 flex flex-col gap-3" data-list-header="">
            {(title !== undefined || count !== undefined || trailing !== undefined) && (
              <div className="flex min-h-8 flex-wrap items-center gap-x-3 gap-y-2">
                <h2 className="flex min-w-0 flex-1 items-baseline gap-2 text-t-body font-semibold text-ink md:text-t-card">
                  {title}
                  {count !== undefined && (
                    <span className="shrink-0 whitespace-nowrap text-t-label font-normal tabular-nums text-ink-muted" data-list-count="">
                      {count}
                    </span>
                  )}
                </h2>
                {trailing !== undefined && <div className="flex shrink-0 items-center gap-2">{trailing}</div>}
              </div>
            )}
            {controls !== undefined && <div className="flex min-w-0 flex-wrap items-center gap-2">{controls}</div>}
          </header>
        )}
        <div className={`-mx-2 ${CARD_ROWS} ${columns === 'fit' ? CARD_COLUMNS : '@container'}`} data-list-body="">
          {children}
        </div>
        {footer !== undefined && <div className="pt-3">{footer}</div>}
      </section>
    )
  }
  const panel = (
    <section
      data-list-panel=""
      aria-label={named}
      className={`relative flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded-tile bg-surface ${className}`}
      {...rest}
    >
      {(title !== undefined || count !== undefined || trailing !== undefined || controls !== undefined) && (
        <header className="flex shrink-0 flex-col gap-1 px-3 pb-1 pt-2" data-list-header="">
          {(title !== undefined || count !== undefined || trailing !== undefined) && (
            <div className="flex items-center gap-x-3">
              <h2 className="flex min-w-0 flex-1 items-baseline gap-2 text-t-body font-semibold text-ink">
                {title}
                {count !== undefined && (
                  <span className="shrink-0 whitespace-nowrap text-t-caption font-normal tabular-nums text-ink-muted" data-list-count="">
                    {count}
                  </span>
                )}
              </h2>
              {trailing !== undefined && <div className="flex shrink-0 items-center gap-2">{trailing}</div>}
            </div>
          )}
          {controls !== undefined && <div className="flex min-w-0 flex-wrap items-center gap-2">{controls}</div>}
        </header>
      )}
      <CutEdge onMore={setMore} className={`@container flex-1 px-3 pb-1 ${PACKED} [&>[data-row-line]:last-child]:border-b-0`} data-list-body="">
        {children}
      </CutEdge>
      {/* THE CUT EDGE: the last 1.25 rem of the body fades into the panel while more rows lie below. A sibling
          overlay, not a mask on the scroller (see CutEdge), and it takes no pointer. */}
      {more && <span aria-hidden="true" data-list-edge="" className="pointer-events-none absolute inset-x-0 bottom-0 h-5 bg-gradient-to-t from-surface to-transparent" />}
    </section>
  )
  return panel
}
