import { useMemo } from 'react'
import { Button, Note, Segmented, Skeleton, categoryLabel } from '../../components/ui'
import { fleetCargoByCode } from '../../domain/fleet'
import { hasBuilding } from '../../domain/port'
import { type FleetView, type SnapshotPort } from '../../lib/rpc'
import { useT } from '../../lib/i18n'
import { useMarketPick } from '../../live/marketPick'
import { useMarketRequests } from '../../live/useMarketRequests'
import { usePortMarket } from '../../live/usePortMarket'
import { TRADE_FACES, useTradeFace, type TradeFace } from '../../live/tradeFace'
import { useWorld } from '../../live/worldStore'
import { RequestsFace } from './RequestPage'
import { TradeCard } from '../../live/TradeCard'
import { tradeRows, type TradeGoodRow } from '../../domain/market'
import { openHq } from '../../app/hqPlace'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE MARKET FACE — the chart on the left region, BUY · SELL · REQUEST in the right panel
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner, 2026-10-31 (verbatim): "when pressing a market, instead of city, i would like to have a
// graph shown, that is changed when pressed a trade good. when pressing buy, a new page pops up -
// this is not good. instead, have BUY, beneath show all the trade goods neatly organized. So is
// sell - cargo good. Request i press, a page shows up, where i search trade good - press it, shows
// up chart, choose price to buy, and then the put the money in it. - the order is made, and
// merchants will come and sell it to you if the price is reasonable" — and "but this feature,
// request, should only be done in your home country- home city. get it?"
//
// SO: the doors are a `Segmented`; beneath the pressed door the goods are listed, grouped by the SERVED category, each good THE one
// goods card the Trade screen draws (`TradeCard`, from tradeRows — the Trade board's one order and membership rule, never re-spelt here;
// S5, 2026-11-11: the HQ's own `TradeRow` ledger was a second card for the same good). A press on a good pins it for the chart
// (marketPick.ts) AND opens THE trade sheet over HQ (2026-11-24, simplify S1: hqPlace.ts `openHq`, HqSheet.tsx) on this city, this
// good and that side, for the fleet docked here — in place, never on another tab (the owner: *"i can make trade in HQ, or trade in
// trade tab. it routes to trade tab"*). With no fleet of yours here the press only pins the good — the board is read-only, as it was.
//
// REQUEST is drawn ONLY when the server says this port is the house's home city
// (world.requests().home). That flag is the SAME public.home_port_of() the verb enforces, so hiding
// the door is a courtesy and the server is the gate. Its face lists the caller's open requests
// (good, quantity, price, the money set aside) with the cancel that refunds the unfilled part; the
// New request row opens the page the owner described: search → press a good → its chart → price and
// quantity → the payment → Place.

export function MarketFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const quay = usePortMarket(port.kind === 'HARBOUR' ? port.id : null)
  const board = useMarketRequests(port.kind === 'HARBOUR' ? port.id : null)
  const face = useTradeFace((s) => s.face)
  const turnTo = useTradeFace((s) => s.turnTo)
  const pin = useMarketPick((s) => s.pick)

  // ALL HOOKS UNCONDITIONALLY, before any early return.
  const goods = useMemo(() => quay.market?.goods ?? [], [quay.market])
  const aboard = useMemo(() => (fleet ? fleetCargoByCode(fleet) : {}), [fleet])
  const goodByCode = useWorld((s) => s.goodByCode)
  const home = board.view?.home ?? false
  const shown: TradeFace = face === 'requests' && !home ? 'buy' : face
  const matching = useMemo(
    () => tradeRows(goods, aboard, goodByCode).filter((r) => shown !== 'sell' || r.units > 0),
    [goods, shown, aboard, goodByCode],
  )
  const groups = useMemo(() => {
    const m = new Map<string, TradeGoodRow[]>()
    for (const g of matching) {
      const k = g.category ?? ''
      const arr = m.get(k)
      if (arr) arr.push(g)
      else m.set(k, [g])
    }
    return [...m.entries()].sort((a, b) => a[0].localeCompare(b[0]))
  }, [matching])

  if (!hasBuilding(port, 'market')) return <Note tone="neutral">{t('city.noMarket')}</Note>
  if (quay.market === undefined) {
    return quay.refusal !== null ? (
      <Note
        tone="danger"
        code={quay.refusal.code}
        figures={quay.refusal.figures}
        action={
          <Button onClick={quay.retry}>
            {t('common.retry')}
          </Button>
        }
      >
        {quay.refusal.sentence}
      </Note>
    ) : (
      <Skeleton className="h-28 w-full" />
    )
  }

  const openGood = (code: string, intent: 'buy' | 'sell') => {
    const good = goods.find((g) => g.code === code)
    if (!good) return
    pin(port.id, good)
    if (fleet) openHq({ sheet: 'trade', port: port.code, fleet: fleet.id, good: code, side: intent })
  }

  return (
    <>
      <Segmented<TradeFace>
        label={t('city.market')}
        segments={TRADE_FACES.filter((f) => f.id !== 'requests' || home)}
        value={shown}
        onChange={turnTo}
        className="mt-2"
      />
      {shown === 'requests' ? (
        <RequestsFace port={port} goods={goods} own={board.view} aboard={aboard} />
      ) : (
        <div className="mt-2" data-testid={`city-market-${shown}`}>
          {matching.length === 0 ? (
            <Note tone="neutral">{t(shown === 'sell' ? 'trade.noCargoSell' : 'trade.noMatch')}</Note>
          ) : (
            groups.map(([category, rows]) => (
              <div key={category || 'all'}>
                {category !== '' && (
                  <div className="pt-2 text-t-caption text-ink-faint" data-testid="city-market-group" data-category={category}>
                    {categoryLabel(category)}
                  </div>
                )}
                <div className="mt-1 grid grid-cols-2 gap-2 lg:grid-cols-[repeat(auto-fill,minmax(min(100%,9.5rem),1fr))]">
                  {rows.map((r) => (
                    <TradeCard
                      key={r.code}
                      portId={port.id}
                      r={r}
                      docked={fleet !== null}
                      on={false}
                      onBuy={(code) => openGood(code, 'buy')}
                      onSell={(code) => openGood(code, 'sell')}
                    />
                  ))}
                </div>
              </div>
            ))
          )}
        </div>
      )}
    </>
  )
}
