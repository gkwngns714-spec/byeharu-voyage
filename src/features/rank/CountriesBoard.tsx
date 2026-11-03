import { useMemo } from 'react'
import { Card, Figure, ListPanel, PageSplit, RankBars, Row, Skeleton, StackedBar, StatCell, type RankRow } from '../../components/ui'
import { formatInt } from '../../lib/format'
import { worldNationStandings } from '../../lib/rpc'
import { HullCountry } from '../../live/HullCountry'
import { useServedRead } from '../../live/useServedRead'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { myCountryOf } from './rankFigures'
import { useT } from '../../lib/i18n'

// RANK → COUNTRIES (0148, docs/INFLUENCE.md §5.4, OWNER O3: fame/rank for leading a city). ONE read,
// `world.nation_standings()`: every country's cities — home and won — the cities won this week, and
// its three biggest givers. Nothing is counted here; the server counts `public.port_nation`.
//
// ON THE PAGE (2026-11-03, owner row 267; RankScreen.tsx has the pattern): MAIN is the countries as ONE list card — a row a
// country, the cities it holds at the row's edge, home · won · this week · its givers under the line, the rows in as many
// columns as the main holds; the SIDE is the tray's column, holding YOUR COUNTRY as graphics (the cities it holds at 24 px,
// home and won as one stacked bar, this week as a line) and CITIES HELD — every country's figure as ranked bars, yours lit.
// Every figure is a served field; the bars are the served rows in the served order. The page scrolls.

export function CountriesBoard() {
  const t = useT()
  const house = useWorld((s) => s.player)
  const nationByCode = useWorld((s) => s.nationByCode)
  const read = useServedRead('countries', worldNationStandings, { name: 'worldNationStandings' })
  const board = read.view
  const yourNation = house?.nation ?? null
  const mine = useMemo(() => (board ? myCountryOf(board, yourNation) : null), [board, yourNation])

  if (!board) {
    return (
      <ListPanel look="card" title={t('rank.countries')} data-testid="rank-countries">
        <div className="space-y-2 py-1">
          <Skeleton className="h-12 w-full" />
          <Skeleton className="h-12 w-full" />
        </div>
      </ListPanel>
    )
  }

  const held: RankRow[] = board.countries.map((c) => ({
    id: c.nation,
    label: nationNameOf(nationByCode, c.nation),
    value: c.held,
    note: t('rank.homeWon', { home: formatInt(c.home), won: formatInt(c.won) }),
    tone: c.nation === mine?.nation ? 'accent' : 'neutral',
  }))

  return (
    <PageSplit
      data-testid="rank-countries-page"
      // no `sideFirst`: on a phone your country stands AFTER the board — its first row is on the first glass
      stickySide
      main={
        <ListPanel look="card" columns="fit" title={t('rank.countries')} count={formatInt(board.countries.length)} data-testid="rank-countries">
          {board.countries.map((c) => (
            <Row
              key={c.nation}
              label={<HullCountry nation={c.nation} />}
              value={<Figure value={formatInt(c.held)} tone={c.nation === mine?.nation ? 'accent' : 'ink'} />}
              tone={c.nation === mine?.nation ? 'accent' : 'default'}
              hairline={false}
              data-testid="rank-country"
            >
              <span className="block text-t-caption text-ink-faint">
                {[
                  t('rank.homeWon', { home: formatInt(c.home), won: formatInt(c.won) }),
                  c.won_week > 0 ? t('rank.thisWeek', { n: formatInt(c.won_week) }) : null,
                  c.top.length > 0 ? c.top.map((g) => g.name).join(', ') : null,
                ]
                  .filter(Boolean)
                  .join(' · ')}
              </span>
            </Row>
          ))}
        </ListPanel>
      }
      side={
        <>
          <Card title={t('rank.country')} data-testid="rank-my-country">
            {mine === null ? (
              <Row label={t('rank.notRanked')} tone="muted" hairline={false} />
            ) : (
              <>
                <HullCountry nation={mine.nation} size="title" />
                <StatCell look="stacked" label={t('rank.held')} value={mine.held} format={formatInt} tone="accent" className="mt-4" data-testid="rank-held" />
                {/* HOME AND WON, as the two parts of what it holds (the bar draws itself once there is a city to split) */}
                <StackedBar
                  parts={[
                    { id: 'home', label: t('rank.home'), value: mine.home, tone: 'accent' },
                    { id: 'won', label: t('rank.won'), value: mine.won, tone: 'info' },
                  ]}
                  format={formatInt}
                  label={t('rank.held')}
                  className="mt-5"
                  data-testid="rank-held-split"
                />
                <div className="mt-3">
                  <StatCell look="line" label={t('rank.week')} value={mine.won_week} format={formatInt} />
                </div>
              </>
            )}
          </Card>
          <Card title={t('rank.held')} data-testid="rank-held-bars">
            <RankBars rules={false} format={formatInt} empty={t('rank.empty')} rows={held} />
          </Card>
        </>
      }
    />
  )
}
