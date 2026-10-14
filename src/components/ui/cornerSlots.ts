// WHERE A CORNER IS — the one table, pure (no React) so react-refresh keeps Corner.tsx
// component-only and something that is not a `Corner` can read the same four anchors.
//
// THERE WERE TWO OF THESE TABLES, byte for byte: `Corner.tsx`'s own `SLOT` and the deprecated
// `overlayLayout.ts`'s `SLOT_POS`, which survived step 10 only because the chart's view controls
// (`chart/ViewControls.tsx`) read their corner from it. Two spellings of one anchor is how a panel
// and the control beside it drift a pixel apart, so overlayLayout.ts is deleted and both read this.
//
// Inset 0.75rem — just inside the chart's edge.

export type CornerSlot = 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right'

const SLOT: Record<CornerSlot, string> = {
  'top-left': 'left-3 top-3',
  'top-right': 'right-3 top-3',
  'bottom-left': 'bottom-3 left-3',
  'bottom-right': 'bottom-3 right-3',
}

/** The anchor classes for one corner. A corner slot cannot be panned, scrolled or clipped away,
 *  which is what lets a control live on a pannable picture at all (docs/CORE_REUSE.md §1.5). */
export function cornerSlotClass(slot: CornerSlot): string {
  return SLOT[slot]
}
