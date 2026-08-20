// Design-system overlay-slot layout — the PURE class builders behind OverlayPanel (the
// screenLayout.ts idiom: a pure module beside the component, so react-refresh stays happy and the
// slot/chrome contract is unit-testable). Tokens only.
//
// WHAT THIS IS FOR, AND WHAT IT IS NOT. These slots position READ-ONLY chrome over the chart: a
// legend, a scale bar, a "3 fleets at sea" readout. THE MAP IS A VIEW, NOT A CONTROLLER — no
// order is ever composed here, so an overlay never carries a command button. (byeharu learned the
// hard way that a control inside a capped, scrollable map rail can be scrolled out of reach; this
// game removes the whole class by keeping controls off the map and on the Command tab.)

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
    slot ? `absolute z-10 ${SLOT_POS[slot]}` : '',
    extra,
  ]
    .filter(Boolean)
    .join(' ')
}
