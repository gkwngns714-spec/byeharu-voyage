import { Fragment, useState, type ReactNode } from 'react'
import {
  Button,
  Card,
  Clip,
  Empty,
  FactsLine,
  FilterBar,
  Figure,
  Flag,
  FlagSlot,
  Hint,
  ListPanel,
  Note,
  PageSplit,
  Row,
  Skeleton,
  StackedBar,
  StatCell,
  Tray,
  ALL,
  oneOf,
  useFilterChoice,
} from '../../components/ui'
import { formatDucats, formatInt, formatKoreaTime, formatRealShort, formatRelative, instantMs } from '../../lib/format'
import { useLocale, useT } from '../../lib/i18n'
import {
  worldStatsFleet,
  worldStatsFleetList,
  type StatsCargoRow,
  type StatsFleetFigs,
  type StatsFleetKindId,
  type StatsFleetLine,
  type StatsFleetList,
  type StatsFleetListRow,
  type StatsFleetPage,
  type StatsFleetState,
} from '../../lib/rpc'
import { nationNameOf, portNameOf, useWorld } from '../../live/worldStore'
import { useLiveRead } from '../../live/liveRead'
import { useShellState } from '../../app/shellState'
import { portName } from './statsFaces'
import { countriesOf } from './statsFilters'

// NAVY, PIRATES, CARGO — one face each, the Merchants face's pattern (0431; the owner, 2026-11-15: *"in stats, i would like to have a separate tab
// for navy, pirates, and cargoships like merchants. and by clicking on navy, i should be able to see how much damage it took, how much money = loot
// it took, fixing fees, and so much more. same for pirates as well. for cargoships i want to see from what city to what city it delivered"*).
//
// ONE READ A FACE, world.stats_fleet_list(kind): the newest Stats count's list of the kind (every fleet: country, home, ships, state, her 7 days)
// and the kind's 24 h and 7 d. A press on a fleet opens HER PAGE in a tray, ONE READ, world.stats_fleet(fleet): where she is and what she does,
// her ships, her 24 h and 7 days, her log, and a cargo ship's gold trips. Both asked on the tab's one rule (useLiveRead, each second). The faces
// decide nothing: every figure, every state and every line is the server's (public.fleet_book, public.fleet_lines, public.convoy_cargo).
//
// MAIN | SIDE (screenLayout.ts "THE PAGE"), as Merchants: the SIDE holds the kind's figures (its fleets and where they are, its last 24 h, its
// 7 days); MAIN holds the one list (by country or home, a sort). On a phone the side comes first.

const FIRST = 60

/** A figure of a fleet's book (absent: it never happened, 0). */
const fig = (f: StatsFleetFigs | undefined, key: string): number => f?.[key] ?? 0
/** What she cost: her hours of pay and her repairs. */
const costs = (f: StatsFleetFigs | undefined): number => fig(f, 'upkeep') + fig(f, 'repairs')

type SortId = 'figure' | 'damage' | 'costs' | 'name'
const SORTS: readonly SortId[] = ['figure', 'damage', 'costs', 'name']

/** The list's headline figure of a kind: a navy ship's fights, a pirate's loot, a cargo ship's gold delivered (7 days). */
const HEADLINE: Record<StatsFleetKindId, { key: string; money: boolean }> = {
  NAVY: { key: 'fights', money: false },
  PIRATE: { key: 'loot', money: true },
  CARGO: { key: 'delivered', money: true },
}

const FACE_TESTID: Record<StatsFleetKindId, string> = { NAVY: 'stats-navy', PIRATE: 'stats-pirates', CARGO: 'stats-cargo' }

export function FleetsFace({ kind }: { kind: StatsFleetKindId }) {
  const t = useT()
  const ko = useLocale() === 'ko'
  const read = useLiveRead<StatsFleetList>(`stats:fleet-list:${kind}`, () => worldStatsFleetList(kind), '', true)
  const v = read.view
  const nationByCode = useWorld((s) => s.nationByCode)
  const portByCode = useWorld((s) => s.portByCode)
  const [choice, choose] = useFilterChoice(`stats.fleets.${kind}`, { place: ALL, sort: 'figure' })
  const [all, setAll] = useState(false)
  const [open, setOpen] = useState<StatsFleetListRow | null>(null)
  const testid = FACE_TESTID[kind]

  if (read.loading && !v) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!v) return <Note tone="danger">{t('stats.fleetsFailed')}</Note>
  if (v.counted_at === null || v.list === undefined) return <Empty data-testid="stats-empty">{t('stats.noFigures')}</Empty>

  const cityOf = (code: string) => portName(portNameOf(portByCode, code))
  const nameOf = (row: { name: string; name_ko?: string }) => (ko && row.name_ko ? row.name_ko : row.name)
  const byHome = kind === 'PIRATE'
  const places = (byHome ? countriesOf(v.list.map((r) => r.home)) : countriesOf(v.list.map((r) => r.nation)))
    .map((code) => ({ id: code, label: byHome ? cityOf(code) : nationNameOf(nationByCode, code) }))
    .sort((a, b) => a.label.localeCompare(b.label))
  const place = oneOf(choice.place, [ALL, ...places.map((p) => p.id)], ALL)
  const sort = oneOf(choice.sort, SORTS, 'figure')
  const head = HEADLINE[kind]
  const pick = (r: StatsFleetListRow) => (sort === 'figure' ? fig(r.week, head.key) : sort === 'damage' ? fig(r.week, 'hull') : costs(r.week))
  const rows = v.list
    .filter((r) => place === ALL || (byHome ? r.home : r.nation) === place)
    .sort((a, b) => (sort === 'name' ? 0 : pick(b) - pick(a)) || nameOf(a).localeCompare(nameOf(b)))
  const shown = all ? rows : rows.slice(0, FIRST)
  const countedMs = instantMs(v.counted_at)
  const sinceMs = instantMs(v.since ?? null)
  // the book starts with 0431: while it is younger than 7 days, say since when its 7 days run
  const young = countedMs !== null && sinceMs !== null && countedMs - sinceMs < 6.9 * 86_400_000
  const kindWord = kind === 'NAVY' ? t('stats.navy') : kind === 'PIRATE' ? t('stats.pirates') : t('stats.cargo')
  const sortWord = (id: SortId) =>
    id === 'name' ? t('stats.name') : id === 'damage' ? t('stats.damage') : id === 'costs' ? t('stats.costs') : kind === 'NAVY' ? t('stats.fights') : kind === 'PIRATE' ? t('stats.loot') : t('stats.delivered')

  return (
    <PageSplit
      data-testid={testid}
      sideFirst
      main={
        <>
          <Hint data-testid={`${testid}-counted`}>
            {countedMs !== null && t('stats.countedAt', { time: formatKoreaTime(countedMs) })}
            {young && sinceMs !== null && <> · {t('stats.dayFrom', { time: formatKoreaTime(sinceMs) })}</>}
          </Hint>
          <ListPanel
            look="card"
            columns="fit"
            controls={
              <>
                <FilterBar
                  compact
                  data-testid={`${testid}-filters`}
                  picks={[
                    {
                      id: 'place',
                      label: byHome ? t('stats.homePort') : t('stats.country'),
                      options: [{ id: ALL, label: byHome ? t('stats.allHomes') : t('stats.allCountries') }, ...places],
                      value: place,
                      onChange: (id) => choose({ place: id }),
                    },
                  ]}
                />
                <FilterBar
                  compact
                  data-testid={`${testid}-sort`}
                  sort={{ id: 'sort', label: t('stats.sortLabel'), options: SORTS.map((id) => ({ id, label: sortWord(id) })), value: sort, onChange: (id) => choose({ sort: id }) }}
                />
              </>
            }
            footer={
              !all && rows.length > FIRST ? (
                <Button variant="secondary" onClick={() => setAll(true)} data-testid={`${testid}-show-all`}>
                  {t('stats.showAll')}
                </Button>
              ) : undefined
            }
            data-testid={`${testid}-list`}
          >
            {rows.length === 0 && (
              <Empty className="my-1 md:col-span-full" data-testid="stats-no-match">
                {v.list.length === 0 ? t('stats.noShips') : t('stats.noMatch')}
              </Empty>
            )}
            {shown.map((r) => (
              <Row
                key={r.id}
                mark={r.nation ? <Flag code={r.nation} name={nationNameOf(nationByCode, r.nation)} size="body" /> : <FlagSlot />}
                label={<Clip>{nameOf(r)}</Clip>}
                value={<Figure value={head.money ? formatDucats(fig(r.week, head.key)) : formatInt(fig(r.week, head.key))} />}
                hairline={false}
                onClick={() => setOpen(r)}
                data-testid="stats-fleet"
              >
                <FactsLine>
                  <span>{stateWord(t, r.state)}</span>
                  {r.home && <span>{cityOf(r.home)}</span>}
                  <span>{t('stats.shipsN', { n: formatInt(r.ships), count: r.ships })}</span>
                  {fig(r.week, 'hull') > 0 && <span>{`${t('stats.damage')} ${formatInt(Math.round(fig(r.week, 'hull')))}`}</span>}
                  {costs(r.week) > 0 && <span>{`${t('stats.costs')} ${formatDucats(costs(r.week))}`}</span>}
                </FactsLine>
              </Row>
            ))}
          </ListPanel>
          {open !== null && (
            <Tray detent="full" onDetentChange={(next) => next === 'closed' && setOpen(null)} title={nameOf(open)} data-testid="stats-fleet-tray">
              <FleetPage id={open.id} />
            </Tray>
          )}
        </>
      }
      side={
        <>
          <Card title={kindWord} data-testid={`${testid}-figures`}>
            <div className="grid grid-cols-2 gap-x-4">
              <StatCell look="stacked" label={t('stats.shipsWord')} value={v.ships ?? 0} format={formatInt} />
              <StatCell look="stacked" label={t('stats.fleetsWord')} value={v.fleets ?? 0} format={formatInt} />
            </div>
            <StackedBar
              parts={[
                { id: 'sea', label: t('stats.atSea'), value: v.sea ?? 0, tone: 'info' as const },
                { id: 'port', label: t('stats.inPort'), value: v.port ?? 0, tone: 'success' as const },
                { id: 'laid_up', label: t('stats.laidUp'), value: v.laid_up ?? 0, tone: 'neutral' as const },
                { id: 'wrecked', label: t('stats.wrecked'), value: v.wrecked ?? 0, tone: 'danger' as const },
              ]}
              format={formatInt}
              label={kindWord}
              className="mt-4"
              data-testid={`${testid}-states`}
            />
          </Card>
          <Card title={t('stats.totals')} data-testid={`${testid}-book`}>
            <BookTable kind={kind} day={v.day} week={v.week} />
          </Card>
        </>
      }
    />
  )
}

type T = ReturnType<typeof useT>

function stateWord(t: T, s: StatsFleetState): string {
  return s === 'sea' ? t('stats.atSea') : s === 'port' ? t('stats.inPort') : s === 'laid_up' ? t('stats.laidUp') : t('stats.wrecked')
}

/** A kind's book as a table: one line a figure, its last 24 h and its 7 days side by side. Counts as counts, money as money, the hull lost
 *  rounded. The server's keys, the face's words. */
function BookTable({ kind, day, week }: { kind: StatsFleetKindId; day: StatsFleetFigs | undefined; week: StatsFleetFigs | undefined }) {
  const t = useT()
  const n = (label: string, key: string) => ({ label, key, format: formatInt })
  const d = (label: string, key: string) => ({ label, key, format: formatDucats })
  const hull = { label: t('stats.damage'), key: 'hull', format: (x: number) => formatInt(Math.round(x)) }
  const cells =
    kind === 'NAVY'
      ? [n(t('stats.fights'), 'fights'), n(t('stats.won'), 'won'), n(t('stats.lost'), 'lost'), n(t('stats.pirateSunk'), 'sunk'), n(t('stats.stops'), 'stops'), hull,
         n(t('stats.wrecked'), 'wrecks'), d(t('stats.fines'), 'fines'), d(t('stats.prizes'), 'prizes'), d(t('stats.upkeep'), 'upkeep'), d(t('stats.repairs'), 'repairs')]
      : kind === 'PIRATE'
        ? [n(t('stats.raids'), 'raids'), n(t('stats.won'), 'raids_won'), n(t('stats.lost'), 'raids_lost'), d(t('stats.loot'), 'loot'), d(t('stats.ransom'), 'ransom'),
           d(t('stats.goldTaken'), 'gold'), n(t('stats.navyFights'), 'navy_fights'), hull, n(t('stats.wrecked'), 'wrecks'), n(t('stats.rebuilt'), 'refits'),
           d(t('stats.upkeep'), 'upkeep'), d(t('stats.repairs'), 'repairs')]
        : [n(t('stats.deliveries'), 'delivered_n'), d(t('stats.delivered'), 'delivered'), n(t('stats.loads'), 'loaded_n'), d(t('stats.returned'), 'returned'),
           d(t('stats.looted'), 'looted'), n(t('stats.attacked'), 'attacked'), n(t('stats.held'), 'held'), hull, n(t('stats.wrecked'), 'wrecks'), d(t('stats.repairs'), 'repairs')]
  return (
    <div className="grid grid-cols-[minmax(0,1fr)_max-content_max-content] items-baseline gap-x-4 gap-y-3" data-testid="stats-fleet-book">
      <span />
      <span className="justify-self-end text-t-caption text-ink-faint">{t('stats.last24')}</span>
      <span className="justify-self-end text-t-caption text-ink-faint">{t('stats.week7')}</span>
      {cells.map((c) => (
        <Fragment key={c.key}>
          <span className="min-w-0 text-t-label text-ink-muted">{c.label}</span>
          <span className="justify-self-end">
            <Figure value={c.format(fig(day, c.key))} />
          </span>
          <span className="justify-self-end">
            <Figure value={c.format(fig(week, c.key))} />
          </span>
        </Fragment>
      ))}
    </div>
  )
}

/** ONE FLEET'S PAGE (world.stats_fleet), in the tray: where she is, her 24 h and 7 days, her ships, a cargo ship's gold trips, her log. */
function FleetPage({ id }: { id: string }) {
  const t = useT()
  const ko = useLocale() === 'ko'
  const read = useLiveRead<StatsFleetPage>(`stats:fleet:${id}`, () => worldStatsFleet(id))
  const p = read.view
  const nationByCode = useWorld((s) => s.nationByCode)
  const portByCode = useWorld((s) => s.portByCode)
  const { nowMs } = useShellState()

  if (read.loading && !p) return <Skeleton className="h-64 w-full" data-testid="stats-waiting" />
  if (!p) return <Note tone="danger">{t('stats.fleetsFailed')}</Note>

  const cityOf = (code: string) => portName(portNameOf(portByCode, code))
  const etaMs = instantMs(p.eta ?? null)
  const leftMs = instantMs(p.departed ?? null)
  const mission = missionWord(t, p.mission)
  const sea = p.status === 'SAILING' && p.to
  const sinceMs = instantMs(p.book_from ?? null)
  const atMs = instantMs(p.at)
  const young = atMs !== null && sinceMs !== null && atMs - sinceMs < 6.9 * 86_400_000

  return (
    <div className="flex flex-col gap-4" data-testid="stats-fleet-page">
      <Card title={t('stats.where')} data-testid="stats-fleet-where">
        <Row
          mark={p.nation ? <Flag code={p.nation} name={nationNameOf(nationByCode, p.nation)} size="body" /> : <FlagSlot />}
          label={<Clip>{ko && p.house_ko ? p.house_ko : (p.house ?? (p.nation ? nationNameOf(nationByCode, p.nation) : ''))}</Clip>}
          value={<Figure value={stateWord(t, p.state)} />}
          hairline={false}
        >
          <FactsLine>
            {!sea && p.port && <span>{cityOf(p.port)}</span>}
            {mission && <span>{mission}</span>}
            {p.home && (sea || p.port !== p.home) && <span>{`${p.kind === 'NAVY' ? t('stats.station') : t('stats.homePort')} ${cityOf(p.home)}`}</span>}
          </FactsLine>
        </Row>
        {sea && (
          <div className="mt-2">
            <StatCell look="line" label={p.from ? `${cityOf(p.from)} → ${cityOf(p.to!)}` : t('stats.toCity', { city: cityOf(p.to!) })} text={etaMs !== null ? t('stats.arrives', { time: formatRelative(etaMs, nowMs) }) : '—'} />
            {leftMs !== null && <Hint>{t('stats.leftAt', { time: formatKoreaTime(leftMs) })}</Hint>}
          </div>
        )}
      </Card>

      {p.cargo && (
        <Card title={t('stats.goldTrips')} data-testid="stats-fleet-gold">
          <StatCell look="stacked" label={t('stats.cargoAboard')} value={p.cargo.aboard} format={formatDucats} />
          {p.cargo.load && <Hint>{`${t('stats.stage_LOADED')} ${cityOf(p.cargo.load.port)} · ${formatDucats(p.cargo.load.ducats)}`}</Hint>}
          <div className="mt-3">
            {p.cargo.rows.length === 0 && <Empty className="my-1">{t('stats.nothingYet')}</Empty>}
            {p.cargo.rows.map((r, i) => (
              <GoldRow key={`${r.at}-${i}`} r={r} cityOf={cityOf} nowMs={nowMs} />
            ))}
          </div>
        </Card>
      )}

      <Card title={t('stats.totals')} data-testid="stats-fleet-book-card">
        <BookTable kind={p.kind} day={p.day} week={p.week} />
        {young && sinceMs !== null && <Hint className="mt-3">{t('stats.dayFrom', { time: formatKoreaTime(sinceMs) })}</Hint>}
      </Card>

      <Card title={t('stats.shipsWord')} data-testid="stats-fleet-ships">
        {p.ships.map((s, i) => (
          <Row key={`${s.name}-${i}`} label={<Clip>{s.name}</Clip>} value={<Figure value={s.hull_max ? `${formatInt(Math.round(s.hull))}/${formatInt(Math.round(s.hull_max))}` : formatInt(Math.round(s.hull))} />} hairline={false}>
            <FactsLine>
              <span>{s.class}</span>
              <span>{t('stats.crewN', { n: formatInt(s.crew) })}</span>
            </FactsLine>
          </Row>
        ))}
      </Card>

      <Card title={t('stats.log')} data-testid="stats-fleet-log">
        {p.lines.length === 0 && <Empty className="my-1">{t('stats.nothingYet')}</Empty>}
        {p.lines.map((l, i) => (
          <LogRow key={`${l.at}-${i}`} l={l} cityOf={cityOf} nowMs={nowMs} />
        ))}
      </Card>
    </div>
  )
}

function missionWord(t: T, m: string | undefined): string | null {
  switch (m) {
    case 'PATROL':
      return t('map.mission_PATROL')
    case 'ESCORT':
      return t('map.mission_ESCORT')
    case 'REINFORCE':
      return t('map.mission_REINFORCE')
    case 'HUNT':
      return t('map.mission_HUNT')
    case 'CRUISE':
      return t('map.mission_CRUISE')
    case 'HOME':
      return t('map.mission_HOME')
    default:
      return null
  }
}

function resultWord(t: T, r: StatsFleetLine['result']): string | null {
  return r === 'WON' ? t('map.fight_WON') : r === 'LOST' ? t('map.fight_LOST') : r === 'DREW' ? t('map.fight_DREW') : null
}

/** One gold row of a cargo ship: what happened where, from which city the load came, how much, how long after the load, how long ago. */
function GoldRow({ r, cityOf, nowMs }: { r: StatsCargoRow; cityOf: (code: string) => string; nowMs: number }) {
  const t = useT()
  const atMs = instantMs(r.at)
  const stage =
    r.stage === 'LOADED' ? t('stats.stage_LOADED') : r.stage === 'DELIVERED' ? t('stats.stage_DELIVERED') : r.stage === 'RETURNED' ? t('stats.stage_RETURNED') : t('stats.stage_LOOTED')
  return (
    <Row label={<Clip>{r.from && r.stage === 'DELIVERED' ? `${cityOf(r.from)} → ${cityOf(r.port)}` : cityOf(r.port)}</Clip>} value={<Figure value={formatDucats(r.ducats)} tone={r.stage === 'LOOTED' ? 'danger' : undefined} />} hairline={false} data-testid="stats-fleet-gold-row">
      <FactsLine>
        <span>{stage}</span>
        {r.after !== undefined && r.stage !== 'LOADED' && <span>{t('stats.afterLoad', { time: formatRealShort(r.after * 1000) })}</span>}
        {atMs !== null && <span>{formatRelative(atMs, nowMs)}</span>}
      </FactsLine>
    </Row>
  )
}

/** One line of her log: what it was, the other side, her side of it, and its figure. */
function LogRow({ l, cityOf, nowMs }: { l: StatsFleetLine; cityOf: (code: string) => string; nowMs: number }) {
  const t = useT()
  const atMs = instantMs(l.at)
  const what =
    l.kind === 'FIGHT'
      ? t('stats.line_FIGHT')
      : l.kind === 'STOP'
        ? t('stats.line_STOP')
        : l.kind === 'RAID'
          ? t('stats.line_RAID')
          : l.kind === 'BATTLE'
            ? t('stats.line_BATTLE')
            : l.kind === 'TAKE'
              ? l.how === 'RANSOM'
                ? t('stats.line_RANSOM')
                : t('stats.line_GOLD')
              : t('stats.line_REFIT')
  const who = l.foe ?? l.victim ?? null
  let value: ReactNode
  if (l.kind === 'TAKE') value = <Figure value={formatDucats(l.amount ?? 0)} tone="success" />
  else if (l.kind === 'REFIT') value = <Figure value={formatDucats(l.cost ?? 0)} />
  else if (l.kind === 'STOP' && (l.fine ?? 0) > 0) value = <Figure value={formatDucats(l.fine ?? 0)} />
  else value = <Figure value={resultWord(t, l.result) ?? '—'} tone={l.result === 'WON' ? 'success' : l.result === 'LOST' ? 'danger' : undefined} />
  return (
    <Row label={<Clip>{who ? `${what} · ${who}` : what}</Clip>} value={value} hairline={false} data-testid="stats-fleet-line">
      <FactsLine>
        {l.kind === 'STOP' && (l.fine ?? 0) > 0 && resultWord(t, l.result) && <span>{resultWord(t, l.result)}</span>}
        {l.sank && <span>{t('map.fight_SUNK')}</span>}
        {l.wrecked && <span>{t('stats.wrecked')}</span>}
        {(l.hull ?? 0) > 0 && <span>{`${t('stats.damage')} ${formatInt(Math.round(l.hull ?? 0))}`}</span>}
        {l.kind === 'STOP' && (l.prize ?? 0) > 0 && <span>{`${t('stats.prizes')} ${formatDucats(l.prize ?? 0)}`}</span>}
        {l.kind === 'REFIT' && l.port && <span>{cityOf(l.port)}</span>}
        {atMs !== null && <span>{formatRelative(atMs, nowMs)}</span>}
      </FactsLine>
    </Row>
  )
}
