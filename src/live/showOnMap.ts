import { useNavigate } from 'react-router-dom'
import { goTo, useGoTo } from '../chart'

/** SHOW A HARBOUR ON THE MAP, its tray up when asked: a view change, not an order (it composes nothing).
 *  The chart is asked through its one entrance (chart/goTo.ts); outside the shell no tab answers the request, so the route does.
 *  A COMMAND face that points at a harbour (the goal card, finding 21) asks through here: COMMAND imports no chart
 *  (tests/verbHomes.spec.ts). */
export function useShowOnMap(): (code: string, open?: boolean) => void {
  const navigate = useNavigate()
  return (code, open = false) => {
    goTo({ kind: 'port', code, open })
    if (!useGoTo.getState().openMap) navigate('/map')
  }
}
