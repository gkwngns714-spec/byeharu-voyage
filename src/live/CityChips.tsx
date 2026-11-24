import { useMemo } from 'react'
import { FlagSlot, TileChoice, TileGrid } from '../components/ui'
import { PortFlag } from './PortFlag'
import { portNameOf, portNationOf, useWorld } from './worldStore'
import { haversineNm } from '../lib/geo/greatCircle'
import { useT } from '../lib/i18n'

// THE CITIES THE TRADE LIST CAN READ (owner row 218): her own first, then the nearest, eight cells. Here since H3 (2026-11-24):
// they stood on the Trade desk's goods board (TradeBoard.tsx), which went with the desk; HQ's Market plate draws them now
// (features/city/MarketFace.tsx).

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
