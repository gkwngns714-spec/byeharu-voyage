import { useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type ReactNode, type RefObject } from 'react'
import { FlagSlot, Hint, Note, ScrollPane, Skeleton, TileChoice, TileGrid } from '../../../components/ui'
import { PortFlag } from '../../../live/PortFlag'
import { TradeCard } from '../../../live/TradeCard'
import { portNameOf, portNationOf, useWorld } from '../../../live/worldStore'
import { haversineNm } from '../../../lib/geo/greatCircle'
import { useT } from '../../../lib/i18n'
import type { BestSale } from '../../../lib/rpc'
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

/** ▲ +3.2 % / ▼ 1.4 % — green when the move is good for her, red when it is bad, nothing else coloured (owner row 229). Selling, a rise
 *  is good; BUYING, a fall is (2026-11-22 play-test: a red "▼ 57.7%" stood beside a cheap price on the buy sheet). */
export function DayChange({ change, side = 'sell', className = '' }: { change: number | null; side?: 'buy' | 'sell'; className?: string }) {
  if (change === null) return <span className={`text-t-caption text-ink-faint ${className}`}>—</span>
  const pts = Math.abs(change * 100)
  if (pts < 0.05) return <span className={`text-t-caption tabular-nums text-ink-faint ${className}`}>0.0%</span>
  const up = change > 0
  const good = up === (side === 'sell')
  return (
    <span className={`whitespace-nowrap text-t-caption tabular-nums ${good ? 'text-success' : 'text-danger'} ${className}`} data-testid="day-change" data-dir={up ? 'up' : 'down'}>
      {up ? '▲' : '▼'} {formatFixed(pts, 1)}%
    </span>
  )
}

function formatFixed(pts: number, d: number) {
  return pts.toFixed(d)
}

/** How many harbours the chip strip names — a short strip, not a directory. */
const CHIPS = 8

/** THE CITY PICKER: where she lies (under way: the city she is bound for), then the harbours nearest it.
 *
 *  A GRID THAT KEEPS ITS WORDS (2026-11-11; components/ui/tileStyles.ts): three columns on a phone, two in the wide desk's left
 *  pane. Four columns at 390 px left a name 41 px, so "Lisbon" broke inside the word. A name here wraps only at its spaces and is
 *  never cut; a cell whose longest word is wider than a column is as wide as that word. tests/trade.layout.spec.ts measures it
 *  for every port name the world has, in English and Korean.
 *
 *  A PRESS MOVES NO CHIP (2026-11-11, the trade-flow slice). The pressed city used to be put in the second cell, so the cell
 *  under the thumb changed its name as it was pressed, and the list was sorted again from each leg's end as she sailed. The
 *  order is now a fact of HER PLACE alone (`home`: her port, or under way her destination — the same city on every leg and
 *  after she lands), nearest first, and the city in hand is only MARKED. A city in hand that is not one of the nearest (pressed
 *  on the map, or a cargo row's far city) takes the LAST cell, so the count and every other cell stay as they were. */
export function CityChips({ home, city, onCity }: { home: string | null; city: string | null; onCity: (code: string) => void }) {
  const t = useT()
  const portByCode = useWorld((s) => s.portByCode)
  const ports = useWorld((s) => s.snapshot?.ports)
  const near = useMemo(() => {
    // nearest to the harbour itself: which harbours are her neighbours is a fact of the map, not of a course
    const from = home ? (portByCode[home] ?? null) : null
    // harbours only: a sea place (a cape, a strait) keeps no market
    const harbours = (ports ?? []).filter((p) => p.kind !== 'SEA_PLACE')
    const sorted = from ? [...harbours].sort((a, b) => haversineNm(from, a) - haversineNm(from, b)).map((p) => p.code) : harbours.map((p) => p.code)
    return [...new Set([...(home ? [home] : []), ...sorted])].slice(0, CHIPS)
  }, [home, portByCode, ports])
  const chips = city && !near.includes(city) ? [...near.slice(0, CHIPS - 1), city] : near
  return (
    // THE CITY PICKER IS A GRID (owner, 2026-10-31) — equal cells on fixed columns, in the same nearest-first order; a flag and
    // a name per cell, never a ragged strip.
    <TileGrid label={t('desk.cityChips')} words={3} wordsWide={2} className="mb-2" data-testid="city-chips">
      {chips.map((c) => (
        <TileChoice key={c} on={c === city} onClick={() => onCity(c)} className="flex-col gap-0.5 py-0.5!" data-testid="city-chip" data-port={c}>
          {/* A FLAG TILE (2026-11-23, the visual overhaul's slice 3): the city's flag leads, 20 px, over its name in the caption
              voice, so the eight cells read as eight flags before they read as words. A free town keeps the flag's room empty
              (FlagSlot), so every name stands on one line across the grid. No `truncate` and no break inside a word: a long
              harbour takes two columns or wraps at its spaces (tests/align.spec.ts's CUT rule, tests/trade.layout.spec.ts). */}
          <CityFlag code={c} />
          <span data-testid="city-chip-name">{portNameOf(portByCode, c)}</span>
        </TileChoice>
      ))}
    </TileGrid>
  )
}

/** A city tile's flag: the nation's, or the room it takes, empty (a free town). */
function CityFlag({ code }: { code: string }) {
  const allegiance = useWorld((s) => s.allegiance)
  return portNationOf(allegiance, code)?.nation ? <PortFlag code={code} size="title" /> : <FlagSlot size="title" />
}

/** THE GOODS CARDS' GRID: two to a line on a phone; from lg as many 9.5-rem cards as the desk's centre pane holds.
 *
 *  FOUR TO A LINE FROM 1,280 TO 1,600 PX (2026-11-13, owner row 318). There the pane held two (1,280) or three (1,440) of the
 *  9.5-rem cards, so a quay's ten cards stood on five or four lines and the pane scrolled (934 px in 626 at 1,280 × 800). Four
 *  to a line is three lines and no scrolling. A card is then about 120 px (the HQ Market's card on a 320-px glass is 123), and a
 *  column is NEVER NARROWER THAN ITS WIDEST CARD'S WORDS (`min-content`): the one Korean city name longer than that
 *  (산타크루스데테네리페, 120 px of letters) makes its own column wider and the other three give the room, so no name is cut
 *  or stands out of its card (the card's own column keeps its words at these widths too: `SALE_COLUMN`,
 *  live/TradeCard.tsx). The gap is 6 px there, not 8: a Korean card's Buy and Sell need 120 px, and four of them with 8-px
 *  gaps were 504 px in the pane's 502 (it scrolled 2 px sideways). From 1,600 px the pane holds four or more 9.5-rem cards by itself, as before. */
const CARDS_GRID =
  'grid grid-cols-2 gap-2 lg:grid-cols-[repeat(auto-fill,minmax(min(100%,9.5rem),1fr))] xl:grid-cols-[repeat(var(--cols,4),minmax(min-content,1fr))] xl:gap-1.5 min-[100rem]:gap-2 min-[100rem]:grid-cols-[repeat(auto-fill,minmax(min(100%,9.5rem),1fr))]'

/** The height of the cards' first row, measured: the first card is as tall as its row (the four lines are the grid's own subgrid).
 *  Null until the first layout. Re-read whenever the grid or its first card is resized, and when another good leads the list. */
function useFirstRowBound(grid: RefObject<HTMLElement | null>, lead: string | null): number | null {
  const [height, setHeight] = useState<number | null>(null)
  useEffect(() => {
    const box = grid.current
    const first = box?.firstElementChild
    if (!box || !first) return
    const read = () => setHeight(Math.ceil(first.getBoundingClientRect().height))
    const observer = new ResizeObserver(read)
    observer.observe(box)
    observer.observe(first)
    read()
    return () => observer.disconnect()
  }, [grid, lead])
  return height
}

/** FOUR TO A LINE, UNLESS THE WORDS DO NOT FIT (the owner's law: nothing scrolls sideways; a row wraps to a new line instead).
 *  Where the board stands its cards four to a line (`CARDS_GRID`, 1,280 to 1,600 px) each column is never narrower than its
 *  widest card's words, and two long city names in two columns together are wider than the pane (a Korean 산루카르데바라메다 is
 *  117 px: 133-px columns, four of them in a 502-px pane). The grid then stands one card fewer to a line, down to two, and the
 *  line the card leaves wraps to the next: no name is cut or broken. Set on the grid as `--cols`, before paint, from what the
 *  pane measures; it is re-read when the pane is resized or any word in the cards changes. */
function useFitColumns(pane: RefObject<HTMLElement | null>, grid: RefObject<HTMLElement | null>, cards: number) {
  useLayoutEffect(() => {
    const box = pane.current
    const cardBox = grid.current
    if (!box || !cardBox) return
    const fit = () => {
      for (let cols = 4; cols >= 2; cols--) {
        cardBox.style.setProperty('--cols', String(cols))
        if (box.scrollWidth <= box.clientWidth + 1) break
      }
    }
    fit()
    // the pane changes size, or a word in a card changes (a name is what makes a column wide)
    const resized = new ResizeObserver(fit)
    resized.observe(box)
    const worded = new MutationObserver(fit)
    worded.observe(cardBox, { subtree: true, childList: true, characterData: true })
    return () => {
      resized.disconnect()
      worded.disconnect()
    }
    // (the pane stands only once the quay has goods: the effect runs again when their number changes)
  }, [pane, grid, cards])
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
  const gridRef = useRef<HTMLDivElement>(null)
  const paneRef = useRef<HTMLDivElement>(null)
  const firstRow = useFirstRowBound(gridRef, rows[0]?.code ?? null)
  useFitColumns(paneRef, gridRef, rows.length)

  return (
    <div data-testid="trade-board" data-city={city ?? ''} data-docked={docked ? 'true' : 'false'}>
      {strip}
      {!city ? (
        <Hint>{t('desk.pickCity')}</Hint>
      ) : (
        <>
          {/* THE BOARD'S OWN LINE, ALWAYS IN ITS PLACE (2026-11-11, the trade-flow slice): whose goods these are, and whether
              she lies there. It stood only where she did not lie, so pressing another city pushed every card 30 px down and
              pressing her own pulled them back up. */}
          {/* FROM lg ONLY: a phone has no line for it (tests/onepage.spec.ts leaves this face 22 px), so there the same words
              stand beside her name (TradeStatus.tsx, compact) and no line comes or goes above the cards at all. */}
          <div className="mb-2 hidden min-h-6 flex-wrap items-baseline gap-x-2 lg:flex" data-testid="trade-board-head">
            <span className="text-t-body font-semibold text-ink" data-testid="trade-board-name">
              <PortFlag code={city} /> {portNameOf(portByCode, city)}
            </span>
            <span className="text-t-caption text-ink-faint" data-testid={docked ? 'trade-board-docked' : 'trade-board-not-docked'}>
              {t(docked ? 'desk.docked' : 'desk.notDocked')}
            </span>
          </div>
          {quay.market === undefined ? (
            quay.refusal ? (
              <Note tone="danger">{quay.refusal.sentence}</Note>
            ) : (
              // on a phone no taller than the one row of cards it stands for: it pushed all under it 152 px down on a city press
              <div className={`max-h-[12.5rem] overflow-hidden lg:max-h-none ${CARDS_GRID}`}>
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
            // THE BOUND HOLDS ONE WHOLE ROW OF CARDS, MEASURED (`useFirstRowBound`): a card's height is the data's, not a constant
            // (a best sale's city or its hours that run a second line make the whole row taller: 165, 174, 190 px seen). At a
            // fixed 10.5 rem the row's Buy and Sell stood under the pane's edge and a press on one first scrolled the cards
            // (tests/desk.layout.spec.ts, "a press … moved the cards": run 44507902138, 6 px). 10.5 rem is only the bound before
            // the first measure.
            // THE NEXT ROW PEEKS (2026-11-22 second play-test: "two cards of ten in view, no sign that the pane scrolls"). Where more cards
            // stand under the first row, the bound is one row and 1 rem more: the row gap and the top of the next two cards show, so the
            // list reads as one that goes on. The first row's Buy and Sell stay wholly inside the pane (a press never scrolls it).
            <ScrollPane
              paneRef={paneRef}
              className={`${rows.length > 2 ? 'max-h-[calc(var(--first-row,10.5rem)+1rem)]' : 'max-h-[var(--first-row,10.5rem)]'} lg:max-h-none`}
              style={{ '--first-row': firstRow ? `${firstRow}px` : undefined } as CSSProperties}
              data-testid="trade-cards-pane"
            >
              <div ref={gridRef} className={CARDS_GRID}>
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
