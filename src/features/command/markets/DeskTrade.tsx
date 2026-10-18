import { useMemo, useState } from 'react'
import { Note, TradeTray } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { usePortHistory } from '../../../live/usePortHistory'
import { usePortMarket } from '../../../live/usePortMarket'
import { useTrade } from '../../../live/useTrade'
import { useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'

// BUY OR SELL HERE, FROM THE DESK (docs/COMMAND_DESK.md §2.2, §3.3) — the good page's Buy / Sell cell
// for the city the fleet is docked at opens THE trade tray, the same one PORT's board opens: the
// ceiling, the stepper, the dry run and the one door (`useTrade` → cmd.issue). Nothing about the act is
// spelt here; this file only finds the market row (world.market, the read the quay makes) and the
// cargo the tray counts. The bargain thread and the basket stay on PORT's face until City (D5) moves
// them; the docked rule is the server's (a fleet at sea is never offered this cell).

export function DeskTrade({
  fleet,
  code,
  intent,
  onClose,
}: {
  fleet: FleetView
  code: string
  intent: 'buy' | 'sell'
  onClose: () => void
}) {
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const port = fleet.port ? (portByCode[fleet.port] ?? null) : null
  const quay = usePortMarket(port?.id ?? null)
  const good = useMemo(() => quay.market?.goods.find((g) => g.code === code) ?? null, [quay.market, code])
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])
  const history = usePortHistory(port?.id ?? '', good ? code : null)
  const [qty, setQty] = useState<number | null>(null)
  const trade = useTrade(fleet, intent, good, qty, onClose)

  if (!port) return null
  if (!good) {
    return quay.refusal ? (
      <Note tone="danger" className="mt-2">
        {quay.refusal.sentence}
      </Note>
    ) : null
  }
  return (
    <TradeTray
      pick={{ good, intent }}
      quay={{
        aboard: aboard[code] ?? 0,
        bulk: goodByCode[code]?.bulk ?? 1,
        culture: port.culture,
        history,
      }}
      trade={trade}
      qty={{ value: qty, onChange: setQty }}
      onClose={onClose}
    />
  )
}
