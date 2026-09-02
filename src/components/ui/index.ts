// Byeharu Voyage design-system primitives — the single import surface.
// Screens import from here, never from the individual files, so the set stays one authority.
export { Button } from './Button'
// The text field. One recipe, replacing four hand-written ones (see Input.tsx).
export { Input } from './Input'
export { buttonClasses, type ButtonVariant, type ButtonSize } from './buttonStyles'
// The text treatments this game repeats: the fine-print voice, the tappable row link, the panel
// head row, and the read figure that sits beside a bar. See typography.ts for the hand-written
// spellings each one replaces — thirty of the first, three of the second, two apiece after that.
export { fineClass, rowLinkClass, headRowClass, inlineFigureClass } from './typography'
export { Card, CardHeader, type CardTone } from './Card'
export { Badge, type BadgeTone } from './Badge'
// PriceIndex — the %NBR pill — was REMOVED in 0071 along with the number it rendered. It drew a
// comparison between this quay and its neighbours, tinted by the buy/hold/sell cut of that number,
// and both are gone: that comparison is the answer the owner asked the game to make the player
// find. A component with nothing left to render is not a component to keep for later.
// The price LINE (0013 gave the server a memory to draw one from). See Sparkline.tsx for what it
// deliberately refuses to do — interpolate, scale to zero, or draw a single point.
export { Sparkline, type SparkTone } from './Sparkline'
export { Meter, type MeterTone } from './Meter'
// Meter's countable counterpart: a resource with a UNIT (tuns, days, berths) drawn as segments
// you can count, rather than as a fraction you must do arithmetic on. See Gauge.tsx.
export { Gauge, type GaugeTone } from './Gauge'
export { Notice, type NoticeTone } from './Notice'
// The one concise rendering of a refusal — bar + figures when the server serves them, the
// sentence when it does not, fixes as the caller's own buttons. See RefusalNote.tsx for the
// owner's concise-and-graphic law and the Explain boundary it amends.
export { RefusalNote } from './RefusalNote'
export { SectionLabel } from './SectionLabel'
export { PageHeader } from './PageHeader'
// SectionLabel's opposite number: the one FIGURE a block is about, drawn as the hero
// (docs/UI_DIRECTION.md §4 rule 2). See HeroFigure.tsx for the three hand-written copies it names.
export { HeroFigure } from './HeroFigure'
export { StatRow } from './StatRow'
// The "TERM (unit) — what it decides" list for the inside of an Explain panel. The words arrive
// as a parameter (domain/fleet's shipStatItems is the first supplier); this is the one chrome.
export { StatLegend, type StatLegendItem } from './StatLegend'
// StatRow's complement: the label/value row for a value that is a SENTENCE (see DetailRow.tsx for
// the boundary between them).
export { DetailRow } from './DetailRow'
export { Screen } from './Screen'
// The page scaffold, and the two-pane split a screen lays INSIDE it — a working list on the left,
// a rail of figures on the right, one column below `md`. See screenLayout.ts for why it is flex
// and not grid, why the breakpoint is `md`, and why no action may live in the rail.
export { screenBodyClass, splitClass, splitMainClass, splitRailClass } from './screenLayout'
export { EmptyState } from './EmptyState'
export { Skeleton } from './Skeleton'
export { Table, TH, TD } from './Table'
export { scrollTableClass, TABLE_SCROLL_HINT } from './tableLayout'
// The sideways-scroll affordance tables and the compendium's filter strips share: the drawn
// permanent scrollbar (one recipe) and the "is this box really clipped" measurement (one hook).
export { hScrollClass, HSCROLL_HINT } from './scrollAffordance'
export { useClipped } from './useClipped'
// The faces of ONE place — a tab strip, for a panel that has several sides rather than a
// page that has several cards (see TabRow.tsx).
export { TabRow, type TabSpec } from './TabRow'
export { OverlayPanel } from './OverlayPanel'
// FOUR CORNERS, ONE TABLE. `overlaySlotClass` is how chrome that is NOT an OverlayPanel reaches
// the same anchors — see overlayLayout.ts for the five spellings it replaced.
export {
  overlayPanelClass,
  overlaySlotClass,
  OVERLAY_SLOTS,
  type OverlaySlot,
  type OverlayTone,
} from './overlayLayout'
export { Icon } from './Icon'
export { ICON_NAMES, ICON_PATHS, type IconName } from './icons'
// A mark for a trade good, and the human spelling of its category. Every good in data/goods.json
// has its OWN drawn glyph — see goodIcons.ts for the table and for why seven was the wrong answer.
export { goodIcon, categoryLabel } from './goodIcons'
// A catalogued THING as a BLOCK — mark + name + corner over aligned figure lines, in three tap
// shapes (see EntryTile.tsx). The compendium's ship classes and officers wear it directly; a trade
// good wears it through GoodTile, which adds the two facts only a good has.
export { EntryTile, EntryTileLine, type EntryTileTap } from './EntryTile'
export { GoodTile } from './GoodTile'
// The FIELD those tiles stand in — one table, read as CSS by `tileFieldClass()` and as a number by
// `tileFieldCols()`/`useTileCols()`, so the grid and the code that must know where a row ENDS
// cannot disagree (tileLayout.ts's header carries the two authorities this folded).
export { tileFieldClass, tileFieldCols, TILE_FIELD, type TileFieldStep } from './tileLayout'
export { useTileCols } from './useTileCols'
// The one rendering of a good's SERVED rarity tier (0032): a colour token AND a shape per tier,
// so the tier survives a colourblind player and a greyscale screenshot. See Rarity.tsx.
export { RarityMark } from './Rarity'
export { rarityLabel, RARITY_TIERS } from './rarityTiers'
// RarityMark's counterpart for WATER: a sea's served danger tier (0040), drawn as countable pips
// in the game's three-tone colour language. Same split, same rules — see DangerMark.tsx.
export { DangerMark } from './DangerMark'
export { dangerLabel, dangerPips, dangerTone, DANGER_PIPS, DANGER_TIERS } from './dangerTiers'
export { Collapsible, CollapsibleCard } from './Collapsible'
// Collapsible's inline counterpart: the tappable ⓘ that folds a standing EXPLANATION rather than
// content (see Explain.tsx for the boundary between them, and for what may never go behind a dot).
export { Explain, ExplainDot, ExplainPanel } from './Explain'
export { useExplainDisclosure, type ExplainDisclosure } from './explainState'
// The two faces of THE ONE CLOCK: the real time now, and the time until a served instant —
// pure display over shellState's nowMs (see Clock.tsx). When a countdown reaches zero the caller
// re-asks the server through useReaskAtEdge; the edge idiom lives once, in reaskAtEdge.ts.
export { WallClock, Countdown } from './Clock'
export { useReaskAtEdge } from './reaskAtEdge'

// THE TRADE FOLD (2026-09-01) — the goods field, its price cells and the quantity step. It came
// out of features/command so a second quay could trade through it (OWNER_REQUESTS row 53); see
// tradePickers.tsx for why it is here and not there.
export { GoodPicker, QtyPicker, FilterBox, TruncationNote } from './tradePickers'
export { inRowsOf } from './inRows'
