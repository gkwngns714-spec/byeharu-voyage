import { worldRouteBoard, type RouteBoard } from '../lib/rpc'
import { useServedRead } from './useServedRead'

// EVERY LANE THE WORLD SAILS (0106, owner row 115) — a doorway onto `useServedRead`, asked when
// ROUTES mounts and again on the world's beat while it is up, keeping its last answer meanwhile.
//
// NOT IN THE STORE, and deliberately: nothing else in the game needs this board, and a store field
// is a thing every screen pays to subscribe to. The subject is a constant because the board takes
// no argument — there is one board and it is the world's.
export function useRouteBoard(): { board: RouteBoard | null; loading: boolean } {
  const read = useServedRead<RouteBoard>('the-board', () => worldRouteBoard())
  return { board: read.view, loading: read.loading }
}
