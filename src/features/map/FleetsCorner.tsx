import { Corner, Icon, Row } from '../../components/ui'
import { CHART_CHROME, type ChartModel, type MapPort } from '../../chart'
import { fleetLine } from './fleetLine'

// THE FLEETS PILL, TOP-LEFT — `⛵ 1`, and a list when it is pressed.
//
// docs/UI_DIRECTION.md §6, MAP: "Fold: the Fleets panel to a pill `⛵ 1` that opens a `Corner`
// list." The old panel was a `MapPanel` — `OverlayPanel` + `Collapsible` + an absolutely-placed
// close button over the fold's header — with a `compact` flag deciding whether it opened by
// default. A `Corner` is the primitive that shape was reaching for: a 44px pill that says what is
// inside it, a fold chevron, glass over the sea, and it never closes, so it can never be lost.
//
// One row per fleet: her name and `fleetLine` — the port she lies in, or where she is going and
// when. No tonnage, no cargo, no condition: those are the Fleets tab's job, and a map that starts
// answering them stops being a map. Pressing a row SELECTS (DESIGN §E.5 says so in as many words);
// the screen also brings the chart to her, which is a view change and nothing else.
//
// `CHART_CHROME` is spread onto the corner for the two jobs it always does: a press here never
// pans the chart, and `useChromeBoxes` measures the box into `keepOut`, so no harbour's name is
// printed under the pill.
export function FleetsCorner({
  model,
  portsByCode,
  selectedId,
  nowMs,
  onSelect,
}: {
  model: ChartModel
  /** The WHOLE port table: a fleet bound for a port off the glass still has to be able to name it. */
  portsByCode: ReadonlyMap<string, MapPort>
  selectedId: string | null
  nowMs: number
  onSelect: (id: string) => void
}) {
  const fleets = model.fleets
  return (
    <Corner
      slot="top-left"
      mark={<Icon name="ship" size={20} className="text-accent" />}
      label={String(fleets.length)}
      className="pointer-events-auto"
      data-testid="map-fleets-corner"
      {...CHART_CHROME}
    >
      {fleets.length === 0 ? (
        <Row tone="muted" hairline={false} label="None at sea or in port." />
      ) : (
        fleets.map((f, i) => (
          <Row
            key={f.fleet.id}
            mark={
              <Icon
                name={f.dockedAtCode ? 'anchor' : 'ship'}
                size={20}
                className={selectedId === f.fleet.id ? 'text-accent' : 'text-ink-faint'}
              />
            }
            label={f.fleet.name}
            tone={selectedId === f.fleet.id ? 'accent' : 'default'}
            hairline={i < fleets.length - 1}
            onClick={() => onSelect(f.fleet.id)}
            data-testid="map-fleet-row"
          >
            <span className="block text-t-caption text-ink-faint">{fleetLine(f, portsByCode, nowMs)}</span>
          </Row>
        ))
      )}
    </Corner>
  )
}
