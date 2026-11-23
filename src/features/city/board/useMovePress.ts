import { useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { useCommandDraft } from '../../../domain/order'
import { yardHref } from '../../../live/cityFaces'
import { useWorld } from '../../../live/worldStore'
import { useDeskGood } from '../../../store/deskGood'
import { useDeskHandoff } from '../../../store/deskHandoff'
import { pressServed } from './servedPress'
import type { MoveData } from './useBoard'

// ONE PRESS, THE BUILDING'S OWN ACTION (docs/design/hq-command-2026-11-23.md): a card never trades, orders or hires by itself. It puts
// the fleet in hand (the command draft's one selection) and hands its ask to the place that already does it:
//   trade    the Trade desk presses that best sale (store/deskHandoff.ts → Trade.tsx's `pressBest`): the same trip, at the same units;
//   request  the Office's City face, on the market, where her fleet lies (its Requests and Fulfil);
//   yard     the Office's City face, on the build yard, that hull's sheet open (its Order), or HQ's port where the yard stands;
//   crew     the Office's City face, on the inn (its Hire);
//   invest   the Office's Invest face.

export function useMovePress(): (m: MoveData) => void {
  const navigate = useNavigate()
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  return useCallback(
    (m: MoveData) => {
      switch (m.kind) {
        case 'trade':
          selectFleet(m.fleet.id)
          useDeskGood.getState().setFocus(null)
          useDeskHandoff.getState().giveBest({ fleet: m.fleet.id, at: m.at, sale: m.sale })
          navigate('/command')
          return
        case 'request':
          selectFleet(m.fleet.id)
          navigate('/office?face=city&building=market')
          return
        case 'yard': {
          const here = useWorld.getState().fleets.find((f) => f.port === m.port && f.voyage === null)
          if (here) {
            selectFleet(here.id)
            navigate(`/office?face=city&building=building_yard&hull=${encodeURIComponent(m.hull)}`)
          } else navigate(yardHref(m.port))
          return
        }
        case 'crew':
          selectFleet(m.fleet.id)
          navigate('/office?face=city&building=inn')
          return
        case 'invest':
          navigate('/office?face=invest')
          return
        // 0480 (lit): the served card commits its own act, through the building's own door (servedPress.ts); HQ stays
        case 'served':
          void pressServed(m.move, m.fleet)
      }
    },
    [navigate, selectFleet],
  )
}

/** A fleet's route page on the desk (RouteFold's own), or the desk with her in hand. */
export function useFleetPress(): (fleet: string, route: boolean) => void {
  const navigate = useNavigate()
  const selectFleet = useCommandDraft((s) => s.selectFleet)
  return useCallback(
    (fleet: string, route: boolean) => {
      selectFleet(fleet)
      if (route) useDeskHandoff.getState().giveRoute(fleet)
      navigate('/command')
    },
    [navigate, selectFleet],
  )
}
