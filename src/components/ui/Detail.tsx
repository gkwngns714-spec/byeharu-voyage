import { useEffect, type ReactNode } from 'react'
import { Icon } from './Icon'
import { ScrollPane } from './ScrollPane'
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
  return (
    <button
      type="button"
      onClick={onClick}
      data-summary-row=""
      className={`flex min-h-11 w-full items-center justify-between gap-3 rounded-control bg-surface px-3 py-2 text-left transition hover:bg-surface-2 ${className}`}
      {...rest}
    >
      <span title={typeof title === 'string' ? title : undefined} className="min-w-0 truncate text-t-body font-semibold text-ink">{title}</span>
      {/* `justify-end` holds the figure/word column's RIGHT edge on every row (align.spec's
          COLUMN law): the content widths differ, the column edge must not. */}
      <span className="flex shrink-0 items-center justify-end gap-2 text-t-caption tabular-nums text-ink-muted">
        {figure !== undefined && <span>{figure}</span>}
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
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label={typeof title === 'string' ? title : undefined}
      data-detail-page=""
      className="fixed inset-0 z-50 flex h-[100dvh] flex-col overflow-hidden bg-bg text-ink"
      {...rest}
    >
      <header className="flex min-h-14 shrink-0 items-center gap-2 border-b border-edge px-gutter py-1">
        <button
          type="button"
          onClick={onClose}
          aria-label={t('common.back')}
          data-detail-back=""
          className="flex min-h-11 min-w-11 shrink-0 items-center justify-center rounded-control text-ink-muted transition hover:text-ink"
        >
          <Icon name="chevron" size={20} className="rotate-180" />
        </button>
        <h1 className="min-w-0 flex-1 truncate text-t-title">{title}</h1>
        {figure !== undefined && <span className="shrink-0 text-t-body font-semibold tabular-nums text-ink">{figure}</span>}
        {word !== undefined && <span className="shrink-0 text-t-caption text-ink-muted">{word}</span>}
      </header>
      <ScrollPane className="flex-1 px-gutter pb-6 pt-3">{children}</ScrollPane>
    </div>
  )
}
