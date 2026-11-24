import { useEffect, useMemo, type ReactNode } from 'react'
import { Button, Note, Segmented, Skeleton, categoryLabel } from '../../components/ui'
import { fleetCargoByCode } from '../../domain/fleet'
import { useCommandDraft } from '../../domain/order'
import { hasBuilding } from '../../domain/port'
import { type BestSale, type FleetView, type SnapshotPort } from '../../lib/rpc'
import { useT } from '../../lib/i18n'
import { useMarketPick } from '../../live/marketPick'
import { useMarketRequests } from '../../live/useMarketRequests'
import { usePortMarket } from '../../live/usePortMarket'
import { TRADE_FACES, useTradeFace, type TradeFace } from '../../live/tradeFace'
import { useWorld } from '../../live/worldStore'
import { RequestsFace } from './RequestPage'
import { TradeCard } from '../../live/TradeCard'
import { tradeRows, type TradeGoodRow } from '../../domain/market'
import { openHq, useHqPlace } from '../../app/hqPlace'
import { CityChips } from '../../live/CityChips'
import { FromHere } from '../../live/FromHere'
import { QuayFair } from '../../live/PortFair'
import { QuayEvents, WorldEventsLine } from '../../live/WorldEventLine'
import { useNearEvent } from '../../live/eventReach'
import { useBestSales } from '../../live/useDesk'
import { useDeskGood } from '../../store/deskGood'

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

// THE ONE TRADE LIST (H3 `desk-into-hq`, 2026-11-24; docs/design/simplify-2026-11-24.md S3). The Trade desk's goods board and the
// Office's market were two more lists of the same goods; both are gone, and what only they had stands here:
//   the city chips    read another city's prices (the chart beside the list follows: live/MarketLeft.tsx); a Buy or Sell pressed
//                     there is a trip in the one trade sheet (Sail & buy, Sail & sell);
//   the best sale     on every card, for the fleet that trades (world.best_sales, the board the desk read), and its press;
//   From here         what sells best where, from the city she lies in;
//   the city's lines  its fair, its events, what it wants now.
// WHO TRADES: her fleet lying at this city (the one in hand first); with none here, the fleet in hand, who sails.
export function MarketFace({ port, fleet }: { port: SnapshotPort; fleet: FleetView | null }) {
  const t = useT()
  const fleets = useWorld((s) => s.fleets)
  const portByCode = useWorld((s) => s.portByCode)
  const hand = useCommandDraft((s) => s.fleetId)
  const trader = fleet ?? fleets.find((f) => f.id === hand) ?? fleets[0] ?? null
  // THE CITY READ: HQ's own, or a chip's (store/deskGood.ts `focus`, the one "city the trade list reads"); a glance, so it is let
  // go when the Market plate closes.
  const focus = useDeskGood((s) => s.focus)
  const setFocus = useDeskGood((s) => s.setFocus)
  useEffect(() => () => useDeskGood.getState().setFocus(null), [])
  const focused = focus ? (portByCode[focus] ?? null) : null
  const read = focused && focused.kind === 'HARBOUR' ? focused : port
  const away = read.code !== port.code
  const here = trader !== null && trader.status === 'DOCKED' && trader.port === read.code
  const quay = usePortMarket(read.kind === 'HARBOUR' ? read.id : null)
  const board = useMarketRequests(port.kind === 'HARBOUR' ? port.id : null)
  const face = useTradeFace((s) => s.face)
  const turnTo = useTradeFace((s) => s.turnTo)
  const pin = useMarketPick((s) => s.pick)
  const best = useBestSales(trader?.id ?? null, trader?.version ?? null, read.id)
  const sales = useMemo<ReadonlyMap<string, BestSale> | null>(
    () => (best.view && best.view.port === read.code ? new Map(best.view.goods.map((g) => [g.good, g])) : null),
    [best.view, read.code],
  )
  const nearEvent = useNearEvent(port.code, trader?.speed_kn ?? 0)
  // the best sale whose trip stands open in the trade sheet: its From-here tile is lit
  const asked = useHqPlace((s) => (s.ask?.sheet === 'trade' ? (s.ask.best ?? null) : null))
  const openSale = asked && asked.port ? { good: asked.good, sellAt: asked.port } : null

  const goods = useMemo(() => quay.market?.goods ?? [], [quay.market])
  const aboard = useMemo(() => (trader ? fleetCargoByCode(trader) : {}), [trader])
  const goodByCode = useWorld((s) => s.goodByCode)
  // Requests are HQ's own city's, at her home
  const home = !away && (board.view?.home ?? false)
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
  // BELOW lg HQ IS TALLER THAN THE GLASS, and while this plate's read is on its way the plate is one short block: the page shrank
  // under its own scroll and the plates' row slid 36 px as Market was pressed (tests/city.page.spec.ts, "pressing market re-flowed
  // the frame"). The plate holds a glass of height there, as Production does (live/PortProduction.tsx).
  const held = (body: ReactNode) => <div className="min-h-dvh lg:min-h-0">{body}</div>
  if (quay.market === undefined) {
    return held(quay.refusal !== null ? (
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
    ))
  }

  const openGood = (code: string, intent: 'buy' | 'sell') => {
    // a carried good this quay does not list has no chart to pin, and still sells (the trade sheet reads its bid: owner row 231)
    const good = goods.find((g) => g.code === code)
    if (good) pin(read.id, good)
    if (trader) openHq({ sheet: 'trade', port: read.code, fleet: trader.id, good: code, side: intent })
  }
  // a best sale pressed: its trip (bought here, sold there), or her cargo sold at its city, in the one trade sheet
  const pressBest = (sale: BestSale) => {
    if (trader) openHq({ sheet: 'trade', port: read.code, fleet: trader.id, good: sale.good, side: 'buy', best: sale })
  }
  const readCity = (c: string) => setFocus(c === port.code ? null : c)
  const chips = (
    <div data-testid="city-market-read" data-city={read.code} data-here={here ? 'true' : 'false'}>
      <WorldEventsLine city={read.code} onCity={readCity} near={nearEvent} />
      <CityChips home={port.code} city={read.code} onCity={readCity} />
      <QuayFair portId={read.id} />
      <QuayEvents portCode={read.code} />
      {quay.market?.wants && quay.market.wants.length > 0 && (
        <Note tone="neutral" className="mt-2" data-testid="city-market-wants">
          {t('ui.wanted', { mult: String(Number(quay.market.wants[0].mult)) })}: {quay.market.wants.map((w) => w.name).join(' · ')}
        </Note>
      )}
    </div>
  )

  return held(
    <>
      {chips}
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
                      portId={read.id}
                      r={r}
                      docked={here}
                      on={false}
                      onBuy={(code) => openGood(code, 'buy')}
                      onSell={(code) => openGood(code, 'sell')}
                      sale={trader ? sales?.get(r.code) : undefined}
                      onBest={trader ? pressBest : undefined}
                    />
                  ))}
                </div>
              </div>
            ))
          )}
          {here && <FromHere sales={sales} open={openSale} onBest={pressBest} />}
        </div>
      )}
    </>,
  )
}
