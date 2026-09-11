import { useMemo, type ReactNode } from 'react'
import { TradeRow, type TradePick } from '../../components/ui'
import { buyableHere, listedHere } from '../../domain/market'
import type { MarketGood } from '../../lib/rpc'

// THE LEDGER — which goods stand on the board, in what order, each as ONE `TradeRow`.
//
// docs/QUAY_LEDGER.md §3 A. The board has two faces — the quay she lies at (PortTrade.tsx, a press
// opens the trade tray) and a quay she is only reading (PortPrices.tsx, a press opens the read-only
// tray) — and on 2026-09-11 both spelt the list themselves: the same `listedHere` filter, the same
// order by name, the same row wiring. The ORDER of a ledger is a rule, and a rule in two files is
// the spaghetti docs/NO_SPAGHETTI.md §1 names, so it is spelt here once and both faces compose it.
//
// WHAT IT DECIDES: nothing about the world. `listedHere` and `buyableHere` are 0061's two served
// answers about a row; `aboard` is the caller's ONE fold of the reader's manifest; what a press
// opens is the caller's affair. The text filter on the trading face is that face's chrome and is
// applied to `goods` BEFORE they reach here — the order is not.

export function QuayLedger({
  goods,
  aboard,
  pick,
  onPick,
  empty,
}: {
  /** `world.market(port)`'s goods for this harbour, already narrowed by any caller's filter. */
  goods: readonly MarketGood[]
  /** Tuns aboard by good code — the reader's manifest, folded once by the caller. */
  aboard: Readonly<Record<string, number>>
  /** Which good and which price is open in a tray, if any — the row draws its wash. */
  pick: TradePick | null
  onPick: (good: MarketGood, intent: 'buy' | 'sell') => void
  /** What to draw when no row is listed — the caller knows WHY (a filter, or an empty quay). */
  empty: ReactNode
}) {
  const shown = useMemo(
    () =>
      goods
        // WHAT IS ON THIS QUAY, PLUS WHAT SHE IS CARRYING (0061): a hold is never stranded.
        .filter((g) => listedHere(g, aboard[g.code] ?? 0))
        .sort((a, b) => a.name.localeCompare(b.name)),
    [goods, aboard],
  )
  if (shown.length === 0) return <>{empty}</>
  return (
    <div className="mt-3" data-testid="quay-ledger">
      {shown.map((g) => (
        <TradeRow
          key={g.code}
          good={g}
          aboard={aboard[g.code] ?? 0}
          canBuy={buyableHere(g)}
          selected={pick?.good.code === g.code ? pick.intent : null}
          onBuy={() => onPick(g, 'buy')}
          onSell={() => onPick(g, 'sell')}
        />
      ))}
    </div>
  )
}
