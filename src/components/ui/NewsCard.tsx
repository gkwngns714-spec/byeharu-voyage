import { createPortal } from 'react-dom'
import { useRef } from 'react'
import { useDismiss } from './useDismiss'
import { agoLabel } from './seriesChartModel'
import type { NewsMarkDot } from './newsMarksModel'
import { useLocale, useT } from '../../lib/i18n'
import { newsHeadline } from '../../lib/i18n/dict/news'

// THE PRESSED MARKER'S CARD (0279, owner row 216): what caused the point — the headline, how long ago
// (the axis's own agoLabel, plus the UTC minute), up to five items of a cluster newest first, and a
// "+N more" line. A marker of an unmapped kind prints its kind (the truthful lesser answer).
//
// OUT OF FLOW BY CONSTRUCTION, so a press SELECTS and never re-flows: the card is a portal to
// document.body at a FIXED position at the pressed dot (the painter hands the dot's client rect), gone
// on a press outside or Escape (the one useDismiss). It is a region over the page, not a modal:
// role="dialog" with aria-modal={false}, as the Tray and the Popover declare themselves.
//
// ONE CARD, FOUR CHARTS: the price chart, the series charts (Stats), the city purse and the merchants
// day all press into this one component; the dot geometry is newsMarksModel's. The city link opens the
// marker's city through the caller's own navigation (goTo / the desk) — the card knows no screen.

const MAX_ITEMS = 5
const CARD_W = 264
const MAX_CARD_H = 200
const GUTTER = 8

export function NewsCard({
  dot,
  anchor,
  nowMs,
  onClose,
  onOpenCity,
}: {
  dot: NewsMarkDot
  /** The pressed dot's client point (the painter's getBoundingClientRect) — the card hangs off it. */
  anchor: { x: number; y: number }
  /** The instant "ago" is read from — the chart's own now. */
  nowMs: number
  onClose: () => void
  /** Opens the marker's city (the caller's navigation); absent when there is no such road. */
  onOpenCity?: (portCode: string) => void
}) {
  const t = useT()
  const locale = useLocale()
  const box = useRef<HTMLDivElement>(null)
  useDismiss(true, box, onClose)
  const items = dot.items.slice(0, MAX_ITEMS)
  const openCity = onOpenCity
    ? dot.items
        .map((m) => m.detail?.city)
        .find((c): c is string => typeof c === 'string' && c.length > 0)
    : undefined

  // the dot's client point, clamped so the card stands on the glass (below the dot where it fits)
  const left = Math.max(GUTTER, Math.min(anchor.x - CARD_W / 2, window.innerWidth - CARD_W - GUTTER))
  const top = Math.min(anchor.y + 10, Math.max(GUTTER, window.innerHeight - MAX_CARD_H - GUTTER))

  return createPortal(
    <div
      ref={box}
      role="dialog"
      aria-modal={false}
      aria-label={t('news.cardLabel')}
      data-testid="news-card"
      className="fixed z-50 rounded-tile bg-surface-2 px-3 py-2 shadow-float"
      style={{ left, top, width: CARD_W }}
      onClick={(e) => e.stopPropagation()}
    >
      <ul>
        {items.map((m) => (
          <li key={m.id} className="py-1" data-testid="news-card-item">
            <span className="block text-t-body text-ink">{newsHeadline(m, locale)}</span>
            <span className="block text-t-caption text-ink-faint tabular-nums">
              {agoLabel(nowMs - Date.parse(m.at))} · {new Date(m.at).toUTCString().slice(17, 22)} UTC
            </span>
          </li>
        ))}
      </ul>
      {dot.count > MAX_ITEMS && (
        <span className="block pb-1 text-t-caption text-ink-faint" data-testid="news-card-more">
          {t('news.more', { n: dot.count - MAX_ITEMS })}
        </span>
      )}
      {openCity !== undefined && onOpenCity && (
        <button
          type="button"
          className="min-h-9 px-1 text-t-caption text-accent"
          data-testid="news-card-city"
          onClick={() => {
            onOpenCity(openCity)
            onClose()
          }}
        >
          {t('news.openCity')}
        </button>
      )}
    </div>,
    document.body,
  )
}
