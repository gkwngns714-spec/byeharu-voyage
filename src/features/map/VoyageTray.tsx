import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { Bar, Figure, Icon, Row, Tray, TrayTitle, type TrayDetent } from '../../components/ui'
import {
  formatCountdown,
  formatDucatsDelta,
  formatFixed,
  formatInt,
  formatMiles,
  formatVoyageDays,
  pointLabel,
  realMsToVoyageDays,
} from '../../lib/format'
import {
  CHART_CHROME,
  GoToLink,
  hullClassOfCode,
  hullPath,
  PlaceLine,
  type FleetOnChart,
  type HullClass,
  type MapPort,
} from '../../chart'
import { fleetParts } from './fleetLine'
import { useWorld } from '../../live/worldStore'
import type { FleetShip } from '../../lib/rpc'
import { ShipPanel } from '../../live/ShipPanel'
import { CrewBonuses } from '../../live/CrewBonuses'
import { TradeHistoryPanel, type TradePick } from '../../live/TradeHistoryPanel'


import { WatersAhead } from './WatersAhead'

// THE FLEET TRAY — what the ship you tapped is doing, rising from the bottom edge.
//
// docs/UI_DIRECTION.md §6, MAP: "the detail panel becomes a `Tray` (peek shows name + one line;
// half shows …)". At peek it is her name and `fleetLine` — the same line the corner prints, so a
// tap on her glyph and a press on her row read as one thing. At half it is rows.
//
// EVERY NUMBER HERE IS THE SERVER'S. `sailed / total` is `voyage.position.nm_done` against
// `total_nm` — SAILED miles, so a passage that rounds a cape reads the distance it really is; the
// two clocks are `departed_at` (0063) and `eta` against the one shell clock, per second, because
// the owner asked for a REAL timer (row 50) and a figure that moves once a minute is not one.
//
// THE STORES BAR is a ratio of two served figures: `endurance_days` (0016) over the days her own
// `eta` still asks for. No burn rate crosses the wire and none is reconstructed. It is the picture
// a short fleet would meet as a refusal at the quay, carried with her — full is ENOUGH, not full
// is full: the bar reads 100% the moment she carries the passage.
//
// THE SENTENCE THAT IS NOT HERE. The old panel ended a docked fleet with *"Tap where she should
// go — a harbour, or any water."* — the code narrating the gesture. Sending is destination-first
// on this screen (SendFleet.tsx is the one authority), the harbour under her is a tap away, and §6
// cuts the hint. There is no send button here for the same reason there never was one: a second
// mover with its own destination picker is what four movers cost this project.
/**
 * ONE FACT, as a term and its figure. A `<dl>` cell rather than a `Row`: the grid owns the spacing,
 * and the pair stays a pair for a screen reader, which a pile of divs would not.
 */
function Fact({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="truncate text-t-caption text-ink-faint">{label}</dt>
      <dd className="truncate text-t-body tabular-nums">{value}</dd>
    </div>
  )
}

/**
 * THE HULLS SHE SAILS, in the silhouettes the chart draws them in (row 120's `hullPath`).
 *
 * THE SAME SHAPES, DELIBERATELY. A reader who has learnt that a spindle is a barca on the water
 * should not have to learn a second vocabulary in the sheet — and a picture of her three naus is a
 * fact no sentence delivers as fast. Drawn at a fixed 26 px box each, bow up, so a squadron reads
 * as a formation rather than a size comparison; the SIZE channel belongs to the chart, where there
 * is a sea to judge it against.
 *
 * A fleet whose classes the server did not name draws the class-less hull, exactly as the chart
 * does: the lesser answer may be lesser, never wrong.
 */
function HullStrip({ hulls }: { hulls: readonly (HullClass | null)[] }) {
  if (hulls.length === 0) return null
  const counted = new Map<string, number>()
  for (const h of hulls) counted.set(h ?? 'ship', (counted.get(h ?? 'ship') ?? 0) + 1)
  return (
    <div className="flex items-center gap-3 py-2" data-testid="tray-hulls">
      <div className="flex items-end gap-1.5">
        {hulls.slice(0, 6).map((cls, i) => (
          <svg key={i} width={30} height={30} viewBox="-15 -15 30 30" aria-hidden className="shrink-0">
            <path
              // DRAWN TO FILL THE BOX, not at her chart size. The first cut passed
              // `hullHalfLengthOf(cls)` — 5.7 for a barca — into a 30-unit box, and she came out a
              // 1.9-unit sliver nobody could read as a hull. The SIZE channel belongs to the chart,
              // where there is a sea to judge her against; in here the job is the SHAPE, so every
              // class is drawn to the same length and a reader sees what she IS.
              d={hullPath(cls, 13)}
              className="fill-accent stroke-chart-sea"
              strokeWidth={0.9}
              strokeLinejoin="round"
            />
          </svg>
        ))}
      </div>
      <span className="min-w-0 truncate text-t-caption text-ink-faint">
        {[...counted].map(([cls, n]) => `${n} ${HULL_WORD[cls] ?? cls}${n > 1 ? 's' : ''}`).join(' · ')}
      </span>
    </div>
  )
}

/** THE FLEET'S SHIPS, one pressable row each (owner, 2026-10-15: *"name of the fleet, then
 *  ships"*); a press slides her own panel in over this one (./ShipPanel.tsx). */
function ShipList({ ships, onOpen }: { ships: readonly FleetShip[]; onOpen: (id: string) => void }) {
  if (ships.length === 0) return null
  return (
    <ul className="flex flex-col gap-1 py-2" data-testid="tray-ships">
      {ships.map((ship) => (
        <li key={ship.id}>
          <button
            type="button"
            onClick={() => onOpen(ship.id)}
            data-testid="tray-ship"
            className="flex min-h-11 w-full items-center gap-3 rounded-control bg-surface-2 px-3 py-2 text-left"
          >
            <svg width={26} height={26} viewBox="-15 -15 30 30" aria-hidden className="shrink-0">
              <path
                d={hullPath(hullClassOfCode(ship.class_code), 13)}
                className="fill-accent stroke-chart-sea"
                strokeWidth={0.9}
                strokeLinejoin="round"
              />
            </svg>
            <span className="min-w-0 flex-1">
              <span className="block truncate text-t-body">{ship.name}</span>
              <span className="block truncate text-t-caption text-ink-faint">
                {ship.is_flagship ? `${ship.class} · flagship` : ship.class}
              </span>
            </span>
            <Icon name="chevron" size={18} className="shrink-0 text-ink-faint" />
          </button>
        </li>
      ))}
    </ul>
  )
}

/** HER ROUTE'S TRADING — the route's name, a "So far" press, the lap under way, and one pill per
 *  closed lap (newest first, the same seven world.fleet_trades serves, so pill i is lap i there).
 *  The nets are the routes book's own (`StandingRoute.laps`), not a sum made here. */
function RouteLaps({
  name,
  laps,
  underWay,
  onOpen,
}: {
  name: string
  laps: readonly number[]
  underWay: boolean
  onOpen: (pick: TradePick) => void
}) {
  const pill = 'whitespace-nowrap rounded-chip px-2 py-0.5 text-t-caption leading-snug tabular-nums transition hover:ring-1 hover:ring-current'
  return (
    <section className="py-2" data-testid="tray-route-laps">
      <div className="flex items-baseline justify-between gap-2 pb-1.5">
        <span className="min-w-0 truncate text-t-caption uppercase tracking-wider text-ink-faint">{`Trading · ${name}`}</span>
      </div>
      <div className="flex flex-wrap gap-1.5">
        <button type="button" className={`${pill} bg-surface-2 text-ink`} onClick={() => onOpen({ kind: 'day' })} data-testid="tray-trades-day">
          So far
        </button>
        {underWay && (
          <button type="button" className={`${pill} bg-accent/15 text-accent`} onClick={() => onOpen({ kind: 'open' })} data-testid="tray-trades-open">
            This lap
          </button>
        )}
        {laps.map((n, i) => (
          <button
            key={i}
            type="button"
            onClick={() => onOpen({ kind: 'lap', index: i })}
            className={`${pill} ${n > 0 ? 'bg-success/15 text-success' : n < 0 ? 'bg-danger/15 text-danger' : 'bg-surface-2 text-ink-muted'}`}
            data-testid="tray-lap-pill"
          >
            {formatDucatsDelta(n)}
          </button>
        ))}
      </div>
    </section>
  )
}

/** What a reader calls each class. The CODE is the server's word; this is the player's. */
const HULL_WORD: Record<string, string> = {
  barca: 'barca',
  carlat: 'caravel',
  nau: 'nau',
  ship: 'ship',
}

export function VoyageTray({
  fleet,
  portsByCode,
  nowMs,
  onClose,
}: {
  fleet: FleetOnChart
  portsByCode: ReadonlyMap<string, MapPort>
  nowMs: number
  onClose: () => void
}) {
  const [detent, setDetent] = useState<TrayDetent>('peek')
  const nameOf = (code: string) => portsByCode.get(code)?.name ?? code
  const voyage = fleet.voyage
  const daysToRun = voyage ? Math.max(0, realMsToVoyageDays(voyage.etaMs - nowMs)) : 0
  const stores = fleet.fleet.enduranceDays
  const own = useWorld((s) => s.fleets.find((f) => f.id === fleet.fleet.id))
  const ships = own?.ships
  // 0157: the captains you keep — the ones a cabin of hers can seat
  const roster = useWorld((s) => s.officers)
  const kept = useMemo(() => (roster?.officers ?? []).filter((o) => o.hired), [roster])
  const loadOfficers = useWorld((s) => s.loadOfficers)
  useEffect(() => {
    if (roster === null) void loadOfficers()
  }, [roster, loadOfficers])
  const [openShipId, setOpenShipId] = useState<string | null>(null)
  const openShip = ships?.find((s) => s.id === openShipId) ?? null
  // HER ROUTE'S LAPS, if she sails one — the company's routes book the shell already holds, so
  // nothing is asked to decide whether to show them. A press opens her trading beside this tray
  // (owner, 2026-10-15), in the slot a ship's panel uses: one of the two at a time.
  const route = useWorld((s) => s.routes?.routes.find((r) => r.fleet?.id === fleet.fleet.id) ?? null)
  const [trades, setTrades] = useState<TradePick | null>(null)
  const openShipPanel = (id: string) => {
    setTrades(null)
    setOpenShipId(id)
  }
  const openTrades = (pick: TradePick) => {
    setOpenShipId(null)
    setTrades(pick)
  }

  return (
    <>
    <Tray
      mode="side"
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={
        <TrayTitle
          name={<GoToLink to={{ kind: 'fleet', id: fleet.fleet.id }}>{fleet.fleet.name}</GoToLink>}
          line={<PlaceLine parts={fleetParts(fleet, portsByCode, nowMs)} />}
        />
      }
      data-testid="map-detail-tray"
      {...CHART_CHROME}
    >
      {/* ── WHAT SHE IS, BEFORE WHAT SHE IS DOING (owner, 2026-10-12: *"too many words… packed with
          info - useful info"*) ──────────────────────────────────────────────────────────────────
          A docked fleet used to open a 422 px sheet to say two things — her port and her supplies —
          and leave some 280 px of it blank. Measured, on the owner's own sheet. The sheet was not
          too big; it had nothing in it.

          HER HULLS ARE THE MISSING SUBJECT, and they were already drawn — row 120 gave every class
          a silhouette, and the tray that opens when you tap her never showed one. They are the
          densest true thing this screen holds: what she is, at a glance, in the SAME shapes the
          chart draws, so the mark on the water and the row in the sheet are one language. No new
          read, no new wire key — `MapFleet.hulls` has been served since row 120. */}
      {ships && ships.length > 0 ? (
        <ShipList ships={ships} onOpen={openShipPanel} />
      ) : (
        <HullStrip hulls={fleet.fleet.hulls ?? []} />
      )}

      {/* ── THE FACTS, IN A GRID RATHER THAN A COLUMN ───────────────────────────────────────────
          Full-width label/value rows spend a whole line on four words and a number, which is how a
          sheet with five facts in it still reads as empty. Two columns put the same facts in half
          the height and let the eye take them in as a block. */}
      <dl className="grid grid-cols-2 gap-x-gutter gap-y-2 py-2">
        {fleet.fleet.kind === 'anchored' && <Fact label="Anchored" value={<GoToLink to={{ kind: 'point', at: fleet.at }}>{pointLabel(fleet.at)}</GoToLink>} />}
        {fleet.fleet.kind === 'docked' && <Fact label="In port" value={<GoToLink to={{ kind: 'port', code: fleet.fleet.portCode }}>{nameOf(fleet.fleet.portCode)}</GoToLink>} />}
        {voyage && (
          <>
            {/* 0039: a destination is a port, or a pinpointed spot of open water. */}
            <Fact
              label="Bound for"
              value={
                voyage.destinationCode ? (
                  <GoToLink to={{ kind: 'port', code: voyage.destinationCode }}>{nameOf(voyage.destinationCode)}</GoToLink>
                ) : voyage.destPoint ? (
                  <GoToLink to={{ kind: 'point', at: voyage.destPoint }}>{pointLabel(voyage.destPoint)}</GoToLink>
                ) : (
                  '—'
                )
              }
            />
            <Fact label="Arrives in" value={formatCountdown(voyage.etaMs - nowMs)} />
            <Fact label="Sailed" value={`${formatInt(voyage.sailedNm)} / ${formatMiles(voyage.totalNm)}`} />
            {voyage.departedMs !== null && (
              <Fact label="At sea" value={formatCountdown(nowMs - voyage.departedMs)} />
            )}
          </>
        )}
      </dl>

      <Row label="Supplies" value={<Figure value={formatFixed(stores, 1)} unit="days" />} hairline={false}>
        {voyage && daysToRun > 0 && Number.isFinite(stores) && (
          <Bar
            pct={Math.min(1, stores / daysToRun) * 100}
            tone={stores < daysToRun ? 'warning' : 'success'}
            label="supplies against the voyage"
            className="mt-1"
            figure={<span className="text-t-caption text-ink-faint">{`${formatVoyageDays(daysToRun)} to run`}</span>}
          />
        )}
      </Row>
      {voyage && <WatersAhead waters={voyage.waters} />}
      <CrewBonuses crew={own?.crew} />
      {route && (
        <RouteLaps
          name={route.name}
          laps={route.laps.slice(0, 7).map((l) => l.net)}
          underWay={route.lap !== null}
          onOpen={openTrades}
        />
      )}
    </Tray>
    {openShip && (
      <ShipPanel
        key={openShip.id}
        ship={openShip}
        onClose={() => setOpenShipId(null)}
        seating={{ shipId: openShip.id, docked: own?.status === 'DOCKED', captains: kept }}
      />
    )}
    {trades && (
      <TradeHistoryPanel fleetId={fleet.fleet.id} pick={trades} onPick={setTrades} onClose={() => setTrades(null)} />
    )}
    </>
  )
}
