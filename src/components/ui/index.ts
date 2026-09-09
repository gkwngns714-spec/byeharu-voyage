// Byeharu Voyage design-system primitives — the single import surface.
// Screens import from here, never from the individual files, so the set stays one authority.
//
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THIS FILE IS IN TWO HALVES, AND THE SECOND ONE IS DYING
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/UI_DIRECTION.md §7 is a ten-step migration. Step 1 rewrote the tokens under the old screens
// without moving a class string. STEP 2 — this — adds the twelve primitives §5 names and CHANGES
// NO SCREEN. Steps 3-9 swap each screen whole, onto the twelve. Step 10 deletes everything under
// DEPRECATED below, together with its last caller.
//
// So for the length of one migration this entrance exports two vocabularies, and the comment on
// each deprecated export names the primitive that replaces it. That is deliberate and it is
// bounded: the app is never a mix of two skins on ONE SCREEN, which is the property §7 is built to
// keep — a screen is on the old set or on the new one, and it changes in a single PR.

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE TWELVE (docs/UI_DIRECTION.md §5)
// ═══════════════════════════════════════════════════════════════════════════════════════════════

// 1. SHEET — the one scrolling surface of a tab. Sections are separated by space and a heading,
//    never by a box. Replaces Screen + PageHeader + Card + CardHeader + SectionLabel + Collapsible.
export { Sheet, SheetSection } from './Sheet'

// 2. TRAY — the bottom-docked sheet with detents (peek 96 · half · full) that every "unfold under
//    the press" becomes. It is `fixed`, so opening one cannot move a tile. `inline` mode folds in
//    flow instead, for the half of the owner's rule that is still open. See Tray.tsx.
export { Tray } from './Tray'
export {
  TRAY_DETENTS,
  TRAY_PEEK,
  detentHeight,
  nearestDetent,
  stepDetent,
  type TrayDetent,
} from './trayDetents'

// 3. CORNER — corner-anchored floating glass, foldable, max two per screen, never the centre.
export { Corner, type CornerSlot } from './Corner'

// 4. ROW — 52px: mark · label · Figure · chevron. What a table was.
export { Row, type RowTone } from './Row'

// 5. FIGURE — value + unit, tabular, in three of the six type steps. Every number in the game.
export { Figure, type FigureSize, type FigureTone } from './Figure'

// 6. TILE — the selectable block, and TileField, the CSS grid it stands in.
export { Tile, TileField, type TileState } from './Tile'

// 7. BAR — one proportion, 4px, continuous or countable. Meter + Gauge + stockBar + pips, folded.
export { Bar, type BarTone } from './Bar'

// 8. CHIP / SEGMENTED — one token in a set; one set of faces.
export { Chip, Segmented, type SegmentSpec } from './Chip'

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

//     NAV — the tab rail: six cells, one row, 22px icon, no uppercase. Step 3 repoints the shell.
export { Nav, type NavItem } from './Nav'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// KEPT — these are not replaced by anything, and §5 says so by name
// ═══════════════════════════════════════════════════════════════════════════════════════════════

export { Icon } from './Icon'
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
// The one rendering of a good's SERVED rarity tier (0032): a colour token AND a shape per tier,
// so the tier survives a colourblind player and a greyscale screenshot. §5 keeps the MARK.
export { RarityMark } from './Rarity'
export { rarityLabel, RARITY_TIERS } from './rarityTiers'
// The served danger tier's words and thresholds (0040). The PIPS become a `<Bar of={…}>`; the
// table is data and stays.
export { dangerLabel, dangerPips, dangerTone, DANGER_PIPS, DANGER_TIERS } from './dangerTiers'

// ═══════════════════════════════════════════════════════════════════════════════════════════════
// DEPRECATED — step 10 deletes each of these with its last caller. Nothing new may use them.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

/** @deprecated → `Field`. */
export { Input } from './Input'
/** @deprecated → `Button` / `Chip`. Still the one author of the legacy chip look (Button.tsx). */
export { buttonClasses, type ButtonVariant, type ButtonSize } from './buttonStyles'
/** @deprecated → `Hint` (fine print), `Row` (label · value), `Sheet` (the head row), `Figure`. */
export { fineClass, rowLinkClass, headRowClass, inlineFigureClass } from './typography'
/** @deprecated → `Sheet` + `SheetSection`. A card is a box, and §4.3 forbids a box. */
export { Card, CardHeader, type CardTone } from './Card'
/** @deprecated → `Note`. Twenty-one status badges is §2 item 5's count. */
export { Badge, type BadgeTone } from './Badge'
/** @deprecated → `Bar`. */
export { Meter, type MeterTone } from './Meter'
/** @deprecated → `Bar` with `of`. */
export { Gauge, type GaugeTone } from './Gauge'
/** @deprecated → `Note`. */
export { Notice, type NoticeTone } from './Notice'
/** @deprecated → `Note` with a `Bar` as its figure; the code goes to console.debug. */
export { RefusalNote } from './RefusalNote'
/** @deprecated → `SheetSection`'s heading. §2 item 15: 31 uppercase letter-spaced labels. */
export { SectionLabel } from './SectionLabel'
/** @deprecated → `Sheet`'s own title. */
export { PageHeader } from './PageHeader'
/** @deprecated → `Figure` at `size="hero"`. */
export { HeroFigure } from './HeroFigure'
/** @deprecated → `Row`. */
export { StatRow } from './StatRow'
/** @deprecated → a `Tray` of `Row`s. */
export { StatLegend, type StatLegendItem } from './StatLegend'
/** @deprecated → `Row`. */
export { DetailRow } from './DetailRow'
/** @deprecated → `Sheet`. */
export { Screen } from './Screen'
/** @deprecated → `Sheet`. The two-pane split dies with the rail it laid out (§2 item 2). */
export { screenBodyClass, splitClass, splitMainClass, splitRailClass } from './screenLayout'
/** @deprecated → one `Row` of `ink-3` text. */
export { EmptyState } from './EmptyState'
/** @deprecated → `Row`. With it goes the whole survive-a-phone apparatus below. */
export { Table, TH, TD } from './Table'
/** @deprecated → `Row`. A row does not scroll sideways. */
export { scrollTableClass, TABLE_SCROLL_HINT } from './tableLayout'
/** @deprecated → `Row` / `Segmented`. */
export { hScrollClass, HSCROLL_HINT } from './scrollAffordance'
/** @deprecated → nothing. Nothing measures its own clipping once nothing clips. */
export { useClipped } from './useClipped'
/** @deprecated → `Segmented`. Seven faces wrapped to two rows at 390px (§2 item 9). */
export { TabRow, type TabSpec } from './TabRow'
/** @deprecated → `Corner` (top slots) / `Tray` (the bottom slot). */
export { OverlayPanel } from './OverlayPanel'
/** @deprecated → `Corner`. */
export {
  overlayPanelClass,
  overlaySlotClass,
  OVERLAY_SLOTS,
  type OverlaySlot,
  type OverlayTone,
} from './overlayLayout'
/** @deprecated → `Tile`. */
export { EntryTile, EntryTileLine, type EntryTileTap } from './EntryTile'
/** @deprecated → `Tile`. */
export { GoodTile } from './GoodTile'
/** @deprecated → `TileField`. The grid is CSS; nothing needs to know where a row ends any more. */
export { tileFieldClass, tileFieldCols, TILE_FIELD, type TileFieldStep } from './tileLayout'
/** @deprecated → `TileField`. */
export { useTileCols } from './useTileCols'
/** @deprecated → `Bar` with `of`. */
export { DangerMark } from './DangerMark'
/** @deprecated → `Tray`. */
export { Collapsible, CollapsibleCard } from './Collapsible'
/** @deprecated → `Hint`, and a `Tray` when the text is genuinely long. 81 ⓘ dots (§2 item 5). */
export { Explain, ExplainDot, ExplainPanel } from './Explain'
/** @deprecated → `Hint`. */
export { useExplainDisclosure, type ExplainDisclosure } from './explainState'
/** @deprecated → `Tile` + `TileField` + `Tray`. The trade fold, 2026-09-01. */
export { GoodPicker, QtyPicker, FilterBox, TruncationNote } from './tradePickers'
/** @deprecated → nothing: with a docked `Tray` there is no fold to place after a row. */
export { inRowsOf } from './inRows'
