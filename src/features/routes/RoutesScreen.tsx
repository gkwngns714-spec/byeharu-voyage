import { useMemo, useState } from 'react'
import {
  Button,
  Card,
  Figure,
  Hint,
  ListHeading,
  ListPanel,
  Note,
  PageSplit,
  RankBars,
  Row,
  Segmented,
  Sheet,
  Skeleton,
  StackedBar,
  StatCell,
  Tray,
  type RankRow,
  type StackedPart,
  type TrayDetent,
} from '../../components/ui'
import { formatDucats, formatInt, formatMiles, formatRelative } from '../../lib/format'
import type { RouteBoard, RouteBoardRow } from '../../lib/rpc'
import { nationNameOf, portNameOf, useWorld } from '../../live/worldStore'
import { useRouteBoard } from '../../live/useRouteBoard'
import { useShellState } from '../../app/shellState'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { tabWord } from '../../app/navTabs'
import { t, useLocale, useT, type TKey } from '../../lib/i18n'
import { companiesOf, figuresOf, groupsOf, rankedOf, sortRoutes, topOf, type Order } from './routesFigures'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ROUTES — every lane the world sails, ON THE PAGE (owner row 115, 2026-10-11; row 267, 2026-11-02).
//
// The owner: *"show all trade routes created"* · *"rank them with distance, earning prices, etc."* — and then, of the
// packing that followed: *"it looks so wrong. The past was better. right now everything is on left, too packed. this was
// a mistake"*.
//
// THE PAGE, NOT THE PACKED COLUMN (2026-11-03). The unfold slice (2026-11-02, row 260) put the board in ONE list panel in a
// 75-rem column with 26 rem kept clear at the right — the lanes packed to their reach floor, scrolling inside the panel. Routes
// is now a PAGE (`Sheet layout="page"`, screenLayout.ts "THE PAGE") on the pattern Stats set (docs/dev-log/2026-11-02-stats-
// design.md, Card.tsx) and the Codex, History and Rank followed: MAIN | SIDE from 1,024 px — MAIN the lanes as ONE list card
// whose rows stand in as many columns as the main holds (hers under their own heading, then the merchants'; the sort and the
// board's one button in the card's header, as they were); the SIDE the tray's column, holding THE BOARD'S SHAPE AS GRAPHICS
// (the lanes and yours at 24 px, within reach and out of reach as one stacked bar, the merchants' and the fleetless as lines),
// the TOP LANES of the order on the glass as ranked bars (the boards follow the sort, as the Codex's follow its filters), and
// the LANES BY COMPANY as ranked bars. The page scrolls, never a list inside itself; nothing is pinned and nothing follows the
// scroll (the side is three cards tall — taller than a 768 glass — so it stands where it is). The numbers it was measured to
// are in docs/dev-log/2026-11-03-routes-design.md.
//
// ── IT CONSULTS; IT DOES NOT ACT ────────────────────────────────────────────────────────────────
// This screen lives in the CABIN group for the reason navTabs gives that group: *"none of them acts
// on the world"*. There is no button on it but the board's own "read again". A route is COMPOSED on
// COMMAND, where its verb lives; this is where you find out what the world's lanes are and what they
// are worth, which is a thing you read and then go and do something about. Taking a lane is not one
// tap from a list, and was never asked for.
//
// ── THE RANKING IS THE WHOLE POINT, AND IT IS DONE HERE ─────────────────────────────────────────
// The server serves every figure and no order (`world.route_board`, 0106 — "a READ: it composes no
// order"), and this screen sorts (routesFigures.ts, pure). That is the right seam: a sort is a VIEW,
// the player changes it three times in ten seconds, and a sort on the wire would be three round trips
// and a knob in the migration for each new column anyone wants to rank by.
//
// Three orders, which are the owner's own three: how far a lap sails, what a lap earns, and how
// many harbours it calls at. Distance leads because it is the one figure every route has from the
// moment it exists — earnings are null until a route has closed two laps, which is a fact about
// where a lap boundary falls (`public.route_earnings`, 0097) and not a gap to paper over.
//
// ── WHAT IS NOT ON IT ───────────────────────────────────────────────────────────────────────────
// Another captain's routes: DESIGN §E.5 keeps other players off the chart and a board is not a
// loophole in that; the server does not serve them and asserts that it does not.
//
// A LEVEL REQUIREMENT. Owner row 117 asks for one and docs/NPC_FLEET_SCALE.md puts the gate in
// slice G, after this board; until that gate exists there is no requirement to print, and a column
// of "—" would be this screen inventing a rule the server does not keep. When `public.passage_gate`
// lands, the row gains the field and this screen gains a line — named here so the seam is not
// rediscovered.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export function RoutesScreen() {
  // THE TITLE IS THE TAB'S OWN WORD (navTabs.tabWord) — one authority with the lit nav cell.
  const title = tabWord(useLocale(), '/routes')
  // FIELDS, NOT THE STORE (worldStore.ts rule 4).
  const phase = useWorld((s) => s.phase)
  const fatal = useWorld((s) => s.fatal)

  if (phase === 'failed') return <WorldFailed title={title} refusal={fatal} />
  if (phase !== 'ready') return <WorldLoading title={title} />
  return <RoutesBody title={title} />
}

const ORDERS: readonly { id: Order; label: TKey }[] = [
  { id: 'nm', label: 'routes.distance' },
  { id: 'earned', label: 'routes.earnings' },
  { id: 'calls', label: 'routes.calls' },
] as const

/** How many lanes the Top lanes board draws as bars, and how many companies the By company board ranks. */
const BOARD = 5

function RoutesBody({ title }: { title: string }) {
  const t = useT()
  // THE ONE CLOCK (src/app/shellState.ts), so the board's age ticks without this screen
  // keeping a second one.
  const { nowMs } = useShellState()
  const { board, loading, refreshing, failed, readAt, refresh } = useRouteBoard()
  const [order, setOrder] = useState<Order>('nm')
  const [open, setOpen] = useState<string | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('closed')

  const rows = useMemo(() => sortRoutes(board?.routes ?? [], order), [board, order])
  const { mine, others } = useMemo(() => groupsOf(rows), [rows])
  const opened = board?.routes.find((r) => r.id === open) ?? null

  const show = (r: RouteBoardRow) => {
    setOpen(r.id)
    setDetent('half')
  }
  const lane = (r: RouteBoardRow) => <Lane key={r.id} route={r} order={order} mine={r.mine} onOpen={() => show(r)} />

  // THE BOARD IS A PHOTOGRAPH, HONESTLY DATED — the title's line says how old it is, and the card offers to ask again (its
  // one button) rather than pretending to be live.
  const read = readAt === null ? null : formatRelative(readAt, nowMs)

  // THE PAGE SCROLLS (2026-11-03, owner row 267): no `fill`, no inner scroll — the board is as tall as its lanes.
  return (
    <Sheet
      title={title}
      layout="page"
      data-testid="routes"
      trailing={read === null ? undefined : <span className="text-t-caption text-ink-faint">{t('routes.read', { when: read })}</span>}
    >
      {board === null ? (
        loading ? (
          <ListPanel look="card" title={t('routes.lanes')} data-testid="routes-list">
            <div className="space-y-2 py-1">
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-2/3" />
            </div>
          </ListPanel>
        ) : (
          <Note tone="warning">{t('routes.failed')}</Note>
        )
      ) : (
        <>
          <PageSplit
            data-testid="routes-page"
            // no `sideFirst`: on a phone the board's figures stand AFTER the lanes — the screen's purpose is the lanes, and
            // the first one is on the first glass (the Codex's lesson, 2026-11-02)
            main={
              <ListPanel
                look="card"
                columns="fit"
                title={t('routes.lanes')}
                count={formatInt(board.routes.length)}
                // THE 44-PX FLOOR (the audit, 2026-10-31): it is the card's one secondary action, so it takes the md size.
                trailing={
                  <Button variant="quiet" onClick={refresh} busy={refreshing} busyLabel={t('routes.reading')} data-testid="routes-refresh">
                    {t('routes.readAgain')}
                  </Button>
                }
                controls={
                  <>
                    {failed && (
                      <Note tone="warning" className="w-full">
                        {t('routes.stale')}
                      </Note>
                    )}
                    <Segmented segments={ORDERS.map((o) => ({ id: o.id, label: t(o.label) }))} value={order} onChange={setOrder} label={t('routes.sortLabel')} />
                  </>
                }
                // THE LANES THE WORLD HOLDS BEYOND THE BOARD: the one caption of the card says the cut
                footer={board.omitted > 0 ? <Hint>{t('routes.omitted', { n: formatInt(board.omitted), count: board.omitted })}</Hint> : undefined}
                data-testid="routes-list"
              >
                {others.length === 0 && mine.length === 0 ? (
                  <Row label={board.merchants ? t('routes.noneAnywhere') : t('routes.noneYours')} tone="muted" hairline={false} />
                ) : mine.length === 0 ? (
                  others.map(lane)
                ) : (
                  // HERS FIRST, then the merchants' — each under its heading (ListHeading spans the card's columns); the order
                  // picked ranks each group, and her lanes read as hers by their accent tone, as RANK draws the captain's line.
                  <>
                    <ListHeading data-testid="routes-yours">{t('routes.yours')}</ListHeading>
                    {mine.map(lane)}
                    {others.length > 0 && (
                      <>
                        <ListHeading data-testid="routes-merchants">{t('stats.merchants')}</ListHeading>
                        {others.map(lane)}
                      </>
                    )}
                  </>
                )}
              </ListPanel>
            }
            side={<Side board={board} rows={rows} order={order} />}
          />
          {opened && <LaneTray route={opened} detent={detent} onDetentChange={setDetent} />}
        </>
      )}
    </Sheet>
  )
}

/** THE SIDE: the board's shape, the top lanes of the order on the glass, the lanes by company — every figure a served field, a
 *  count over served rows or a slice of the ordered rows (routesFigures.ts). */
function Side({ board, rows, order }: { board: RouteBoard; rows: readonly RouteBoardRow[]; order: Order }) {
  const t = useT()
  const nationByCode = useWorld((s) => s.nationByCode)
  const figures = useMemo(() => figuresOf(board), [board])
  const top = useMemo(() => topOf(rows, order, BOARD), [rows, order])
  const companies = useMemo(() => companiesOf(rows, BOARD), [rows])
  const flag = (code: string | null) => (code === null ? null : nationNameOf(nationByCode, code))
  const empty = board.merchants ? t('routes.noneAnywhere') : t('routes.noneYours')

  // WITHIN REACH AND OUT OF REACH, as the parts of one bar (0108: the gate read forward against your own levels)
  const reach: StackedPart[] = [
    { id: 'in', label: t('routes.inReach'), value: figures.inReach, tone: 'accent' },
    { id: 'out', label: t('routes.outOfReach'), value: figures.outOfReach, tone: 'warning' },
  ]
  const format = (v: number) => (order === 'nm' ? formatMiles(v) : order === 'earned' ? formatDucats(v) : formatInt(v))
  const topRows: RankRow[] = top.map(({ route, value }) => ({
    id: route.id,
    label: route.name,
    value,
    note: [route.mine ? t('routes.yours') : route.company, t('routes.callsN', { n: formatInt(route.stop_count), count: route.stop_count })].filter(Boolean).join(' · '),
    tone: route.mine ? 'accent' : 'neutral',
  }))
  const companyRows: RankRow[] = companies.map((c) => ({
    id: c.company ?? 'yours',
    label: c.company ?? t('routes.yours'),
    value: c.lanes,
    note: flag(c.nation) ?? undefined,
    tone: c.company === null ? 'accent' : 'neutral',
  }))

  return (
    <>
      <Card title={t('stats.overview')} data-testid="routes-overview">
        <div className="grid grid-cols-2 gap-4">
          <StatCell look="stacked" label={t('routes.lanes')} value={figures.lanes} format={formatInt} tone="accent" data-testid="routes-lanes" />
          <StatCell look="stacked" label={t('routes.yours')} value={figures.mine} format={formatInt} data-testid="routes-mine" />
        </div>
        {/* THE SPLIT, drawn — the bar draws itself only once there is a lane to split; before that the two lines say 0 */}
        {figures.lanes > 0 ? (
          <StackedBar parts={reach} format={formatInt} label={t('routes.byReach')} className="mt-5" data-testid="routes-reach" />
        ) : (
          <div className="mt-3">
            <StatCell look="line" label={t('routes.inReach')} value={figures.inReach} format={formatInt} />
            <StatCell look="line" label={t('routes.outOfReach')} value={figures.outOfReach} format={formatInt} />
          </div>
        )}
        <div className="mt-3">
          <StatCell look="line" label={t('stats.merchants')} value={figures.merchants} format={formatInt} />
          <StatCell look="line" label={t('routes.noFleet')} value={figures.noFleet} format={formatInt} />
        </div>
      </Card>
      {/* THE TOP LANES FOLLOW THE ORDER ON THE GLASS: the card's one small control is the order's word */}
      <Card title={t('routes.top')} aside={<span className="text-t-label text-ink-muted">{t(ORDERS.find((o) => o.id === order)!.label)}</span>} data-testid="routes-top">
        <RankBars rules={false} format={format} empty={empty} rows={topRows} />
      </Card>
      <Card title={t('routes.byCompany')} data-testid="routes-companies">
        <RankBars rules={false} format={formatInt} empty={empty} rows={companyRows} />
      </Card>
    </>
  )
}

/** One lane: its name, the figure the board is ranked by, and one line saying whose it is and what
 *  shape it has. */
function Lane({ route, order, mine = false, onOpen }: { route: RouteBoardRow; order: Order; mine?: boolean; onOpen: () => void }) {
  const ranked = rankFigure(route, order)
  return (
    // A LANE YOU CANNOT SAIL IS STILL ON THE BOARD, and reads as muted rather than being
    // hidden: the owner asked to SEE every route created (row 115), and what it would take is
    // the reason to go and study (row 117). Yours wins the tone when both apply — nothing you
    // keep is ever shown as out of your own reach among your own lanes (first on the board).
    <Row
      label={route.name}
      value={
        ranked === null ? (
          <span className="text-ink-faint">{t(order === 'nm' ? 'routes.unmeasured' : 'routes.notYet')}</span>
        ) : (
          <Figure value={ranked} tone={mine ? 'accent' : undefined} />
        )
      }
      tone={mine ? 'accent' : route.closed ? 'muted' : undefined}
      chevron
      onClick={onOpen}
      hairline={false}
      data-testid="route-lane"
    >
      <span className="block text-t-caption text-ink-faint">{laneLine(route, mine, order)}</span>
    </Row>
  )
}

/** The figure being ranked on, as it reads; NULL where the server has none (an unmeasured lap, earnings before a second lap
 *  closes) — the row says so in a word, it never draws a dash. */
function rankFigure(route: RouteBoardRow, order: Order): string | null {
  const value = rankedOf(route, order)
  if (value === null) return null
  return order === 'nm' ? formatMiles(value) : order === 'calls' ? formatInt(value) : formatDucats(value)
}

/** Whose lane, and its shape: `Casa da Índia · 5 calls · 3 regions · 4,120 nm`. Her own says so by
 *  being on her own panel and does not repeat a company name she knows. A lane that is shut to
 *  you ends with WHY — the one figure that is standing between you and it, not both, because a
 *  second-line is one reading and two numbers in it is a table. THE FIGURE THE ROW IS RANKED BY IS
 *  NOT SAID TWICE (2026-11-03, the page slice): under Distance the miles stand at the row's edge, so
 *  the line keeps the calls and the regions; under Calls the calls are the figure, so the line keeps
 *  the miles. */
function laneLine(route: RouteBoardRow, mine: boolean, order: Order): string {
  return [
    mine ? t('routes.yours') : route.company,
    order === 'calls' ? null : t('routes.callsN', { n: formatInt(route.stop_count), count: route.stop_count }),
    route.regions > 1 ? t('routes.regionsN', { n: formatInt(route.regions) }) : null,
    route.nm === null || order === 'nm' ? null : formatMiles(route.nm),
    route.assigned ? null : t('routes.noFleet'),
    route.closed ? shutBecause(route) : null,
  ]
    .filter(Boolean)
    .join(' · ')
}

/** The ONE thing standing between you and a lane: the navigation its longest leg asks (0218, owner
 *  row 204: there is no region door any more, so nothing else shuts a lane). A lane is `closed`
 *  only when that level is known and above yours. */
function shutBecause(route: RouteBoardRow): string | null {
  return route.requires.navigation === null ? null : t('routes.needsNav', { n: formatInt(route.requires.navigation) })
}

/** THE LANE, OPENED: where she calls, in order, and what the laps say. Every figure is the
 *  server's — `public.route_nm` for the distance and `public.route_earnings` for the rest. It slides over the page's side
 *  column (`useInPage()` in Tray.tsx, the Stats mechanism; nothing here chose it) and moves nothing. */
function LaneTray({
  route,
  detent,
  onDetentChange,
}: {
  route: RouteBoardRow
  detent: TrayDetent
  onDetentChange: (d: TrayDetent) => void
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const nationByCode = useWorld((s) => s.nationByCode)
  const calls = route.stops.map((c) => portNameOf(portByCode, c))

  return (
    <Tray detent={detent} onDetentChange={onDetentChange} title={route.name} data-testid="route-tray">
      {!route.mine && route.company !== null && (
        <Row
          label={route.company}
          value={route.nation_code === null ? undefined : nationNameOf(nationByCode, route.nation_code)}
        />
      )}
      <Row label={t('routes.callsAt')} value={<Figure value={formatInt(route.stop_count)} />}>
        {/* The loop closes on its first harbour, so the arrow comes back to where it began — which
            is the owner's own shape for a route (row 122) and not a flourish. */}
        <span className="block text-t-caption text-ink-faint">{`${calls.join(' → ')} → ${calls[0] ?? '—'}`}</span>
      </Row>
      <Row
        label={t('routes.lapSails')}
        value={
          route.nm === null ? (
            <span className="text-ink-faint">{t('routes.unmeasured')}</span>
          ) : (
            <Figure value={formatMiles(route.nm)} />
          )
        }
      >
        {route.nm === null && (
          <span className="block text-t-caption text-ink-faint">
            {t('routes.noDistance')}
          </span>
        )}
      </Row>
      {route.regions > 1 && <Row label={t('routes.regions')} value={<Figure value={formatInt(route.regions)} />} />}
      <Row
        label={t('routes.asks')}
        value={
          route.requires.navigation === null ? (
            <span className="text-ink-faint">{t('routes.unmeasured')}</span>
          ) : (
            <Figure
              value={t('routes.asksNav', { nav: formatInt(route.requires.navigation) })}
              tone={route.closed ? 'warning' : undefined}
            />
          )
        }
      >
        <span className="block text-t-caption text-ink-faint">
          {route.closed
            ? t('routes.wouldRefuse')
            : t('routes.within')}
        </span>
      </Row>
      <Row label={t('routes.state')} value={route.state} />
      <Row
        label={t('routes.lapEarns')}
        value={
          route.earnings.lap === null ? (
            <span className="text-ink-faint">{t('routes.notYet')}</span>
          ) : (
            <Figure value={formatDucats(route.earnings.lap)} tone="accent" />
          )
        }
      >
        <span className="block text-t-caption text-ink-faint">
          {route.earnings.lap === null
            ? t('routes.twoLaps')
            : t('routes.meanOf', { n: formatInt(route.earnings.lap_basis), count: route.earnings.lap_basis })}
        </span>
      </Row>
      <Row
        label={t('routes.lapsClosed')}
        value={<Figure value={formatInt(route.earnings.laps_done)} />}
        hairline={false}
      />
      {!route.assigned && <Hint className="mt-2">{t('routes.plan')}</Hint>}
    </Tray>
  )
}
