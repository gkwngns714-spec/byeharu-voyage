// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COMMAND DESK'S THREE READS (docs/COMMAND_DESK.md §5.8, §7.6) — asked when the desk opens a good
// or the list, and again at the MARKET'S EDGE (the served clock.next_change_at), never on the beat.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// They ride `useServedRead` (one subject, the last answer kept while the next is on the wire — a re-ask
// never blanks the figures), with its `trigger` moved by `useReaskAtEdge` (the edge idiom's one home)
// instead of the world's 3-s beat: world.good_board costs ~0.3–0.5 s on prod (0171's dev-log), and a
// price moves only at the edge. A change the player makes — a trade, a fleet chosen, an amount — is a
// new QUESTION, so it is asked at once and the old figures stand, `stale`, until it lands.

import { useCallback, useState } from 'react'
import { useReaskAtEdge } from '../components/ui'
import { useShellState } from '../app/shellState'
import { worldGoodBoard, worldPriceOutlook, worldWatchlist } from '../lib/rpc'
import type { GoodBoard, PriceOutlook, RpcResult, Watchlist } from '../lib/rpc'
import { useServedRead, type ServedRead } from './useServedRead'

/** A served read with a clock, re-asked when its own edge passes. */
function useEdgeRead<V extends { clock: { now: string; next_change_at: string } }>(
  subject: string | null,
  ask: () => Promise<RpcResult<V>>,
  question: string | null = subject,
): ServedRead<V> {
  const { nowMs } = useShellState()
  const [edges, setEdges] = useState(0)
  const read = useServedRead<V>(subject, ask, { question, trigger: edges })
  const edgeMs = read.view ? Date.parse(read.view.clock.next_change_at) : null
  const atMs = read.view ? Date.parse(read.view.clock.now) : null
  useReaskAtEdge(
    edgeMs,
    atMs,
    nowMs,
    useCallback(() => setEdges((n) => n + 1), []),
  )
  return read
}

/** Every good once (world.watchlist) — what the fleet carries rides the question. */
export function useWatchlist(fleetId: string | null, fleetVersion: number | null): ServedRead<Watchlist> {
  return useEdgeRead<Watchlist>('watchlist', () => worldWatchlist(fleetId), `${fleetId ?? '-'}:${fleetVersion ?? '-'}`)
}

/** One good at every city for this fleet (world.good_board). A trade (the fleet's version) or a new
 *  amount is a new question. */
export function useGoodBoard(
  goodId: string | null,
  fleetId: string | null,
  fleetVersion: number | null,
  qty: number | null,
  /** The city it would be bought at (the plan builder's choice); null: the board's own (the cheapest). */
  fromPortId: string | null = null,
): ServedRead<GoodBoard> {
  const subject = goodId && fleetId ? `${goodId}:${fleetId}` : null
  return useEdgeRead<GoodBoard>(
    subject,
    () => worldGoodBoard(goodId as string, fleetId as string, fromPortId, qty),
    subject ? `${subject}:${fleetVersion ?? '-'}:${qty ?? '-'}:${fromPortId ?? '-'}` : null,
  )
}

/** A good's estimated price at one city on one side (world.price_outlook). */
export function usePriceOutlook(
  portId: string | null,
  goodId: string | null,
  side: 'mid' | 'ask' | 'bid',
  slots: number | null = null,
): ServedRead<PriceOutlook> {
  const subject = portId && goodId ? `${portId}:${goodId}:${side}` : null
  return useEdgeRead<PriceOutlook>(
    subject,
    () => worldPriceOutlook(portId as string, goodId as string, slots, side),
    subject ? `${subject}:${slots ?? '-'}` : null,
  )
}
