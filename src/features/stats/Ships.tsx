import { useState, type ReactNode } from 'react'
import {
  Card,
  CardRow,
  Clip,
  Empty,
  FactsLine,
  Figure,
  Flag,
  FlagSlot,
  Hint,
  ListPanel,
  Note,
  PageSplit,
  Row,
  Segmented,
  Skeleton,
  StatCell,
  deltaTone,
} from '../../components/ui'
import { formatDucats, formatDucatsDelta, formatInt, formatKoreaTime, formatTons, instantMs } from '../../lib/format'
import { useT } from '../../lib/i18n'
import { worldStatsFleets, type StatsFleetKind, type StatsFleets } from '../../lib/rpc'
import { nationNameOf, useWorld } from '../../live/worldStore'
import { useLiveRead } from '../../live/liveRead'
import { portName } from './statsFaces'
import { FleetStates } from './FleetStatesBar'

// SHIPS — the merchants, the navy, the pirates and the cargo ships on one face (0419; the owner, 2026-11-15: *"in stats, show like merchants
// navy, pirates, anad cargo"*). ONE READ, world.stats_fleets: the Stats count's own small row (twice an hour) and the last 24 hours of its windows,
// asked on the tab's one rule (useLiveRead). The face decides nothing: every figure and every state is the server's.
//
// MAIN | SIDE (screenLayout.ts "THE PAGE"): MAIN holds the four kinds, a card each, two across from 768 px: how many fleets and ships, where the
// FLEETS are (one stacked bar, the five states of fleetStates.ts; the server puts each fleet in ONE of them and counts, 0448), and the kind's
// figures of the last 24 hours; above them (0427) the battles of the last 24 hours. The SIDE holds the ONE list: the navy by country, or the pirates by home.

type View = 'navy' | 'homes'

export function FleetsByKindFace() {
  const t = useT()
  const read = useLiveRead<StatsFleets>('stats:fleets', worldStatsFleets, '', true)
  const v = read.view
  const nationByCode = useWorld((s) => s.nationByCode)
  const [view, setView] = useState<View>('navy')

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.shipsFailed')}</Note>
  if (v.counted_at === null || !v.navy || !v.pirates || !v.cargo) return <Empty data-testid="stats-empty">{t('stats.noFigures')}</Empty>

  const countedMs = instantMs(v.counted_at)
  const fromMs = instantMs(v.day_from ?? null)
  // the 24 h figures are short of a day only while the count is younger than a day (the first day after 0419): say from when
  const shortDay = countedMs !== null && fromMs !== null && countedMs - fromMs < 23 * 3_600_000
  const navy = v.navy
  const pirates = v.pirates
  const cargo = v.cargo
  const merchants = v.merchants ?? null
  const battles = v.battles ?? null

  return (
    <PageSplit
      data-testid="stats-ships"
      main={
        <>
          <Hint data-testid="stats-ships-counted">
            {countedMs !== null && t('stats.countedAt', { time: formatKoreaTime(countedMs) })}
            {shortDay && fromMs !== null && <> · {t('stats.dayFrom', { time: formatKoreaTime(fromMs) })}</>}
          </Hint>
          {battles && (
            // 0427 (the owner, 2026-11-15: "in stats i see no engagement"): the engagements of the last 24 hours, the server's figures
            <Card title={t('stats.battles')} data-testid="stats-ships-battles">
              <Hint>{t('stats.last24')}</Hint>
              <div className="grid grid-cols-1 gap-x-4 md:grid-cols-2">
                <StatCell look="line" label={t('stats.raids')} value={battles.raids_day} format={formatInt} />
                <StatCell look="line" label={t('stats.pirateWins')} value={battles.won_day} format={formatInt} />
                <StatCell look="line" label={t('stats.merchantsHeld')} value={battles.held_day} format={formatInt} />
                <StatCell look="line" label={t('stats.fled')} value={battles.fled_day ?? 0} format={formatInt} />
                <StatCell look="line" label={t('stats.navyCame')} value={battles.navy_day} format={formatInt} />
                <StatCell look="line" label={t('stats.navyFights')} value={battles.navy_fights_day} format={formatInt} />
                <StatCell look="line" label={t('stats.playerAttacks')} value={battles.attacks_day} format={formatInt} />
              </div>
            </Card>
          )}
          <CardRow>
            {merchants && (
              <KindCard title={t('stats.merchants')} kind={merchants} testid="stats-ships-merchants">
                <StatCell look="line" label={t('stats.earned')} value={merchants.profit_day ?? 0} format={formatDucatsDelta} tone={deltaTone(merchants.profit_day ?? 0)} />
                <StatCell look="line" label={t('stats.lapsWord')} value={merchants.laps_day ?? 0} format={formatInt} />
              </KindCard>
            )}
            <KindCard title={t('stats.navy')} kind={navy} testid="stats-ships-navy">
              <StatCell look="line" label={t('stats.fights')} value={navy.fights_day} format={formatInt} />
              <StatCell look="line" label={t('stats.pirateSunk')} value={navy.sunk_day} format={formatInt} />
            </KindCard>
          </CardRow>
          <CardRow>
            <KindCard title={t('stats.pirates')} kind={pirates} testid="stats-ships-pirates">
              <StatCell look="line" label={t('stats.plunder')} value={pirates.plunder_day} format={formatDucats} />
              <StatCell look="line" label={t('stats.raidsPaid')} value={pirates.raids_paid_day} format={formatInt} />
              <StatCell look="line" label={t('stats.wrecks')} value={pirates.wrecks_day} format={formatInt} />
              <StatCell look="line" label={t('stats.rebuilt')} value={pirates.reborn_day} format={formatInt} />
            </KindCard>
            <KindCard title={t('stats.cargoShips')} kind={cargo} testid="stats-ships-cargo" now>
              <StatCell look="line" label={t('stats.cargoAboard')} value={cargo.tuns} format={(n) => formatTons(n)} />
              <StatCell look="line" label={t('stats.fundsAboard')} value={cargo.funds} format={formatDucats} />
            </KindCard>
          </CardRow>
        </>
      }
      side={
        <ListPanel
          look="card"
          controls={
            <Segmented
              segments={[
                { id: 'navy', label: t('stats.byCountry') },
                { id: 'homes', label: t('stats.pirateHomes') },
              ]}
              value={view}
              onChange={setView}
              label={t('stats.ships')}
              columns={2}
              className="shrink-0"
            />
          }
          data-testid={view === 'navy' ? 'stats-ships-by-country' : 'stats-ships-by-home'}
        >
          {view === 'navy' && navy.nations.length === 0 && <Empty className="my-1">{t('stats.noShips')}</Empty>}
          {view === 'navy' &&
            navy.nations.map(([code, fleets, ships]) => (
              <Row
                key={code}
                mark={<Flag code={code} name={nationNameOf(nationByCode, code)} size="body" />}
                label={<Clip>{nationNameOf(nationByCode, code)}</Clip>}
                value={<Figure value={t('stats.shipsN', { n: formatInt(ships), count: ships })} />}
                hairline={false}
                data-testid="stats-ships-country"
              >
                <FactsLine>
                  <span>{t('stats.fleetsN', { n: formatInt(fleets), count: fleets })}</span>
                </FactsLine>
              </Row>
            ))}
          {view === 'homes' && pirates.homes.length === 0 && <Empty className="my-1">{t('stats.noShips')}</Empty>}
          {view === 'homes' &&
            pirates.homes.map(([code, name, fleets, ships]) => (
              <Row
                key={code}
                mark={<FlagSlot />}
                label={<Clip>{portName(name)}</Clip>}
                value={<Figure value={t('stats.shipsN', { n: formatInt(ships), count: ships })} />}
                hairline={false}
                data-testid="stats-ships-home"
              >
                <FactsLine>
                  <span>{t('stats.fleetsN', { n: formatInt(fleets), count: fleets })}</span>
                </FactsLine>
              </Row>
            ))}
        </ListPanel>
      }
    />
  )
}

/** One kind's card: its ships (the figure) and fleets, where its fleets are, and its own figures under "Last 24 h" (or, `now`, as they stand). */
function KindCard({ title, kind, testid, now = false, children }: { title: string; kind: StatsFleetKind; testid: string; now?: boolean; children: ReactNode }) {
  const t = useT()
  return (
    <Card title={title} data-testid={testid}>
      <FleetStates tally={kind} label={title} data-testid={`${testid}-states`} />
      <div className="mt-4">
        {!now && <Hint>{t('stats.last24')}</Hint>}
        {children}
      </div>
    </Card>
  )
}
