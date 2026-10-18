import { useState } from 'react'
import { RarityMark, Tray, type TrayDetent } from '../../../components/ui'
import type { FleetView, SnapshotGood } from '../../../lib/rpc'
import { useDeskGood } from '../../../store/deskGood'
import type { PlanDraft } from '../plans/planDraft'
import { GoodChart } from './GoodChart'
import { GoodTicket } from './GoodTicket'
import { useGoodDesk } from './useGoodDesk'

// ONE GOOD, EVERY CITY — ON A PHONE (docs/COMMAND_DESK.md §3.3, §3.9). The good's page is a tray that
// opens at full: the chart first, then the ticket (Best trade, Buy at, Sell at). On a wide glass the
// same two halves stand as the desk's centre and right panes instead (Terminal.tsx); both read the
// good once through `useGoodDesk`.

export function GoodPage({
  fleet,
  good,
  onTrade,
  onPlan,
}: {
  fleet: FleetView
  good: SnapshotGood
  /** The docked city's Buy / Sell: the desk opens the trade tray in this slot. */
  onTrade: (intent: 'buy' | 'sell') => void
  /** A Plan: the desk opens the plan builder in this slot. */
  onPlan: (plan: PlanDraft) => void
}) {
  const close = useDeskGood((s) => s.close)
  const [detent, setDetent] = useState<TrayDetent>('full')
  const desk = useGoodDesk(fleet, good)
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? close() : setDetent(next))}
      title={
        <span className="flex items-center gap-2">
          {good.name} <RarityMark rarity={good.rarity} />
        </span>
      }
      data-testid="good-page"
    >
      <GoodChart good={good} desk={desk} showName={false} />
      <div className="mt-4">
        <GoodTicket good={good} desk={desk} onTrade={onTrade} onPlan={onPlan} />
      </div>
    </Tray>
  )
}
