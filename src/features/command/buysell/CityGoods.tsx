import type { ReactNode } from 'react'
import { Col, Cols, Hint, Icon, Note, Row, Skeleton, goodIcon } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import type { PortMarketState } from '../../../live/usePortMarket'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatInt, formatPriceFigure } from '../../../lib/format'
import type { MarketGood } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'

// THE CITY'S GOODS — the list under the mini map on the Buy and Sell faces (owner row 218). ONE row per good, each
// the good, the units aboard and ONE price, the side's: on BUY every good the city sells (`buyableHere`) at its ask;
// on SELL every good in her cargo at the city's bid ("—" where the city keeps no row for it). Which rows stand is the
// caller's (BuySell.tsx); this file draws them and hands a press up. Nothing is priced here: the figures are
// world.market's (usePortMarket, the read the quay makes).
//
// A press selects (COMMAND_DESK §3.5): the row takes the wash and the good's page (GoodDetail.tsx) opens — under the
// row on a phone (`detail`), in the centre pane on a wide glass. Nothing above it moves.

export interface CityGoodRow {
  code: string
  name: string
  category: string
  units: number
  /** The city's market row for the good, or null where it keeps none. */
  row: MarketGood | null
  /** The side's price, or null ("—"). */
  price: number | null
}

export function CityGoods({
  side,
  city,
  docked,
  quay,
  rows,
  picked,
  onPick,
  detail,
}: {
  side: 'buy' | 'sell'
  city: string | null
  docked: boolean
  quay: PortMarketState
  rows: readonly CityGoodRow[]
  picked: string | null
  onPick: (code: string | null) => void
  /** A phone: the good's page under its row. */
  detail?: (row: CityGoodRow) => ReactNode
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  if (!city) return <Hint data-testid="city-goods">{t('desk.pickCity')}</Hint>
  return (
    <div data-testid="city-goods" data-city={city} data-side={side} data-docked={docked ? 'true' : 'false'}>
      <Row
        label={
          <span className="text-t-body font-semibold" data-testid="city-goods-name">
            <PortFlag code={city} /> {portNameOf(portByCode, city)}
          </span>
        }
        value={
          <Cols>
            <Col w="sm" className="text-t-caption text-ink-faint">
              {t('desk.hold')}
            </Col>
            <Col w="sm" className="text-t-caption text-ink-faint">
              {t(side === 'buy' ? 'desk.buy' : 'desk.sell')}
            </Col>
          </Cols>
        }
        data-testid="city-goods-head"
      />
      {!docked && (
        <Hint className="mt-1" data-testid="city-goods-not-docked">
          {t('desk.notDocked')}
        </Hint>
      )}
      {side === 'buy' && quay.market === undefined ? (
        quay.refusal ? (
          <Note tone="danger" className="mt-2">
            {quay.refusal.sentence}
          </Note>
        ) : (
          Array.from({ length: 6 }, (_, i) => <Skeleton key={i} className="my-1 h-row w-full" />)
        )
      ) : rows.length === 0 ? (
        <Hint className="mt-2" data-testid="city-goods-none">
          {t(side === 'buy' ? 'desk.noBuy' : 'desk.holdEmpty')}
        </Hint>
      ) : (
        rows.map((r, i) => {
          const on = picked === r.code
          return (
            <div key={r.code}>
              <Row
                label={
                  <span className="flex items-center gap-3">
                    <Icon name={goodIcon(r.code, r.category)} size={20} className="shrink-0 text-ink-muted" />
                    <span className="min-w-0 break-words">{r.name}</span>
                  </span>
                }
                value={
                  <Cols>
                    <Col w="sm" className={r.units > 0 ? '' : 'text-ink-faint'}>
                      {r.units > 0 ? formatInt(r.units) : '—'}
                    </Col>
                    <Col w="sm" className={r.price === null ? 'text-ink-faint' : ''}>
                      <span data-testid="city-good-price">
                        {r.price === null ? (quay.market === undefined ? '…' : '—') : formatPriceFigure(r.price)}
                      </span>
                    </Col>
                  </Cols>
                }
                tone={on ? 'accent' : 'default'}
                hairline={i < rows.length - 1}
                onClick={() => onPick(on ? null : r.code)}
                aria-pressed={on}
                data-testid="city-good"
                data-good={r.code}
              />
              {on && detail?.(r)}
            </div>
          )
        })
      )}
    </div>
  )
}
