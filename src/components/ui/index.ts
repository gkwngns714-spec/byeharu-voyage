// Byeharu Voyage design-system primitives — the single import surface.
// Screens import from here, never from the individual files, so the set stays one authority.
export { Button } from './Button'
// The text field. One recipe, replacing four hand-written ones (see Input.tsx).
export { Input } from './Input'
export { buttonClasses, type ButtonVariant, type ButtonSize } from './buttonStyles'
// The two text treatments this game repeats: the fine-print voice and the tappable row link. See
// typography.ts for the thirty and the three hand-written spellings they replace.
export { fineClass, rowLinkClass, headRowClass } from './typography'
export { Card, CardHeader, type CardTone } from './Card'
export { Badge, type BadgeTone } from './Badge'
// Badge's numeric counterpart: the %NBR pill (see PriceIndex.tsx for the boundary — a
// status WORD is a Badge, the figure the game is played from is a PriceIndex).
export { PriceIndex, type PriceAdvice } from './PriceIndex'
// The price LINE (0013 gave the server a memory to draw one from). See Sparkline.tsx for what it
// deliberately refuses to do — interpolate, scale to zero, or draw a single point.
export { Sparkline, type SparkTone } from './Sparkline'
export { Meter, type MeterTone } from './Meter'
// Meter's countable counterpart: a resource with a UNIT (tuns, days, berths) drawn as segments
// you can count, rather than as a fraction you must do arithmetic on. See Gauge.tsx.
export { Gauge, type GaugeTone } from './Gauge'
export { Notice, type NoticeTone } from './Notice'
export { SectionLabel } from './SectionLabel'
export { PageHeader } from './PageHeader'
// SectionLabel's opposite number: the one FIGURE a block is about, drawn as the hero
// (docs/UI_DIRECTION.md §4 rule 2). See HeroFigure.tsx for the three hand-written copies it names.
export { HeroFigure } from './HeroFigure'
export { StatRow } from './StatRow'
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
// A trade good as a BLOCK — icon + name + rarity over aligned figures. MARKET and the COMPENDIUM
// compose it; COMMAND's good picker is the named next caller (see GoodTile.tsx for the boundary).
export { GoodTile, GoodTileLine } from './GoodTile'
export { goodTileGridClass } from './goodTileLayout'
// The one rendering of a good's SERVED rarity tier (0032): a colour token AND a shape per tier,
// so the tier survives a colourblind player and a greyscale screenshot. See Rarity.tsx.
export { RarityMark } from './Rarity'
export { rarityLabel, RARITY_TIERS } from './rarityTiers'
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
