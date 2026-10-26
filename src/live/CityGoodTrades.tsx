import { useEffect, useState } from 'react'
import { useShellState } from '../app/shellState'
import { Empty, Row } from '../components/ui'
import { formatInt, formatPrice, formatRelative } from '../lib/format'
import { worldCityGoodTrades, type CityGoodTrades as Served } from '../lib/rpc'
import { useT } from '../lib/i18n'

// WHO BOUGHT WHAT — a city's recent trades of ONE good (0227, owner row 211, 2026-10-26: *"i want to see
// who bought what when pressed a city - clicking trade goods"*). The ONE list every press on a city's
// good opens: PORT's read-only price tray (PriceTray, also the MAP's city panel) and the quay's trade
// tray (PortTrade → TradeTray) both render this, never a second copy.
//
// Each row: the company (a player's or a merchant's — the owner's word: names are shown), Bought or
// Sold (the COMPANY's side), units, price each, and when. Newest first, the last 7 days, at most 50 —
// the server's `world.city_good_trades`. No purse, no fleet, no position. A name is never cut: the
// label wraps, and its full text is the hover title too.
//
// A failed read is quiet (the list decorates a tray that is true without it). `refresh` re-asks:
// the quay passes the fleet's version, so a trade she just made appears.

function useCityGoodTrades(portId: string, goodId: string, refresh: unknown): Served | null | undefined {
  const key = `${portId}:${goodId}`
  const [got, setGot] = useState<{ key: string; value: Served | null } | null>(null)
  useEffect(() => {
    let live = true
    void worldCityGoodTrades(portId, goodId).then((r) => {
      if (live) setGot({ key, value: r.ok ? r.value : null })
    })
    return () => {
      live = false
    }
  }, [portId, goodId, key, refresh])
  // undefined = not landed for this pair yet; null = the read failed
  return got && got.key === key ? got.value : undefined
}

export function CityGoodTrades({ portId, goodId, refresh }: { portId: string; goodId: string; refresh?: unknown }) {
  const t = useT()
  const { nowMs } = useShellState()
  const served = useCityGoodTrades(portId, goodId, refresh)
  if (served === null) return null
  return (
    <section className="mt-4" data-testid="city-good-trades">
      <span className="block text-t-caption text-ink-faint">{t('trade.trades')}</span>
      {served === undefined ? (
        <Empty className="mt-2">{t('trade.loading')}</Empty>
      ) : served.trades.length === 0 ? (
        <Empty className="mt-2" data-testid="city-good-trades-none">
          {t('trade.tradesNone')}
        </Empty>
      ) : (
        served.trades.map((x, i, all) => {
          const tag = x.own ? t('trade.tradesYou') : x.merchant ? t('trade.tradesMerchant') : null
          return (
            <Row
              key={`${x.at}:${i}`}
              label={
                <span className="break-words" title={x.company}>
                  {x.company}
                  {tag && <span className="text-t-caption text-ink-faint"> · {tag}</span>}
                </span>
              }
              value={<span className="text-t-caption text-ink-faint">{formatRelative(Date.parse(x.at), nowMs)}</span>}
              tone={x.own ? 'accent' : 'default'}
              hairline={i < all.length - 1}
              data-testid="city-good-trade"
            >
              <span className="text-t-caption text-ink-faint" data-side={x.side}>
                {t('trade.tradesLine', {
                  side: t(x.side === 'bought' ? 'trade.tradesBought' : 'trade.tradesSold'),
                  qty: formatInt(x.qty),
                  price: formatPrice(x.price),
                })}
              </span>
            </Row>
          )
        })
      )}
    </section>
  )
}
