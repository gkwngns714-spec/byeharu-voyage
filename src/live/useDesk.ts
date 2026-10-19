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
//
// REMEMBERED UNTIL THE EDGE (2026-10-19, owner: "when pressing a different trade goods, it takes too long
// to load"): each read keeps its answer (servedMemo.ts) under its own question until the market's next
// edge — the moment the open desk would re-ask it anyway — so going back to a good just shown draws at
// once, and `prefetchDeskReads` asks a good's reads before its panes need them (a row the pointer rests
// on; the focus city's estimate beside the board, not after it). One spelling of each question, below:
// the hook and the prefetch ask the same thing under the same key.

import { useCallback, useState } from 'react'
import { useReaskAtEdge } from '../components/ui'
import { useShellState } from '../app/shellState'
import { worldGoodBoard, worldPriceOutlook, worldPriceWhy, worldWatchlist } from '../lib/rpc'
import type { GoodBoard, PriceOutlook, PriceWhy, RpcResult, Watchlist } from '../lib/rpc'
import { askServed } from './servedMemo'
import { useServedRead, type ServedRead } from './useServedRead'

type Clocked = { clock: { now: string; next_change_at: string } }

/** A clocked answer is fresh until its own edge (both ends on the server's clock, so the glass's skew
 *  does not matter). */
const untilEdge = (v: Clocked) => Date.parse(v.clock.next_change_at) - Date.parse(v.clock.now)

/** One desk question: what it is FOR, what is asked, and the RPC. */
interface DeskRead<V> {
  subject: string | null
  question: string | null
  ask: () => Promise<RpcResult<V>>
}

const memoKey = (name: string, question: string) => `${name}|${question}`

/** A served read with a clock, re-asked when its own edge passes, kept until then. */
function useEdgeRead<V extends Clocked>(name: string, { subject, question, ask }: DeskRead<V>): ServedRead<V> {
  const { nowMs } = useShellState()
  const [edges, setEdges] = useState(0)
  const read = useServedRead<V>(subject, ask, {
    question,
    trigger: edges,
    memo: subject && question ? { key: memoKey(name, question), freshMs: untilEdge } : null,
  })
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

/** Ask a desk question ahead of its panes: kept under the hook's own key, joined if already asked. */
function prefetch<V extends Clocked>(name: string, { subject, question, ask }: DeskRead<V>): void {
  if (subject && question) void askServed<V>(memoKey(name, question), ask, untilEdge)
}

const watchlistRead = (fleetId: string | null, fleetVersion: number | null): DeskRead<Watchlist> => ({
  subject: 'watchlist',
  question: `${fleetId ?? '-'}:${fleetVersion ?? '-'}`,
  ask: () => worldWatchlist(fleetId),
})

function goodBoardRead(
  goodId: string | null,
  fleetId: string | null,
  fleetVersion: number | null,
  qty: number | null,
  fromPortId: string | null,
): DeskRead<GoodBoard> {
  const subject = goodId && fleetId ? `${goodId}:${fleetId}` : null
  return {
    subject,
    question: subject ? `${subject}:${fleetVersion ?? '-'}:${qty ?? '-'}:${fromPortId ?? '-'}` : null,
    ask: () => worldGoodBoard(goodId as string, fleetId as string, fromPortId, qty),
  }
}

function priceOutlookRead(
  portId: string | null,
  goodId: string | null,
  side: 'mid' | 'ask' | 'bid',
  slots: number | null,
): DeskRead<PriceOutlook> {
  const subject = portId && goodId ? `${portId}:${goodId}:${side}` : null
  return {
    subject,
    question: subject ? `${subject}:${slots ?? '-'}` : null,
    ask: () => worldPriceOutlook(portId as string, goodId as string, slots, side),
  }
}

function priceWhyRead(portId: string | null, goodId: string | null): DeskRead<PriceWhy> {
  const subject = portId && goodId ? `${portId}:${goodId}` : null
  return { subject, question: subject, ask: () => worldPriceWhy(portId as string, goodId as string) }
}

/** Every good once (world.watchlist) — what the fleet carries rides the question. */
export function useWatchlist(fleetId: string | null, fleetVersion: number | null): ServedRead<Watchlist> {
  return useEdgeRead('watchlist', watchlistRead(fleetId, fleetVersion))
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
  return useEdgeRead('good_board', goodBoardRead(goodId, fleetId, fleetVersion, qty, fromPortId))
}

/** A good's estimated price at one city on one side (world.price_outlook). */
export function usePriceOutlook(
  portId: string | null,
  goodId: string | null,
  side: 'mid' | 'ask' | 'bid',
  slots: number | null = null,
): ServedRead<PriceOutlook> {
  return useEdgeRead('price_outlook', priceOutlookRead(portId, goodId, side, slots))
}

/** Why a good's market price at one city is what it is (world.price_why, 0185). */
export function usePriceWhy(portId: string | null, goodId: string | null): ServedRead<PriceWhy> {
  return useEdgeRead('price_why', priceWhyRead(portId, goodId))
}

/** Ask ahead of the panes what a desk good page asks: its board (when `board` names the fleet; the
 *  board's own amount and city) and, at each city named, the estimate and the breakdown — the very
 *  questions useGoodBoard / usePriceOutlook / usePriceWhy ask, so the panes find them answered or on
 *  the wire. */
export function prefetchDeskReads({
  goodId,
  board,
  outlook,
  portIds,
}: {
  goodId: string
  board: { fleetId: string; fleetVersion: number | null } | null
  outlook: { side: 'mid' | 'ask' | 'bid'; slots: number | null }
  portIds: readonly string[]
}): void {
  if (board) prefetch('good_board', goodBoardRead(goodId, board.fleetId, board.fleetVersion, null, null))
  for (const portId of portIds) {
    prefetch('price_outlook', priceOutlookRead(portId, goodId, outlook.side, outlook.slots))
    prefetch('price_why', priceWhyRead(portId, goodId))
  }
}
