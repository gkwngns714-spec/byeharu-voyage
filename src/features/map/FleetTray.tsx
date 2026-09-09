import { useState } from 'react'
import { Bar, Figure, Row, Tray, type TrayDetent } from '../../components/ui'
import { formatCountdown, formatFixed, formatInt, formatNm, formatVoyageDays, realMsToVoyageDays } from '../../lib/format'
import { pointLabel } from '../../domain/passage'
import { CHART_CHROME, type FleetOnChart, type MapPort } from '../../chart'
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
export function FleetTray({
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
      {fleet.fleet.kind === 'anchored' && <Row label="At anchor" value={pointLabel(fleet.at)} />}
      {voyage && (
        <>
          {/* 0039: a destination is a port, or a pinpointed spot of open water. */}
          <Row
            label="To"
            value={
              voyage.destinationCode
                ? nameOf(voyage.destinationCode)
                : voyage.destPoint
                  ? pointLabel(voyage.destPoint)
                  : '—'
            }
          />
          <Row
            label="Sailed"
            value={<Figure value={`${formatInt(voyage.sailedNm)} / ${formatNm(voyage.totalNm)}`} />}
          />
          {voyage.departedMs !== null && (
            <Row label="At sea" value={<Figure value={formatCountdown(nowMs - voyage.departedMs)} />} />
          )}
          <Row label="Arrives" value={<Figure value={formatCountdown(voyage.etaMs - nowMs)} />} />
        </>
      )}
      <Row label="Stores" value={<Figure value={formatFixed(stores, 1)} unit="days" />} hairline={false}>
        {voyage && daysToRun > 0 && Number.isFinite(stores) && (
          <Bar
            pct={Math.min(1, stores / daysToRun) * 100}
            tone={stores < daysToRun ? 'warning' : 'success'}
            label="stores against the passage"
            className="mt-1"
            figure={<span className="text-t-caption text-ink-faint">{`${formatVoyageDays(daysToRun)} to run`}</span>}
          />
        )}
      </Row>
      {voyage && <WatersAhead waters={voyage.waters} />}
    </Tray>
  )
}
