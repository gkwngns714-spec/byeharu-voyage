import { useMemo, type MouseEvent } from 'react'
import { newsMarksModel, type ChartNews } from './newsMarksModel'
import { useT } from '../../lib/i18n'

// THE DOTS (0347, owner row 216): a layer laid OVER a chart's svg, in the same box, so a dot is a real button with a 24-px target and
// nothing in the page moves when one is drawn or pressed (the owner's law: a press never re-flows the page). Placed in percent of the
// chart's sheet, so it stands where the model put it at any width. A headline (importance 3) is the accent; the rest are muted. A dot of
// several shows how many. The press is the caller's (it opens the card); it never reaches the chart under it.

export function NewsDots({ news, plot, axis, width, height }: {
  news: ChartNews
  plot: { x: number; y: number; w: number; h: number }
  axis: { fromMs: number; toMs: number }
  /** The chart's sheet (its viewBox). */
  width: number
  height: number
}) {
  const t = useT()
  const dots = useMemo(() => newsMarksModel(news.marks, plot, axis), [news.marks, plot, axis])
  if (dots.length === 0) return null
  return (
    <div className="pointer-events-none absolute inset-0" data-testid="news-dots">
      {dots.map((d) => {
        const many = d.ids.length > 1
        const press = (e: MouseEvent) => {
          e.stopPropagation()
          news.onPress(d.ids)
        }
        return (
          <button
            key={d.ids.join('-')}
            type="button"
            onClick={press}
            onPointerDown={(e) => e.stopPropagation()}
            aria-label={t('news.dot', { n: d.ids.length })}
            data-testid="news-dot"
            data-importance={d.importance}
            className="pointer-events-auto absolute flex h-6 w-6 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-chip"
            style={{ left: `${(d.x / width) * 100}%`, top: `${(d.y / height) * 100}%` }}
          >
            <span
              className={`flex items-center justify-center rounded-chip text-[9px] font-semibold leading-none text-surface ${
                many ? 'h-3.5 min-w-3.5 px-0.5' : 'h-1.5 w-1.5'
              } ${d.importance >= 3 ? 'bg-accent' : 'bg-ink-muted'}`}
            >
              {many ? d.ids.length : null}
            </span>
          </button>
        )
      })}
    </div>
  )
}
