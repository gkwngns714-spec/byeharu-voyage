// RE-ASK AT THE EDGE, NEVER RE-REASON — the hook form of the idiom PortFair.tsx proved by hand.
//
// A payload carries served instants: a fair's `ends_at`, the market clock's `next_change_at`
// (0029). When THE ONE CLOCK crosses one, the payload in hand has stopped being true — and the
// answer is to ask the SERVER again, never to flip a flag or step a price on this side. For the
// market this is load-bearing twice over: the re-ask is itself what winds the drift where pg_cron
// is absent (0029's wind), so a client that "saved a round trip" by assuming would be looking at
// prices the server never moved.
//
// TERMINATION is the part that must not be hand-rolled per screen, because it is the part that
// was subtle: the effect fires only while the payload's OWN timestamp (`payloadAtMs`, its served
// `now`) is still before the edge. After the re-ask lands, the fresh payload's `now` is past that
// edge, so one edge cannot fire twice — and a server that is somehow stale cannot cause a hot
// loop of requests. (PortFair.tsx:80-90 is the original; it should fold onto this hook when that
// file is next open for edits.)
//
// In its own file because the react-refresh rule forbids exporting hooks from a component file
// (app/shellState.ts records the same constraint).

import { useEffect } from 'react'

/**
 * Call `reask` once when `nowMs` crosses `edgeMs`, judged against the payload's own timestamp.
 *
 * @param edgeMs      The served instant to watch (Date.parse of e.g. `clock.next_change_at`),
 *                    or null while there is no payload.
 * @param payloadAtMs The payload's own served `now` (Date.parse of e.g. `clock.now`), or null.
 * @param nowMs       THE ONE CLOCK, from `useShellState()`.
 * @param reask       The screen's reload for that payload (e.g. `() => void loadMarket(portId)`).
 */
export function useReaskAtEdge(
  edgeMs: number | null,
  payloadAtMs: number | null,
  nowMs: number,
  reask: () => void,
): void {
  const due = edgeMs !== null && payloadAtMs !== null && nowMs >= edgeMs && payloadAtMs < edgeMs
  useEffect(() => {
    if (due) reask()
  }, [due, reask])
}
