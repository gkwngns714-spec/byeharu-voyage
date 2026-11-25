import { useState } from 'react'
import { Button, Hint, Icon, Note, Skeleton, Tray, goodIcon, useWide, type TrayDetent } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { portNameOf, useWorld } from '../../../live/worldStore'
import type { PortMarketState } from '../../../live/usePortMarket'
import type { TradeGoodRow } from '../../../domain/market'
import { formatPriceFigure } from '../../../lib/format'
import { useT } from '../../../lib/i18n'

// A PLACE PRESSED ON THE TRADE TAB'S MAP SHOWS ITS PRICES — the owner, 2026-11-25 (docs/design/owner-spec-2026-11-25.md):
//
//     "In the trade tab there should be a map, showing no NPCs but only locations, where you can click them for
//      info – price info."
//
// THE SHEET: the place's name, then one line a good — what the city asks (Buy) and what it bids (Sell) — and ONE press,
// "Trade here", which closes the map on the board of that city, where Buy and Sell are pressed as before.
//
// NO READ OF ITS OWN. A place pressed on the map is the city in hand (Trade.tsx `pressCity`, as it was), and the city in
// hand's market is the board's one read (`usePortMarket`); this sheet is handed that same answer and the board's own rows
// (domain/market `tradeRows`). So a press asks the server once, exactly as a chip pressed does, and the sheet and the board
// behind it can never show two prices for one good.
//
// WHERE IT STANDS: on a phone the bottom half of the glass (the map stays whole above it); on a wide glass the desk's right
// pane (the big map's page: the panel at the right edge). It opens on a press and closes on a press; nothing on the map page moves for it.

export function CityPrices({
  city,
  docked,
  quay,
  rows,
  onTrade,
  onClose,
  pane = false,
}: {
  /** The place pressed (port CODE): the city in hand. */
  city: string
  /** She lies there. */
  docked: boolean
  /** The board's read of that city's market. */
  quay: PortMarketState
  /** The board's rows for it. */
  rows: readonly TradeGoodRow[]
  /** "Trade here": the map closes on that city's board. */
  onTrade: () => void
  onClose: () => void
  /** On a wide glass: it stands in the desk's right pane (the face), not at the glass's edge (the big map's page). */
  pane?: boolean
}) {
  const t = useT()
  const wide = useWide()
  const portByCode = useWorld((s) => s.portByCode)
  const [detent, setDetent] = useState<TrayDetent>('half')
  const price = (p: number | null) => (p === null ? '—' : formatPriceFigure(p))
  // the place's own prices: a good she carries that this quay does not list has no figure in the market's answer (the board's
  // card asks its bid apart, world.price_why), so it is not a line of price info here
  const priced = rows.filter((r) => r.buy !== null || r.sell !== null)
  return (
    <Tray
      detent={detent}
      onDetentChange={(next) => (next === 'closed' ? onClose() : setDetent(next))}
      title={
        <span className="flex min-w-0 items-center gap-2" data-testid="city-prices-name">
          <PortFlag code={city} />
          <span className="min-w-0">{portNameOf(portByCode, city)}</span>
        </span>
      }
      mode={wide ? (pane ? 'pane' : 'side') : 'docked'}
      action={
        <Button variant="primary" className="w-full" onClick={onTrade} data-testid="city-prices-trade">
          {t('desk.tradeHere')}
        </Button>
      }
      data-testid="city-prices"
      data-city={city}
    >
      <p className="pb-1 text-t-caption text-ink-faint" data-testid="city-prices-where">
        {t(docked ? 'desk.docked' : 'desk.notDocked')}
      </p>
      {quay.market === undefined ? (
        quay.refusal ? (
          <Note tone="danger">{quay.refusal.sentence}</Note>
        ) : (
          <div className="flex flex-col gap-2" data-testid="city-prices-loading">
            {Array.from({ length: 5 }, (_, i) => (
              <Skeleton key={i} className="h-9 w-full" />
            ))}
          </div>
        )
      ) : priced.length === 0 ? (
        <Hint data-testid="city-prices-empty">{t('desk.noBuy')}</Hint>
      ) : (
        <table className="w-full border-collapse text-left" data-testid="city-prices-list">
          <thead>
            <tr className="text-t-caption text-ink-faint">
              <th scope="col" className="py-1 font-normal">
                {t('desk.good')}
              </th>
              <th scope="col" className="w-[5.5rem] py-1 text-right font-normal">
                {t('desk.buy')}
              </th>
              <th scope="col" className="w-[5.5rem] py-1 text-right font-normal">
                {t('desk.sell')}
              </th>
            </tr>
          </thead>
          <tbody>
            {priced.map((r) => (
              <tr key={r.code} className="border-t border-edge" data-testid="city-price" data-good={r.code}>
                <th scope="row" className="h-11 py-1 pr-2 font-normal">
                  <span className="flex items-center gap-2 text-t-body text-ink">
                    <Icon name={goodIcon(r.code, r.category)} size={18} className="shrink-0 text-ink-muted" />
                    <span className="min-w-0 break-words">{r.name}</span>
                  </span>
                </th>
                <td className={`text-right text-t-body font-semibold tabular-nums ${r.buy === null ? 'text-ink-faint' : 'text-ink'}`} data-testid="city-price-buy">
                  {price(r.buy)}
                </td>
                <td className={`text-right text-t-body tabular-nums ${r.sell === null ? 'text-ink-faint' : 'text-ink-muted'}`} data-testid="city-price-sell">
                  {price(r.sell)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </Tray>
  )
}
