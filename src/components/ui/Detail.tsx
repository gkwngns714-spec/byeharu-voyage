import type { ReactNode } from 'react'
import { Icon } from './Icon'
import { ScrollPane } from './ScrollPane'
import { detailColumnClass, glassBesideRailClass } from './screenLayout'
import { KEEP_WORDS_CLASS } from './tileStyles'
import { useBackLayer } from './useBackLayer'
import { useT } from '../../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE POP-UP PAGE, AND THE SUMMARY ROW THAT OPENS IT (owner, 2026-10-31)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"everything has folded. enough with folding things. make everything small, compact and once
// clicked show new page popping up. this is wrong"*
//
// ONE MECHANISM, EVERYWHERE. A compact block is ONE `SummaryRow`: its title, its key figure, the
// plain word Open and a chevron, 44 px tall. A press opens a `DetailPage`: a full-screen page fixed
// OVER the tab (not a route, not an in-place unfold), with a back press, the block's title and
// figure in its header, and its content scrolling inside the page's own bounded body. The tab
// behind is never re-flowed — a fixed overlay is out of flow by construction — so the owner's
// press law holds (a press selects and opens; nothing behind moves).
//
// WHY AN OVERLAY AND NOT A ROUTE: a route would remount the tab and lose the compact screen's
// state (which city is in hand, which face is selected), and the owner's law says the surface
// behind the press must not move or rebuild. The overlay keeps the tab exactly as it was; a back
// press reveals it untouched. It is also the ONE implementation: no screen invents its own page.
//
// THE PAGE LAW: the page is `fixed inset-0 h-[100dvh]` and does NOT scroll itself; its body is one
// `ScrollPane`, so the page lands with the same no-scroll law as a tab (`onepage.spec.ts` measures
// `[data-detail-page]`). Nothing is deleted: the whole former block lives in the page.

/** A compact block's one line: title, key figure, the word Open, and a chevron. `data-summary-row`
 *  is what the one-page spec walks. The test id names the row; its page is `${testid}-page`. */
export function SummaryRow({
  title,
  figure,
  word,
  onClick,
  className = '',
  ...rest
}: {
  title: ReactNode
  /** The block's key figure — a number, a formatted string, a `<Figure>`. */
  figure?: ReactNode
  /** ONE plain word ("Open"). */
  word?: ReactNode
  onClick: () => void
  className?: string
} & { 'data-testid'?: string }) {
  // ── ON A PHONE'S HALF GLASS THE TITLE IS NEVER CUT (2026-11-02; owner: an Inn row read "Capt…" with nothing to press
  // to read it). Inside a query container narrower than 15 rem (`narrow:`, index.css — the HQ's panel at 390 and 320)
  // the row is a WRAPPING line, as `Row` is: the title keeps its words (up to 5 rem before it wraps), the figure drops
  // under it when the two do not fit one line, and the chevron is laid over the right edge of line 1. A summary row
  // that is not inside such a container is one line while its title fits.
  // THE TITLE IS NEVER CUT ON ANY GLASS (2026-11-11, the full-names slice): a title is often a NAME (a good, a city, a fleet), and the
  // owner's rule is that a name is printed whole. It keeps its words (`KEEP_WORDS_CLASS`): it turns only at a space and its box is never
  // narrower than its longest word. The pop-up page's own title, below, follows the same rule.
  // THE ROW IS A WRAPPING LINE ON EVERY GLASS: the title takes what the figure and the word leave (never under its longest word, never
  // over its own width, so the figure still hugs it), and where its longest word does not fit beside them (two rows side by side on a
  // phone: 187 px each on Trade) the word and the chevron stand on the next line, at the right, instead of the row running off the glass.
  // THE ROW IS A BAR YOU CAN SEE (2026-11-14, the look pass). Its fill was `surface`, the card's own tone: inside a card (the Inn, the
  // Port) the bar was invisible and its 12-px inset read as a row out of line with the card's title and with every plain row. It is
  // `surface-2` now, the tone of every pressable inset, so it is a bar on the sea and in a card alike (two in a stack: `SUMMARY_STACK_CLASS`, cardStyles.ts).
  // Inside a `narrow:` container the row has no inset and no fill, as before.
  return (
    <button
      type="button"
      onClick={onClick}
      data-summary-row=""
      className={`flex min-h-11 w-full flex-wrap items-center justify-between gap-x-3 rounded-control bg-surface-2 px-3 py-2 text-left transition hover:bg-edge narrow:bg-transparent narrow:relative narrow:flex-wrap narrow:content-center narrow:justify-start narrow:gap-y-0 narrow:px-0 narrow:pr-6 ${className}`}
      {...rest}
    >
      <span
        title={typeof title === 'string' ? title : undefined}
        data-row-cell="label"
        data-name=""
        className={`${KEEP_WORDS_CLASS} max-w-max flex-[1_1_0%] text-t-body font-semibold text-ink narrow:flex-[1_1_5rem]`}
      >
        {title}
      </span>
      {/* THE FIGURE HUGS ITS TITLE (owner, 2026-11-01: *"empty spaces between words and numbers
          horizontally… make it so that htey are closer, more compact"*). It used to be pushed to the
          right edge by `justify-between`; now only the WORD and the chevron stand at the edge — the
          affordance keeps its place, the number keeps its label. The `data-row-cell` names are the
          slots align.spec reads: label · value (beside it) · action (the edge affordance). */}
      {figure !== undefined && <span data-row-cell="value" className="shrink-0 text-t-caption tabular-nums text-ink-muted">{figure}</span>}
      <span data-row-cell="action" className="ml-auto flex shrink-0 items-center justify-end gap-2 text-t-caption tabular-nums text-ink-muted narrow:absolute narrow:right-0 narrow:top-[11px] narrow:ml-0">
        {word !== undefined && <span className="text-ink-faint">{word}</span>}
        <Icon name="chevron" size={16} />
      </span>
    </button>
  )
}

/** THE PAGE a summary opens: fixed over the tab, a back press, the block's title and figure, and
 *  ONE bounded scroll in the body. `data-detail-page` is the one-page spec's hook. */
export function DetailPage({
  title,
  figure,
  word,
  onClose,
  children,
  ...rest
}: {
  title: ReactNode
  figure?: ReactNode
  word?: ReactNode
  onClose: () => void
  children: ReactNode
} & { 'data-testid'?: string }) {
  const t = useT()
  // Escape is the keyboard's back press; the visible back control is the thumb's.
  useBackLayer(onClose)
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={typeof title === 'string' ? title : undefined}
      data-detail-page=""
      // A QUERY CONTAINER OF ITS OWN (index.css, `narrow:`): the page is the whole glass, however narrow the HQ panel it was
      // opened from — its rows must ask the page, not the panel under it.
      // ON THE GLASS BESIDE THE RAIL (screenLayout.ts THE SHELL): the whole window on a phone, all but the rail from `lg`, so the
      // rail stays in view and pressable. Its header and body stand in ONE centred column (`detailColumnClass`, 64 rem): a fleet's
      // ships, cargo and supplies read as one block on a laptop instead of three islands across 1,280 px (the S9 playtest).
      className={`@container ${glassBesideRailClass()} inset-y-0 z-50 flex h-[100dvh] flex-col overflow-hidden bg-bg text-ink`}
      {...rest}
    >
      <header className="shrink-0 border-b border-edge px-gutter">
        <div className={`${detailColumnClass()} flex min-h-14 items-center gap-2 py-1`}>
          <button
            type="button"
            onClick={onClose}
            aria-label={t('common.back')}
            data-detail-back=""
            className="flex min-h-11 min-w-11 shrink-0 items-center justify-center rounded-control text-ink-muted transition hover:text-ink"
          >
            <Icon name="chevron" size={20} className="rotate-180" />
          </button>
          <h1 data-name="" className={`flex-1 ${KEEP_WORDS_CLASS} text-t-title`}>{title}</h1>
          {figure !== undefined && <span className="shrink-0 text-t-body font-semibold tabular-nums text-ink">{figure}</span>}
          {word !== undefined && <span className="shrink-0 text-t-caption text-ink-muted">{word}</span>}
        </div>
      </header>
      <ScrollPane className="flex-1 px-gutter pb-6 pt-3">
        <div className={detailColumnClass()}>{children}</div>
      </ScrollPane>
    </div>
  )
}
