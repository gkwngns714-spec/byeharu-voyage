import { Button, Figure, Hint, PriceRows, Row } from '../../../components/ui'
import { CityGoodTrades } from '../../../live/CityGoodTrades'
import { usePriceWhy } from '../../../live/useDesk'
import { usePriceSeries } from '../../../live/usePriceSeries'
import { formatPriceFigure } from '../../../lib/format'
import type { MarketGood } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'
import { WhyThisPrice } from '../markets/WhyThisPrice'

// ONE GOOD AT ONE CITY — what a press on a good of the Buy / Sell list opens (owner row 218, 2026-10-26: *"when
// pressed upon, show trade goods with prices, and charts"*). Nothing here is new; it is the city's own row read
// through the design system's pieces:
//   · the price this side trades at (world.market's ask on Buy, its bid on Sell), as served;
//   · THE ACT: docked at this city → Buy here / Sell here, which opens THE trade tray (markets/DeskTrade.tsx, the
//     desk's one trade doorway); and always Plan trip, which opens the trip's card (plans/TradeCard.tsx) — the one
//     Go path (docked here on Sell, its sell list says where else it sells);
//   · Kind · Trend (the chart, open, over the chosen span: usePriceSeries, 0226) · Range · In stock (PriceRows);
//   · why the price is what it is (world.price_why, 0185: WhyThisPrice);
//   · who bought what here (0227: CityGoodTrades).
// SELL: what this city WANTS (owner row 218: mark the city's wants) is not served yet; when it is, its mark stands in
// this head beside the price, read from the server — never guessed here.

export function GoodDetail({
  side,
  portId,
  row,
  docked,
  canAct,
  onAct,
  onPlan,
  refresh,
}: {
  side: 'buy' | 'sell'
  portId: string
  /** The city's own market row for the good (world.market). */
  row: MarketGood
  /** She lies at this city. */
  docked: boolean
  /** The act can run here now (Buy: the city sells it; Sell: she carries it and the city deals in it). */
  canAct: boolean
  onAct: () => void
  onPlan: () => void
  /** Re-ask who bought what after her own trade (the fleet's version). */
  refresh: unknown
}) {
  const t = useT()
  const trend = usePriceSeries(portId, row.good_id)
  const why = usePriceWhy(portId, row.good_id)
  const price = side === 'buy' ? row.buy : row.sell
  return (
    <div className="mt-1 mb-3 rounded-md border border-edge px-3 pb-3 pt-1" data-testid="good-detail" data-good={row.code} data-side={side}>
      <Row
        label={t(side === 'buy' ? 'desk.buy' : 'desk.sell')}
        value={<Figure value={formatPriceFigure(price)} size="figure" />}
        data-testid="good-detail-price"
      />
      <div className="mt-2 flex flex-wrap gap-2">
        {docked && (
          <Button variant="primary" disabled={!canAct} onClick={onAct} data-testid={side === 'buy' ? 'good-buy' : 'good-sell'}>
            {t(side === 'buy' ? 'desk.buyNow' : 'desk.sellNow')}
          </Button>
        )}
        <Button variant={docked ? 'secondary' : 'primary'} onClick={onPlan} data-testid="good-plan">
          {t('desk.planTrip')}
        </Button>
      </div>
      {!docked && (
        <Hint className="mt-1" data-testid="good-not-docked">
          {t('desk.notDocked')}
        </Hint>
      )}
      <div className="mt-2">
        <PriceRows good={row} trend={trend} startOpen />
      </div>
      <WhyThisPrice why={why.view ?? null} loading={why.loading} />
      <CityGoodTrades portId={portId} goodId={row.good_id} refresh={refresh} />
    </div>
  )
}
