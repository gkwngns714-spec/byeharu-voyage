// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE COMMAND DESK'S EDGE READS (docs/COMMAND_DESK.md §5.8, §7.6) — the trip's board and why a price is what
// it is; asked when the desk opens them, and again at the MARKET'S EDGE (the served clock.next_change_at), never on the beat.
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
// once. (The watchlist, the outlook and their prefetch left with the Markets face, owner row 218.) One
// spelling of each question, below.

import { useCallback, useState } from 'react'
import { useReaskAtEdge } from '../components/ui'
import { useShellState } from '../app/shellState'
import { worldGoodBoard, worldPriceWhy } from '../lib/rpc'
import type { GoodBoard, PriceWhy, RpcResult } from '../lib/rpc'
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

function priceWhyRead(portId: string | null, goodId: string | null): DeskRead<PriceWhy> {
  const subject = portId && goodId ? `${portId}:${goodId}` : null
  return { subject, question: subject, ask: () => worldPriceWhy(portId as string, goodId as string) }
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

/** Why a good's market price at one city is what it is (world.price_why, 0185). */
export function usePriceWhy(portId: string | null, goodId: string | null): ServedRead<PriceWhy> {
  return useEdgeRead('price_why', priceWhyRead(portId, goodId))
}
