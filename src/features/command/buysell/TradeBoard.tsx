import { useMemo, type ReactNode } from 'react'
import { Hint, Note, ScrollPane, Skeleton, TileChoice, TileGrid } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { TradeCard } from '../../../live/TradeCard'
import { portNameOf, useWorld } from '../../../live/worldStore'
import { haversineNm } from '../../../lib/geo/greatCircle'
import { sailOrigin } from '../../../domain/passage'
import { useT } from '../../../lib/i18n'
import type { BestSale, FleetView } from '../../../lib/rpc'
import type { PortMarketState } from '../../../live/usePortMarket'
import type { TradeGoodRow } from '../../../domain/market'

// THE COMBINED TRADE BOARD (owner 2026-10-30: *"removing the map, just have combined buy and sell tab with trade
// goods when docked"*) — the city in hand's goods in ONE list, each row showing the city's ASK (Buy) and BID (Sell)
// side by side, so a trade is one press, not a face turn. It replaced the mirrored Buy / Sell cards
// (CityBoard.tsx, deleted 2026-10-30 — one board, not two).
//
//   CITY CHIPS  a short strip of the harbours nearest her, for a thumb that misses on the small map — names only,
//               never a price: what a city pays is found by pressing it (owner row 229, no cross-city list on Buy).
//               The short strip of nearest harbours CityBoard drew. `CityChips` below: on a phone it stands at the head
//               of the board; on the wide desk Trade.tsx stands it in the left pane, the cards alone in the centre.
//   CARDS       ONE card per good: its icon and name, BOTH prices (the city's ask on the left, its bid on the right),
//               ▲▼ against a day ago, the day's line, and her units aboard. At a city she is NOT at, a carried good
//               its quay does not list is bid for by world.price_why — the server buys it there all the same (owner
//               row 231: "i can't sell because i can't dock").
//   BEST SALE   0348 (owner row 307): under the prices, the good's best sale from the city in hand — the city and the
//               served PROFIT (world.best_sales: ONE read for the board, never one per card — Trade.tsx asks it). Green
//               when it pays, red "No gain" when no city she can sail to pays. A press opens the trip to that city at
//               the units the figure was priced for, so the tray's first figure is the card's.
//
// The rows are domain/market/tradeRows.ts — a pure function; the card is live/TradeCard.tsx (the HQ Market draws it too),
// so this file holds only the board and the strip.

/** ▲ +3.2 % / ▼ 1.4 % — green up, red down, nothing else coloured (owner row 229). */
export function DayChange({ change, className = '' }: { change: number | null; className?: string }) {
  if (change === null) return <span className={`text-t-caption text-ink-faint ${className}`}>—</span>
  const pts = Math.abs(change * 100)
  if (pts < 0.05) return <span className={`text-t-caption tabular-nums text-ink-faint ${className}`}>0.0%</span>
  const up = change > 0
  return (
    <span className={`whitespace-nowrap text-t-caption tabular-nums ${up ? 'text-success' : 'text-danger'} ${className}`} data-testid="day-change" data-dir={up ? 'up' : 'down'}>
      {up ? '▲' : '▼'} {formatFixed(pts, 1)}%
    </span>
  )
}

function formatFixed(pts: number, d: number) {
  return pts.toFixed(d)
}

/** How many harbours the chip strip names — a short strip, not a directory. */
const CHIPS = 8

/** THE CITY PICKER: the city in hand, where she lies, then the harbours nearest where she departs from.
 *
 *  A GRID THAT KEEPS ITS WORDS (2026-11-11; components/ui/tileStyles.ts): three columns on a phone, two in the wide desk's left
 *  pane. Four columns at 390 px left a name 41 px, so "Lisbon" broke inside the word. A name here wraps only at its spaces and is
 *  never cut; a cell whose longest word is wider than a column is as wide as that word. tests/trade.layout.spec.ts measures it
 *  for every port name the world has, in English and Korean. */
export function CityChips({ fleet, city, onCity }: { fleet: FleetView; city: string | null; onCity: (code: string) => void }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const ports = useWorld((s) => s.snapshot?.ports)
  const chips = useMemo(() => {
    const from = sailOrigin(fleet, portByCode)
    // harbours only: a sea place (a cape, a strait) keeps no market
    const harbours = (ports ?? []).filter((p) => p.kind !== 'SEA_PLACE')
    const near = from ? [...harbours].sort((a, b) => haversineNm(from, a) - haversineNm(from, b)).map((p) => p.code) : harbours.map((p) => p.code)
    const head = [fleet.status === 'DOCKED' ? fleet.port : null, city].filter((c): c is string => !!c)
    return [...new Set([...head, ...near])].slice(0, CHIPS)
  }, [fleet, portByCode, ports, city])
  return (
    // THE CITY PICKER IS A GRID (owner, 2026-10-31) — equal cells on fixed columns, in the same nearest-first order; a flag and
    // a name per cell, never a ragged strip.
    <TileGrid label={t('desk.cityChips')} words={3} wordsWide={2} className="mb-2" data-testid="city-chips">
      {chips.map((c) => (
        <TileChoice key={c} on={c === city} onClick={() => onCity(c)} data-testid="city-chip" data-port={c}>
          {/* one child: the flag and the name stay ONE group, centred. No `truncate` and no break inside a word: a long
              harbour wraps at its spaces (tests/align.spec.ts's CUT rule, tests/trade.layout.spec.ts). */}
          <span className="flex items-center gap-1">
            <PortFlag code={c} /> <span data-testid="city-chip-name">{portNameOf(portByCode, c)}</span>
          </span>
        </TileChoice>
      ))}
    </TileGrid>
  )
}

export function TradeBoard({
  strip,
  city,
  docked,
  quay,
  rows,
  picked,
  onBuy,
  onSell,
  sales,
  onBest,
}: {
  /** The city picker (`CityChips`) at the head of the board, on a phone; the wide desk stands it in its left pane instead. */
  strip?: ReactNode
  /** The city in hand (port CODE); the board reads its market. */
  city: string | null
  /** She lies at the city in hand. */
  docked: boolean
  quay: PortMarketState
  rows: readonly TradeGoodRow[]
  /** The good whose panel is open. */
  picked: string | null
  onBuy: (code: string) => void
  onSell: (code: string) => void
  /** 0348: each good's best sale from the city in hand, by good CODE; null while it has not landed. */
  sales: ReadonlyMap<string, BestSale> | null
  onBest: (sale: BestSale) => void
}) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const portId = city ? (portByCode[city]?.id ?? null) : null

  return (
    <div data-testid="trade-board" data-city={city ?? ''} data-docked={docked ? 'true' : 'false'}>
      {strip}
      {!city ? (
        <Hint>{t('desk.pickCity')}</Hint>
      ) : (
        <>
          {/* where she lies, the strip's lit chip says it all; anywhere else the city is named, "Not docked" */}
          {!docked && (
            <div className="mb-2 flex flex-wrap items-baseline gap-x-2" data-testid="trade-board-head">
              <span className="text-t-body font-semibold text-ink" data-testid="trade-board-name">
                <PortFlag code={city} /> {portNameOf(portByCode, city)}
              </span>
              <span className="text-t-caption text-ink-faint" data-testid="trade-board-not-docked">
                {t('desk.notDocked')}
              </span>
            </div>
          )}
          {quay.market === undefined ? (
            quay.refusal ? (
              <Note tone="danger">{quay.refusal.sentence}</Note>
            ) : (
              <div className="grid grid-cols-2 gap-2 lg:grid-cols-[repeat(auto-fill,minmax(min(100%,9.5rem),1fr))]">
                {Array.from({ length: 6 }, (_, i) => (
                  <Skeleton key={i} className="h-28 w-full" />
                ))}
              </div>
            )
          ) : rows.length === 0 ? (
            <Hint data-testid="trade-board-empty">{t('desk.noBuy')}</Hint>
          ) : (
            // THE CARDS ARE THE ONE LONG LIST ON THIS FACE: at a busy quay they run past the
            // glass, so they scroll inside their own bounded pane (the page above stays put).
            // From lg the desk's centre pane is already the scroller — no second bound there.
            // THE BOUND HOLDS ONE WHOLE ROW OF CARDS (10.5 rem = 168 px; a card is 165-166 px since its best sale's city
            // is printed whole). At 9 rem (sized for the 151-px card) the row's Buy and Sell buttons stood 13 px under the
            // pane's edge, so a press on one first scrolled the cards 13 px (tests/desk.layout.spec.ts, "a press … moved the cards").
            <ScrollPane className="max-h-[10.5rem] lg:max-h-none">
              <div className="grid grid-cols-2 gap-2 lg:grid-cols-[repeat(auto-fill,minmax(min(100%,9.5rem),1fr))]">
                {rows.map((r) => (
                  <TradeCard
                    key={r.code}
                    portId={portId}
                    r={r}
                    docked={docked}
                    on={picked === r.code}
                    onBuy={onBuy}
                    onSell={onSell}
                    sale={sales?.get(r.code)}
                    onBest={onBest}
                  />
                ))}
              </div>
            </ScrollPane>
          )}
        </>
      )}
    </div>
  )
}
