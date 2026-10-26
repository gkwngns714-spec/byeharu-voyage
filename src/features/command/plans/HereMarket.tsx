import { useMemo } from 'react'
import { Col, Cols, Hint, Icon, Note, Row, Skeleton, goodIcon } from '../../../components/ui'
import { fleetCargoByCode } from '../../../domain/fleet'
import { buyableHere } from '../../../domain/market'
import { PortFlag } from '../../../live/PortFlag'
import { usePortMarket } from '../../../live/usePortMarket'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { formatInt, formatPriceFigure } from '../../../lib/format'
import type { FleetView, MarketGood, SnapshotGood } from '../../../lib/rpc'
import { useT } from '../../../lib/i18n'

// HERE — THE PORT'S MARKET (owner row 210, 2026-10-26: *"the command trade- Here part, i dont get it. its either
// sell or buy, and yet nothing works. it should show my cargo, sell and buy prices at the center. thats it right?
// why is there days, supplies?"*). The centre pane on Trade › Here: ONE list — every good this port trades and
// every good in her cargo — each row the good, the units aboard, this port's BUY price (the ask) and SELL price
// (the bid; "—" where the port has no row for it), and the two presses that trade RIGHT HERE. No days, no
// supplies, no sell cities: those are the trip's, and the trip is Cargo's (TradeStart.tsx → the card).
//
// NOTHING ABOUT THE ACT IS HERE. A press hands (good, side) to the caller, which opens THE trade tray
// (markets/DeskTrade.tsx, the desk's one trade doorway: the ceiling, the count, the dry run, the one door) — the same
// tray the Markets face and the quay open. The prices are world.market's (usePortMarket, the read the quay
// makes); which goods can be bought is `buyableHere` (domain/market, 0061), never a field tested here.
//
// AT SEA the rows are the NEXT port's prices, read-only: "Not docked", and no presses (a BUY or SELL happens
// where she lies — COMMAND_DESK §2.1).

export interface HerePick {
  code: string
  intent: 'buy' | 'sell'
}

export function HereMarket({ fleet, pick, onPick }: { fleet: FleetView; pick: HerePick | null; onPick: (pick: HerePick) => void }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const goodByCode = useWorld((s) => s.goodByCode)
  const docked = fleet.status === 'DOCKED' ? fleet.port : null
  const portCode = docked ?? fleet.voyage?.to ?? null
  const quay = usePortMarket(portCode ? (portByCode[portCode]?.id ?? null) : null)
  const aboard = useMemo(() => fleetCargoByCode(fleet), [fleet])

  // THE ROWS: this port's goods it trades (buyableHere), plus every good aboard — with this port's row when it has
  // one (0061 serves a carried good's row so it can be sold), else none ("—", nothing to press).
  const rows = useMemo(() => {
    const market = quay.market?.goods ?? []
    const byCode = new Map(market.map((g) => [g.code, g]))
    const codes = new Set([...market.filter((g) => buyableHere(g)).map((g) => g.code), ...Object.keys(aboard).filter((c) => (aboard[c] ?? 0) > 0)])
    return [...codes]
      .map((code) => ({ good: goodByCode[code] ?? null, row: byCode.get(code) ?? null, units: aboard[code] ?? 0 }))
      .filter((r): r is { good: SnapshotGood; row: MarketGood | null; units: number } => r.good !== null)
      .sort((a, b) => a.good.name.localeCompare(b.good.name))
  }, [quay.market, aboard, goodByCode])

  if (!portCode) return <Hint data-testid="here-market">{t('desk.hereNone')}</Hint>
  return (
    <div data-testid="here-market" data-docked={docked ? 'true' : 'false'}>
      {/* THE HEAD: which port, and the three columns' names over the columns themselves. */}
      <Row
        label={
          <span className="text-t-body font-semibold">
            <PortFlag code={portCode} /> {portNameOf(portByCode, portCode)}
          </span>
        }
        value={
          <Cols>
            <Col w="sm" className="text-t-caption text-ink-faint">
              {t('desk.hold')}
            </Col>
            <Col w="sm" className="text-t-caption text-ink-faint">
              {t('desk.buy')}
            </Col>
            <Col w="sm" className="text-t-caption text-ink-faint">
              {t('desk.sell')}
            </Col>
          </Cols>
        }
        data-testid="here-head"
      />
      {!docked && (
        <Hint className="mt-2" data-testid="here-not-docked">
          {t('desk.notDocked')}
        </Hint>
      )}
      {quay.market === undefined ? (
        quay.refusal ? (
          <Note tone="danger" className="mt-2">
            {quay.refusal.sentence}
          </Note>
        ) : (
          Array.from({ length: 6 }, (_, i) => <Skeleton key={i} className="my-1 h-row w-full" />)
        )
      ) : rows.length === 0 ? (
        <Hint className="mt-2">{t('desk.hereNone')}</Hint>
      ) : (
        rows.map((r, i) => {
          const canBuy = docked !== null && r.row !== null && buyableHere(r.row)
          const canSell = docked !== null && r.row !== null && r.units > 0
          return (
            <Row
              key={r.good.code}
              label={
                // the mark rides in the label, both centred on the 44-px price presses beside them
                <span className="flex min-h-11 items-center gap-3">
                  <Icon name={goodIcon(r.good.code, r.good.category)} size={20} className="shrink-0 text-ink-muted" />
                  <span className="min-w-0 break-words">{r.good.name}</span>
                </span>
              }
              value={
                <Cols>
                  <Col w="sm" className={r.units > 0 ? '' : 'text-ink-faint'}>
                    {r.units > 0 ? formatInt(r.units) : '—'}
                  </Col>
                  <PriceCol
                    price={r.row && buyableHere(r.row) ? r.row.buy : null}
                    live={docked !== null}
                    enabled={canBuy}
                    on={pick?.code === r.good.code && pick.intent === 'buy'}
                    label={`${t('desk.buy')} ${r.good.name}`}
                    onPress={() => onPick({ code: r.good.code, intent: 'buy' })}
                    testid="here-buy"
                  />
                  <PriceCol
                    price={r.row ? r.row.sell : null}
                    live={docked !== null}
                    enabled={canSell}
                    on={pick?.code === r.good.code && pick.intent === 'sell'}
                    label={`${t('desk.sell')} ${r.good.name}`}
                    onPress={() => onPick({ code: r.good.code, intent: 'sell' })}
                    testid="here-sell"
                  />
                </Cols>
              }
              tone={pick?.code === r.good.code ? 'accent' : 'default'}
              hairline={i < rows.length - 1}
              data-testid="here-row"
              data-good={r.good.code}
            />
          )
        })
      )}
    </div>
  )
}

/** One price, and — docked — the press that trades it here. "—" where there is no price; at sea, the figure only. */
function PriceCol({
  price,
  live,
  enabled,
  on,
  label,
  onPress,
  testid,
}: {
  price: number | null
  live: boolean
  enabled: boolean
  on: boolean
  label: string
  onPress: () => void
  testid: string
}) {
  const figure = price === null ? '—' : formatPriceFigure(price)
  if (!live || price === null) {
    return (
      <Col w="sm" className={price === null ? 'text-ink-faint' : ''}>
        <span data-testid={testid}>{figure}</span>
      </Col>
    )
  }
  return (
    <Col w="sm">
      <button
        type="button"
        onClick={onPress}
        disabled={!enabled}
        aria-pressed={on}
        aria-label={label}
        className={`min-h-11 w-full rounded-control px-1.5 text-right tabular-nums disabled:opacity-45 ${on ? 'bg-accent-soft text-accent' : 'bg-surface-2 text-ink'}`}
        data-testid={testid}
      >
        {figure}
      </button>
    </Col>
  )
}
