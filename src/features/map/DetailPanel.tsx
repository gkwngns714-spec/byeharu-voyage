import { MapPanel } from './MapPanel'
import { fleetsAtPort, fleetsBoundFor, type ChartModel } from './chartModel'
import type { MapPort, MapSelection } from './mapTypes'
import { formatEta } from './voyage'

// PANEL TWO, BOTTOM-RIGHT — the detail of whatever is selected. DESIGN §E.5's "selected fleet
// detail", widened by one case: a port, when a port is what was tapped.
//
// ONE PANEL FOR BOTH, and one `MapSelection` behind it, deliberately. A second floating card for
// ports would be a third panel (§E.5 allows two), it would have to be positioned somewhere, and
// two selections could then disagree about what the player is looking at. So: one selection, one
// detail, in one corner. Nothing is ever drawn over the middle of the chart.
//
// It is READ-ONLY, all of it. There is no "sail here", no "set course", no button that starts an
// order half-composed. The panel ends with where orders actually come from.

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
  compact,
  onDismiss,
}: {
  model: ChartModel
  portsByCode: ReadonlyMap<string, MapPort>
  selection: MapSelection
  compact: boolean
  onDismiss: () => void
}) {
  if (!selection) return null

  if (selection.kind === 'fleet') {
    const fleet = model.fleets.find((f) => f.fleet.id === selection.id)
    if (!fleet) return null

    const destination = fleet.destinationCode
      ? (portsByCode.get(fleet.destinationCode)?.name ?? fleet.destinationCode)
      : null

    return (
      <MapPanel
        positionClassName="bottom-11 right-3"
        title="Fleet"
        compact={compact}
        onDismiss={onDismiss}
        storageKey="map.detail"
        testId="map-detail-panel"
      >
        <p className="mb-1 truncate font-serif text-sm text-ink">{fleet.fleet.name}</p>
        {fleet.dockedAtCode ? (
          <Line label="at" value={portsByCode.get(fleet.dockedAtCode)?.name ?? fleet.dockedAtCode} />
        ) : (
          <>
            <Line label="to" value={destination ?? '—'} />
            {fleet.progress && (
              <>
                <Line
                  label="sailed"
                  value={`${Math.round(fleet.progress.sailedNm)} / ${Math.round(fleet.progress.totalNm)} nm`}
                />
                <Line label="arrives" value={formatEta(fleet.progress.remainingMs)} />
              </>
            )}
          </>
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
      positionClassName="bottom-11 right-3"
      title="Port"
      compact={compact}
      onDismiss={onDismiss}
      storageKey="map.detail"
      testId="map-detail-panel"
    >
      <p className="mb-1 truncate font-serif text-sm text-ink">{port.name}</p>
      <Line label="in" value={port.country} />
      <Line
        label="yours here"
        value={here.length > 0 ? here.map((f) => f.fleet.name).join(', ') : 'none'}
      />
      {bound.length > 0 && <Line label="on passage" value={bound.map((f) => f.fleet.name).join(', ')} />}
    </MapPanel>
  )
}
