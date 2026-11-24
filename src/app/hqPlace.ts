import { create } from 'zustand'
import type { BestSale } from '../lib/rpc'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE ONE WAY TO OPEN AN HQ SHEET (2026-11-24, docs/design/simplify-2026-11-24.md S1)
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-11-24: *"when i press HQ - city, a whole new tab shows up then i cannot go back to the previous page … i can make
// trade in HQ, or trade in trade tab. it routes to trade tab."* Every press on HQ (a door, a board card, a fleet row, the Market's
// Buy / Sell) opens its activity IN PLACE: a sheet over HQ (HqSheet.tsx) with a visible back; Esc and the browser's back close it
// (components/ui/useBackLayer.ts); HQ's scroll and its open plate stay as they were. Nothing on HQ navigates to another tab.
//
// `openHq` is the one door; `hqHref` the link another screen uses to land on HQ with a sheet open (HqSheet takes the ask out of
// the URL once, so the URL stays `/city`).

export type HqAsk =
  /** The company's shares and the city halls it may invest in (features/command/invest/Invest.tsx). */
  | { sheet: 'invest' }
  /** Profit by section, Today / Week / All (features/command/report/Report.tsx). */
  | { sheet: 'report' }
  /** A city's building yard (port CODE), a hull's sheet open when one is named. */
  | { sheet: 'yard'; port: string; hull?: string }
  /** A city's inn, for her fleet lying there. */
  | { sheet: 'inn'; port: string; fleet?: string }
  /** A city's market Requests, for her fleet lying there (its Fulfil). */
  | { sheet: 'requests'; port: string; fleet: string }
  /** THE trade sheet (features/command/buysell/TradePanel.tsx): one good at one city, Buy or Sell; with `best`, the board's best
   *  sale for it (a trip: bought here, sold there; or her cargo sold there). */
  | { sheet: 'trade'; port: string; fleet: string; good: string; side: 'buy' | 'sell'; best?: BestSale }
  /** A fleet's sheet: her cargo and where it sells, her route, her orders; `route` stands her route first. */
  | { sheet: 'fleet'; fleet: string; route?: boolean }
  /** THE ONE ASSIGN SHEET (features/city/corp/AssignSheet.tsx; docs/design/hq-corp-2026-11-24.md C3): work for one worker, a fleet's id
   *  or 'party' (the land party). A caller that knows the trade fills it in: the good and its two harbours (port CODES). */
  | { sheet: 'assign'; worker: string; good?: string; buy?: string; sell?: string }
  /** A worker's sheet: her action, what it did, Change and Stop (the worker named as Assign names her). */
  | { sheet: 'worker'; worker: string }

interface HqPlaceState {
  /** The sheet standing over HQ, or none. */
  ask: HqAsk | null
  /** The sheet a trade sheet was opened from: closing the trade goes back to it. */
  back: HqAsk | null
  open: (ask: HqAsk) => void
  close: () => void
  /** HQ left (its screen unmounted): nothing stands over it when it comes back. */
  clear: () => void
}

export const useHqPlace = create<HqPlaceState>()((set) => ({
  ask: null,
  back: null,
  // A trade pressed inside a sheet (a fleet's cargo, the Requests' market) stands in its place, and its close returns to it.
  open: (ask) => set((s) => ({ ask, back: ask.sheet === 'trade' && s.ask && s.ask.sheet !== 'trade' ? s.ask : null })),
  close: () => set((s) => ({ ask: s.back, back: null })),
  clear: () => set({ ask: null, back: null }),
}))

/** Open an HQ sheet, in place. */
export function openHq(ask: HqAsk): void {
  useHqPlace.getState().open(ask)
}

/** The URL fields a link carries, by the ask's own field (`best` is not one: a link names the good and the side). The sheet's city
 *  rides as `at`, since `port` is HQ's own city. */
const FIELDS = { sheet: 'sheet', port: 'at', fleet: 'fleet', good: 'good', side: 'side', hull: 'hull', route: 'route', worker: 'worker', buy: 'buy', sell: 'sell' } as const
const SHEETS: readonly HqAsk['sheet'][] = ['invest', 'report', 'yard', 'inn', 'requests', 'trade', 'fleet', 'assign', 'worker']

/** A link to HQ from another screen: on `port` (else the city in hand), the `place` plate open, and `ask`'s sheet over it. */
export function hqHref({ port, place, ask }: { port?: string; place?: string; ask?: HqAsk } = {}): string {
  const q = new URLSearchParams()
  if (port) q.set('port', port)
  if (place) q.set('place', place)
  if (ask)
    for (const [k, name] of Object.entries(FIELDS)) {
      const v = (ask as Record<string, unknown>)[k]
      if (v !== undefined && v !== false) q.set(name, String(v))
    }
  const s = q.toString()
  return s ? `/city?${s}` : '/city'
}

/** The sheet a URL asks for (the inverse of `hqHref`), or null. */
export function askOfParams(p: URLSearchParams): HqAsk | null {
  const sheet = p.get('sheet') as HqAsk['sheet'] | null
  if (!sheet || !SHEETS.includes(sheet)) return null
  const port = p.get('at')
  const fleet = p.get('fleet')
  switch (sheet) {
    case 'invest':
    case 'report':
      return { sheet }
    case 'yard':
      return port ? { sheet, port, hull: p.get('hull') ?? undefined } : null
    case 'inn':
      return port ? { sheet, port, fleet: fleet ?? undefined } : null
    case 'requests':
      return port && fleet ? { sheet, port, fleet } : null
    case 'trade': {
      const good = p.get('good')
      const side = p.get('side') === 'sell' ? 'sell' : 'buy'
      return port && fleet && good ? { sheet, port, fleet, good, side } : null
    }
    case 'fleet':
      return fleet ? { sheet, fleet, route: p.get('route') === 'true' } : null
    case 'assign': {
      const worker = p.get('worker')
      return worker ? { sheet, worker, good: p.get('good') ?? undefined, buy: p.get('buy') ?? undefined, sell: p.get('sell') ?? undefined } : null
    }
    case 'worker': {
      const worker = p.get('worker')
      return worker ? { sheet, worker } : null
    }
  }
}

/** The URL fields `hqHref` writes for a sheet, which HqSheet removes once it has opened it. */
export const HQ_ASK_FIELDS: readonly string[] = Object.values(FIELDS)
