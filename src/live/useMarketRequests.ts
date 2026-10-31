// THE MARKET'S REQUESTS AT ONE PORT — `world.requests(port)` (0288), read on the world's beat.
//
// One subject — the port — on `useServedRead`: the caller's own open requests there, and the
// server's `home` flag (the same reading cmd.request_place enforces). The Market face draws the
// Request door only when `home` is true; the server refuses anywhere else regardless, so the door
// is a courtesy and the gate is the truth.

import { worldRequests } from '../lib/rpc'
import type { PortRequests } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

export function useMarketRequests(portId: string | null): ServedRead<PortRequests> {
  return useServedRead<PortRequests>(portId, () => worldRequests(portId as string), { name: 'worldRequests' })
}
