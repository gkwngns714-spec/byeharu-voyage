import { useCallback } from 'react'
import { useCommandDraft } from '../../../domain/order'
import { useWorld } from '../../../live/worldStore'
import { openHq } from '../../../app/hqPlace'
import { litAway, useAwayReport } from '../../../live/useAwayReport'
import { assignOf, pressServed } from './servedPress'
import type { MoveData } from './useBoard'

// ONE PRESS, THE BUILDING'S OWN ACTION, IN PLACE (docs/design/hq-command-2026-11-23.md; 2026-11-24, simplify S1): a card never trades,
// orders or hires by itself. It puts the fleet in hand (the command draft's one selection) and opens, OVER HQ (hqPlace.ts `openHq`,
// HqSheet.tsx), the sheet of the place that already does it — HQ stays where it was, and nothing jumps to another tab:
//   trade    the trade sheet on that best sale (the same trip, at the same units);
//   request  that city's market on its Requests (its Fulfil);
//   yard     that city's building yard, that hull's sheet open (its Order);
//   crew     her city's inn (its Hire);
//   invest   the Invest sheet.

export function useMovePress(): (m: MoveData) => void {
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  // the one Assign sheet works where the standing jobs are lit (0481)
  const assignOpen = litAway(useAwayReport().view) !== null
  return useCallback(
    (m: MoveData) => {
      switch (m.kind) {
        case 'trade':
          selectFleet(m.fleet.id)
          openHq({ sheet: 'trade', port: m.at, fleet: m.fleet.id, good: m.sale.good, side: 'buy', best: m.sale })
          return
        case 'request':
          selectFleet(m.fleet.id)
          openHq({ sheet: 'requests', port: m.at, fleet: m.fleet.id })
          return
        case 'yard': {
          // her fleet lying at that yard; with no yard named, one lying anywhere, whose city's yard it is
          const here = useWorld.getState().fleets.find((f) => f.port !== null && f.voyage === null && (m.port === null || f.port === m.port))
          if (here) selectFleet(here.id)
          const port = m.port ?? here?.port ?? null
          if (port) openHq({ sheet: 'yard', port, hull: m.hull })
          return
        }
        case 'crew':
          selectFleet(m.fleet.id)
          if (m.fleet.port) openHq({ sheet: 'inn', port: m.fleet.port, fleet: m.fleet.id })
          return
        case 'invest':
          openHq({ sheet: 'invest' })
          return
        // 0480 (lit): the served card commits its own act, through the building's own door (servedPress.ts); HQ stays
        // A TRADE SHE BUYS FOR OPENS ASSIGN, FILLED IN (docs/design/hq-corp-2026-11-24.md C3): one press never commits it
        case 'served': {
          const a = assignOpen ? assignOf(m.move) : null
          if (a) {
            selectFleet(a.fleet)
            openHq({ sheet: 'assign', worker: a.fleet, good: a.good, buy: a.buy, sell: a.sell })
          } else void pressServed(m.move, m.fleet)
        }
      }
    },
    [selectFleet, assignOpen],
  )
}

/** A fleet row's press: her sheet over HQ (cargo, route, orders), her route first on `route`. */
export function useFleetPress(): (fleet: string, route: boolean) => void {
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  return useCallback(
    (fleet: string, route: boolean) => {
      selectFleet(fleet)
      openHq({ sheet: 'fleet', fleet, route })
    },
    [selectFleet],
  )
}
