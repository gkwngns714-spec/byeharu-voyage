import { useEffect, useState } from 'react'
import { worldNewsMarks, type NewsMark } from '../lib/rpc'

// A CHART'S NEWS MARKS (0279, owner row 216): one read over the chart's drawn window, re-read when the
// window, the span or the subject changes — never per second (docs/NEWS_AND_MARKERS.md §3.2: marks are
// re-read with the chart's window; the live feed is N2's slice). The caller passes the window IT DREW —
// the served series' own first and last instants, which the caller already holds — so nothing here is
// computed that the server could serve; the server filters the window and caps at the newest 300.
//
// The first failed ask is an answer of nothing (null — the chart draws no dots and stays exactly what it
// was); a later failure keeps the last answer for the same window, the same rule useLiveRead keeps.

export function useNewsMarks(
  chart: 'price' | 'city' | 'world' | 'merchants',
  port: string | null,
  good: string | null,
  fromMs: number | null,
  toMs: number | null,
): NewsMark[] | null {
  const key = [chart, port ?? '', good ?? '', fromMs ?? '', toMs ?? ''].join('|')
  const [answer, setAnswer] = useState<{ key: string; marks: NewsMark[] | null } | null>(null)
  const active = fromMs !== null && toMs !== null && Number.isFinite(fromMs) && Number.isFinite(toMs)

  useEffect(() => {
    if (!active) return
    let alive = true
    void worldNewsMarks(chart, port, good, new Date(fromMs as number).toISOString(), new Date(toMs as number).toISOString()).then((r) => {
      if (!alive) return
      setAnswer((prev) => (r.ok ? { key, marks: r.value } : prev !== null && prev.key === key ? prev : { key, marks: null }))
    })
    return () => {
      alive = false
    }
    // `key` is the subject: a new window is a new ask, the same window asks once
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, active])

  if (!active || answer === null || answer.key !== key) return null
  return answer.marks
}
