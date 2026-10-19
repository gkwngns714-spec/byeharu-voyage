import type { ReactNode } from 'react'
import { Icon } from '../../../components/ui'
import { useWorld } from '../../../live/worldStore'
import type { FleetView, SnapshotGood } from '../../../lib/rpc'
import { DeskMainPane, DeskPanes, DeskSidePane } from '../DeskFrame'
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

  // THE DESK'S FRAME (DeskFrame.tsx): the same three panes every face stands in.
  return (
    <DeskPanes
      face="markets"
      testid="desk-terminal"
      list={<Markets fleet={fleet} selected={shown} market={market} />}
      main={null}
      panes={
        good ? (
          <GoodPanes
            key={`${good.code}:${fleet.id}`}
            fleet={fleet}
            good={good}
            cheapest={market.byCode[good.code]?.best?.port ?? null}
            slot={slot}
            onTrade={onTrade}
            onPlan={onPlan}
          />
        ) : (
          <>
            <DeskMainPane scroll={false}>
              <span className="flex flex-1 items-center justify-center text-t-body text-ink-faint">
                <Icon name="search" size={18} className="mr-2" /> No good matches the list.
              </span>
            </DeskMainPane>
            <DeskSidePane />
          </>
        )
      }
    />
  )
}

function GoodPanes({
  fleet,
  good,
  cheapest,
  slot,
  onTrade,
  onPlan,
}: {
  fleet: FleetView
  good: SnapshotGood
  /** The watchlist's cheapest seller (a port code): a city the chart is likely to follow, asked early. */
  cheapest: string | null
  slot: ReactNode
  onTrade: (code: string, intent: 'buy' | 'sell') => void
  onPlan: (plan: PlanDraft) => void
}) {
  const desk = useGoodDesk(fleet, good, cheapest)
  return (
    <>
      <DeskMainPane scroll={false}>
        <GoodChart good={good} desk={desk} fill />
      </DeskMainPane>
      <DeskSidePane>
        {slot ?? (
          <div className="bv-scroll h-full overflow-y-auto px-4 pb-6 pt-4" data-testid="good-page">
            <GoodTicket good={good} desk={desk} onTrade={(intent) => onTrade(good.code, intent)} onPlan={onPlan} />
          </div>
        )}
      </DeskSidePane>
    </>
  )
}
