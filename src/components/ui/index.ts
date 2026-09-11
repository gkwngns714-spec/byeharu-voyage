// Byeharu Voyage design-system primitives — the single import surface.
// Screens import from here, never from the individual files, so the set stays one authority.
//
// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SECOND HALF IS DEAD. TEN LINES OF IT ARE LEFT, AND EACH ONE NAMES ITS OWN SCREEN
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// docs/UI_DIRECTION.md §7 is a ten-step migration. Step 1 rewrote the tokens under the old screens
// without moving a class string; step 2 added the twelve primitives §5 names and changed no
// screen; steps 3-9 swapped each tab whole onto the twelve. STEP 10 — done — deleted every
// deprecated export whose last caller had gone: twenty-three files, and tests/tableLayout.spec.ts
// with them.
//
// What survives at the foot of this file is the ten the twelve have NOT reached, and eight of them
// are on the three surfaces a player meets before the tab shell — AuthPage, SignTheBook, WorldGate
// — which the migration never covered because it walked the TABS. The property §7 was built to
// keep still holds and is why the remainder is safe: the app is never a mix of two skins on ONE
// screen. A screen is on the old set or on the new one, and it changes in a single PR.

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
//    The tone a SIGNED figure takes — gain, loss, or plain ink at zero. One rule for every delta.
export { deltaTone } from './deltaTone'

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
// COMPOSITIONS OF THE TWELVE that two faces draw — docs/QUAY_LEDGER.md (owner row 76): the quay
// she lies at trades through them, and a quay she is not on is read through the same row. They
// stand here because a good may not look different on the two, and because a component that two
// trays compose (PriceRows) may not live in a screen (tests/sections.spec.ts). Like the trade fold
// they replace, they read nothing: the server's capacity answer and the act arrive as props.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

//     TRADE ROW — a good with its two prices as its two acts, and the tide inside its range.
//     Replaced TRADE TILE on 2026-09-11 (one row per good; the 2026-08-26 grid rule is reversed).
export { TradeRow } from './TradeRow'
//     PRICE ROWS — Trend and Range, the two rows under a good wherever it is unfolded.
export { PriceRows } from './PriceRows'
//     TRADE TRAY — the row unfolded: trend, range, stock, paid, the ceiling, the stepper, and the
//     ONE button at the bottom edge.
export { TradeTray, type TradeAct, type TradeControls, type TradePick, type TradeQuay } from './TradeTray'

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
// WHAT IS LEFT OF THE DEPRECATED HALF, AFTER STEP 10
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// Step 10 deleted every deprecated export that had lost its last caller — twenty-three files, and
// tests/tableLayout.spec.ts with them, because that spec existed only to guard Table.tsx's
// `w-full`. The header above this one used to say the second half was dying. It has died.
//
// What is below is NOT a leftover vocabulary. It is the exact set the twelve have not reached, and
// every line names the screen that still holds it. Eight of the ten live on AuthPage, SignTheBook
// and WorldGate — the three surfaces a player meets BEFORE the tab shell, which the §7 migration
// never covered because it walked the tabs. That is the next step's list, written as code rather
// than as a plan, so it cannot go stale: when a caller goes, its line goes with it.
//
// Nothing new may use any of them.

/** @deprecated → `Field`. AuthPage, SignTheBook. */
export { Input } from './Input'
/** @deprecated → `Hint`, the fine-print voice. SmallChart, SignTheBook. */
export { fineClass } from './typography'
/** @deprecated → `Sheet` + `SheetSection`. A card is a box, and §4.3 forbids a box. AuthPage, SignTheBook, WorldGate. */
export { Card, CardHeader } from './Card'
/** @deprecated → `Note`. AuthPage, SignTheBook, WorldGate. */
export { Notice } from './Notice'
/** @deprecated → `Sheet`'s own title. SignTheBook, WorldGate. */
export { PageHeader } from './PageHeader'
/** @deprecated → `Sheet`. SignTheBook, WorldGate. */
export { Screen } from './Screen'
/** @deprecated → `SheetSection`'s heading. WorldGate. */
export { SectionLabel } from './SectionLabel'
/** @deprecated → `Hint`, and a `Tray` when the text is genuinely long. WorldGate. */
export { Explain } from './Explain'
/** @deprecated → `Corner`. The chart's view controls read the corner table straight. ViewControls. */
export { overlaySlotClass } from './overlayLayout'
