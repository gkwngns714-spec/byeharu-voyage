import { useMemo, useState } from 'react'
import { Note, type TradePick } from '../../components/ui'
import { fleetCargoByCode, fleetPortCode } from '../../domain/fleet'
import type { FleetView, MarketGood, SnapshotPort } from '../../lib/rpc'
import { usePortHistory } from '../../live/usePortHistory'
import { useWorld } from '../../live/worldStore'
import { PriceTray } from './PriceTray'
import { QuayLedger } from './QuayLedger'

// THE LEDGER, READ-ONLY — a quay none of yours is lying at. docs/QUAY_LEDGER.md §3 A: *"the board
// opens on the quay a fleet lies at; elsewhere is read-only"*. This is the MARKET tab's one job
// (docs/OWNER_REQUESTS.md rows 64 and 70: read prices somewhere else) folded onto PORT on
// 2026-09-11 (row 76), where the same rows, the same field and the same harbour choice already
// stood — RESUME.md had measured the two screens drifting and named the fold as owed.
//
// THE SAME LEDGER AS THE QUAY THAT TRADES (QuayLedger.tsx). What a cell OPENS is the one
// difference: nobody is alongside, so there is no quantity to step and nothing to issue, and a
// press opens `PriceTray` — the prices, the trend, the range, the passage as a figure, the stock.
// No order is composed here and no SAIL is handed anywhere (that door is the MAP, rows 45/46).
//
// WHOSE HOLD the `aboard` caption and the sell cell read: the fleet PortScreen calls `acting` —
// the one her orders would run from — so a sell cell is live for what she is carrying and dead
// ("none aboard") for what she is not, on a distant quay as on her own. Folded ONCE, here.
//
// THE PASSAGE FIGURE only READS `reaches` for where she lies. The `world.reach` call is owned by
// the port field on the same sheet (PortField.tsx), which is always mounted and needs the same
// answer to order its chips; two callers on first paint were two round-trips for one figure
// (the store guards its cache, not a read in flight). Until that read lands there is no figure,
// and no Passage row — a truthful, lesser answer.

export function PortPrices({
  goods,
  port,
  reader,
}: {
  /** `world.market(port)`'s goods for THIS harbour — the read PortScreen already makes. */
  goods: readonly MarketGood[]
  /** The harbour being read. */
  port: SnapshotPort
  /** The fleet whose hold the ledger is read against, or null when the house has none. */
  reader: FleetView | null
}) {
  const portByCode = useWorld((s) => s.portByCode)
  const reaches = useWorld((s) => s.reaches)
  const [pick, setPick] = useState<TradePick | null>(null)
  const points = usePortHistory(port.id, pick?.good.code ?? null)

  // Where she lies (or is bound), and the sailed distance from there to this quay — a figure,
  // never a passage ordered here.
  const anchorCode = reader ? fleetPortCode(reader) : null
  const anchorPort = anchorCode ? (portByCode[anchorCode] ?? null) : null
  const passage =
    anchorPort && anchorCode !== port.code ? (reaches[anchorPort.id]?.reaches[port.code] ?? null) : null

  const aboard = useMemo(() => (reader ? fleetCargoByCode(reader) : {}), [reader])

  return (
    <>
      <QuayLedger
        goods={goods}
        aboard={aboard}
        pick={pick}
        onPick={(good, intent) => setPick({ good, intent })}
        empty={
          <Note tone="neutral" className="mt-3">
            Nothing is traded here.
          </Note>
        }
      />
      {pick && <PriceTray good={pick.good} points={points} passage={passage} onClose={() => setPick(null)} />}
    </>
  )
}
