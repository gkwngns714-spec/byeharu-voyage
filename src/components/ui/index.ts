// Byeharu Voyage design-system primitives — the single import surface.
// Screens import from here, never from the individual files, so the set stays one authority.
export { Button } from './Button'
export { buttonClasses, type ButtonVariant, type ButtonSize } from './buttonStyles'
export { Card, CardHeader, type CardTone } from './Card'
export { Badge, type BadgeTone } from './Badge'
// Badge's numeric counterpart: the %NBR pill (see PriceIndex.tsx for the boundary — a
// status WORD is a Badge, the figure the game is played from is a PriceIndex).
export { PriceIndex, type PriceAdvice } from './PriceIndex'
export { Meter, type MeterTone } from './Meter'
export { Notice, type NoticeTone } from './Notice'
export { SectionLabel } from './SectionLabel'
export { PageHeader } from './PageHeader'
export { StatRow } from './StatRow'
// StatRow's complement: the label/value row for a value that is a SENTENCE (see DetailRow.tsx for
// the boundary between them).
export { DetailRow } from './DetailRow'
export { Screen } from './Screen'
export { screenBodyClass, screenSplitClass, screenRailClass } from './screenLayout'
export { EmptyState } from './EmptyState'
export { Skeleton } from './Skeleton'
export { Table, TH, TD, ListRow } from './Table'
export { scrollTableClass, TABLE_SCROLL_HINT } from './tableLayout'
export { Sheet } from './Sheet'
export { OverlayPanel } from './OverlayPanel'
export { overlayPanelClass, OVERLAY_SLOTS, type OverlaySlot, type OverlayTone } from './overlayLayout'
export { Icon } from './Icon'
export { ICON_NAMES, ICON_PATHS, type IconName } from './icons'
export { Collapsible, CollapsibleCard } from './Collapsible'
// Collapsible's inline counterpart: the tappable ⓘ that folds a standing EXPLANATION rather than
// content (see Explain.tsx for the boundary between them, and for what may never go behind a dot).
export { Explain, ExplainDot, ExplainPanel } from './Explain'
export { useExplainDisclosure, type ExplainDisclosure } from './explainState'
export { foldStorageKey, foldStateValue, readFoldState } from './collapsibleState'
