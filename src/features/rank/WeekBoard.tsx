import { Card, Figure, Hint, ListHeading, ListPanel, PageSplit, Row, Skeleton, StatCell } from '../../components/ui'
import { formatInt, formatRelative } from '../../lib/format'
import type { HouseWeekRow, HousesWeek } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { useT } from '../../lib/i18n'

// RANK → WEEK (0467, docs/design/content-plan-2026-11.md 5.3 item 5): the merchant houses and the companies with a login, by THIS WEEK's
// profit (earned less lost, public.history_company_day), counted by the history job's run. ONE read, `world.houses_week()`, asked by
// RankScreen (it decides whether this face exists: dark, the server answers {on: false} and the face is not offered). Nothing is ranked
// here: every place, tie, count and gap is served. The page is Captains' pattern: MAIN the board as one list card, your line in its place
// or under its own heading after the board; SIDE your standing: the place "#37 of 874", the profit, and the house just ahead.

export function WeekBoard({ read }: { read: HousesWeek | null }) {
  const t = useT()
  const nationByCode = useWorld((s) => s.nationByCode)
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
  const flag = (code: string | null) => (code === null ? null : nationNameOf(nationByCode, code))
  const settled =
    read.age_seconds !== null && read.age_seconds !== undefined ? formatRelative(-read.age_seconds * 1000, 0) : null
  const row = (r: HouseWeekRow) => (
    <Row
      key={`${r.position}-${r.company_name}`}
      mark={<Figure value={formatInt(r.position)} tone={r.is_you ? 'accent' : 'faint'} className="w-7 justify-end" />}
      label={r.company_name}
      value={<Figure value={formatInt(r.net)} tone={r.is_you ? 'accent' : 'ink'} />}
      tone={r.is_you ? 'accent' : 'default'}
      hairline={false}
      data-testid={r.is_you ? 'rank-week-you' : 'rank-week-row'}
    >
      {(() => {
        const text = [flag(r.nation), r.company ? t('rank.company') : null, r.tied ? t('rank.tied') : null].filter(Boolean).join(' · ')
        return text === '' ? null : <span className="block text-t-caption text-ink-faint">{text}</span>
      })()}
    </Row>
  )

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
          {read.board.map(row)}
          {you !== null && !you.on_board && (
            <>
              <ListHeading data-testid="rank-week-you-heading">{t('rank.yourCompany')}</ListHeading>
              {row({
                position: you.position,
                tied: you.tied,
                company_name: house?.company_name ?? t('rank.yourCompany'),
                nation: house?.nation ?? null,
                company: true,
                net: you.net,
                is_you: true,
              })}
            </>
          )}
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
                  <span className="block text-t-caption text-ink-faint">
                    {t('rank.placeOf', { n: formatInt(you.position), of: formatInt(houses) })}
                    {you.tied ? ` · ${t('rank.tied')}` : ''}
                  </span>
                </StatCell>
                <StatCell look="stacked" label={t('rank.profit')} value={you.net} format={formatInt} data-testid="rank-week-profit" />
              </div>
              <p className="mt-3 text-t-caption text-ink-faint" data-testid="rank-week-ahead">
                {you.ahead === null ? t('rank.leading') : t('rank.ahead', { name: you.ahead.name, gap: formatInt(you.ahead.gap) })}
              </p>
            </>
          )}
        </Card>
      }
    />
  )
}
