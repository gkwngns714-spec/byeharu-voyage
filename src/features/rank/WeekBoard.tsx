import { Card, Hint, ListPanel, PageSplit, Row, Skeleton, StatCell } from '../../components/ui'
import { formatInt, formatRelative } from '../../lib/format'
import type { HouseWeekRow, HousesWeek } from '../../lib/rpc'
import { useWorld } from '../../live/worldStore'
import { useT } from '../../lib/i18n'
import { BoardRow, Pinned, Podium } from './Podium'

// RANK → WEEK (0467, docs/design/content-plan-2026-11.md 5.3 item 5): the merchant houses and the companies with a login, by THIS WEEK's
// profit (earned less lost, public.history_company_day), counted by the history job's run. ONE read, `world.houses_week()`, asked by
// RankScreen (it decides whether this face exists: dark, the server answers {on: false} and the face is not offered). Nothing is ranked
// here: every place, tie, count and gap is served. The page is Captains' pattern (2026-11-23, slice 8: Podium.tsx): MAIN the board as
// one list card — the top three on a podium, your line pinned at its head and lit, every row the place, the flag and the whole name,
// the profit and a bar against the first (green a gain, red a loss); SIDE your standing: the place "of 874", the profit, the house ahead.

export function WeekBoard({ read }: { read: HousesWeek | null }) {
  const t = useT()
  const house = useWorld((s) => s.player)

  if (!read || !read.on || !read.board) {
    return (
      <ListPanel look="card" title={t('rank.houses')} data-testid="rank-week">
        <div className="space-y-2 py-1">
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-12 w-full" />
        </div>
      </ListPanel>
    )
  }

  const you = read.you ?? null
  const houses = read.houses ?? 0
  const settled =
    read.age_seconds !== null && read.age_seconds !== undefined ? formatRelative(-read.age_seconds * 1000, 0) : null
  const widest = Math.abs(read.board[0]?.net ?? 0)
  const tone = (net: number) => (net > 0 ? ('success' as const) : net < 0 ? ('danger' as const) : ('neutral' as const))
  const row = (r: HouseWeekRow, pinned = false) => (
    <BoardRow
      key={`${pinned ? 'pin' : 'row'}-${r.position}-${r.company_name}`}
      place={r.position}
      name={r.company_name}
      nation={r.nation}
      value={r.net}
      text={formatInt(r.net)}
      widest={widest}
      mine={r.is_you}
      pinned={pinned}
      tone={r.is_you ? 'accent' : tone(r.net)}
      // a company with a login beside the merchant houses: its one word stays (a fact no mark carries); the flag is a picture
      caption={r.company && !r.is_you ? t('rank.company') : undefined}
      data-testid={pinned ? 'rank-week-you' : 'rank-week-row'}
    />
  )
  // YOUR LINE, PINNED: the board's row when you placed, else the `you` the read carries off the board's end
  const mine: HouseWeekRow | null =
    you === null
      ? null
      : (read.board.find((r) => r.is_you) ?? {
          position: you.position,
          tied: you.tied,
          company_name: house?.company_name ?? t('rank.yourCompany'),
          nation: house?.nation ?? null,
          company: true,
          net: you.net,
          is_you: true,
        })

  return (
    <PageSplit
      data-testid="rank-week-page"
      stickySide
      main={
        <ListPanel
          look="card"
          columns="fit"
          title={t('rank.houses')}
          count={formatInt(houses)}
          // 0473: your figure is live; the board's other rows are the history job's count, and the word says so (not "Updated", the
          // page's word for the Captains' photograph)
          footer={settled === null ? undefined : <Hint data-testid="rank-week-counted">{t('rank.othersCounted', { when: settled })}</Hint>}
          data-testid="rank-week"
        >
          {read.board.length === 0 && <Row label={t('rank.empty')} tone="muted" hairline={false} />}
          <Podium
            label={t('rank.podium')}
            steps={read.board.slice(0, 3).map((r) => ({
              key: `${r.position}-${r.company_name}`,
              place: r.position,
              name: r.company_name,
              nation: r.nation,
              value: r.net,
              text: formatInt(r.net),
              mine: r.is_you,
            }))}
          />
          {mine !== null && <Pinned>{row(mine, true)}</Pinned>}
          {read.board.map((r) => row(r))}
        </ListPanel>
      }
      side={
        <Card title={t('rank.standing')} data-testid="rank-week-standing">
          {you === null ? (
            <Row label={t('rank.notRanked')} tone="muted" hairline={false} />
          ) : (
            <>
              <div className="grid grid-cols-2 gap-4">
                <StatCell look="stacked" label={t('rank.place')} value={you.position} format={formatInt} tone="accent" data-testid="rank-week-place">
                  <span className="block text-t-caption text-ink-faint">{t('rank.ofN', { of: formatInt(houses) })}</span>
                </StatCell>
                <StatCell look="stacked" label={t('rank.profit')} value={you.net} format={formatInt} tone={you.net > 0 ? 'success' : you.net < 0 ? 'danger' : 'ink'} data-testid="rank-week-profit" />
              </div>
              {/* THE HOUSE AHEAD, when there is one; a first place that is shared leads no one, so it says nothing (the audit: "You
                  lead." for a company with no trade) */}
              {(you.ahead !== null || !you.tied) && (
                <p className="mt-3 text-t-caption text-ink-faint" data-testid="rank-week-ahead">
                  {you.ahead === null ? t('rank.leading') : t('rank.ahead', { name: you.ahead.name, gap: formatInt(you.ahead.gap) })}
                </p>
              )}
            </>
          )}
        </Card>
      }
    />
  )
}
