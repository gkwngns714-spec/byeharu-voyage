import { useEffect, useRef, useState } from 'react'
import { Button, Empty, ListPanel, Segmented, Skeleton } from '../../components/ui'
import { useShellState } from '../../app/shellState'
import { useT } from '../../lib/i18n'
import { worldNewsFeed, type NewsFilter, type NewsItem, type StatsNow } from '../../lib/rpc'
import { NewsLine } from '../../live/NewsCard'
import { newsAtMs } from '../../live/newsWords'
import { WorldEventsLine } from '../../live/WorldEventLine'
import { useDeskGood } from '../../store/deskGood'
import { useNavigate } from 'react-router-dom'

// THE NEWS FACE (0347, owner row 216: *"major event, real time news-like feature"*; docs/NEWS_AND_MARKERS.md §4). Newest first, fifty
// at a time; "Older" asks the fifty under the last. LIVE WITHOUT A SECOND POLL: the tab already asks world.stats_now every second
// (statsLive.ts), and since 0347 it serves `news_head`, the newest news id. When it moves past what this face has seen, the face asks
// world.news_feed for the rows after it and puts them on top. World: every notable item (importance 2+). My cities: the news of the
// ports where you hold shares, lie, or are heading.

const PAGE = 50

const FILTERS: readonly NewsFilter[] = ['world', 'cities']

type NewsList = { filter: NewsFilter; items: NewsItem[]; more: boolean }

/** THE LAST LIST OF EACH FILTER, kept across a remount (row 250, *"keep it even though you move from tab to tab"*; src/live/liveRead.ts
 *  `keep` says the same for the other Stats reads): since slice 2 Stats opens on News, so a return to Stats draws the list it left at once,
 *  while the first page is asked again, and shows no skeleton (tests/drive.nav.spec.ts). */
const keptNews = new Map<NewsFilter, NewsList>()

export function NewsFace({ live }: { live: StatsNow | null }) {
  const t = useT()
  const navigate = useNavigate()
  const setDeskCity = useDeskGood((s) => s.setFocus)
  const { nowMs } = useShellState()
  const [filter, setFilter] = useState<NewsFilter>('world')
  const [list, setList] = useState<NewsList | null>(() => keptNews.get('world') ?? null)
  const seen = useRef<{ filter: NewsFilter; head: number } | null>(null)
  const head = live?.news_head ?? null

  // THE FIRST PAGE, on open and on a change of filter
  useEffect(() => {
    let on = true
    seen.current = null
    void worldNewsFeed(filter, null, null, PAGE).then((r) => {
      if (!on || !r.ok) return
      seen.current = { filter, head: Number(r.value.head ?? 0) }
      setList({ filter, items: r.value.items, more: r.value.items.length === PAGE })
    })
    return () => {
      on = false
    }
  }, [filter])

  // THE LIVE TOP: the head moved past what was seen, so the rows after it are asked once and put on top
  useEffect(() => {
    const s = seen.current
    if (head === null || s === null || s.filter !== filter || Number(head) <= s.head) return
    const after = s.head
    s.head = Number(head)
    void worldNewsFeed(filter, after, null, PAGE).then((r) => {
      if (!r.ok || r.value.items.length === 0) return
      setList((cur) => {
        if (cur === null || cur.filter !== filter) return cur
        const known = new Set(cur.items.map((i) => Number(i.id)))
        return { ...cur, items: [...r.value.items.filter((i) => !known.has(Number(i.id))), ...cur.items] }
      })
    })
  }, [head, filter])

  // what is on screen is kept for the next mount
  useEffect(() => {
    if (list !== null) keptNews.set(list.filter, list)
  }, [list])

  const older = () => {
    if (list === null || list.items.length === 0) return
    const before = Math.min(...list.items.map((i) => Number(i.id)))
    void worldNewsFeed(filter, null, before, PAGE).then((r) => {
      if (!r.ok) return
      setList((cur) => (cur === null || cur.filter !== filter ? cur : { ...cur, items: [...cur.items, ...r.value.items], more: r.value.items.length === PAGE }))
    })
  }

  const shown = list !== null && list.filter === filter ? list : (keptNews.get(filter) ?? null)
  const openHarbour = (code: string) => {
    setDeskCity(code)
    navigate('/command')
  }
  // THE FACE'S LIST is a card list like every Stats face's (consistency.spec: each face stands one list panel)
  return (
    <ListPanel
      look="card"
      title={t('news.heading')}
      controls={
        <Segmented
          segments={FILTERS.map((f) => ({ id: f, label: t(`news.${f}`) }))}
          value={filter}
          onChange={setFilter}
          label={t('news.heading')}
          className="w-fit max-w-full"
        />
      }
      footer={
        shown !== null && shown.more ? (
          <Button variant="secondary" onClick={older} data-testid="news-older">
            {t('news.older')}
          </Button>
        ) : undefined
      }
      data-testid="stats-news"
    >
      {/* X8 (live/eventReach.ts): EVERY WORLD EVENT, near or far, heads the news; the Trade desk keeps only those within two hours'
          sail. A press opens the desk on that harbour. Nothing while dark or none is on. */}
      <WorldEventsLine city={null} onCity={openHarbour} className="mx-3 mb-3" />
      {shown === null ? (
        <Skeleton className="h-40 w-full" />
      ) : shown.items.length === 0 ? (
        <Empty data-testid="news-empty">{t('news.none')}</Empty>
      ) : (
        <>
          <NewsTimeline items={shown.items} nowMs={nowMs} />
          <div data-testid="news-list">
            {shown.items.map((item) => (
              <NewsLine key={item.id} item={item} nowMs={nowMs} />
            ))}
          </div>
        </>
      )}
    </ListPanel>
  )
}


/** The dots' side, px, by importance: a headline larger than a notable item, a notable item larger than a local one. */
const DOT_PX = (importance: number) => (importance >= 3 ? 10 : importance >= 2 ? 8 : 6)

/** THE FACE LEADS WITH A PICTURE (2026-11-23, the visual overhaul's slice 8): the happenings the list holds, on one line of time from the
 *  oldest of them to now (the green dot, the tab's "right now") — a dot each at its own instant, the headlines larger and in full ink. It
 *  counts nothing and is pressed nowhere: the list under it is the reading, and the picture says at a glance whether the world has been
 *  quiet or busy, and when. The dots are boxes placed by percent on a line, so they stay round at any width. */
function NewsTimeline({ items, nowMs }: { items: readonly NewsItem[]; nowMs: number }) {
  const t = useT()
  const marks = items.flatMap((i) => {
    const atMs = newsAtMs(i)
    return atMs === null ? [] : [{ id: String(i.id), atMs, importance: Number(i.importance) }]
  })
  if (marks.length < 2) return null
  const fromMs = Math.min(...marks.map((m) => m.atMs))
  const toMs = Math.max(nowMs, ...marks.map((m) => m.atMs))
  const span = toMs - fromMs
  if (!(span > 0)) return null
  return (
    <div role="img" aria-label={t('news.timeline')} className="relative mx-3 mb-3 mt-1 h-8" data-testid="news-timeline">
      <span aria-hidden="true" className="absolute inset-x-0 top-1/2 h-px -translate-y-1/2 bg-edge" />
      {[...marks]
        .sort((a, b) => a.importance - b.importance)
        .map((m) => {
          const side = DOT_PX(m.importance)
          return (
            <span
              key={m.id}
              aria-hidden="true"
              className={`absolute top-1/2 -translate-x-1/2 -translate-y-1/2 rounded-full ring-2 ring-surface ${m.importance >= 3 ? 'bg-ink' : 'bg-ink-faint'}`}
              style={{ left: `${((m.atMs - fromMs) / span) * 100}%`, width: side, height: side }}
            />
          )
        })}
      <span aria-hidden="true" className="absolute right-0 top-1/2 h-2 w-2 -translate-y-1/2 translate-x-1/2 rounded-full bg-success" />
    </div>
  )
}
