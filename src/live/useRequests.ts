// THE REQUEST BOARD OF ONE HARBOUR — `world.contracts(port)` (0087), read on the world's beat.
//
// A request is a fact about a PORT: what it asks for, how much, by when, at what premium. The
// read takes a port and nothing about a fleet — what a fleet carries is on `world.fleets`, and the
// screen folds it once (`fleetCargoByCode`). Reading it is also what WINDS the board where nothing
// else has (0087: the read is the catch-up, 0026/0028/0029's idiom), so a face that shows requests
// is the thing that makes them exist on that port — the draw is pure in (port, day, secret), so a
// board wound late is the same board.
//
// ONE subject — the port — on `useServedRead`: a re-read keeps the last board on screen and marks
// it `loading`; another port shows nothing of this one's. A refusal clears it (there is nothing to
// draw), which is the read family's rule.

import { worldContracts } from '../lib/rpc'
import type { RequestBoard } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

export function useRequests(portId: string | null): ServedRead<RequestBoard> {
  return useServedRead<RequestBoard>(portId, () => worldContracts(portId as string))
}
