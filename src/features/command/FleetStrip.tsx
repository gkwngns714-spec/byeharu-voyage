import { Bar, Figure } from '../../components/ui'
import { fleetHoldTotal, fleetHoldUsed } from '../../domain/fleet'
import { formatOfTotal, formatVoyageDays, tonsWord } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'
import { FleetPicker } from './FleetPicker'

// THE FLEET STRIP (docs/COMMAND_DESK.md §3.1, §2.1) — which fleet the desk acts for, and her two
// deciding figures. Every face reads the fleet named here; an act at a place is offered only for
// the city she is docked at (the server refuses otherwise — the strip only names her).
//
// 2026-10-20: the fleet is ONE button, the picker (FleetPicker.tsx) — her flag, name, signal dot
// and ▾, opening the list of your fleets — where it was a chip per fleet with her where line. A
// press SELECTS and moves nothing; where she is now reads on the picker's rows. The figures stand
// beside the picker on the wide header and under it on the phone, exactly as before.

export function FleetStrip({
  fleets,
  onSelect,
  fleet,
  inline = false,
}: {
  fleets: readonly FleetView[]
  onSelect: (id: string) => void
  fleet: FleetView | null
  /** The wide desk's header: the picker and the two figures on ONE line (docs/COMMAND_DESK.md §3.9). */
  inline?: boolean
}) {
  if (inline) {
    return (
      <div className="flex min-w-0 flex-1 items-center gap-6" data-testid="fleet-strip">
        <FleetPicker fleets={fleets} fleet={fleet} onSelect={onSelect} />
        {fleet && (
          <div className="flex shrink-0 items-center gap-6" data-testid="command-line">
            <span className="flex items-baseline gap-2">
              <span className="text-t-caption text-ink-faint">Supplies</span>
              <Figure value={formatVoyageDays(fleet.endurance_days)} />
            </span>
            <span className="flex items-center gap-2">
              <span className="text-t-caption text-ink-faint">Cargo</span>
              <Figure value={formatOfTotal(fleetHoldUsed(fleet), fleetHoldTotal(fleet))} unit={tonsWord(fleetHoldTotal(fleet))} />
              <Bar
                pct={fleetHoldTotal(fleet) > 0 ? (fleetHoldUsed(fleet) / fleetHoldTotal(fleet)) * 100 : 0}
                tone={fleet.free_hold <= 0 ? 'warning' : 'accent'}
                label={`cargo, ${formatOfTotal(fleetHoldUsed(fleet), fleetHoldTotal(fleet))} ${tonsWord(fleetHoldTotal(fleet))}`}
                className="w-24"
              />
            </span>
          </div>
        )}
      </div>
    )
  }
  return (
    <div data-testid="fleet-strip">
      {/* The picker's own 16px of padding is pulled back to the gutter, so her name starts where the
          chips used to. One row of the 44 floor; the figures' 52 follow it. */}
      <div className="-ml-4 flex min-h-11 items-center">
        <FleetPicker fleets={fleets} fleet={fleet} onSelect={onSelect} />
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
