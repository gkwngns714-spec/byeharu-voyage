import { useEffect, useRef, useState } from 'react'
import { worldMoneyFeed, type MoneyMove, type RpcResult } from '../../lib/rpc'
import { emptyDrip, enqueue, step, type Drip } from './moneyDrip'
import { SECTORS, sectorOf, type Sector } from './moneySectors'
import { useLiveRead } from './statsLive'

// THE MONEY LOG'S FEED AND ITS FILTER (0235, owner row 219): every money move in the world as it happens.
// The drip (moneyDrip.ts) reveals batches a few rows a second; each row keeps its real time. Moved out of
// MoneyLog.tsx by the unfold slice (2026-11-02) so the Overview face holds the read for as long as it is
// open — whichever of the panel's two views is showing — and so the file that draws the rows exports only
// components. The read itself is exactly what it was: every second, through the tab's one `useLiveRead`.

const KEEP = 300
const ASK = 100
const FILTER_KEY = 'bv:moneylog-filter'
const LATE_MS = 20_000

export type MovePick = 'all' | Sector
export interface MoveFilter {
  pick: MovePick
  mine: boolean
}

export function loadMoveFilter(): MoveFilter {
  try {
    const j = JSON.parse(localStorage.getItem(FILTER_KEY) ?? 'null') as Partial<MoveFilter> | null
    const pick = j?.pick
    return { pick: pick === 'all' || (SECTORS as readonly string[]).includes(pick as string) ? (pick as MovePick) : 'all', mine: j?.mine === true }
  } catch {
    return { pick: 'all', mine: false }
  }
}

export function saveMoveFilter(f: MoveFilter): void {
  try {
    localStorage.setItem(FILTER_KEY, JSON.stringify(f))
  } catch {
    /* storage may be blocked: the choice just is not remembered */
  }
}

const atMs = (m: MoneyMove) => Date.parse(m.at)
export { atMs as moveAtMs }

function newestFirst(a: MoneyMove, b: MoneyMove): number {
  const d = atMs(b) - atMs(a)
  if (d !== 0) return d
  if (a.at !== b.at) return a.at < b.at ? 1 : -1
  return a.key < b.key ? 1 : a.key > b.key ? -1 : 0
}

function merge(held: MoneyMove[], got: MoneyMove[]): MoneyMove[] {
  const byKey = new Map<string, MoneyMove>()
  for (const m of held) byKey.set(m.key, m)
  for (const m of got) byKey.set(m.key, m)
  return [...byKey.values()].sort(newestFirst).slice(0, KEEP)
}

export function useMoneyFeed(): { view: MoneyMove[] | null; loading: boolean } {
  const held = useRef<MoneyMove[]>([])
  const seen = useRef<Set<string> | null>(null)
  const drip = useRef<Drip>(emptyDrip)
  const [shown, setShown] = useState<MoneyMove[] | null>(null)
  const read = useLiveRead<MoneyMove[]>('stats:money-feed', async (): Promise<RpcResult<MoneyMove[]>> => {
    const newest = held.current[0]
    const after = newest === undefined ? null : new Date(atMs(newest) - LATE_MS).toISOString()
    const r = await worldMoneyFeed(after, ASK)
    if (!r.ok) return r
    held.current = merge(held.current, r.value.moves)
    if (seen.current === null) {
      seen.current = new Set(r.value.moves.map((m) => m.key))
      setShown(held.current)
    } else {
      const fresh = r.value.moves.filter((m) => !seen.current!.has(m.key))
      for (const m of fresh) seen.current.add(m.key)
      const mine = fresh.filter((m) => m.own)
      if (mine.length > 0) setShown((s) => merge(s ?? [], mine))
      drip.current = enqueue(drip.current, fresh.filter((m) => !m.own))
    }
    return { ok: true, value: held.current }
  })
  useEffect(() => {
    const id = setInterval(() => {
      const { released, next } = step(drip.current)
      if (released.length === 0) return
      drip.current = next
      setShown((s) => merge(s ?? [], released))
    }, 1000)
    return () => clearInterval(id)
  }, [])
  return { view: read.view === null ? null : shown ?? read.view, loading: read.loading }
}

/** The moves under a filter: the base (Mine applied), each sector's count over that base, and the rows
 *  the sector pick leaves. Pure. */
export function sliceMoves(
  view: readonly MoneyMove[],
  filter: MoveFilter,
): { base: readonly MoneyMove[]; counts: ReadonlyMap<Sector, number>; rows: readonly MoneyMove[] } {
  const base = filter.mine ? view.filter((m) => m.own) : view
  const counts = new Map<Sector, number>()
  for (const m of base) {
    const k = sectorOf(m.kind, m.holder)
    counts.set(k, (counts.get(k) ?? 0) + 1)
  }
  const rows = filter.pick === 'all' ? base : base.filter((m) => sectorOf(m.kind, m.holder) === filter.pick)
  return { base, counts, rows }
}
