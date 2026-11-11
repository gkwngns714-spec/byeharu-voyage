import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { ChartNews } from '../components/ui'
import { worldNewsMarks, type NewsChart, type NewsItem } from '../lib/rpc'
import { NewsCard } from './NewsCard'
import { newsAtMs } from './newsWords'

// THE NEWS OF ONE CHART (0347, owner row 216): what `world.news_marks` says this chart is about, from its first point on, as the dots
// the chart draws (`ChartNews`) and the card a press opens. The subject is the chart (price at a city of a good, a city, the world,
// the merchants) and where its record starts, to the minute; it is asked again on a change of subject and every half minute while the
// chart is drawn — a chart's record moves in slots of a quarter hour, and the News face is the live list.

const REASK_MS = 30_000

/** Where a chart's record starts: its earliest instant (ms), or null for none. */
export function firstAtMs(points: readonly { atMs: number }[]): number | null {
  let first: number | null = null
  for (const p of points) if (Number.isFinite(p.atMs) && (first === null || p.atMs < first)) first = p.atMs
  return first
}

export interface ChartNewsRead {
  /** For the chart's `news` prop; undefined while there is nothing to draw. */
  news: ChartNews | undefined
  /** The card, to be placed anywhere beside the chart (it is a Tray: fixed, out of the flow). */
  card: ReactNode
}

export function useChartNews(chart: NewsChart, portId: string | null, goodId: string | null, fromMs: number | null): ChartNewsRead {
  const needsPort = chart === 'price' || chart === 'city'
  const fromMinute = fromMs === null || !Number.isFinite(fromMs) ? null : Math.floor(fromMs / 60_000) * 60_000
  const subject = needsPort && portId === null ? null : `${chart}|${portId ?? ''}|${goodId ?? ''}|${fromMinute ?? ''}`
  const [read, setRead] = useState<{ subject: string; items: NewsItem[] } | null>(null)
  const [open, setOpen] = useState<number[] | null>(null)

  useEffect(() => {
    if (subject === null) return
    let live = true
    const ask = () => {
      if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return
      void worldNewsMarks(chart, portId, goodId, fromMinute === null ? null : new Date(fromMinute).toISOString(), null).then((r) => {
        if (live && r.ok) setRead({ subject, items: r.value.items })
      })
    }
    ask()
    const timer = window.setInterval(ask, REASK_MS)
    return () => {
      live = false
      window.clearInterval(timer)
    }
  }, [subject, chart, portId, goodId, fromMinute])

  const items = useMemo(() => (read !== null && read.subject === subject ? read.items : []), [read, subject])
  const onPress = useCallback((ids: number[]) => setOpen(ids), [])
  const news = useMemo<ChartNews | undefined>(() => {
    const marks = items.flatMap((i) => {
      const atMs = newsAtMs(i)
      return atMs === null ? [] : [{ id: Number(i.id), atMs, importance: Number(i.importance) }]
    })
    return marks.length === 0 ? undefined : { marks, onPress }
  }, [items, onPress])
  const shown = open === null ? null : open.flatMap((id) => items.filter((i) => Number(i.id) === id))
  return { news, card: <NewsCard items={shown} onClose={() => setOpen(null)} /> }
}
