import type { ReactNode } from 'react'
import { Icon } from '../../../components/ui'
import { useWorld } from '../../../live/worldStore'
import type { FleetView, SnapshotGood } from '../../../lib/rpc'
import type { PlanDraft } from '../plans/planDraft'
import { GoodChart } from './GoodChart'
import { GoodTicket } from './GoodTicket'
import { Markets } from './Markets'
import { useMarketRows } from './marketRows'
import { useGoodDesk } from './useGoodDesk'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TRADING TERMINAL — the Markets face on a wide glass (docs/COMMAND_DESK.md §3.9, 2026-10-18)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, on his own screen (DPR 2, 1440×731): *"wtf what about the command tab?"* — the desk was a
// phone list in a 750-px column with half the glass empty until a good was pressed. A trading screen
// (a broker's watchlist + chart + order ticket, TradingView / Bloomberg) uses the whole glass:
//
//   ┌ WATCHLIST ─────┬ CHART ─────────────────────────────────┬ TICKET ─────────────┐
//   │ search, chips  │ good · city · price · move · stock     │ BEST TRADE          │
//   │ rows: mark,    │ city chips (flags)        1h 6h 12h    │  buy A · sell B     │
//   │ name, stock,   │ ┌────────────────────────────────────┐ │  net / t · net hold │
//   │ spark, price,  │ │ record ─── estimate ┄┄ band ░ ◆    │ │  days · arrive·best │
//   │ move           │ │ stock ▁▂▃ (normal ┄)               │ │  [Buy here][Plan]   │
//   │                │ └────────────────────────────────────┘ │ BUY AT  ladder      │
//   │                │ ◆ best time · likely range             │ SELL AT ladder      │
//   └────────────────┴────────────────────────────────────────┴─────────────────────┘
//
// EACH PANE IS ITS OWN SCROLL (thin bars, `.bv-scroll`), so the Best trade card is above the fold at
// 731 px and stays there while the watchlist is read. A PRESS SELECTS: a row opens its good in the
// centre and right panes, which change in place; the list does not move. The ticket pane is THE SLOT:
// the plan builder or the trade tray stand in it (Tray mode="pane") and closing them gives the ticket
// back. Nothing is chosen yet → the list's first row is shown (never an empty half of the glass).

export function Terminal({
  fleet,
  code,
  slot,
  onTrade,
  onPlan,
}: {
  fleet: FleetView
  /** The good open on the desk, or null for "the list's first". */
  code: string | null
  /** The plan builder or the trade tray, when one stands in the ticket pane. */
  slot: ReactNode
  onTrade: (code: string, intent: 'buy' | 'sell') => void
  onPlan: (plan: PlanDraft) => void
}) {
  const goodByCode = useWorld((s) => s.goodByCode)
  const market = useMarketRows(fleet)
  const { rows } = market
  const shown = code ?? rows[0]?.code ?? null
  const good = shown ? (goodByCode[shown] ?? null) : null

  return (
    <div
      className="grid min-h-0 flex-1 grid-cols-[minmax(17rem,22rem)_minmax(0,1fr)_minmax(20rem,25rem)]"
      data-testid="desk-terminal"
    >
      <section className="bv-scroll min-h-0 overflow-y-auto border-r border-edge px-4 pb-6 pt-3" data-testid="desk-pane-list">
        <Markets fleet={fleet} selected={shown} market={market} />
      </section>
      {good ? (
        <GoodPanes key={`${good.code}:${fleet.id}`} fleet={fleet} good={good} slot={slot} onTrade={onTrade} onPlan={onPlan} />
      ) : (
        <>
          <section className="flex min-h-0 items-center justify-center text-t-body text-ink-faint" data-testid="desk-pane-chart">
            <Icon name="search" size={18} className="mr-2" /> No good matches the list.
          </section>
          <section className="min-h-0 border-l border-edge" data-testid="desk-pane-ticket" />
        </>
      )}
    </div>
  )
}

function GoodPanes({
  fleet,
  good,
  slot,
  onTrade,
  onPlan,
}: {
  fleet: FleetView
  good: SnapshotGood
  slot: ReactNode
  onTrade: (code: string, intent: 'buy' | 'sell') => void
  onPlan: (plan: PlanDraft) => void
}) {
  const desk = useGoodDesk(fleet, good)
  return (
    <>
      <section className="flex min-h-0 flex-col px-6 pb-3 pt-4" data-testid="desk-pane-chart">
        <GoodChart good={good} desk={desk} fill />
      </section>
      <section className="min-h-0 border-l border-edge bg-surface" data-testid="desk-pane-ticket">
        {slot ?? (
          <div className="bv-scroll h-full overflow-y-auto px-4 pb-6 pt-4" data-testid="good-page">
            <GoodTicket good={good} desk={desk} onTrade={(intent) => onTrade(good.code, intent)} onPlan={onPlan} />
          </div>
        )}
      </section>
    </>
  )
}
