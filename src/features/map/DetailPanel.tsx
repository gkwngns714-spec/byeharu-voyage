import { formatInt, formatNm, formatRealShort } from '../../lib/format'
import type { FleetView, VerbSpec } from '../../lib/rpc'
import { fleetsAtPort, fleetsBoundFor, type ChartModel, type MapPort, type MapSelection } from '../../chart'
import { MapPanel } from './MapPanel'
import { SailHere } from './SailHere'

// PANEL TWO, BOTTOM-RIGHT — the detail of whatever is selected, and the ONE place you act from.
// DESIGN §E.5's "selected fleet detail", widened by one case: a port, when a port is what was
// tapped.
//
// ONE PANEL FOR BOTH, and one `MapSelection` behind it, deliberately. A second floating card for
// ports would be a third panel (§E.5 allows two), it would have to be positioned somewhere, and
// two selections could then disagree about what the player is looking at. So: one selection, one
// detail, in one corner. Nothing is ever drawn over the middle of the chart.
//
// EVERY NUMBER HERE IS THE SERVER'S. `sailed / total` is `voyage.position.nm_done` against
// `total_nm` — SAILED miles, so a passage that rounds a cape reads the distance it really is — and
// the countdown is `voyage.eta` against the shell clock. The map computes none of it.
//
// ── IT USED TO SAY "IT IS READ-ONLY, ALL OF IT" (deleted 2026-08-23) ───────────────────────────
// The paragraph that stood here read: *"There is no 'sail here', no 'set course', no button that
// starts an order half-composed. The panel ends with where orders actually come from."* Every word
// of it was true, and it was the defect — the owner's verdict on this tab was that a map you
// cannot act from is a picture, and the caption at the foot of the chart said so out loud.
//
// A selected PORT now carries exactly one action, `SailHere`. The distinction the old paragraph
// was reaching for survives whole, and it is the important half: **this panel still composes
// nothing.** It names one intent, asks the SERVER what that intent would do, prints the answer —
// including the refusal, when there is one — and hands the intent to the one composer. There is
// still no argument picker on this screen, no quantity control, and no legality check.

/** One label/value line — the panel is a tiny table and nothing more. */
function Line({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-2 py-0.5">
      <span className="shrink-0 font-mono text-[10px] text-ink-faint">{label}</span>
      <span className="min-w-0 truncate text-right font-mono text-[11px] text-ink">{value}</span>
    </div>
  )
}

export function DetailPanel({
  model,
  portsByCode,
  selection,
  nowMs,
  compact,
  acting,
  verbs,
  onSail,
  onDismiss,
}: {
  model: ChartModel
  /** The WHOLE port table: the selected fleet's destination may be well off the glass. */
  portsByCode: ReadonlyMap<string, MapPort>
  selection: MapSelection
  nowMs: number
  compact: boolean
  /** The hull an order from this panel belongs to. It is `domain/order`'s draft's `fleetId`,
   *  resolved against the served roster in MapScreen — this screen keeps NO second idea of which
   *  fleet is in hand. Null when the house has chosen none; the hand-off then carries none and
   *  Command asks. */
  acting: FleetView | null
  /** The server's own verb grammar (`world.snapshot().verbs`). Nothing here lists verbs. */
  verbs: readonly VerbSpec[]
  /** Hand a SAIL to the one composer and go to it. MapScreen owns the two lines, exactly as
   *  FleetsScreen, PortScreen and MarketScreen each do. */
  onSail: (fleetId: string | null, args: Record<string, string>) => void
  onDismiss: () => void
}) {
  if (!selection) return null

  const nameOf = (code: string) => portsByCode.get(code)?.name ?? code

  if (selection.kind === 'fleet') {
    const fleet = model.fleets.find((f) => f.fleet.id === selection.id)
    if (!fleet) return null

    return (
      <MapPanel
        slot="bottom-right"
        title="Fleet"
        compact={compact}
        onDismiss={onDismiss}
        storageKey="map.detail"
        testId="map-detail-panel"
      >
        <p className="mb-1 truncate font-serif text-sm text-ink">{fleet.fleet.name}</p>
        {fleet.dockedAtCode ? (
          <Line label="at" value={nameOf(fleet.dockedAtCode)} />
        ) : (
          fleet.leg && (
            <>
              <Line label="to" value={nameOf(fleet.leg.destinationCode)} />
              {/* The leg it is ON, which is the only one the server serves. When the voyage has
                  further legs to run, this is NOT the same as "to" — and saying both is the honest
                  way to show that without drawing water the chart was not given. */}
              {fleet.leg.toCode !== fleet.leg.destinationCode && (
                <Line label="this leg" value={`${nameOf(fleet.leg.fromCode)} → ${nameOf(fleet.leg.toCode)}`} />
              )}
              <Line
                label="sailed"
                value={`${formatInt(fleet.leg.sailedNm)} / ${formatNm(fleet.leg.totalNm)}`}
              />
              <Line label="arrives" value={formatRealShort(fleet.leg.etaMs - nowMs)} />
            </>
          )
        )}
      </MapPanel>
    )
  }

  const port = portsByCode.get(selection.code)
  if (!port) return null

  const here = fleetsAtPort(model, port.code)
  const bound = fleetsBoundFor(model, port.code)

  return (
    <MapPanel
      slot="bottom-right"
      title="Port"
      compact={compact}
      onDismiss={onDismiss}
      storageKey="map.detail"
      // A PORT CARRIES AN ACTION, so this panel is wider than the fleet's on a phone. The compact
      // default (`max-w-[55vw]`, ~214 px at 390) was sized for four short label/value lines; a
      // refusal is a SENTENCE the server wrote, and squeezing it into a 214 px column turns a
      // readable reason into a ragged tower that pushes the button toward the top of the glass.
      // The chart div clips at its own edge, so panel HEIGHT is the thing that has to stay bounded
      // — and width is what buys height back.
      widthClassName={compact ? 'w-[74vw] max-w-[74vw]' : 'w-56 max-w-[45vw]'}
      testId="map-detail-panel"
    >
      <p className="mb-1 truncate font-serif text-sm text-ink">{port.name}</p>
      <Line label="in" value={port.country} />
      <Line
        label="yours here"
        value={here.length > 0 ? here.map((f) => f.fleet.name).join(', ') : 'none'}
      />
      {bound.length > 0 && <Line label="on passage" value={bound.map((f) => f.fleet.name).join(', ')} />}

      {/* THE ONE ACT ON THIS SCREEN. It composes nothing — see this file's header and SailHere's. */}
      <SailHere
        fleet={acting}
        portCode={port.code}
        portName={port.name}
        verbs={verbs}
        onSail={onSail}
      />
    </MapPanel>
  )
}
