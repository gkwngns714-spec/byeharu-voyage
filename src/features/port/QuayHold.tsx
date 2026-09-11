import { Bar, Figure } from '../../components/ui'
import { fleetHoldTotal, fleetHoldUsed } from '../../domain/fleet'
import { formatInt } from '../../lib/format'
import type { FleetView } from '../../lib/rpc'

// THE HOLD GAUGE ON THE BOARD — how full she is, and what the staged manifest would make her.
// docs/QUAY_LEDGER.md §3 A ("hold gauge with the staged tuns hatched") and C ("hold-after drawn
// back onto the top gauge"). Owner row 76, slice 2.
//
// Until 2026-09-11 the only hold gauge in the game was the fleet row on FLEETS (FleetsScreen.tsx);
// the board had none, so a player staging three buys had no picture of the room they were spending.
// This is that gauge, on the quay, composed from the same two folds FLEETS draws (`fleetHoldUsed`,
// `fleetHoldTotal`, domain/fleet) so the two cannot disagree about how full she is.
//
// IT IS A LINE UNDER THE STORES ROW, NOT A ROW OF ITS OWN — FleetsScreen's own composition (the
// bars ride on the fleet row's caption line). A 52px row for a 4px bar would have cost the board a
// whole good above the fold: tests/layout.spec.ts measures FIVE complete rows there (K.1), and a
// first cut of this file as a `Row` left four. PortTrade mounts it as the Stores row's second line.
//
// ── WHAT `staged` IS, AND IS NOT ───────────────────────────────────────────────────────────────
// `staged` is the SERVER's `hold.tuns_delta` from `cmd.preview_basket` (0083): what the hold would
// take on, bulk and stowage already applied by `public.fleet_free_hold` inside the dry run, negative
// when she would lighten. It arrives as a PROP because PortTrade asks the preview ONCE and the
// manifest tray reads the same answer — a second ask here would be a second estimate. Nothing on
// this side multiplies a quantity by a bulk; `used + staged` and `staged / total` are the same
// formatting arithmetic as `used / total`, drawn against a served delta. Null while no line is
// staged or the answer is on its way: the gauge then shows today, plainly.

export function QuayHold({
  fleet,
  staged,
}: {
  fleet: FleetView
  /** `estimate.hold.tuns_delta`, served — or null when there is no priced manifest. */
  staged: number | null
}) {
  const used = fleetHoldUsed(fleet)
  const total = fleetHoldTotal(fleet)
  const pct = total > 0 ? (used / total) * 100 : 0
  const pending = staged !== null && total > 0 ? (staged / total) * 100 : undefined
  const reading =
    staged !== null ? `${formatInt(used)} → ${formatInt(used + staged)} / ${formatInt(total)}` : `${formatInt(used)} / ${formatInt(total)}`
  return (
    <span className="mt-1 flex items-center gap-2" data-testid="quay-hold">
      <span className="text-t-caption text-ink-faint">Hold</span>
      <Bar
        pct={pct}
        pending={pending}
        tone={fleet.free_hold <= 0 ? 'warning' : 'accent'}
        label="hold"
        figure={<Figure value={reading} unit="t" />}
        className="min-w-0 flex-1"
      />
    </span>
  )
}
