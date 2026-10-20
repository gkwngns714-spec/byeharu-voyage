import { SheetSection } from '../../../components/ui'
import { useWorld } from '../../../live/worldStore'
import type { FleetView } from '../../../lib/rpc'
import type { DeskLayout } from '../DeskFrame'
import { useDeskView } from '../deskView'
import { Queue } from '../Queue'
import { RouteFold } from '../RouteFold'
import { InsuredVoyages } from './InsuredVoyages'
import { PlanBuilder } from './PlanBuilder'
import { useDeskPlan } from './planDraft'

// PLANS — the fleet's plan, its route and its orders (docs/COMMAND_DESK.md §3.5): the standing route
// (0092; it folds in place), the queue with its ✕ and Clear (busy only while their own press is on the
// wire — Queue.tsx wears the one `usePress`), and the plan builder when a draft exists.
//
// THE DESK LAYS IT OUT (DeskFrame.tsx, 2026-10-19): on a wide glass the orders stand in the left pane
// (a list, as the watchlist is), the route in the centre, and the plan builder in the right — the
// ticket pane, where it stands on Markets too. On a phone: Plan, Route, Orders, one under the other, the
// builder in flow (never a tray over the screen).

export function Plans({ fleet, layout }: { fleet: FleetView; layout: DeskLayout }) {
  const readAt = useWorld((s) => s.readAt)
  const cancel = useWorld((s) => s.cancel)
  const clearQueue = useWorld((s) => s.clear)
  const goodByCode = useWorld((s) => s.goodByCode)
  const plan = useDeskPlan((s) => s.plan)
  const turnTo = useDeskView((s) => s.turnTo)
  const good = plan ? (goodByCode[plan.good] ?? null) : null
  return layout({
    testid: 'desk-plans',
    order: ['side', 'main', 'list'],
    list: (
      <>
        <SheetSection heading="Orders" surface data-testid="command-queue">
          <Queue
            fleet={fleet}
            readAt={readAt}
            onCancel={(position) => cancel(fleet.id, position)}
            onClear={() => clearQueue(fleet.id)}
          />
        </SheetSection>
        {/* 0212: the insured voyages under way and what the insurance paid — only when there are any. */}
        <InsuredVoyages />
      </>
    ),
    main: <RouteFold fleet={fleet} />,
    side:
      plan && good ? (
        <PlanBuilder
          key={`${plan.good}:${fleet.id}`}
          mode="pane"
          fleet={fleet}
          good={good}
          plan={plan}
          onQueued={() => turnTo('plans')}
          onRoute={() => turnTo('plans')}
        />
      ) : null,
    sideHint: 'No plan open. On Markets, press Plan on a good to plan a buy and a sell; it stands here.',
  })
}
