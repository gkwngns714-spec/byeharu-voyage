import { useEffect, useRef, useState } from 'react'
import { Button, Empty, ListPanel, Segmented, Skeleton } from '../../components/ui'
import { useShellState } from '../../app/shellState'
import { useT } from '../../lib/i18n'
import { worldNewsFeed, type NewsFilter, type NewsItem, type StatsNow } from '../../lib/rpc'
import { NewsLine } from '../../live/NewsCard'

// THE NEWS FACE (0347, owner row 216: *"major event, real time news-like feature"*; docs/NEWS_AND_MARKERS.md §4). Newest first, fifty
// at a time; "Older" asks the fifty under the last. LIVE WITHOUT A SECOND POLL: the tab already asks world.stats_now every second
// (statsLive.ts), and since 0347 it serves `news_head`, the newest news id. When it moves past what this face has seen, the face asks
// world.news_feed for the rows after it and puts them on top. World: every notable item (importance 2+). My cities: the news of the
// ports where you hold shares, lie, or are heading.

const PAGE = 50

const FILTERS: readonly NewsFilter[] = ['world', 'cities']

export function NewsFace({ live }: { live: StatsNow | null }) {
  const t = useT()
  const { nowMs } = useShellState()
  const [filter, setFilter] = useState<NewsFilter>('world')
  const [list, setList] = useState<{ filter: NewsFilter; items: NewsItem[]; more: boolean } | null>(null)
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

  const older = () => {
    if (list === null || list.items.length === 0) return
    const before = Math.min(...list.items.map((i) => Number(i.id)))
    void worldNewsFeed(filter, null, before, PAGE).then((r) => {
      if (!r.ok) return
      setList((cur) => (cur === null || cur.filter !== filter ? cur : { ...cur, items: [...cur.items, ...r.value.items], more: r.value.items.length === PAGE }))
    })
  }

  const shown = list !== null && list.filter === filter ? list : null
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
      {shown === null ? (
        <Skeleton className="h-40 w-full" />
      ) : shown.items.length === 0 ? (
        <Empty data-testid="news-empty">{t('news.none')}</Empty>
      ) : (
        <div data-testid="news-list">
          {shown.items.map((item) => (
            <NewsLine key={item.id} item={item} nowMs={nowMs} />
          ))}
        </div>
      )}
    </ListPanel>
  )
}
