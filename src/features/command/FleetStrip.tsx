import { Bar, Chip, Figure } from '../../components/ui'
import { fleetHoldTotal, fleetHoldUsed, fleetPortCode, whereabouts, whereLine } from '../../domain/fleet'
import { PortFlag } from '../../live/PortFlag'
import { portNameOf, useWorld } from '../../live/worldStore'
import { formatOfTotal, formatVoyageDays, tonsWord } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'

// THE FLEET STRIP (docs/COMMAND_DESK.md §3.1, §2.1) — which fleet the desk acts for, where it is, and
// its two deciding figures. Every face reads the fleet named here; an act at a place is offered only
// for the city it is docked at (the server refuses otherwise — the strip only says where it is).
//
// Fleet chips scroll sideways; pressing one SELECTS it and moves nothing. The where line is
// domain/fleet's one rule (`whereabouts` / `whereLine`).

export function FleetStrip({
  fleets,
  fleetId,
  onSelect,
  fleet,
}: {
  fleets: readonly FleetView[]
  fleetId: string | null
  onSelect: (id: string) => void
  fleet: FleetView | null
}) {
  const portByCode = useWorld((s) => s.portByCode)
  return (
    <div data-testid="fleet-strip">
      <div className="-mx-gutter flex gap-2 overflow-x-auto px-gutter pb-1">
        {fleets.map((f) => (
          <Chip key={f.id} on={f.id === fleetId} onClick={() => onSelect(f.id)} className="shrink-0 whitespace-nowrap">
            {fleetPortCode(f) && <PortFlag code={fleetPortCode(f) as string} />}
            {f.name} · {whereLine(whereabouts(f), (c) => portNameOf(portByCode, c))}
          </Chip>
        ))}
      </div>
      {fleet && <FleetFigures fleet={fleet} />}
    </div>
  )
}

/** The fleet's two deciding figures, side by side — a caption over each, the cargo share drawn as a
 *  bar beside its figure (warning once the served free hold is gone).
 *
 *  EXACTLY THE ROW'S 52px, ON THE SHEET, NOT ON A PANEL. A first cut seated these on a `surface`
 *  panel with the figures at `t-figure` over a bar: 56px taller, and that was enough to push the
 *  route editor's port chips out of the glass, so a press there scrolled the sheet and the stops
 *  under the finger moved (tests/route.stopface.spec.ts, owner row 15). Caption 16 + figure 28 +
 *  8 of padding is the 52 the sentence stood in, so nothing below it moved by one pixel. */
function FleetFigures({ fleet }: { fleet: FleetView }) {
  const used = fleetHoldUsed(fleet)
  const total = fleetHoldTotal(fleet)
  return (
    <div className="grid min-h-row grid-cols-2 gap-4 py-1" data-testid="command-line">
      <div>
        <span className="block text-t-caption text-ink-faint">Supplies</span>
        <Figure value={formatVoyageDays(fleet.endurance_days)} size="figure" />
      </div>
      <div className="min-w-0">
        <span className="block text-t-caption text-ink-faint">Cargo</span>
        <span className="flex items-center gap-2">
          <Figure value={formatOfTotal(used, total)} unit={tonsWord(total)} size="figure" />
          <Bar
            pct={total > 0 ? (used / total) * 100 : 0}
            tone={fleet.free_hold <= 0 ? 'warning' : 'accent'}
            label={`cargo, ${formatOfTotal(used, total)} ${tonsWord(total)}`}
            className="min-w-0 flex-1"
          />
        </span>
      </div>
    </div>
  )
}
