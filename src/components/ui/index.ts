// Byeharu Voyage design-system primitives — the single import surface.
// Screens import from here, never from the individual files, so the set stays one authority.
//
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SECOND HALF IS DEAD. ONE LINE OF IT IS LEFT, AND IT NAMES ITS OWN CALLER
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/UI_DIRECTION.md §7 is a ten-step migration. Step 1 rewrote the tokens under the old screens
// without moving a class string; step 2 added the twelve primitives §5 names and changed no
// screen; steps 3-9 swapped each tab whole onto the twelve. STEP 10 — done — deleted every
// deprecated export whose last caller had gone: twenty-three files, and tests/tableLayout.spec.ts
// with them. Cleanup 2 moved the surfaces a player meets before the tab shell (AuthPage,
// SignTheBook) onto the twelve and deleted eight more; the foot of this file says what is left.

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TWELVE (docs/UI_DIRECTION.md §5)
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// 1. SHEET — the one scrolling surface of a tab. Sections are separated by space and a heading,
//    never by a box. Replaces Screen + PageHeader + Card + CardHeader + SectionLabel + Collapsible.
export { Sheet, SheetSection } from './Sheet'

// 2. TRAY — the bottom-docked sheet with detents (peek 96 · half · full) that every "unfold under
//    the press" becomes. It is `fixed`, so opening one cannot move a tile. `inline` mode folds in
//    flow instead, for the half of the owner's rule that is still open. See Tray.tsx.
export { Tray, type TrayMode } from './Tray'
export { TrayTitle } from './TrayTitle'
//    Inside the COMMAND desk a docked tray stands in the desk's own slot instead (trayContext.ts).
export { DeskTraySlot, useTraySlot, type TraySlot } from './trayContext'
export {
  TRAY_DETENTS,
  TRAY_PEEK,
  detentHeight,
  nearestDetent,
  stepDetent,
  type TrayDetent,
} from './trayDetents'

// 3. CORNER — corner-anchored floating glass, foldable, max two per screen, never the centre.
export { Corner } from './Corner'
export { cornerSlotClass, type CornerSlot } from './cornerSlots'
//    POPOVER — the wide glass's small answer to "unfold under the press": a panel hung under its
//    control, out of the flow, gone on a press outside or Escape (useDismiss, the one dismissal).
//    The COMMAND desk's fleet picker (2026-10-20); on a phone the same caller mounts a Tray.
export { Popover } from './Popover'
export { useDismiss } from './useDismiss'
//    DOT — one state as an 8-px disc of a tone, beside a name (a fleet's sailing · waiting · stuck).
export { Dot, type DotTone } from './Dot'

// 4. ROW — 52px: mark · label · Figure · chevron. What a table was.
export { Row, type RowTone } from './Row'

// 5. FIGURE — value + unit, tabular, in three of the six type steps. Every number in the game.
export { Figure, type FigureSize, type FigureTone } from './Figure'
//    The tone a SIGNED figure takes — gain, loss, or plain ink at zero. One rule for every delta.
export { deltaTone } from './deltaTone'
//    THE COUNTER — the same figure, WALKING to its new value when the server's answer changes
//    (2026-10-20, owner request 188: "no number moving around"). The only motion §4.6 does not
//    forbid, and `prefers-reduced-motion` turns it off; countUp.ts holds the arithmetic.
export { Counter } from './Counter'
export { COUNT_UP_MS, countUpEase, countUpValue } from './countUp'
//    THE STAT CELL — a label, that one figure (counting), its move and its line. The dashboard
//    tile the Stats tab had hand-written fourteen times; no box, because §4.3 allows none.
export { StatCell } from './StatCell'

// 6. TILE — the selectable block, and TileField, the CSS grid it stands in.
export { Tile, TileField, type TileState } from './Tile'
//    THE FOUR TILES TWO FACES SHARE (2026-10-08, docs/NPC_TRADERS.md §8.3): a hull, a fleet's cargo
//    rows, an officer, a skill — moved out of FLEETS, the Codex and the Academy so a merchant's
//    sheet prints the SAME shapes. Pure props: the callers derive, these print.
export { ShipTile } from './ShipTile'
export { CargoRows } from './CargoRows'
export { OfficerTile } from './OfficerTile'
export { SkillTile } from './SkillTile'

// 7. BAR — one proportion, 4px, continuous or countable. Meter + Gauge + stockBar + pips, folded.
export { Bar, type BarTone } from './Bar'
//    THE STACKED BAR — one whole cut into the KINDS that make it up, with the legend that keeps
//    colour from being the only channel (the world's money by holder; the merchants' fleets).
export { StackedBar, type StackedPart } from './StackedBar'
//    RANKED BARS — a short list in order, each row's bar measured against the biggest. Six places
//    on the Stats tab asked "which of these is big" and five numbers do not answer it.
export { RankBars, type RankRow } from './RankBars'
//    SIGNED BARS — one bar a period, up for a gain and down for a loss from the one zero line.
//    The COMMAND desk's Profit idiom, promoted when the Stats tab wanted it three more times.
export { SignedBars } from './SignedBars'
//    THE CARGO BAR — `51 / 60 tons` with a staged basket washed on. One recipe for FLEETS and the
//    basket panel (PR #59 review SHOULD 4c: it had been hand-written twice).
export { CargoBar } from './CargoBar'

// 8. CHIP / SEGMENTED — one token in a set; one set of faces.
export { Chip, Segmented, type SegmentSpec } from './Chip'
export { LanguageSwitch } from './LanguageSwitch'

// 9. BUTTON — flat: primary / secondary / quiet / destructive, 44 and 36, icon.
export { Button, type ButtonTone } from './Button'

// 10. FIELD / STEPPER — the text field (and the field that opens a tray), and "how much", with the
//     owner's gauge: the slider spans the STOCK and the server's ceiling is a tick on it.
export { Field, FieldButton } from './Field'
export { Stepper } from './Stepper'

// 11. NOTE — one line, a tone, at most one action. The code goes to console.debug, never on screen.
export { Note, type NoteTone } from './Note'

// 12. HINT — the caption voice, printed rather than hidden, one per section. Long text opens a Tray.
export { Hint } from './Hint'
//     EMPTY — the empty-list well: one caption line on the quiet surface. Two panels had hand-written it.
export { Empty } from './Empty'
//     FACTS LINE — small facts under a row's label, wrapping. The fleet row and the Stats tab's rows had
//     hand-written it three times (2026-10-20).
export { FactsLine } from './FactsLine'

//     NAV — the tab rail: six cells, one row, 22px icon, no uppercase. Step 3 repoints the shell.
export { Nav, type NavItem } from './Nav'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// COMPOSITIONS OF THE TWELVE that two faces draw — docs/QUAY_LEDGER.md (owner row 76): the quay
// she lies at trades through them, and a quay she is not on is read through the same row. They
// stand here because a good may not look different on the two, and because a component that two
// trays compose (PriceRows) may not live in a screen (tests/sections.spec.ts). Like the trade fold
// they replace, they read nothing: the server's capacity answer and the act arrive as props.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

//     ACT CELL — one act on a row with the figure it is about, dead with its reason when it is.
//     TradeRow's price cell, promoted 2026-09-13 when the Storage face wanted the same box for
//     `Put in storage` / `Take on board` (owner row 88). Two callers, one box.
export { ActCell } from './ActCell'
//     BONUS ROWS — what a source adds, one row per source, the server's words on both sides. A
//     ship's skill bonuses (ShipPanel, 0133) and a fleet's crew bonuses (CrewBonuses, 0157) had
//     hand-written the same row; promoted 2026-10-18 when tests/duplication.spec.ts caught it.
export { BonusRows, type BonusRow } from './BonusRows'
//     TRADE ROW — a good with its two prices as its two acts, and the tide inside its range.
//     Replaced TRADE TILE on 2026-09-11 (one row per good; the 2026-08-26 grid rule is reversed).
export { PriceCell, TradeRow } from './TradeRow'
//     PRICE ROWS — Trend, Range and In stock, the rows under a good wherever it is unfolded; the
//     Trend row folds between the Sparkline and the PriceChart. `PriceTrend` is the shape the
//     history hook hands both trays (points + the served cadence).
export { PriceRows, type PriceTrend } from './PriceRows'
//     PRICE CHART — the sparkline unfolded: the same served line with a three-figure scale, an
//     axis in hours before now, and the low / high / now marks (owner row 76, slice 3). The
//     geometry is `priceChartModel`, pure, so tests/priceChart.spec.ts proves the axis in Node.
export { PriceChart } from './PriceChart'
export { priceChartModel, PRICE_CHART_H, PRICE_CHART_W, type PriceChartModel } from './priceChartModel'
//     SERIES CHART — one figure over time, on its own scale: the Stats tab's small multiple (0214). Three
//     faces draw it (the Overview's holders, a city's purse, the merchants' day), so it is the system's.
//     The geometry is `seriesChartModel`, pure, so tests/seriesChart.spec.ts proves the axis in Node.
export { SeriesChart, type SeriesTone, type SeriesPoint } from './SeriesChart'
export { seriesChartModel, agoLabel, nearestDot, SERIES_CHART_H, SERIES_CHART_W, type SeriesChartModel } from './seriesChartModel'
//     TRADE TRAY — the row unfolded: trend, range, stock, paid, the ceiling, the stepper, and the
//     ONE button at the bottom edge.
export { TradeTray, type TradeAct, type TradeControls, type TradePick, type TradeQuay } from './TradeTray'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// KEPT — these are not replaced by anything, and §5 says so by name
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export { Icon, IconDisc, type IconDiscTone } from './Icon'
// A NATION'S FLAG (2026-10-18) — the bundled picture for a server nation code, one 3:2 box in three
// sizes. Pure: HullCountry and PortFlag (src/live) decide WHICH nation; the chart's names draw the
// same file through `flagSrc`. Sources and licences: public/flags/SOURCES.md.
export { Flag } from './Flag'
export { flagSrc, FLAG_SIZES, type FlagSize } from './flagSrc'
export { ICON_NAMES, ICON_PATHS, type IconName } from './icons'
// A mark for a trade good, and the human spelling of its category. Every good in data/goods.json
// has its OWN drawn glyph — see goodIcons.ts for the table and for why seven was the wrong answer.
export { goodIcon, categoryLabel } from './goodIcons'
export { Skeleton } from './Skeleton'
// The two faces of THE ONE CLOCK: the real time now, and the time until a served instant —
// pure display over shellState's nowMs (see Clock.tsx). When a countdown reaches zero the caller
// re-asks the server through useReaskAtEdge; the edge idiom lives once, in reaskAtEdge.ts.
export { WallClock, Countdown } from './Clock'
export { useReaskAtEdge } from './reaskAtEdge'
// The price LINE (0013 gave the server a memory to draw one from). §5 names it `Bar.trend`
// eventually; the fold waits for the screen that needs both in one place.
export { Sparkline, type SparkTone } from './Sparkline'
export { StockGauge } from './StockGauge'
export { ChipRow } from './ChipRow'
export { sheetBodyClass, sheetColumnClass } from './screenLayout'
export { stockLevel, stockFillPct, type StockLevel } from './stockLevel'
// THE ONE READING OF "IS THIS A WIDE GLASS?" (screenLayout.ts). The Tray reads it to stand as a
// side panel; a screen reads it when what a tray MEANS differs by glass — the basket panel is
// permanent beside the column and puts itself away only on a phone (ManifestPanel.tsx).
export { useWide } from './useWide'
// WHERE A SIDE TRAY STANDS, and therefore where a chart's corner chrome has to stop (MAP's zoom
// column and Regions were drawn UNDER the merchant sheet at 1280). The table is screenLayout.ts's;
// this is the entrance a screen reads it through.
export { chromeAsideTrayClass, chromeAsideSideTrayClass } from './screenLayout'
// The one rendering of a good's SERVED rarity tier (0032): a colour token AND a shape per tier,
// so the tier survives a colourblind player and a greyscale screenshot. §5 keeps the MARK.
export { RarityMark } from './Rarity'
export { rarityLabel, RARITY_TIERS } from './rarityTiers'
// WHAT A GOOD IS, in its two served words — its kind and its rarity tier (owner row 177).
export { GoodKind } from './GoodKind'
// The served danger tier's words and thresholds (0040). The PIPS become a `<Bar of={…}>`; the
// table is data and stays.
export { dangerLabel, dangerPips, dangerTone, DANGER_PIPS, DANGER_TIERS } from './dangerTiers'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// WHAT IS LEFT OF THE DEPRECATED HALF — ONE LINE
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Step 10 deleted every deprecated export that had lost its last caller — twenty-three files. The
// ten that survived it were the exact set the twelve had not reached: AuthPage and SignTheBook
// (surfaces a player meets BEFORE the tab shell) and the chart's view controls. Cleanup 2
// (2026-10-14) moved those callers onto Sheet / Field / Note / Hint / Row and `cornerSlotClass`,
// and deleted Input, Card, Notice, PageHeader, Screen, SectionLabel, Explain (with explainState)
// and overlayLayout.
//
// Nothing new may use what is below; when its last caller goes, its line goes with it.

/** @deprecated → `Hint`, the fine-print voice. SmallChart. */
export { fineClass } from './typography'
