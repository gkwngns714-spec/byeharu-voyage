// Design-system overlay-slot layout — the PURE class builders behind OverlayPanel (the
// screenLayout.ts idiom: a pure module beside the component, so react-refresh stays happy and the
// slot/chrome contract is unit-testable). Tokens only.
//
// WHAT THIS IS FOR. These slots position chrome over a chart: a legend, a scale bar, a "3 fleets
// at sea" readout, a corner panel — and, since 2026-08-23, the Map tab's one action.
//
// THIS BLOCK USED TO SAY *"THE MAP IS A VIEW, NOT A CONTROLLER — no order is ever composed here,
// so an overlay never carries a command button."* Half of it is still the law and the other half
// was never the point. **No order is composed on an overlay**, and none is: what a corner panel
// may carry is a HAND-OFF — a button that names an intent and goes to the one tab that composes
// it (`features/map/SailHere.tsx`). What the sentence was really protecting is REACH, so that is
// what it says now:
//
//   AN ACTION MAY LIVE IN A SLOT PRECISELY BECAUSE A SLOT CANNOT BE PANNED, SCROLLED OR CLIPPED
//   AWAY. It is anchored to a corner of the box, not to a coordinate in the picture that a pan
//   could carry off the glass, and the panel filling it keeps its header and its controls outside
//   any capped region (`features/map/MapPanel.tsx`). byeharu shipped a button with 8 of its 44
//   pixels on screen because a rail was capped at the CALL SITE; the answer to that is this
//   table, not a ban on acting.

export const OVERLAY_SLOTS = ['top-left', 'top-right', 'bottom-left', 'bottom-right'] as const
export type OverlaySlot = (typeof OVERLAY_SLOTS)[number]

export type OverlayTone = 'default' | 'accent' | 'success' | 'warning' | 'danger'

// Corner anchor (inset 0.75rem — just inside the chart's rounded-card border).
const SLOT_POS: Record<OverlaySlot, string> = {
  'top-left': 'left-3 top-3',
  'top-right': 'right-3 top-3',
  'bottom-left': 'bottom-3 left-3',
  'bottom-right': 'bottom-3 right-3',
}

/**
 * WHERE A CORNER IS — for chrome that is not an OverlayPanel but must sit in the same four places.
 *
 * The map's zoom/fit column is three bare buttons rather than a panel, and it carried its own
 * hand-written `absolute right-3 top-3`: a fifth spelling of a corner, beside this table and the
 * free-text `positionClassName` strings `MapPanel` used to take from each of its callers. Four
 * names for one anchor is how a panel and the control beside it drift a pixel apart. There is one
 * table, and this is how something that is not a panel reads it.
 */
export function overlaySlotClass(slot: OverlaySlot): string {
  return SLOT_POS[slot]
}

// Border tint per tone — mirrors Card's TONE alphas so identity reads the same language.
const TONE: Record<OverlayTone, string> = {
  default: 'border-edge',
  accent: 'border-accent/25',
  success: 'border-success/25',
  warning: 'border-warning/25',
  danger: 'border-danger/25',
}

/** The overlay chrome classes (pure). `slot` self-positions the panel in a corner of its
 *  `relative` chart box; `inert` (the default posture for map chrome) makes it pointer-transparent
 *  so it can never swallow a pan/zoom gesture. */
export function overlayPanelClass(tone: OverlayTone = 'default', slot?: OverlaySlot, extra = '', inert = true): string {
  return [
    inert ? 'pointer-events-none' : 'pointer-events-auto',
    // MATERIAL, D12: the map's corner chrome is a panel like every other panel — the warm body and
    // the 7px chamfer, not a rounded web card floating over the chart. It keeps its translucency
    // and blur, which the flat panels do not have: this one sits ON the world and has to let the
    // coastline under it stay legible.
    //
    // The blur is deliberately NOT applied to the flat screens. CCP measured window blur at up to
    // 32 ms a frame and drop it entirely at low shader quality; two small corner panels over a
    // static SVG is a budget that survives it, a whole screen of panels is not.
    'bv-cut border bg-panel/90 p-2 shadow-overlay backdrop-blur',
    TONE[tone],
    slot ? `absolute z-10 ${overlaySlotClass(slot)}` : '',
    extra,
  ]
    .filter(Boolean)
    .join(' ')
}
