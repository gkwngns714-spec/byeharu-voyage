import { useState } from 'react'
import { Bar, Figure, Row, Tray, type TrayDetent } from '../../components/ui'
import { formatCountdown, formatFixed, formatInt, formatMiles, formatVoyageDays, realMsToVoyageDays } from '../../lib/format'
import { pointLabel } from '../../domain/passage'
import { CHART_CHROME, hullPath, type FleetOnChart, type HullClass, type MapPort } from '../../chart'
import { fleetLine } from './fleetLine'
import { MapTrayTitle } from './MapTrayTitle'
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
function Fact({ label, value }: { label: string; value: string }) {
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

  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={<MapTrayTitle name={fleet.fleet.name} line={fleetLine(fleet, portsByCode, nowMs)} />}
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
      <HullStrip hulls={fleet.fleet.hulls ?? []} />

      {/* ── THE FACTS, IN A GRID RATHER THAN A COLUMN ───────────────────────────────────────────
          Full-width label/value rows spend a whole line on four words and a number, which is how a
          sheet with five facts in it still reads as empty. Two columns put the same facts in half
          the height and let the eye take them in as a block. */}
      <dl className="grid grid-cols-2 gap-x-gutter gap-y-2 py-2">
        {fleet.fleet.kind === 'anchored' && <Fact label="Anchored" value={pointLabel(fleet.at)} />}
        {fleet.fleet.kind === 'docked' && <Fact label="In port" value={nameOf(fleet.fleet.portCode)} />}
        {voyage && (
          <>
            {/* 0039: a destination is a port, or a pinpointed spot of open water. */}
            <Fact
              label="Bound for"
              value={
                voyage.destinationCode
                  ? nameOf(voyage.destinationCode)
                  : voyage.destPoint
                    ? pointLabel(voyage.destPoint)
                    : '—'
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
    </Tray>
  )
}
