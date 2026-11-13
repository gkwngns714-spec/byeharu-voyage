import { useState } from 'react'
import { Tray, type TrayDetent } from '../components/ui'
import { useShellState } from '../app/shellState'
import { formatRelative } from '../lib/format'
import { useLocale, useT } from '../lib/i18n'
import type { NewsItem } from '../lib/rpc'
import { newsAtMs, newsHeadline, newsMove } from './newsWords'

// WHAT CAUSED IT (0347, owner row 216: *"i will be able to press it to see what caused it"*). One news item as a line: its headline in
// the reader's language, how long ago (and the UTC time, small), and what moved when a figure did. The News face lists these; a chart's
// dot opens the CARD: the same lines in a Tray (the bottom tray on a phone, the side pane on a wide glass — fixed, so nothing in the page
// moves), at most five, newest first, and how many more the dot holds.

const CARD_MAX = 5

export function NewsLine({ item, nowMs }: { item: NewsItem; nowMs: number }) {
  const locale = useLocale()
  const atMs = newsAtMs(item)
  const move = newsMove(item, locale)
  return (
    <div className="border-b border-edge px-2 py-2 last:border-b-0" data-testid="news-item" data-kind={item.kind} data-importance={item.importance}>
      <span className={`block break-words text-t-body ${item.importance >= 3 ? 'font-semibold text-ink' : 'text-ink'}`} data-testid="news-headline">
        {newsHeadline(item, locale)}
      </span>
      {move !== null && (
        <span className="block text-t-caption tabular-nums text-ink-muted" data-testid="news-move">
          {move}
        </span>
      )}
      {atMs !== null && (
        <span className="block text-t-caption tabular-nums text-ink-faint" data-testid="news-ago">
          {formatRelative(atMs, nowMs, { seconds: true })} · {new Date(atMs).toISOString().slice(11, 16)} UTC
        </span>
      )}
    </div>
  )
}

/** The card a dot opens. `items` null: closed. */
export function NewsCard({ items, onClose }: { items: readonly NewsItem[] | null; onClose: () => void }) {
  const t = useT()
  const { nowMs } = useShellState()
  const [detent, setDetent] = useState<TrayDetent>('half')
  if (items === null || items.length === 0) return null
  const shown = items.slice(0, CARD_MAX)
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => {
        if (next === 'closed') {
          setDetent('half')
          onClose()
        } else setDetent(next)
      }}
      title={t('news.heading')}
      over
      data-testid="news-card"
    >
      <div className="px-gutter">
        {shown.map((item) => (
          <NewsLine key={item.id} item={item} nowMs={nowMs} />
        ))}
      </div>
      {items.length > CARD_MAX && <p className="px-gutter pb-2 text-t-caption text-ink-faint">{t('news.more', { n: items.length - CARD_MAX })}</p>}
    </Tray>
  )
}
