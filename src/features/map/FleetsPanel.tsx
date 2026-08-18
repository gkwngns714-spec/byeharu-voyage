import { MapPanel } from './MapPanel'
import type { ChartModel, FleetOnChart } from './chartModel'
import type { MapPort, MapSelection } from './mapTypes'
import { formatEta } from './voyage'

// PANEL ONE, TOP-LEFT — what you have, and where it is. DESIGN §E.5's fleet list.
//
// One line per fleet: its name, and either the port it lies in or where it is going and when it
// gets there. No tonnage, no cargo, no condition — those are the Fleets tab's job, and a map that
// starts answering them stops being a map.
//
// Tapping a row SELECTS. That is a view change (§E.5 says so in as many words), and the only thing
// it changes is what the other panel reads.

function statusOf(f: FleetOnChart, portsByCode: ReadonlyMap<string, MapPort>): string {
  if (f.dockedAtCode) return portsByCode.get(f.dockedAtCode)?.name ?? f.dockedAtCode
  const destination = f.destinationCode ? (portsByCode.get(f.destinationCode)?.name ?? f.destinationCode) : '—'
  return `→ ${destination} · ${f.progress ? formatEta(f.progress.remainingMs) : '—'}`
}

export function FleetsPanel({
  model,
  portsByCode,
  selection,
  compact,
  onSelect,
}: {
  model: ChartModel
  portsByCode: ReadonlyMap<string, MapPort>
  selection: MapSelection
  /** Phone-sized surface — see COMPACT_WIDTH_PX and `defaultOpen` below. */
  compact: boolean
  onSelect: (id: string) => void
}) {
  const selectedId = selection?.kind === 'fleet' ? selection.id : null

  return (
    <MapPanel
      positionClassName="left-3 top-3"
      title="Fleets"
      aside={model.fleets.length}
      storageKey="map.fleets"
      testId="map-fleets-panel"
      compact={compact}
      // DEFECT 3, MEASURED: open by default at 390x844 this panel filled y 0-505 of 844 - 60% of
      // the chart, from a component whose whole brief is "corner panel". On a phone it therefore
      // starts FOLDED, as the header chip "FLEETS 4", and one tap opens it. Desktop is unchanged:
      // at 1280 the same panel is a quarter of the width and reads perfectly open.
      // (A player who folds or opens it themselves is remembered by `storageKey`, at both sizes.)
      defaultOpen={!compact}
      // The ONE capped region on this panel, and it holds information only — the fold control that
      // could otherwise be scrolled out of reach lives outside it (see MapPanel, the reach law).
      bodyClassName="max-h-44 overflow-y-auto"
    >
      {model.fleets.length === 0 ? (
        <p className="px-1 py-2 font-mono text-[10px] text-ink-faint">None at sea or in port.</p>
      ) : (
        <ul>
          {model.fleets.map((f) => {
            const selected = selectedId === f.fleet.id
            return (
              <li key={f.fleet.id}>
                <button
                  type="button"
                  onClick={() => onSelect(f.fleet.id)}
                  aria-pressed={selected}
                  className={`flex min-h-11 w-full items-center gap-2 rounded px-1 text-left transition ${
                    selected ? 'bg-accent-soft' : 'hover:bg-surface-2'
                  }`}
                >
                  {/* The glyph, repeated at label size so the list and the chart read as one thing:
                      a filled mark for a fleet at anchor, a dot for one at sea. */}
                  <span
                    aria-hidden="true"
                    className={`shrink-0 font-mono text-[10px] ${selected ? 'text-ink' : 'text-accent'}`}
                  >
                    {f.dockedAtCode ? '▲' : '•'}
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate font-mono text-[11px] text-ink">{f.fleet.name}</span>
                    <span className="block truncate font-mono text-[10px] text-ink-faint">
                      {statusOf(f, portsByCode)}
                    </span>
                  </span>
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </MapPanel>
  )
}
