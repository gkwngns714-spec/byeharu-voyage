import { useMemo } from 'react'
import { SheetSection } from '../../components/ui'
import { MerchantRow } from '../../live/MerchantRow'
import { restEndsAt } from '../../live/merchantWords'
import type { PortMerchant } from '../../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// IN PORT — the merchants lying in the tapped city, soonest to sail first (owner, 2026-10-13)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// *"when i press city, it says how many ships are resting. i want there to be a list, showing the
// total level, and its current time till the resting finishes."*
//
// A resting merchant is no longer drawn on the chart (chartModel.ts, the same day), so the city's
// tray is the ONE place she shows on the map. The rows are the harbour's own read
// (`world.port_merchants`, the same answer PORT lists), filtered to the ones LYING here — never the
// capped sea window, which drops exactly the merchants at anchor. The row is `src/live/MerchantRow`,
// the same one PORT prints, so the two cannot drift.
//
// SOONEST FIRST. The server ranks the harbour's list by what each merchant is doing (0104), which
// is the right order for a list of everyone the harbour concerns; for a list of who is lying here
// the owner's question is "when does she sail", so this view orders by the instant her rest ends,
// and the ones with no instant — laid up, or free to sail on the next tick — after them, in the
// server's own order among themselves. A sort is a VIEW; no figure is changed by it.
export function RestingHere({
  rows,
  nowMs,
  onOpen,
}: {
  /** The merchants LYING in the city — the harbour's read, already filtered to `port === city` by
   *  MapScreen, which is the one place that knows which city was tapped. */
  rows: readonly PortMerchant[]
  nowMs: number
  onOpen: (fleetId: string) => void
}) {
  const here = useMemo(() => {
    const withEnd = rows.map((m, i) => ({ m, i, ends: restEndsAt(m) }))
    withEnd.sort((a, b) => {
      if (a.ends !== null && b.ends !== null) return a.ends - b.ends || a.i - b.i
      if (a.ends !== null) return -1
      if (b.ends !== null) return 1
      return a.i - b.i
    })
    return withEnd.map((x) => x.m)
  }, [rows])

  if (here.length === 0) return null
  return (
    <SheetSection heading="In port" surface data-testid="map-resting">
      {here.map((m, i) => (
        <MerchantRow key={m.id} m={m} here nowMs={nowMs} onOpen={onOpen} hairline={i < here.length - 1} />
      ))}
    </SheetSection>
  )
}
