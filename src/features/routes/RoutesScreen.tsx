import { useMemo, useState } from 'react'
import {
  Button,
  Figure,
  Hint,
  Note,
  DetailPage,
  Row,
  Segmented,
  Sheet,
  SheetSection,
  Skeleton,
  SummaryRow,
  Tray,
  type TrayDetent,
} from '../../components/ui'
import { formatDucats, formatInt, formatMiles, formatRelative } from '../../lib/format'
import type { RouteBoardRow } from '../../lib/rpc'
import { nationNameOf, portNameOf, useWorld } from '../../live/worldStore'
import { useRouteBoard } from '../../live/useRouteBoard'
import { useShellState } from '../../app/shellState'
import { WorldFailed, WorldLoading } from '../../live/WorldGate'
import { tabWord } from '../../app/navTabs'
import { t, useLocale, useT, type TKey } from '../../lib/i18n'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// ROUTES — every lane the world sails, on one board (owner row 115, 2026-10-11).
//
// The owner: *"show all trade routes created"* · *"rank them with distance, earning prices, etc."*
//
// ── IT CONSULTS; IT DOES NOT ACT ────────────────────────────────────────────────────────────────
// This screen lives in the CABIN group for the reason navTabs gives that group: *"none of them acts
// on the world"*. There is no button on it. A route is COMPOSED on COMMAND, where its verb lives;
// this is where you find out what the world's lanes are and what they are worth, which is a thing
// you read and then go and do something about. Taking a lane is not one tap from a list, and was
// never asked for.
//
// ── THE RANKING IS THE WHOLE POINT, AND IT IS DONE HERE ─────────────────────────────────────────
// The server serves every figure and no order (`world.route_board`, 0106 — "a READ: it composes no
// order"), and this screen sorts. That is the right seam: a sort is a VIEW, the player changes it
// three times in ten seconds, and a sort on the wire would be three round trips and a knob in the
// migration for each new column anyone wants to rank by.
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

type Order = 'nm' | 'earned' | 'calls'

const ORDERS: readonly { id: Order; label: TKey }[] = [
  { id: 'nm', label: 'routes.distance' },
  { id: 'earned', label: 'routes.earnings' },
  { id: 'calls', label: 'routes.calls' },
] as const

function RoutesBody({ title }: { title: string }) {
  const t = useT()
  // THE ONE CLOCK (src/app/shellState.ts), so the board's age ticks without this screen
  // keeping a second one.
  const { nowMs } = useShellState()
  const { board, loading, refreshing, failed, readAt, refresh } = useRouteBoard()
  const [order, setOrder] = useState<Order>('nm')
  const [open, setOpen] = useState<string | null>(null)
  const [detent, setDetent] = useState<TrayDetent>('closed')
  // THE BOARD IS A PAGE (owner, 2026-10-31); the compact screen is the sort strip and one summary.
  const [page, setPage] = useState(false)

  const rows = useMemo(() => sortRoutes(board?.routes ?? [], order), [board, order])
  const mine = rows.filter((r) => r.mine)
  const others = rows.filter((r) => !r.mine)
  const opened = board?.routes.find((r) => r.id === open) ?? null

  return (
    <Sheet title={title} data-testid="routes">
      {board === null ? (
        loading ? (
          <div className="space-y-2">
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-2/3" />
          </div>
        ) : (
          <Note tone="warning">{t('routes.failed')}</Note>
        )
      ) : (
        <>
          <SummaryRow
            title={title}
            figure={formatInt(board.total)}
            word={t('common.open')}
            onClick={() => setPage(true)}
            data-testid="routes-open"
          />
          {page && (
            <DetailPage
              title={title}
              figure={formatInt(board.total)}
              onClose={() => {
                setPage(false)
                setOpen(null)
              }}
              data-testid="routes-open-page"
            >
              {/* THE BOARD IS A PHOTOGRAPH, HONESTLY DATED — it says how old it is and offers to be
                  asked again rather than pretending to be live. */}
              <div className="flex flex-wrap items-center gap-2 pb-2 text-t-caption text-ink-faint">
                <span>
                  {board.omitted > 0
                    ? t('routes.someLanes', { n: formatInt(board.routes.length), total: formatInt(board.total) })
                    : t('routes.lanes', { n: formatInt(board.total), count: board.total })}
                </span>
                {readAt !== null && <span>{formatRelative(readAt, nowMs)}</span>}
                {/* THE 44-PX FLOOR (the audit, 2026-10-31): this stood at 36px with no neighbour
                    on the floor. It is the page's one secondary action, so it takes the md size. */}
                <Button variant="quiet" onClick={refresh} busy={refreshing} busyLabel={t('routes.reading')} data-testid="routes-refresh">
                  {t('routes.readAgain')}
                </Button>
              </div>
          {failed && (
            <Note tone="warning" className="mb-3">
              {t('routes.stale')}
            </Note>
          )}
          <Segmented segments={ORDERS.map((o) => ({ id: o.id, label: t(o.label) }))} value={order} onChange={setOrder} label={t('routes.sortLabel')} className="mb-3" />
          {mine.length > 0 && (
            // HERS ON HER OWN PANEL, as RANK pins the captain's line: one tone step, so her lanes
            // read as hers rather than as the first rows of a printout.
            <SheetSection surface>
              {mine.map((r, i) => (
                <Lane
                  key={r.id}
                  route={r}
                  order={order}
                  mine
                  hairline={i < mine.length - 1}
                  onOpen={() => {
                    setOpen(r.id)
                    setDetent('half')
                  }}
                />
              ))}
            </SheetSection>
          )}

          {others.length === 0 && mine.length === 0 ? (
            <Row
              label={
                board.merchants
                  ? t('routes.noneAnywhere')
                  : t('routes.noneYours')
              }
              tone="muted"
              hairline={false}
            />
          ) : (
            <SheetSection surface className={mine.length > 0 ? 'mt-2' : undefined}>
              {others.map((r, i) => (
                <Lane
                  key={r.id}
                  route={r}
                  order={order}
                  hairline={i < others.length - 1}
                  onOpen={() => {
                    setOpen(r.id)
                    setDetent('half')
                  }}
                />
              ))}
            </SheetSection>
          )}

          {board.omitted > 0 && (
            <Hint className="mt-2">
              {t('routes.omitted', { n: formatInt(board.omitted), count: board.omitted })}
            </Hint>
          )}
          {opened && <LaneTray route={opened} detent={detent} onDetentChange={setDetent} />}
            </DetailPage>
          )}
        </>
      )}
    </Sheet>
  )
}

/** The order the board is read in. Within each order the tie-break is the NAME, so the list does
 *  not shuffle under the player between two reads of the same figures. A figure the server has not
 *  got — earnings before a second lap closes, a distance it will not measure — sorts LAST rather
 *  than as a zero: the route has not earned nothing and is not nought miles long, the server has
 *  declined to say. */
function sortRoutes(rows: readonly RouteBoardRow[], order: Order): RouteBoardRow[] {
  const by = (r: RouteBoardRow): number =>
    order === 'nm'
      ? (r.nm ?? Number.NEGATIVE_INFINITY)
      : order === 'calls'
        ? r.stop_count
        : (r.earnings.lap ?? Number.NEGATIVE_INFINITY)
  return [...rows].sort((a, b) => by(b) - by(a) || a.name.localeCompare(b.name))
}

/** One lane: its name, the figure the board is ranked by, and one line saying whose it is and what
 *  shape it has. */
function Lane({
  route,
  order,
  mine = false,
  hairline,
  onOpen,
}: {
  route: RouteBoardRow
  order: Order
  mine?: boolean
  hairline: boolean
  onOpen: () => void
}) {
  return (
    // A LANE YOU CANNOT SAIL IS STILL ON THE BOARD, and reads as muted rather than being
    // hidden: the owner asked to SEE every route created (row 115), and what it would take is
    // the reason to go and study (row 117). Yours wins the tone when both apply — nothing you
    // keep is ever shown as out of your own reach on your own panel.
    <Row
      label={route.name}
      value={<Figure value={rankFigure(route, order)} tone={mine ? 'accent' : undefined} />}
      tone={mine ? 'accent' : route.closed ? 'muted' : undefined}
      chevron
      onClick={onOpen}
      hairline={hairline}
      data-testid="route-lane"
    >
      <span className="block text-t-caption text-ink-faint">{laneLine(route, mine)}</span>
    </Row>
  )
}

/** The figure being ranked on, and the ABSENCE where the server has one. */
function rankFigure(route: RouteBoardRow, order: Order): string {
  if (order === 'nm') return route.nm === null ? '—' : formatMiles(route.nm)
  if (order === 'calls') return formatInt(route.stop_count)
  return route.earnings.lap === null ? '—' : formatDucats(route.earnings.lap)
}

/** Whose lane, and its shape: `Casa da Índia · 5 calls · 3 regions · 4,120 nm`. Her own says so by
 *  being on her own panel and does not repeat a company name she knows. A lane that is shut to
 *  you ends with WHY — the one figure that is standing between you and it, not both, because a
 *  second-line is one reading and two numbers in it is a table. */
function laneLine(route: RouteBoardRow, mine: boolean): string {
  return [
    mine ? t('routes.yours') : route.company,
    t('routes.callsN', { n: formatInt(route.stop_count), count: route.stop_count }),
    route.regions > 1 ? t('routes.regionsN', { n: formatInt(route.regions) }) : null,
    route.nm === null ? null : formatMiles(route.nm),
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
 *  server's — `public.route_nm` for the distance and `public.route_earnings` for the rest. */
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
