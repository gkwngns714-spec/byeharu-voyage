import { useEffect, useMemo, useState, type MouseEvent } from 'react'
import { NEWS_HIT_PX, newsMarksModel, type ChartNews } from './newsMarksModel'
import { useT } from '../../lib/i18n'

// THE DOTS (0347, owner row 216): a layer laid OVER a chart's svg, in the same box, so a dot is a real button and nothing in the page
// moves when one is drawn or pressed (the owner's law: a press never re-flows the page). A headline (importance 3) is the accent; the
// rest are muted. A dot of several shows how many. The press is the caller's (it opens the card); it never reaches the chart under it.
//
// THE TARGET IS 44 PX, THE MARK IS SMALL (2026-11-11, docs/dev-log/2026-11-11-news-dot-size.md). The button was a 24-px box, under the
// 44-px law of every control (tests/design.fixture.ts `smallControls`), and nothing measured it on a chart that had news. It is now
// NEWS_HIT_PX square, the way the game's other small marks are (Stepper, Tray's close, Field's clear: an `h-11 w-11` box around a
// small glyph). The layer measures its own box (the ResizeObserver is the external system), so the model works in px of the GLASS
// whatever the scale of the chart's sheet: marks under a target apart are one dot, and each target is kept inside the chart's box, so
// no target lies over another or over the chart's neighbours. The mark is drawn at its own instant, wherever its target was kept.

export function NewsDots({ news, plot, axis, width, height }: {
  news: ChartNews
  plot: { x: number; y: number; w: number; h: number }
  axis: { fromMs: number; toMs: number }
  /** The chart's sheet (its viewBox). */
  width: number
  height: number
}) {
  const t = useT()
  const [layer, setLayer] = useState<HTMLDivElement | null>(null)
  const [box, setBox] = useState<{ w: number; h: number } | null>(null)
  useEffect(() => {
    if (layer === null) return
    const read = () => {
      const r = layer.getBoundingClientRect()
      setBox((was) => (was !== null && was.w === r.width && was.h === r.height ? was : { w: r.width, h: r.height }))
    }
    read()
    if (typeof ResizeObserver === 'undefined') return
    const watch = new ResizeObserver(read)
    watch.observe(layer)
    return () => watch.disconnect()
  }, [layer])
  const dots = useMemo(() => {
    if (box === null || box.w <= 0 || box.h <= 0 || width <= 0 || height <= 0) return []
    const sx = box.w / width
    const sy = box.h / height
    return newsMarksModel(news.marks, { x: plot.x * sx, y: plot.y * sy, w: plot.w * sx, h: plot.h * sy }, axis, box)
  }, [news.marks, plot, axis, width, height, box])
  return (
    <div ref={setLayer} className="pointer-events-none absolute inset-0" data-testid="news-dots">
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
            className="pointer-events-auto absolute -translate-x-1/2 -translate-y-1/2 rounded-chip"
            style={{ left: d.hitX, top: d.hitY, width: NEWS_HIT_PX, height: NEWS_HIT_PX }}
          >
            <span
              data-testid="news-dot-mark"
              className={`absolute flex -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-chip text-[9px] font-semibold leading-none text-surface ${
                many ? 'h-3.5 min-w-3.5 px-0.5' : 'h-1.5 w-1.5'
              } ${d.importance >= 3 ? 'bg-accent' : 'bg-ink-muted'}`}
              style={{ left: NEWS_HIT_PX / 2 + d.x - d.hitX, top: NEWS_HIT_PX / 2 + d.y - d.hitY }}
            >
              {many ? d.ids.length : null}
            </span>
          </button>
        )
      })}
    </div>
  )
}
