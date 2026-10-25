import { useState } from 'react'
import { Hint, SheetSection } from '../../../components/ui'
import { useGoodBoard } from '../../../live/useDesk'
import { useWorld } from '../../../live/worldStore'
import type { FleetView, GoodBoard } from '../../../lib/rpc'
import type { DeskLayout } from '../DeskFrame'
import { useDeskView } from '../deskView'
import { Queue } from '../Queue'
import { RouteFold } from '../RouteFold'
import { InsuredVoyages } from './InsuredVoyages'
import { useDeskPlan } from './planDraft'
import { SellList } from './SellList'
import { TradeCard } from './TradeCard'
import { TradeStart } from './TradeStart'
import { useT } from '../../../lib/i18n'

// TRADE — the one page the whole trip is made on (docs/COMMAND_REDESIGN.md §2, §5; owner rows 190 and 194,
// 2026-10-25: *"i can only plan on buying but not for selling"*, *"this game must be playable, yet it is hard to
// do so with just whats in the plan page"*). Three parts, one board read:
//
//   START   Hold (what is on board) or Here (what this port sells) → a good pressed opens the draft
//           (TradeStart.tsx). Under it, THE SELL LIST: every city the board serves for that good, each row its
//           own press — open rows first, shut rows last with a 1–2 word reason (SellList.tsx). "Where can I
//           sell X" is answered by pressing X; "sell what is in my hold" is Start = Hold.
//   CARD    one good, one buy city or the hold, one sell city, the days, the supplies the SAIL will buy, the
//           wages, the profit, and the ONE button, Go (TradeCard.tsx). The chart and the legs under it.
//   ORDERS  the standing route (0092) above the queue the Go filled, and the insured voyages (0213).
//
// THE BOARD IS READ ONCE, HERE, and handed to the list and the card: world.good_board for the picked good, FROM
// the chosen buy city FOR the asked amount (0171, 0188, 0221). Every figure on this page is served; nothing is
// added up on the client.
//
// THE DESK LAYS IT OUT (DeskFrame.tsx): on a wide glass Start and the sell list stand in the left pane, the card
// in the centre, the orders in the right. On a phone, one under the other in that order, the Go button at the
// card's foot. A press selects (COMMAND_DESK §3.5): a good or a row changes the card's figures in place; nothing
// above it collapses or moves.
//
// The face keeps its id `plans` (deskView.ts; the test id `desk-plans`); its label is Trade / 거래 (row 202).

export function Trade({ fleet, layout }: { fleet: FleetView; layout: DeskLayout }) {
  const t = useT()
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  const goodByCode = useWorld((s) => s.goodByCode)
  const portByCode = useWorld((s) => s.portByCode)
  const plan = useDeskPlan((s) => s.plan)
  const turnTo = useDeskView((s) => s.turnTo)
  const good = plan ? (goodByCode[plan.good] ?? null) : null
  const buyPort = plan?.buyAt ? (portByCode[plan.buyAt] ?? null) : null
  // THE UNITS THE BOARD PRICES: what the player typed, else — once a sell city is chosen — the units that fit beside
  // the stores that leg asks (the row's served `supplies.units_fit`, 0221), so a BUY never fills the room the casks
  // need. The first read prices the capacity; the row then names the fit and the board is asked again for it.
  const [units, setUnits] = useState<number | null>(null)
  const board = useGoodBoard(good?.id ?? null, fleet.id, fleet.version, plan?.buyAt ? (plan.units ?? units) : null, buyPort?.id ?? null)
  // THE LAST BOARD STANDS WHILE THE NEXT IS ASKED (a press selects; nothing above the card moves): a re-ask for other
  // units would otherwise empty the sell list for a beat and the card would jump. A new good or buy city starts clean.
  const heldKey = `${good?.id ?? ''}:${plan?.buyAt ?? ''}`
  const [held, setHeld] = useState<{ key: string; view: GoodBoard } | null>(null)
  if (board.view && (held?.view !== board.view || held.key !== heldKey)) setHeld({ key: heldKey, view: board.view })
  const b = board.view ?? (held?.key === heldKey ? held.view : null)
  const fit = plan?.buyAt && plan.units === null && plan.sellAt ? (b?.sell.find((r) => r.port === plan.sellAt)?.supplies?.units_fit ?? null) : null
  // derive-from-the-last-render (PlanVoyage.tsx's pattern): the row's fit hands the next read its units, in place
  if (fit !== null && fit > 0 && fit !== units) setUnits(fit)
  return layout({
    testid: 'desk-plans',
    order: ['list', 'main', 'side'],
    list: (
      <>
        <TradeStart fleet={fleet} plan={plan} />
        {plan && good && <SellList plan={plan} board={b} loading={board.loading && !b} />}
      </>
    ),
    main:
      plan && good ? (
        <TradeCard
          key={`${plan.good}:${plan.buyAt ?? ''}:${fleet.id}`}
          fleet={fleet}
          good={good}
          plan={plan}
          board={b}
          units={plan.units ?? units}
          onQueued={() => turnTo('plans')}
          onRoute={() => turnTo('plans')}
        />
      ) : (
        <Hint data-testid="trade-empty">{t('desk.planSide')}</Hint>
      ),
    side: (
      <div className="lg:h-full lg:min-h-0 lg:overflow-y-auto lg:px-4 lg:pb-6 lg:pt-3">
        {/* the standing route above the queue (0092, COMMAND_DESK §3.5: the one thing that writes orders by itself) */}
        <RouteFold fleet={fleet} />
        <SheetSection heading={t('desk.orders')} surface data-testid="command-queue">
          <Queue fleet={fleet} onCancel={(position) => cancel(fleet.id, position)} onClear={() => clearQueue(fleet.id)} />
        </SheetSection>
        {/* 0213: the insured voyages under way and what the insurance paid — only when there are any. */}
        <InsuredVoyages />
      </div>
    ),
  })
}
